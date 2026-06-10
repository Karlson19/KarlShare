import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/avatar_presets.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/widgets/karlshare_bottom_sheet.dart';
import '../../../core/widgets/karlshare_button.dart';
import '../../../core/widgets/karlshare_qr.dart';
import '../../../core/widgets/kente_pattern.dart';
import '../../../models/device.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../../../providers/user_provider.dart';
import '../../transfer/providers/receive_info_provider.dart';
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

  late final bool _isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _noneTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _waitedLongEnough = true);
    });
    // Start listening for incoming transfers as soon as the radar is up, so
    // any phone sitting on this screen can receive without tapping anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) startReceiving(ref);
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

  @override
  Widget build(BuildContext context) {
    // An incoming transfer just started — jump to the transfer screen to show
    // it. Wired on every platform so a PC that's passively listening still
    // surfaces the transfer. Keyed on a change of transfer id (not prev == null)
    // so a transfer that arrives right after a previous one finishes still
    // navigates, even while the old, completed transfer is still in state and
    // the success screen is on top.
    ref.listen<Transfer?>(activeTransferProvider, (prev, next) {
      if (next != null &&
          next.direction == TransferDirection.received &&
          next.status == TransferStatus.transferring &&
          prev?.id != next.id) {
        context.push(RoutePaths.transfer);
      }
    });

    return _isDesktop ? _buildDesktop(context) : _buildMobile(context);
  }

  /// Mobile home: the radar people scan with, plus Send / Receive actions.
  Widget _buildMobile(BuildContext context) {
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
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Scan to connect',
            // The working scan flow — connects straight to whatever device's
            // QR you point at (a PC's code or a phone hosting a hotspot).
            onPressed: () => context.push(RoutePaths.sendConnect),
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
              onInvite: () => context.push(RoutePaths.receive),
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
                      onPressed: () {
                        // Choosing recipient by scanning happens after picking
                        // files, so clear any stale radar selection.
                        ref.read(selectedDeviceProvider.notifier).state = null;
                        context.push(RoutePaths.filePicker);
                      },
                    ),
                  ),
                  const SizedBox(width: AppConstants.space16),
                  Expanded(
                    child: KarlshareButton(
                      label: 'Receive',
                      icon: Icons.arrow_downward_rounded,
                      variant: KarlshareButtonVariant.secondary,
                      onPressed: () => context.push(RoutePaths.receive),
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

  /// Desktop home: the PC is a passive receiver. It opens straight to its own
  /// connect-code QR (server + beacon already running), so a phone scans and
  /// sends with zero setup on the PC. A "Send from this PC" list handles the
  /// reverse direction for any phone the beacon has found.
  Widget _buildDesktop(BuildContext context) {
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
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh network address',
            // Re-reads this PC's IP — use it after joining Wi-Fi or switching
            // networks, since the address is otherwise read once at launch.
            onPressed: () => ref.invalidate(desktopConnectCodeProvider),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: KentePattern(opacity: 0.09, cell: 64),
            ),
          ),
          const SafeArea(child: _DesktopHomeBody()),
        ],
      ),
    );
  }
}

/// Merges the last-received device (first, so "send back" is the obvious pick)
/// with live-discovered devices, de-duplicated by IP.
List<Device> _mergeDevices(Device? last, List<Device> discovered) {
  final seen = <String>{};
  final out = <Device>[];
  for (final d in [?last, ...discovered]) {
    final key = d.ipAddress ?? d.address ?? d.id;
    if (key.isEmpty || !seen.add(key)) continue;
    out.add(d);
  }
  return out;
}

