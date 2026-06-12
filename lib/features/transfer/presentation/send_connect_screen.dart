import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/device.dart';
import '../../../models/enums.dart';
import '../../../services/connect_code.dart';
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
  String? _pendingName;

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
        _connectTo(ip, _pendingName);
        break;
      case HotspotEventType.joinError:
        setState(() {
          // The commonest real-world cause: the host phone opened its hotspot
          // on a 5GHz band this phone can't see. No app can change the band,
          // so give the two fallbacks that actually work.
          _status = "Couldn't reach the hotspot. This phone may not see the "
              "network the other phone created.\n\n"
              "Fix it one of these ways:\n"
              "• Swap roles: YOU tap Receive, and let the other phone scan "
              "your code instead.\n"
              "• Or put both phones on the same Wi-Fi or hotspot — you'll "
              "find each other on the radar, no scanning needed.";
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
    final code = ConnectCode.tryParse(raw);
    if (code == null) return; // not our QR

    // PC / same-network code: just an address — connect straight away, no join.
    if (!code.hasHotspot && code.hasAddress) {
      setState(() {
        _joining = true;
        _error = false;
        _status = 'Connecting…';
      });
      _connectTo(code.hostIp!, code.name);
      return;
    }

    // Phone-hotspot code: auto-join the network first, then connect to its host.
    if (code.hasHotspot) {
      setState(() {
        _joining = true;
        _error = false;
        _pendingHostIp = code.hasAddress ? code.hostIp : null;
        _pendingName = code.name;
        _status =
            'Joining ${code.ssid}… When Android asks to connect, tap Connect.';
      });
      ref
          .read(hotspotServiceProvider)
          .joinHotspot(ssid: code.ssid!, password: code.password!);
    }
  }

  void _connectTo(String ip, String? name) {
    ref.read(selectedDeviceProvider.notifier).state = Device(
      id: ip,
      name: (name != null && name.isNotEmpty) ? name : 'Receiving device',
      status: DeviceStatus.ready,
      address: ip,
      ipAddress: ip,
    );
    if (!mounted) return;
    // Scanned after picking files -> send now. Scanned from home (no files
    // yet) -> connected, go pick what to send to this device.
    final hasFiles = ref.read(selectedFilesProvider).isNotEmpty;
    context.pushReplacement(
        hasFiles ? RoutePaths.transfer : RoutePaths.filePicker);
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
