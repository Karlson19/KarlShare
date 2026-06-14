import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../models/device.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../../../models/transfer_file.dart';
import '../../../providers/user_provider.dart';
import '../../../services/transfer_service.dart';
import '../../history/providers/history_provider.dart';

/// This device's advertised name: the user's profile name, else the OS
/// hostname. Sent in the transfer handshake so peers show it, not an IP.
/// Resolving the name must never break a transfer, so the profile read is
/// guarded — a missing/uninitialised profile just falls back to the hostname.
String _resolveIdentityName(String? Function() readProfileName) {
  String? profileName;
  try {
    profileName = readProfileName();
  } catch (_) {
    // Profile/prefs not ready — fall through to the hostname.
  }
  final p = profileName?.trim();
  if (p != null && p.isNotEmpty) return p;
  try {
    return Platform.localHostname;
  } catch (_) {
    return 'Karlshare device';
  }
}

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

/// Immutable snapshot of every transfer in the current exchange session.
///
/// A session is MANY transfers: the peer can send batch after batch, and both
/// sides can send simultaneously (the Xender model). The previous state held
/// exactly one transfer and silently discarded events for any other id — which
/// is why received files stopped appearing mid-session: the engine wrote them
/// to disk while the UI never heard about them. Here every event lands on its
/// transfer, keyed by id, and nothing is ever dropped.
class TransferSession {
  const TransferSession({
    this.transfers = const {},
    this.focusedId,
    this.protocolFilesDone = 0,
  });

  /// All transfers this session, in arrival order (map literal preserves
  /// insertion order).
  final Map<String, Transfer> transfers;

  /// The transfer the classic single-transfer screens follow — the most
  /// recently started or adopted one.
  final String? focusedId;

  /// Received files completed at the PROTOCOL layer. The session integrity
  /// check compares this against what the UI actually renders.
  final int protocolFilesDone;

  Transfer? get focused => focusedId == null ? null : transfers[focusedId];

  List<Transfer> get all => List.unmodifiable(transfers.values);

  List<Transfer> get received => transfers.values
      .where((t) => t.direction == TransferDirection.received)
      .toList(growable: false);

  List<Transfer> get sent => transfers.values
      .where((t) => t.direction == TransferDirection.sent)
      .toList(growable: false);

  bool get hasActive => transfers.values.any((t) =>
      t.status == TransferStatus.transferring ||
      t.status == TransferStatus.paused ||
      t.status == TransferStatus.pending);

  /// Received files the UI can see at 100% — must equal [protocolFilesDone].
  int get renderedReceivedFilesDone => transfers.values
      .where((t) => t.direction == TransferDirection.received)
      .expand((t) => t.files)
      .where((f) => f.progress >= 1.0)
      .length;
}

