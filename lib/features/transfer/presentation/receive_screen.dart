import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

    _sub = hotspot.events().listen(_onEvent);
    setState(() => _status = 'Starting hotspot…');
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
    _sub?.cancel();
    ref.read(hotspotServiceProvider).stopHotspot();
    super.dispose();
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
            icon: const Icon(Icons.close_rounded), onPressed: context.pop),
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

