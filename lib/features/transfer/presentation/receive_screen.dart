import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../../../services/hotspot_service.dart';
import '../providers/transfer_provider.dart';

/// Receiver side of the offline (hotspot) flow: this phone becomes a Wi-Fi
/// hotspot and shows a QR the sender scans to join. Status is shown live so
/// any failure is visible on screen.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  StreamSubscription<HotspotEvent>? _sub;
  String _status = 'Starting hotspot…';
  String? _ssid;
  String? _password;
  bool _error = false;
  bool _ready = false; // desktop: listening, no hotspot to host

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    // Open the listening server on every platform.
    await startReceiving(ref);
    final hotspot = ref.read(hotspotServiceProvider);
    if (!hotspot.isPlatformSupported) {
      // Desktop / non-Android: no app-hosted hotspot. Just be discoverable on
      // the shared network and wait for an incoming transfer.
      if (mounted) {
        setState(() {
          _ready = true;
          _status =
              "Ready to receive. You'll appear on the sender's radar when "
              "they're on the same network. Keep this open.";
        });
      }
      return;
    }
    _sub = hotspot.events().listen(_onEvent);
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
          _status = 'Hotspot ready. Have the sender scan this code.';
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
        break; // joiner-side events
    }
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

    // Jump to the transfer view the moment a file starts arriving.
    ref.listen<Transfer?>(activeTransferProvider, (prev, next) {
      if (next != null &&
          next.direction == TransferDirection.received &&
          prev == null) {
        context.pushReplacement(RoutePaths.transfer);
      }
    });

    final qrData = (_ssid != null && _password != null)
        ? jsonEncode({'k': 'karlshare', 's': _ssid, 'p': _password})
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive'),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: context.pop),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              if (qrData != null)
                _QrCard(data: qrData, colors: colors)
              else
                SizedBox(
                  height: 240,
                  child: Center(
                    child: _error
                        ? Icon(Icons.error_outline_rounded,
                            size: 56, color: AppColors.error)
                        : _ready
                            ? Icon(Icons.wifi_rounded, size: 64, color: colors.accent)
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
                Text(
                  'Network: $_ssid',
                  style: Theme.of(context).textTheme.bodyMedium,
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

class _QrCard extends StatelessWidget {
  const _QrCard({required this.data, required this.colors});

  final String data;
  final KarlshareColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: AppGradients.signature,
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge - 4),
        ),
        child: QrImageView(
          data: data,
          size: 232,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: AppColors.electricPurple,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF15131F),
          ),
        ),
      ),
    );
  }
}