/// The desktop home content: connect-code QR up top, "send from this PC" below.
class _DesktopHomeBody extends ConsumerWidget {
  const _DesktopHomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final codeAsync = ref.watch(desktopConnectCodeProvider);
    // Watching the device list keeps the LAN beacon alive (so this PC is also
    // discoverable on a phone's radar) and powers the send-from-PC list. The
    // phone we last received from is included so the user can send back even
    // if live discovery hasn't picked it up.
    final discovered =
        ref.watch(discoveredDevicesProvider).valueOrNull ?? const <Device>[];
    final last = ref.watch(lastReceivedDeviceProvider);
    final devices = _mergeDevices(last, discovered);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppConstants.space8),
          Text(
            'Ready to receive',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppConstants.space4),
          Text(
            'On your phone: open Karlshare, tap Send, choose files, then scan '
            'this code.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppConstants.space8),
          Text(
            "No Wi-Fi? Turn on your phone's hotspot, connect this PC to it, "
            'then tap refresh.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppConstants.space24),
          codeAsync.when(
            loading: () => const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _DesktopNotice(
              icon: Icons.error_outline_rounded,
              message: "Couldn't prepare this PC to receive.\n$e",
              isError: true,
              colors: colors,
              onRetry: () => ref.invalidate(desktopConnectCodeProvider),
            ),
            data: (code) {
              if (code == null || !code.hasAddress) {
                return _DesktopNotice(
                  icon: Icons.wifi_off_rounded,
                  message: "Connect this PC to Wi-Fi (or a phone's hotspot) so "
                      "a phone can reach it, then tap Try again.",
                  isError: false,
                  colors: colors,
                  onRetry: () => ref.invalidate(desktopConnectCodeProvider),
                );
              }
              return Column(
                children: [
                  Center(child: KarlshareQr(data: code.encode())),
                  const SizedBox(height: AppConstants.space16),
                  Text(
                    code.name ?? 'This PC',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppConstants.space4),
                  Text(
                    '${code.hostIp}:${code.port}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppConstants.space32),
          Divider(color: colors.border),
          const SizedBox(height: AppConstants.space16),
          _SendFromPc(
            devices: devices,
            colors: colors,
            onSend: (device) {
              ref.read(selectedDeviceProvider.notifier).state = device;
              context.push(RoutePaths.filePicker);
            },
          ),
        ],
      ),
    );
  }
}

/// A centered icon + message block for the desktop "no network / error" states.
class _DesktopNotice extends StatelessWidget {
  const _DesktopNotice({
    required this.icon,
    required this.message,
    required this.isError,
    required this.colors,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final bool isError;
  final KarlshareColors colors;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 48,
                color: isError ? colors.accent : colors.textTertiary),
            const SizedBox(height: AppConstants.space12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppConstants.space12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lists phones the beacon has found so the PC can push files to them. Tapping
/// one selects it and opens the file picker.
class _SendFromPc extends StatelessWidget {
  const _SendFromPc({
    required this.devices,
    required this.colors,
    required this.onSend,
  });

  final List<Device> devices;
  final KarlshareColors colors;
  final void Function(Device) onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Send from this PC',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppConstants.space8),
        if (devices.isEmpty)
          Text(
            'Phones on the same Wi-Fi appear here. You can also just share the '
            'code above to receive files.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
          )
        else
          ...devices.map(
            (d) => Card(
              margin: const EdgeInsets.only(bottom: AppConstants.space8),
              child: ListTile(
                leading: const Icon(Icons.smartphone_rounded),
                title: Text(d.name),
                subtitle: Text(d.ipAddress ?? d.address ?? ''),
                trailing: const Icon(Icons.arrow_forward_rounded),
                onTap: () => onSend(d),
              ),
            ),
          ),
      ],
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
        deviceCount == 1
            ? 'Tap the device to send it files'
            : 'Tap a device to send it files',
        style: Theme.of(context).textTheme.bodyLarge,
      );
    }
    if (!platformSupported) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.space24),
        child: Text(
          'Install Karlshare on Android or a PC on the same network to share.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    if (waitedLongEnough && scanning) {
      return Column(
        children: [
          Text('No one nearby yet.',
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: AppConstants.space4),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppConstants.space24),
            child: Text(
              "Open Karlshare on the other device, and make sure both are on "
              "the same Wi-Fi — or turn on one phone's hotspot and connect the "
              "other to it.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: AppConstants.space8),
          TextButton.icon(
            onPressed: onInvite,
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('Share over hotspot'),
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
