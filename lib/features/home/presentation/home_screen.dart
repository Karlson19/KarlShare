import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/avatar_presets.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/widgets/karlshare_avatar.dart';
import '../../../core/widgets/karlshare_bottom_sheet.dart';
import '../../../core/widgets/karlshare_button.dart';
import '../../../core/widgets/kente_pattern.dart';
import '../../../models/device.dart';
import '../../../providers/user_provider.dart';
import '../../transfer/providers/transfer_provider.dart';
import '../providers/discovery_provider.dart';
import '../widgets/device_detail_sheet.dart';
import '../widgets/radar_widget.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _noneTimer;
  bool _waitedLongEnough = false;

  @override
  void initState() {
    super.initState();
    _noneTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _waitedLongEnough = true);
    });
  }

  @override
  void dispose() {
    _noneTimer?.cancel();
    super.dispose();
  }

  void _openDevice(Device device) {
    HapticFeedback.selectionClick();
    KarlshareBottomSheet.show(
      context: context,
      builder: (_) => DeviceDetailSheet(device: device),
    );
  }

  Future<void> _openReceive(String name) async {
    // Become Group Owner + open the TCP server so a sender can dial in.
    await ref.read(discoveryServiceProvider).createGroup();
    await startReceiving(ref);

    if (!mounted) return;
    KarlshareBottomSheet.show(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KarlshareAvatar(name: name, size: 72),
          const SizedBox(height: AppConstants.space16),
          Text('Ready to receive',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppConstants.space8),
          Text(
            "You're discoverable as \"$name\". Ask a nearby friend to send.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.space24),
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: AppConstants.space24),
        ],
      ),
    ).whenComplete(() async {
      // Stop listening when the sheet is dismissed.
      await stopReceiving(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final scanning = ref.watch(isScanningProvider);
    final devicesAsync = ref.watch(discoveredDevicesProvider);
    final devices = devicesAsync.valueOrNull ?? const <Device>[];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => context.push(RoutePaths.settings),
        ),
        title: GradientText(
          AppConstants.appName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            onPressed: () => context.push(RoutePaths.qrPair),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Kente weave watermark behind the radar so the brand DNA is present
          // on the screen people spend the most time on.
          const Positioned.fill(
            child: IgnorePointer(
              child: KentePattern(opacity: 0.09, cell: 64),
            ),
          ),
          SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.space24),
                child: RadarWidget(
                  devices: devices,
                  onDeviceTap: _openDevice,
                  centerIcon: AvatarPresets.byIndex(profile?.avatarIndex ?? 0),
                ),
              ),
            ),
            _StatusLine(
              scanning: scanning,
              deviceCount: devices.length,
              waitedLongEnough: _waitedLongEnough,
              platformSupported:
                  ref.watch(discoveryServiceProvider).isPlatformSupported,
              onInvite: () => context.push(RoutePaths.qrPair),
            ),
            const SizedBox(height: AppConstants.space24),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space24,
                0,
                AppConstants.space24,
                AppConstants.space24,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: KarlshareButton(
                      label: 'Send',
                      icon: Icons.arrow_upward_rounded,
                      onPressed: () => context.push(RoutePaths.filePicker),
                    ),
                  ),
                  const SizedBox(width: AppConstants.space16),
                  Expanded(
                    child: KarlshareButton(
                      label: 'Receive',
                      icon: Icons.arrow_downward_rounded,
                      variant: KarlshareButtonVariant.secondary,
                      onPressed: () =>
                          _openReceive(profile?.displayName ?? 'My Phone'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.scanning,
    required this.deviceCount,
    required this.waitedLongEnough,
    required this.platformSupported,
    required this.onInvite,
  });

  final bool scanning;
  final int deviceCount;
  final bool waitedLongEnough;
  final bool platformSupported;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    if (deviceCount > 0) {
      return Text(
        '$deviceCount ${deviceCount == 1 ? "device" : "devices"} nearby',
        style: Theme.of(context).textTheme.bodyLarge,
      );
    }
    if (!platformSupported) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.space24),
        child: Text(
          'Karlshare uses WiFi Direct — install on an Android device to scan for peers.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    if (waitedLongEnough && scanning) {
      return Column(
        children: [
          Text('No one nearby.',
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: AppConstants.space8),
          TextButton.icon(
            onPressed: onInvite,
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('Invite a friend'),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppConstants.space12),
        Text('Looking for nearby devices…',
            style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}