/// Routes every engine [TransferEvent] into the session, keyed by transfer id.
///
/// Correctness rules, learned the hard way:
///  * NO stale-id guard. Events for an unknown id create a transfer (incoming
///    headers) or a placeholder (our own `started` racing ahead of [start]'s
///    return) — they are never discarded.
///  * Progress events are coalesced: the mutable working set absorbs them and
///    the immutable state is emitted at most ~30×/sec, so a fast sender can't
///    flood the widget tree into jank. Structural events (header, completion,
///    error) flush immediately.
///  * An integrity counter cross-checks protocol-layer completions against
///    rendered completions and logs loudly if they ever diverge.
class TransferSessionNotifier extends StateNotifier<TransferSession> {
  TransferSessionNotifier(this._ref) : super(const TransferSession()) {
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

  /// Mutable working set, flushed into immutable [state] by [_flush].
  final Map<String, Transfer> _working = {};
  String? _focusedId;
  int _protocolFilesDone = 0;
  Timer? _flushTimer;
  DateTime? _startedAt;
  bool _wakeOn = false;

  // Per-transfer speed sampling (totalBytes deltas over >=200ms windows).
  final Map<String, int> _lastBytes = {};
  final Map<String, DateTime> _lastSample = {};

  /// Last error message from the engine, shown on the transfer screen when a
  /// transfer fails so problems are visible (no cable for logs).
  String? lastError;

  /// Returns true when the transfer was successfully dispatched into the
  /// engine. False → caller should surface an explanation (no recipient IP,
  /// platform unsupported, etc).
  Future<bool> start({
    required Device device,
    required List<TransferFile> files,
    TransferDirection direction = TransferDirection.sent,
  }) async {
    final service = _ref.read(transferServiceProvider);
    if (!service.isPlatformSupported) return false;
    service.setIdentityName(_resolveIdentityName(
        () => _ref.read(userProfileProvider)?.displayName));
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

    final pickerFiles = files.map((f) => f.copyWith(progress: 0)).toList();
    final racedAhead = _working[transferId];
    if (racedAhead == null) {
      _working[transferId] = Transfer(
        id: transferId,
        device: device,
        direction: direction,
        files: pickerFiles,
        timestamp: DateTime.now(),
        status: TransferStatus.transferring,
      );
    } else {
      // The engine emitted started/header events before sendFiles returned.
      // Keep any progress it already reported (file ids match: the engine
      // echoes the picker's ids), but attach the real device and the picker's
      // richer file metadata (types, names).
      final seenById = {for (final f in racedAhead.files) f.id: f};
      _working[transferId] = racedAhead.copyWith(
        device: device,
        status: TransferStatus.transferring,
        files: pickerFiles.map((f) {
          final seen = seenById[f.id];
          return seen == null
              ? f
              : f.copyWith(progress: seen.progress, path: seen.path);
        }).toList(),
      );
    }
    _focusedId = transferId;
    _startedAt = DateTime.now();
    _flush();
    return true;
  }

  void _onEvent(TransferEvent event) {
    switch (event.type) {
      case TransferEventType.started:
        // Sender-side announcement: create the slot so headers racing ahead
        // of start()'s return have somewhere to land.
        _working.putIfAbsent(
          event.transferId,
          () => Transfer(
            id: event.transferId,
            device: const Device(
              id: 'pending',
              name: 'Connecting…',
              status: DeviceStatus.connecting,
            ),
            direction: event.direction == 'received'
                ? TransferDirection.received
                : TransferDirection.sent,
            files: const [],
            timestamp: DateTime.now(),
            status: TransferStatus.transferring,
          ),
        );
        _flush();
        break;

      case TransferEventType.header:
        _onHeader(event);
        _flush();
        break;

      case TransferEventType.progress:
        final t = _working[event.transferId];
        if (t == null) break;
        final files = t.files.map((f) {
          if (f.id != event.fileId) return f;
          final p = event.fileTotal == 0
              ? 0.0
              : event.fileBytes / event.fileTotal;
          return f.copyWith(progress: p.clamp(0.0, 1.0));
        }).toList();
        _working[event.transferId] = t.copyWith(
          files: files,
          speedBytesPerSec:
              _sampleSpeed(event.transferId, event.totalBytes, t.speedBytesPerSec),
        );
        _scheduleFlush();
        break;

      case TransferEventType.fileComplete:
        final t = _working[event.transferId];
        if (t == null) break;
        if (t.direction == TransferDirection.received) _protocolFilesDone++;
        final files = t.files
            .map((f) => f.id == event.fileId
                ? f.copyWith(progress: 1.0, path: event.savePath ?? f.path)
                : f)
            .toList();
        _working[event.transferId] = t.copyWith(files: files);
        _flush();
        break;

      case TransferEventType.transferComplete:
        final t = _working[event.transferId];
        if (t == null) break;
        final finished =
            t.copyWith(status: TransferStatus.completed, speedBytesPerSec: 0);
        _working[event.transferId] = finished;
        _ref.read(historyProvider.notifier).add(finished);
        _flush();
        break;

      case TransferEventType.cancelled:
      case TransferEventType.error:
        if (event.type == TransferEventType.error) lastError = event.message;
        final t = _working[event.transferId];
        if (t == null) break; // engine-level error with no transfer attached
        _working[event.transferId] =
            t.copyWith(status: TransferStatus.failed, speedBytesPerSec: 0);
        _flush();
        break;

      case TransferEventType.retry:
        final t = _working[event.transferId];
        if (t == null) break;
        // Fresh connection — reset this transfer's speed sampling.
        _lastBytes.remove(event.transferId);
        _lastSample.remove(event.transferId);
        _working[event.transferId] = t.copyWith(
          status: TransferStatus.paused, // UI maps paused → "Reconnecting…"
          speedBytesPerSec: 0,
        );
        _flush();
        break;
    }
  }

  void _onHeader(TransferEvent event) {
    final existing = _working[event.transferId];
    if (existing != null) {
      // Additional file within a transfer we already track.
      if (!existing.files.any((f) => f.id == (event.fileId ?? ''))) {
        _working[event.transferId] =
            existing.copyWith(files: [...existing.files, _fileFrom(event)]);
      }
      return;
    }
    // A transfer we've never heard of: an incoming one (receivers get no
    // start() call). Adopt it, focus it, and remember the sender for
    // one-tap send-back.
    final peerIp = event.peerIp;
    final peerName = event.peerName?.trim();
    // Prefer the name the sender advertised; fall back to a friendly label
    // (never a bare IP) when an older peer sends no name.
    final displayName = (peerName != null && peerName.isNotEmpty)
        ? peerName
        : 'Nearby device';
    final device = Device(
      id: peerIp ?? 'incoming-${event.transferId}',
      name: displayName,
      status: DeviceStatus.connecting,
      address: peerIp,
      ipAddress: peerIp,
    );
    if (peerIp != null && peerIp.isNotEmpty) {
      _ref.read(lastReceivedDeviceProvider.notifier).state =
          device.copyWith(status: DeviceStatus.ready);
    }
    _working[event.transferId] = Transfer(
      id: event.transferId,
      device: device,
      direction: TransferDirection.received,
      files: [_fileFrom(event)],
      timestamp: DateTime.now(),
      status: TransferStatus.transferring,
    );
    _focusedId = event.transferId;
    _startedAt ??= DateTime.now();
  }

  TransferFile _fileFrom(TransferEvent event) => TransferFile(
        id: event.fileId ?? const Uuid().v4(),
        name: event.fileName ?? 'file',
        sizeBytes: event.fileSize,
        type: _inferType(event.fileName ?? ''),
        progress: 0,
        path: event.savePath,
      );

  /// The wire mime is a generic octet-stream, so received files get their
  /// type (icon, accent color) from the extension.
  static KFileType _inferType(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' || 'bmp' =>
        KFileType.image,
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || '3gp' => KFileType.video,
      'mp3' || 'wav' || 'm4a' || 'ogg' || 'flac' || 'aac' => KFileType.audio,
      'apk' => KFileType.app,
      'pdf' || 'doc' || 'docx' || 'xls' || 'xlsx' || 'ppt' || 'pptx' ||
      'txt' || 'zip' || 'rar' || '7z' =>
        KFileType.document,
      _ => KFileType.other,
    };
  }

