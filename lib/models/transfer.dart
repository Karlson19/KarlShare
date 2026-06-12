import 'package:flutter/foundation.dart';
import 'device.dart';
import 'enums.dart';
import 'transfer_file.dart';

/// A transfer session with one device (Section 6.6 history rows).
@immutable
class Transfer {
  const Transfer({
    required this.id,
    required this.device,
    required this.direction,
    required this.files,
    required this.timestamp,
    this.status = TransferStatus.pending,
    this.speedBytesPerSec = 0,
  });

  final String id;
  final Device device;
  final TransferDirection direction;
  final List<TransferFile> files;
  final DateTime timestamp;
  final TransferStatus status;
  final double speedBytesPerSec;

  int get totalBytes =>
      files.fold(0, (sum, f) => sum + f.sizeBytes);

  int get transferredBytes => files.fold(
        0,
        (sum, f) => sum + (f.sizeBytes * f.progress).round(),
      );

  double get overallProgress {
    if (totalBytes == 0) return 0;
    return transferredBytes / totalBytes;
  }

  int get fileCount => files.length;

  Transfer copyWith({
    Device? device,
    List<TransferFile>? files,
    TransferStatus? status,
    double? speedBytesPerSec,
  }) =>
      Transfer(
        id: id,
        device: device ?? this.device,
        direction: direction,
        files: files ?? this.files,
        timestamp: timestamp,
        status: status ?? this.status,
        speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      );
}
