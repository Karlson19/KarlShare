import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Spec for an outbound file the engine should send.
@immutable
class OutgoingFile {
  const OutgoingFile({
    required this.path,
    required this.name,
    required this.mime,
    required this.size,
  });

  final String path;
  final String name;
  final String mime;
  final int size;

  Map<String, dynamic> toMap() => {
        'path': path,
        'name': name,
        'mime': mime,
        'size': size,
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
  });

  final TransferEventType type;
  final String transferId;
  final String? fileId;
  final String? fileName;
  final String? fileMime;
  final int fileSize;
  final String? savePath;
  final int fileCount;

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

  bool get isPlatformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> startServer() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('startServer');
  }

  Future<void> stopServer() async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('stopServer');
  }

  Future<void> setSaveDir(String path) async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('setSaveDir', {'path': path});
  }

  /// Returns the new transfer's ID, or null when the platform has no native
  /// bridge (web/desktop) — the UI then shows a "not supported here" state.
  Future<String?> sendFiles({
    required String peerIp,
    required List<OutgoingFile> files,
  }) async {
    if (!isPlatformSupported) return null;
    return _method.invokeMethod<String>('sendFiles', {
      'peerIp': peerIp,
      'files': files.map((f) => f.toMap()).toList(),
    });
  }

  Future<void> cancel(String transferId) async {
    if (!isPlatformSupported) return;
    await _method.invokeMethod<void>('cancel', {'transferId': transferId});
  }

  Stream<TransferEvent> events() {
    if (!isPlatformSupported) return const Stream.empty();
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
    );
  }
}