  double _sampleSpeed(String id, int totalBytes, double current) {
    final now = DateTime.now();
    final last = _lastSample[id];
    if (last == null) {
      _lastSample[id] = now;
      _lastBytes[id] = totalBytes;
      return current;
    }
    final dtMs = now.difference(last).inMilliseconds;
    if (dtMs < 200) return current;
    final speed = (totalBytes - (_lastBytes[id] ?? 0)) / (dtMs / 1000.0);
    _lastSample[id] = now;
    _lastBytes[id] = totalBytes;
    return speed < 0 ? 0 : speed;
  }

  /// Keep the device awake while a transfer is live. A screen timeout
  /// otherwise suspends the app and drops Wi-Fi power-save, killing the socket
  /// mid-transfer. Tied to the session (not a screen), so it holds even if the
  /// user navigates away, and releases the moment nothing is in flight.
  void _applyWakelock(bool active) {
    if (active == _wakeOn) return;
    _wakeOn = active;
    unawaited(() async {
      try {
        if (active) {
          await WakelockPlus.enable();
        } else {
          await WakelockPlus.disable();
        }
      } catch (_) {
        // Best effort; unsupported platforms (e.g. web) just no-op.
      }
    }());
  }

  // ---- Coalesced state emission -------------------------------------------

  /// Lazy flush: progress floods collapse into ~30 state emissions per second.
  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 33), _flush);
  }

  /// Urgent flush: structural changes render on the next frame.
  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!mounted) return;
    final next = TransferSession(
      transfers: Map.unmodifiable(Map.of(_working)),
      focusedId: _focusedId,
      protocolFilesDone: _protocolFilesDone,
    );
    state = next;
    _applyWakelock(next.hasActive);
    // Session integrity: what the protocol finished must be what the UI shows.
    final rendered = next.renderedReceivedFilesDone;
    if (rendered < _protocolFilesDone) {
      debugPrint(
        'KARLSHARE INTEGRITY WARNING: protocol completed $_protocolFilesDone '
        'received file(s) but the UI renders $rendered — a file was dropped '
        'from rendering. Report this.',
      );
    }
  }

  // ---- Focused-transfer conveniences (the classic screens use these) ------

  double get elapsedSeconds {
    final start = _startedAt;
    if (start == null) return 0;
    return DateTime.now().difference(start).inMilliseconds / 1000;
  }

  double get etaSeconds {
    final s = state.focused;
    if (s == null || s.status == TransferStatus.completed) return 0;
    final remaining = s.totalBytes - s.transferredBytes;
    if (s.speedBytesPerSec <= 0 || remaining <= 0) return 0;
    return remaining / s.speedBytesPerSec;
  }

  /// Cancels the focused transfer and removes it from the session.
  Future<void> cancel() async {
    final id = _focusedId;
    if (id != null) await cancelById(id);
  }

  /// Cancels one specific transfer and removes it from the session.
  Future<void> cancelById(String id) async {
    await _ref.read(transferServiceProvider).cancel(id);
    final removed = _working.remove(id);
    if (removed != null) _shrinkIntegrityBaseline(removed);
    _lastBytes.remove(id);
    _lastSample.remove(id);
    if (_focusedId == id) _focusedId = _latestActiveId();
    _flush();
  }

  /// Removes finished (completed/failed) transfers — the Done button. Anything
  /// still in flight keeps running and stays visible.
  void clearFinished() {
    _working.removeWhere((_, t) {
      final finished = t.status == TransferStatus.completed ||
          t.status == TransferStatus.failed;
      if (finished) _shrinkIntegrityBaseline(t);
      return finished;
    });
    final focused = _focusedId;
    if (focused != null && !_working.containsKey(focused)) {
      _focusedId = _latestActiveId();
      if (_focusedId == null) _startedAt = null;
    }
    _flush();
  }

  /// A transfer leaving the session takes its completed received files out of
  /// the integrity baseline — otherwise every flush after Done would falsely
  /// warn that the UI dropped files.
  void _shrinkIntegrityBaseline(Transfer t) {
    if (t.direction != TransferDirection.received) return;
    _protocolFilesDone -= t.files.where((f) => f.progress >= 1.0).length;
    if (_protocolFilesDone < 0) _protocolFilesDone = 0;
  }

  String? _latestActiveId() {
    String? candidate;
    for (final t in _working.values) {
      if (t.status == TransferStatus.transferring ||
          t.status == TransferStatus.paused) {
        candidate = t.id;
      }
    }
    return candidate;
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _eventSub?.cancel();
    _applyWakelock(false);
    super.dispose();
  }
}

