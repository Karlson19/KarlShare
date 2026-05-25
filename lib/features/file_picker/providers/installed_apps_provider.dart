import 'dart:convert' show base64Decode;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/enums.dart';
import '../../../models/transfer_file.dart';

@immutable
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    required this.apkPath,
    required this.sizeBytes,
    required this.versionName,
    this.iconBytes,
  });

  final String packageName;
  final String label;
  final String apkPath;
  final int sizeBytes;
  final String versionName;

  /// The app's launcher icon as PNG bytes, for display in the picker grid.
  final Uint8List? iconBytes;

  TransferFile toTransferFile() => TransferFile(
        id: packageName,
        name: '$label.apk',
        sizeBytes: sizeBytes,
        type: KFileType.app,
        path: apkPath,
      );
}

bool get _supportsAppEnumeration => !kIsWeb && Platform.isAndroid;

const _channel = MethodChannel('karlshare/apps');

/// Lists user-installed apps on Android. Empty list elsewhere — the picker
/// hides the tab when [InstalledApp] lookups aren't supported.
final installedAppsProvider =
    FutureProvider.autoDispose<List<InstalledApp>>((ref) async {
  if (!_supportsAppEnumeration) return const [];
  try {
    final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('list');
    if (raw == null) return const [];
    return raw
        .map((row) => InstalledApp(
              packageName: row['packageName'] as String? ?? '',
              label: row['label'] as String? ?? 'Unknown',
              apkPath: row['sourceApkPath'] as String? ?? '',
              sizeBytes: (row['sizeBytes'] as num?)?.toInt() ?? 0,
              versionName: row['versionName'] as String? ?? '',
              iconBytes: _decodeIcon(row['iconPng'] as String?),
            ))
        .where((a) => a.apkPath.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
});

Uint8List? _decodeIcon(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}
