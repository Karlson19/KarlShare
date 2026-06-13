import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop/dart_transfer_engine.dart';

/// Spec for an outbound file the engine should send.
@immutable
class OutgoingFile {
  const OutgoingFile({
    required this.path,
    required this.name,
    required this.mime,
    required this.size,
    this.id,
  });

  final String path;
  final String name;
  final String mime;
  final int size;

  /// The caller's id for this file (the picker's). The engine echoes it in
  /// progress events so the sender UI can match them to its existing rows.
  final String? id;

  Map<String, dynamic> toMap() => {
        'path': path,
        'name': name,
        'mime': mime,
        'size': size,
        'id': id,
      };
}

enum TransferEventType {
  started,
  header,
  progress,
  fileComplete,
  transferComplete,
  error,
  cancelled,
  retry,
}

@immutable
class TransferEvent {
  const TransferEvent({
    required this.type,
    required this.transferId,
    this.fileId,
    this.fileName,
    this.fileMime,
    this.fileSize = 0,
    this.savePath,
    this.fileCount = 0,
    this.fileBytes = 0,
    this.fileTotal = 0,
    this.totalBytes = 0,
    this.grandTotal = 0,
    this.direction,
    this.message,
    this.attempt = 0,
    this.backoffMs = 0,
    this.peerIp,
    this.peerName,
  });

  final TransferEventType type;
  final String transferId;
  final String? fileId;
  final String? fileName;
  final String? fileMime;
  final int fileSize;
  final String? savePath;
  final int fileCount;

  /// The remote device's IP on an incoming (received) transfer, so the
  /// receiver can later send files back to it. Null for outgoing transfers.
  final String? peerIp;

  /// The remote device's friendly name (from its handshake), so the receiver
  /// shows "Karlson's phone" instead of a bare IP. Null/empty for older peers.
  final String? peerName;

  /// Per-file progress (header → fileComplete).
  final int fileBytes;
  final int fileTotal;

  /// Aggregate transfer progress.
  final int totalBytes;
  final int grandTotal;
  final String? direction;
  final String? message;

  /// 1-based retry counter sent with `retry` events.
  final int attempt;

  /// How long the engine is waiting before its next retry attempt.
  final int backoffMs;
}

/// Typed wrapper around the `karlshare/transfer` platform channels.
class TransferService {
  TransferService({MethodChannel? method, EventChannel? events})
      : _method = method ?? const MethodChannel('karlshare/transfer'),
        _events = events ?? const EventChannel('karlshare/transfer/events');

  final MethodChannel _method;
  final EventChannel _events;
  Stream<TransferEvent>? _cached;
  DartTransferEngine? _engine;

  /// iOS still rides its native Multipeer/Network.framework bridge.
  bool get _channelSupported => !kIsWeb && Platform.isIOS;

  /// Android and desktop share the one pure-Dart engine — both ends of a
  /// transfer run the exact code the loopback test verifies. (The Kotlin
  /// engine is retired from the transfer path: its hardware-keystore TLS
  /// server failed on real phones in ways we can't debug remotely.)
  bool get _useDartEngine =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS);

  DartTransferEngine _ensureEngine() {
    final engine = _engine ??= DartTransferEngine();
    if (!kIsWeb && Platform.isAndroid) {
      // Hand verified files to MediaStore so they land in Gallery/Files under
      // Pictures|Movies|Music|Download /Karlshare with their original names.
      engine.publishReceivedFile ??= (path, name, mime) async {
        try {
          return await const MethodChannel('karlshare/store')
              .invokeMethod<String>('publish', {
            'path': path,
            'name': name,
            'mime': mime,
          });
        } catch (_) {
          return null; // keep the app-private copy; transfer already succeeded
        }
      };
    }
    return engine;
  }

  bool get isPlatformSupported => _channelSupported || _useDartEngine;

  /// Sets this device's friendly name, advertised in the transfer handshake so
  /// the peer shows it instead of a bare IP.
  void setIdentityName(String name) {
    if (_useDartEngine) _ensureEngine().localName = name;
  }

  Future<void> startServer() async {
    if (_useDartEngine) {
      await _ensureEngine().startServer();
      return;
    }
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('startServer');
  }

  Future<void> stopServer() async {
    if (_useDartEngine) {
      await _ensureEngine().stopServer();
      return;
    }
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('stopServer');
  }

  Future<void> setSaveDir(String path) async {
    if (_useDartEngine) return; // desktop engine manages its own save folder
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('setSaveDir', {'path': path});
  }

  /// Returns the new transfer's ID, or null when the platform has no native
  /// bridge (web/desktop) — the UI then shows a "not supported here" state.
  Future<String?> sendFiles({
    required String peerIp,
    required List<OutgoingFile> files,
  }) async {
    if (_useDartEngine) return _ensureEngine().sendFiles(peerIp, files);
    if (!_channelSupported) return null;
    return _method.invokeMethod<String>('sendFiles', {
      'peerIp': peerIp,
      'files': files.map((f) => f.toMap()).toList(),
    });
  }

  Future<void> cancel(String transferId) async {
    if (_useDartEngine) {
      await _ensureEngine().cancel(transferId);
      return;
    }
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('cancel', {'transferId': transferId});
  }

  /// Clears every trusted-peer fingerprint (Settings ▸ Reset paired devices).
  Future<void> forgetAllPeers() async {
    if (_useDartEngine) {
      await _ensureEngine().forgetAllPeers();
      return;
    }
    if (!_channelSupported) return;
    await _method.invokeMethod<void>('forgetAllPeers');
  }

  Stream<TransferEvent> events() {
    if (_useDartEngine) return _ensureEngine().events();
    if (!_channelSupported) return const Stream.empty();
    return _cached ??= _events
        .receiveBroadcastStream()
        .map(_parse)
        .where((e) => e != null)
        .cast<TransferEvent>()
        .asBroadcastStream();
  }

  TransferEvent? _parse(dynamic raw) {
    if (raw is! Map) return null;
    final transferId = raw['transferId'] as String? ?? '';
    final type = switch (raw['type'] as String?) {
      'started' => TransferEventType.started,
      'header' => TransferEventType.header,
      'progress' => TransferEventType.progress,
      'fileComplete' => TransferEventType.fileComplete,
      'transferComplete' => TransferEventType.transferComplete,
      'error' => TransferEventType.error,
      'cancelled' => TransferEventType.cancelled,
      'retry' => TransferEventType.retry,
      _ => null,
    };
    if (type == null) return null;
    return TransferEvent(
      type: type,
      transferId: transferId,
      fileId: raw['fileId'] as String?,
      fileName: raw['name'] as String?,
      fileMime: raw['mime'] as String?,
      fileSize: (raw['size'] as num?)?.toInt() ?? 0,
      savePath: raw['savePath'] as String?,
      fileCount: (raw['fileCount'] as num?)?.toInt() ?? 0,
      fileBytes: (raw['fileBytes'] as num?)?.toInt() ?? 0,
      fileTotal: (raw['fileTotal'] as num?)?.toInt() ?? 0,
      totalBytes: (raw['totalBytes'] as num?)?.toInt() ?? 0,
      grandTotal: (raw['grandTotal'] as num?)?.toInt() ?? 0,
      direction: raw['direction'] as String?,
      message: raw['message'] as String?,
      attempt: (raw['attempt'] as num?)?.toInt() ?? 0,
      backoffMs: (raw['backoffMs'] as num?)?.toInt() ?? 0,
      peerIp: raw['peerIp'] as String?,
      peerName: raw['peerName'] as String?,
    );
  }
}
