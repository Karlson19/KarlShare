import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../models/device.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../../../models/transfer_file.dart';
import '../../../services/transfer_service.dart';
import '../../history/providers/history_provider.dart';

/// Shared [TransferService] instance.
final transferServiceProvider = Provider<TransferService>((ref) {
  return TransferService();
});

/// Files chosen on the picker, handed to the transfer screen.
final selectedFilesProvider = StateProvider<List<TransferFile>>((ref) => []);

/// Device chosen from the radar / device sheet.
final selectedDeviceProvider = StateProvider<Device?>((ref) => null);

/// The device we most recently received a transfer from. Lets a receiver (the
/// PC in particular, which has no camera to scan a QR) send files back to it
/// with one tap, without waiting for the radar to rediscover it.
final lastReceivedDeviceProvider = StateProvider<Device?>((ref) => null);

/// Drives an active transfer by forwarding native [TransferEvent]s into the
/// app's [Transfer] domain model. On platforms where the native bridge isn't
/// available (no Android), [start] reports failure and the UI shows a graceful
/// fallback.
class ActiveTransferNotifier extends StateNotifier<Transfer?> {
  ActiveTransferNotifier(this._ref) : super(null) {
    // Always listen, so INCOMING transfers (where we never called start)
    // populate state and the UI can react. The receiver's server is started
    // from the home screen.
    final service = _ref.read(transferServiceProvider);
    if (service.isPlatformSupported) {
      _eventSub = service.events().listen(_onEvent);
    }
  }

  final Ref _ref;
  StreamSubscription<TransferEvent>? _eventSub;
  String? _activeTransferId;
  DateTime? _startedAt;
  double _speedBytesPerSec = 0;
  int _lastTotalBytes = 0;
  DateTime _lastSpeedSample = DateTime.fromMillisecondsSinceEpoch(0);

  /// Last error message from the engine, shown on the transfer screen when a
  /// transfer fails so problems are visible (no cable for logs).
  String? lastError;

  /// Returns true when the transfer was successfully dispatched into the
  /// native engine. False → caller should surface an explanation (no
  /// recipient IP, platform unsupported, etc).
  Future<bool> start({
    required Device device,
    required List<TransferFile> files,
    TransferDirection direction = TransferDirection.sent,
  }) async {
    final service = _ref.read(transferServiceProvider);
    if (!service.isPlatformSupported) return false;
    final peerIp = device.ipAddress;
    if (peerIp == null || peerIp.isEmpty) return false;

    final outgoing = files
        .where((f) => f.path != null && f.path!.isNotEmpty)
        .map((f) => OutgoingFile(
              id: f.id,
              path: f.path!,
              name: f.name,
              mime: 'application/octet-stream',
              size: f.sizeBytes,
            ))
        .toList();
    if (outgoing.isEmpty) return false;

    final transferId = await service.sendFiles(peerIp: peerIp, files: outgoing);
    if (transferId == null) {
      return false;
    }
    _activeTransferId = transferId;
    _startedAt = DateTime.now();
    _lastSpeedSample = DateTime.now();
    _lastTotalBytes = 0;

    state = Transfer(
      id: transferId,
      device: device,
      direction: direction,
      files: files.map((f) => f.copyWith(progress: 0)).toList(),
      timestamp: DateTime.now(),
      status: TransferStatus.transferring,
    );
    return true;
  }

  void _onEvent(TransferEvent event) {
    final current = state;

    // The first frame of any transfer is its header. If a header arrives for a
    // different transfer than the one we're tracking, and the tracked one has
    // already finished (or we aren't tracking any), it's a brand-new incoming
    // transfer — adopt it. Without this, a transfer that arrives right after
    // one completes is dropped by the stale-id guard below (or merged into the
    // finished transfer), so the receiver never sees it.
    if (event.type == TransferEventType.header &&
        event.transferId != _activeTransferId &&
        _isFinished(current)) {
      _beginIncoming(event);
      return;
    }

    // Ignore events that belong to a different transfer than the active one.
    if (_activeTransferId != null && event.transferId != _activeTransferId) {
      return;
    }
    switch (event.type) {
      case TransferEventType.started:
        break;
      case TransferEventType.header:
        // Additional file within the transfer we're already tracking.
        if (current != null &&
            !current.files.any((f) => f.id == (event.fileId ?? ''))) {
          state = current.copyWith(
            files: [...current.files, _fileFrom(event)],
          );
        }
        break;
      case TransferEventType.progress:
        if (current == null) return;
        final updated = current.files.map((f) {
          if (f.id != event.fileId) return f;
          final progress = event.fileTotal == 0
              ? 0.0
              : event.fileBytes / event.fileTotal;
          return f.copyWith(progress: progress.clamp(0.0, 1.0));
        }).toList();
        _refreshSpeed(event.totalBytes);
        state = current.copyWith(
          files: updated,
          speedBytesPerSec: _speedBytesPerSec,
        );
        break;
      case TransferEventType.fileComplete:
        if (current == null) return;
        final updated = current.files.map((f) {
          if (f.id != event.fileId) return f;
          return f.copyWith(progress: 1.0, path: event.savePath ?? f.path);
        }).toList();
        state = current.copyWith(files: updated);
        break;
      case TransferEventType.transferComplete:
        if (current == null) return;
        final finished = current.copyWith(
          status: TransferStatus.completed,
          speedBytesPerSec: 0,
        );
        state = finished;
        _ref.read(historyProvider.notifier).add(finished);
        break;
      case TransferEventType.cancelled:
        if (current == null) return;
        state = current.copyWith(
          status: TransferStatus.failed,
          speedBytesPerSec: 0,
        );
        break;
      case TransferEventType.error:
        lastError = event.message;
        if (current == null) return;
        state = current.copyWith(
          status: TransferStatus.failed,
          speedBytesPerSec: 0,
        );
        break;
      case TransferEventType.retry:
        if (current == null) return;
        // Reset per-attempt counters — the engine starts a fresh connection.
        _lastTotalBytes = 0;
        _speedBytesPerSec = 0;
        state = current.copyWith(
          status: TransferStatus.paused, // UI maps paused → "Reconnecting…"
          speedBytesPerSec: 0,
        );
        break;
    }
  }

