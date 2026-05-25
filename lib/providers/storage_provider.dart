import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Hive box names used by the app.
class HiveBoxes {
  HiveBoxes._();
  static const String transfers = 'transfers_v1';
}

/// The opened history box. Overridden in main() once Hive has loaded.
/// Holding the [Box] in a provider lets [HistoryNotifier] be fully testable
/// — tests can hand it an in-memory or fake box without touching disk.
final transfersBoxProvider = Provider<Box<Map<dynamic, dynamic>>>(
  (ref) => throw UnimplementedError(
    'Override transfersBoxProvider in main() with the opened Hive box.',
  ),
);
