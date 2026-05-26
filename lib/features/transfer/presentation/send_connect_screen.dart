import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/device.dart';
import '../../../models/enums.dart';
import '../../../services/hotspot_service.dart';
import '../providers/transfer_provider.dart';

/// Sender side of the offline (hotspot) flow: scan the receiver's QR, join its
/// hotspot, then hand off to the transfer screen. Status is shown live.
class SendConnectScreen extends ConsumerStatefulWidget {
  const SendConnectScreen({super.key});

  @override
  ConsumerState<SendConnectScreen> createState() => _SendConnectScreenState();
}

class _SendConnectScreenState extends ConsumerState<SendConnectScreen> {
  StreamSubscription<HotspotEvent>? _sub;
  bool _joining = false;
  bool _error = false;
  String _status = 'Point your camera at the receiver’s QR code.';

  @override
  void initState() {
    super.initState();
    final hotspot = ref.read(hotspotServiceProvider);
    if (hotspot.isPlatformSupported) {
      _sub = hotspot.events().listen(_onEvent);
    }
  }

  void _onEvent(HotspotEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case HotspotEventType.status:
        setState(() => _status = e.message ?? _status);
        break;
      case HotspotEventType.joined:
        final ip = e.gatewayIp;
        if (ip == null || ip.isEmpty) return;
        ref.read(selectedDeviceProvider.notifier).state = Device(
          id: ip,
          name: 'Receiving device',
          status: DeviceStatus.ready,
          address: ip,
          ipAddress: ip,
        );
        if (mounted) context.pushReplacement(RoutePaths.transfer);
        break;
      case HotspotEventType.joinError:
        setState(() {
          _status = e.message ?? 'Could not join. Try scanning again.';
          _error = true;
          _joining = false;
        });
        break;
      case HotspotEventType.hotspotReady:
      case HotspotEventType.hotspotError:
        break; // host-side events
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_joining) return;
    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null) return;
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return; // not our QR
    }
    if (data['k'] != 'karlshare') return;
    final ssid = data['s'] as String?;
    final pass = data['p'] as String?;
    if (ssid == null || pass == null) return;

    setState(() {
      _joining = true;
      _error = false;
      _status = 'Joining $ssid…';
    });
    ref.read(hotspotServiceProvider).joinHotspot(ssid: ssid, password: pass);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan to connect'),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: context.pop),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_joining)
            MobileScanner(onDetect: _onDetect)
          else
            Container(color: AppColors.darkBackground),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.space24),
              color: Colors.black.withValues(alpha: 0.55),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_joining && !_error)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppConstants.space12),
                      child: CircularProgressIndicator(),
                    ),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error ? AppColors.error : Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  if (_error) ...[
                    const SizedBox(height: AppConstants.space12),
                    TextButton(
                      onPressed: () => setState(() {
                        _joining = false;
                        _error = false;
                        _status = 'Point your camera at the receiver’s QR code.';
                      }),
                      child: const Text('Scan again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