  TransferFile _fileFrom(TransferEvent event) => TransferFile(
        id: event.fileId ?? const Uuid().v4(),
        name: event.fileName ?? 'file',
        sizeBytes: event.fileSize,
        type: KFileType.other,
        progress: 0,
        path: event.savePath,
      );

  /// A transfer is "finished" (free to be replaced by a new incoming one) when
  /// there is none, or it has completed or failed.
  bool _isFinished(Transfer? t) =>
      t == null ||
      t.status == TransferStatus.completed ||
      t.status == TransferStatus.failed;

  /// Starts tracking a fresh incoming (received) transfer from its header,
  /// resetting the per-transfer counters so stats don't carry over from a
  /// previous one.
  void _beginIncoming(TransferEvent event) {
    _activeTransferId = event.transferId;
    _startedAt = DateTime.now();
    _lastSpeedSample = DateTime.now();
    _lastTotalBytes = 0;
    _speedBytesPerSec = 0;
    lastError = null;
    final peerIp = event.peerIp;
    final device = Device(
      id: peerIp ?? 'incoming',
      name: peerIp ?? 'Incoming device',
      status: DeviceStatus.connecting,
      address: peerIp,
      ipAddress: peerIp,
    );
    // Remember the sender so the user can send files straight back to it.
    if (peerIp != null && peerIp.isNotEmpty) {
      _ref.read(lastReceivedDeviceProvider.notifier).state =
          device.copyWith(status: DeviceStatus.ready);
    }
    state = Transfer(
      id: event.transferId,
      device: device,
      direction: TransferDirection.received,
      files: [_fileFrom(event)],
      timestamp: DateTime.now(),
      status: TransferStatus.transferring,
    );
  }

  void _refreshSpeed(int totalBytes) {
    final now = DateTime.now();
    final dt = now.difference(_lastSpeedSample).inMilliseconds;
    if (dt < 200) return;
    final delta = totalBytes - _lastTotalBytes;
    _speedBytesPerSec = delta / (dt / 1000.0);
    _lastTotalBytes = totalBytes;
    _lastSpeedSample = now;
  }

  double get elapsedSeconds {
    final start = _startedAt;
    if (start == null) return 0;
    return DateTime.now().difference(start).inMilliseconds / 1000;
  }

  double get etaSeconds {
    final s = state;
    if (s == null || s.status == TransferStatus.completed) return 0;
    final remaining = s.totalBytes - s.transferredBytes;
    if (_speedBytesPerSec <= 0 || remaining <= 0) return 0;
    return remaining / _speedBytesPerSec;
  }

  Future<void> cancel() async {
    final id = _activeTransferId;
    if (id != null) {
      await _ref.read(transferServiceProvider).cancel(id);
    }
    // Keep the event subscription alive — it's our permanent receive listener.
    state = null;
    _activeTransferId = null;
    _startedAt = null;
    _speedBytesPerSec = 0;
    _lastTotalBytes = 0;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}

final activeTransferProvider =
    StateNotifierProvider<ActiveTransferNotifier, Transfer?>((ref) {
  return ActiveTransferNotifier(ref);
});

/// Drives the receiver side — when the user taps "Receive" we start the TCP
/// server. Incoming transfers populate via the same [activeTransferProvider]
/// listener (the header event with no prior outgoing transfer flips state to
/// received).
final receivingProvider = StateProvider<bool>((ref) => false);

Future<void> startReceiving(WidgetRef ref) async {
  final service = ref.read(transferServiceProvider);
  if (!service.isPlatformSupported) return;
  await service.startServer();
  // Make sure the listener is wired so incoming events flow into state.
  // ignore: unused_local_variable
  final _ = ref.read(activeTransferProvider.notifier);
  ref.read(receivingProvider.notifier).state = true;
}

Future<void> stopReceiving(WidgetRef ref) async {
  final service = ref.read(transferServiceProvider);
  if (!service.isPlatformSupported) return;
  await service.stopServer();
  ref.read(receivingProvider.notifier).state = false;
}
