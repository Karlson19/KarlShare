import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/karlshare_button.dart';

/// Onboarding's permission step (Section 6.2 screen 3). Actually requests
/// the OS permissions Karlshare needs to discover peers and read media.
///
/// On Android 13+ the gallery permissions split into READ_MEDIA_IMAGES /
/// VIDEO / AUDIO; older devices get READ_EXTERNAL_STORAGE. WiFi-Direct
/// discovery switched from ACCESS_FINE_LOCATION (≤12) to NEARBY_WIFI_DEVICES
/// (13+). We just ask permission_handler for both — the SDK no-ops the ones
/// that aren't applicable.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  final Map<_PermissionGroup, PermissionStatus> _statuses = {};
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatuses());
  }

  /// Whether this platform actually exposes the OS permissions we care about.
  /// Desktop/web boots straight through with the CTA enabled so QA can
  /// preview the rest of the onboarding flow.
  bool get _platformSupported => !kIsWeb && Platform.isAndroid;

  Future<void> _refreshStatuses() async {
    if (!_platformSupported) return;
    final next = <_PermissionGroup, PermissionStatus>{};
    for (final group in _PermissionGroup.values) {
      next[group] = await group.currentStatus();
    }
    if (mounted) {
      setState(() {
        _statuses
          ..clear()
          ..addAll(next);
      });
    }
  }

  Future<void> _requestAll() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    if (_platformSupported) {
      for (final group in _PermissionGroup.values) {
        await group.request();
      }
      await _refreshStatuses();
    }

    if (!mounted) return;
    setState(() => _requesting = false);

    // Advance even if the user denied some — they can re-trigger from the
    // tab that needs the permission. Critical denials (nearby + media) will
    // surface their own prompts in the picker / home screen.
    context.go(RoutePaths.profileSetup);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final allGranted = _statuses.values.every((s) => s.isGranted) &&
        _statuses.length == _PermissionGroup.values.length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: context.pop,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A few permissions',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: AppConstants.space12),
              Text(
                _platformSupported
                    ? 'Karlshare works fully offline. We only ask for what sharing needs.'
                    : "You're previewing on a non-Android platform — these prompts will appear when you install on a phone.",
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppConstants.space32),
              Expanded(
                child: ListView.separated(
                  itemCount: _PermissionGroup.values.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppConstants.space12),
                  itemBuilder: (context, i) {
                    final group = _PermissionGroup.values[i];
                    final status = _statuses[group];
                    return _PermissionTile(
                      group: group,
                      status: status,
                      colors: colors,
                    );
                  },
                ),
              ),
              if (_platformSupported &&
                  _statuses.values.any((s) => s.isPermanentlyDenied))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppConstants.space12),
                  child: TextButton(
                    onPressed: openAppSettings,
                    child: const Text('Open system settings to grant denied permissions'),
                  ),
                ),
              KarlshareButton(
                label: _requesting
                    ? 'Requesting…'
                    : (allGranted ? 'Continue' : 'Allow Permissions'),
                onPressed: _requesting ? null : _requestAll,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.group,
    required this.status,
    required this.colors,
  });

  final _PermissionGroup group;
  final PermissionStatus? status;
  final KarlshareColors colors;

  @override
  Widget build(BuildContext context) {
    final (icon, label, trailingColor) = switch (status) {
      null => (Icons.help_outline_rounded, 'Checking…', colors.textTertiary),
      _ when status!.isGranted => (
          Icons.check_circle_rounded,
          'Granted',
          const Color(0xFF1FBA66),
        ),
      _ when status!.isPermanentlyDenied => (
          Icons.block_rounded,
          'Blocked',
          const Color(0xFFE5483E),
        ),
      _ when status!.isDenied => (
          Icons.radio_button_unchecked_rounded,
          'Not granted',
          colors.textTertiary,
        ),
      _ => (Icons.help_outline_rounded, 'Unknown', colors.textTertiary),
    };

    return Container(
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
            ),
            child: Icon(group.icon, size: 20, color: colors.accent),
          ),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  group.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.space8),
          Row(
            children: [
              Icon(icon, size: 16, color: trailingColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: trailingColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A user-facing bundle of related OS permissions — Karlshare's onboarding
/// asks per-purpose ("Nearby Devices"), not per-Android-permission, so this
/// enum maps each purpose to the actual [Permission]s to request.
enum _PermissionGroup {
  nearby(
    icon: Icons.wifi_tethering_rounded,
    title: 'Nearby Devices',
    description: 'Discover friends running Karlshare around you',
    permissions: [
      Permission.nearbyWifiDevices,
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ],
  ),
  media(
    icon: Icons.perm_media_rounded,
    title: 'Photos, Videos & Music',
    description: 'Show your gallery in the picker so you can send media',
    permissions: [
      Permission.photos,
      Permission.videos,
      Permission.audio,
      Permission.storage,
    ],
  ),
  camera(
    icon: Icons.photo_camera_rounded,
    title: 'Camera',
    description: 'Scan QR codes for instant pairing',
    permissions: [Permission.camera],
  );

  const _PermissionGroup({
    required this.icon,
    required this.title,
    required this.description,
    required this.permissions,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Permission> permissions;

  /// Granted iff *any* of the group's permissions is granted — we only
  /// need one of (photos|videos|audio|storage) to call media access "on,"
  /// for example.
  Future<PermissionStatus> currentStatus() async {
    PermissionStatus? aggregate;
    for (final perm in permissions) {
      final s = await perm.status;
      if (s.isGranted) return s;
      if (s.isPermanentlyDenied) {
        aggregate = s;
      } else {
        aggregate ??= s;
      }
    }
    return aggregate ?? PermissionStatus.denied;
  }

  Future<Map<Permission, PermissionStatus>> request() async {
    return permissions.request();
  }
}
