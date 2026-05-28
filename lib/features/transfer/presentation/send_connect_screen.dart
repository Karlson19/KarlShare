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
  String? _pendingHostIp;

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
        // Prefer the host IP from the QR; fall back to the network gateway.
        final ip = (_pendingHostIp != null && _pendingHostIp!.isNotEmpty)
            ? _pendingHostIp!
            : e.gatewayIp;
        if (ip == null || ip.isEmpty) {
          setState(() {
            _status = "Joined, but couldn't find the other device. Try again.";
            _error = true;
            _joining = false;
          });
          return;
        }
        _connectTo(ip);
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
    final hostIp = data['h'] as String?;

    // PC / same-network code: just an address — connect straight away, no join.
    if ((ssid == null || pass == null) && hostIp != null && hostIp.isNotEmpty) {
      setState(() {
        _joining = true;
        _error = false;
        _status = 'Connecting…';
      });
      _connectTo(hostIp);
      return;
    }

    // Phone-hotspot code: auto-join the network first, then connect to its host.
    if (ssid != null && pass != null) {
      setState(() {
        _joining = true;
        _error = false;
        _pendingHostIp = (hostIp != null && hostIp.isNotEmpty) ? hostIp : null;
        _status = 'Joining $ssid…';
      });
      ref.read(hotspotServiceProvider).joinHotspot(ssid: ssid, password: pass);
    }
  }

  void _connectTo(String ip) {
    ref.read(selectedDeviceProvider.notifier).state = Device(
      id: ip,
      name: 'Receiving device',
      status: DeviceStatus.ready,
      address: ip,
      ipAddress: ip,
    );
    if (mounted) context.pushReplacement(RoutePaths.transfer);
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