/// The session — every transfer, both directions, nothing dropped.
final transferSessionProvider =
    StateNotifierProvider<TransferSessionNotifier, TransferSession>((ref) {
  return TransferSessionNotifier(ref);
});

/// The transfer the classic single-transfer screens follow (most recently
/// started or adopted). The full picture lives in [transferSessionProvider].
final focusedTransferProvider = Provider<Transfer?>((ref) {
  return ref.watch(transferSessionProvider).focused;
});

/// Drives the receiver side — when the user taps "Receive" we start the TCP
/// server. Incoming transfers populate via the session listener (a header
/// event for an unknown transfer id is adopted as a received transfer).
final receivingProvider = StateProvider<bool>((ref) => false);

Future<void> startReceiving(WidgetRef ref) async {
  final service = ref.read(transferServiceProvider);
  if (!service.isPlatformSupported) return;
  // Advertise our name before listening, so a sender's handshake reply (and
  // the name we send) carries the real device name.
  service.setIdentityName(
      _resolveIdentityName(() => ref.read(userProfileProvider)?.displayName));
  await service.startServer();
  // Make sure the listener is wired so incoming events flow into state.
  // ignore: unused_local_variable
  final _ = ref.read(transferSessionProvider.notifier);
  ref.read(receivingProvider.notifier).state = true;
}

Future<void> stopReceiving(WidgetRef ref) async {
  final service = ref.read(transferServiceProvider);
  if (!service.isPlatformSupported) return;
  await service.stopServer();
  ref.read(receivingProvider.notifier).state = false;
}
