/// Formatting helpers for sizes, speeds, durations and date grouping.
class FormatUtils {
  FormatUtils._();

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var size = bytes / 1024;
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final precision = size >= 100 ? 0 : 1;
    return '${size.toStringAsFixed(precision)} ${units[unit]}';
  }

  static String speed(double bytesPerSec) {
    final mbps = bytesPerSec / (1024 * 1024);
    return '${mbps.toStringAsFixed(1)} MB/s';
  }

  /// Seconds remaining -> compact "1m 20s" / "45s".
  static String eta(double seconds) {
    if (seconds.isInfinite || seconds.isNaN || seconds < 0) return '--';
    final s = seconds.round();
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final rem = s % 60;
    return '${m}m ${rem}s';
  }

  /// Buckets a timestamp into a history section label (Section 6.6).
  static String dateGroup(DateTime ts, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff <= 7) return 'This Week';
    return 'Earlier';
  }

  static String clockTime(DateTime ts) {
    final h = ts.hour % 12 == 0 ? 12 : ts.hour % 12;
    final m = ts.minute.toString().padLeft(2, '0');
    final period = ts.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }
}
