import 'package:flutter/foundation.dart';
import 'enums.dart';

/// A single file within a transfer (Section 5.3 / 7.2).
@immutable
class TransferFile {
  const TransferFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.type,
    this.progress = 0.0,
    this.path,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final KFileType type;

  /// 0–1 transfer progress for this file.
  final double progress;

  /// Local path once received (null while in flight / for mock data).
  final String? path;

  TransferFile copyWith({double? progress, String? path}) => TransferFile(
        id: id,
        name: name,
        sizeBytes: sizeBytes,
        type: type,
        progress: progress ?? this.progress,
        path: path ?? this.path,
      );
}
