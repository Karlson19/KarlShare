import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/karlshare_qr.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../../../providers/user_provider.dart';
import '../../../services/connect_code.dart';
import '../../../services/desktop/desktop_net.dart';
import '../../../services/hotspot_service.dart';
import '../providers/transfer_provider.dart';

/// Receiver side. The phone hosts a hotspot and shows a QR (network + its IP);
/// the PC just shows a QR with its own IP (it's already on the shared network).
/// Either way the sender scans this code and connects straight to the host —
/// no radar, no typing.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  static const int _port = 8988;

  StreamSubscription<HotspotEvent>? _sub;
  String _status = 'Getting ready…';
  String? _ssid;
  String? _password;
  String? _hostIp;
  String? _selfName;
  bool _error = false;
  String? _errorReason;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    _selfName = ref.read(userProfileProvider)?.displayName;
    await startReceiving(ref); // open the listening server on every platform
    final hotspot = ref.read(hotspotServiceProvider);

    if (!hotspot.isPlatformSupported) {
      // Desktop: no hotspot to host. Show a QR with this PC's IP so a phone
      // already on the same network (or this PC's hotspot) can scan + connect.
      await DesktopNet.ensureFirewallRule(_port);
      final ip = await DesktopNet.localIPv4();
      if (!mounted) return;
      setState(() {
        _hostIp = ip;
        _error = ip == null;
        _status = ip == null
            ? "Couldn't find this PC's network address. Connect to a Wi-Fi or a phone's hotspot first."
            : 'Scan this from your phone (Send, then Scan) to send files here.';
      });
      return;
    }

    _sub ??= hotspot.events().listen(_onEvent);

    // Android refuses to host a hotspot without Location: gate on the
    // permission and the system toggle HERE, with fix-it buttons, instead of
    // letting startLocalOnlyHotspot die with a cryptic failure.
    final perm = await Permission.locationWhenInUse.request();
    if (!mounted) return;
    if (!perm.isGranted) {
      setState(() {
        _error = true;
        _errorReason =
            perm.isPermanentlyDenied ? 'permission-settings' : 'permission';
        _status =
            'Karlshare needs Location permission to create the hotspot — an Android rule for all apps.';
      });
      return;
    }
    if (!await hotspot.isLocationEnabled()) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _errorReason = 'location';
        _status =
            'Turn on Location to start the hotspot — Android requires it.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _error = false;
      _errorReason = null;
      _status = 'Starting hotspot…';
    });
    await hotspot.startHotspot();
  }

  void _onEvent(HotspotEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case HotspotEventType.status:
        setState(() => _status = e.message ?? _status);
        break;
      case HotspotEventType.hotspotReady:
        setState(() {
          _ssid = e.ssid;
          _password = e.password;
          _hostIp = (e.hostIp != null && e.hostIp!.isNotEmpty) ? e.hostIp : null;
          _status = 'Have the other phone scan this (Send, then Scan).';
          _error = false;
        });
        break;
      case HotspotEventType.hotspotError:
        setState(() {
          _status = e.message ?? 'Hotspot failed to start.';
          _error = true;
          _errorReason = e.reason;
        });
        break;
      case HotspotEventType.joined:
      case HotspotEventType.joinError:
        break;
    }
  }

  String? get _qrData {
    if (_ssid != null && _password != null) {
      return ConnectCode(
        hostIp: _hostIp,
        port: _port,
        name: _selfName,
        ssid: _ssid,
        password: _password,
      ).encode();
    }
    if (_hostIp != null) {
      return ConnectCode(hostIp: _hostIp, port: _port, name: _selfName).encode();
    }
    return null;
  }

  @override
  void dispose() {
    // Deliberately do NOT stop the hotspot here. This screen is disposed
    // automatically when an incoming transfer navigates away — killing the
    // hotspot at that moment would collapse the network mid-transfer. The
    // session outlives the screen (Xender model): both devices stay connected
    // for repeat sends in either direction. The hotspot ends only when the
    // user explicitly closes this screen, or Android tears it down with the
    // app.
    _sub?.cancel();
    super.dispose();
  }

  void _close() {
    ref.read(hotspotServiceProvider).stopHotspot();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;

    ref.listen<Transfer?>(activeTransferProvider, (prev, next) {
      if (next != null &&
          next.direction == TransferDirection.received &&
          prev == null) {
        context.pushReplacement(RoutePaths.transfer);
      }
    });

    final qr = _qrData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive'),
        leading: IconButton(
            icon: const Icon(Icons.close_rounded), onPressed: _close),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.space24),
          child: Column(
            children: [
              const Spacer(),
              if (qr != null)
                KarlshareQr(data: qr)
              else
                SizedBox(
                  height: 240,
                  child: Center(
                    child: _error
                        ? Icon(Icons.error_outline_rounded,
                            size: 56, color: AppColors.error)
                        : const CircularProgressIndicator(),
                  ),
                ),
              const SizedBox(height: AppConstants.space24),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _error ? AppColors.error : colors.textSecondary,
                    ),
              ),
              if (_ssid != null) ...[
                const SizedBox(height: AppConstants.space8),
                Text('Network: $_ssid',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (_error) ...[
                const SizedBox(height: AppConstants.space12),
                Wrap(
                  spacing: AppConstants.space12,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_errorReason == 'location')
                      FilledButton.icon(
                        onPressed: () => ref
                            .read(hotspotServiceProvider)
                            .openLocationSettings(),
                        icon: const Icon(Icons.location_on_rounded),
                        label: const Text('Turn on Location'),
                      ),
                    if (_errorReason == 'permission-settings')
                      FilledButton.icon(
                        onPressed: openAppSettings,
                        icon: const Icon(Icons.settings_rounded),
                        label: const Text('Open app settings'),
                      ),
                    TextButton.icon(
                      onPressed: _begin,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              Text(
                'Keep this screen open until the transfer finishes.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

