import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/avatar_presets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/karlshare_avatar.dart';
import '../../../providers/user_provider.dart';
import '../../home/providers/discovery_provider.dart';

/// Section 6.8: Show My Code (QR with gradient frame) and Scan Code (live
/// camera). Scanning a `karlshare://pair/{deviceId}` payload kicks off a
/// WiFi-Direct connect to that peer (via [DiscoveryService.connect]) — the
/// QR is the manual-fallback discovery path from spec §7.4 layer 5.
class QrPairScreen extends ConsumerStatefulWidget {
  const QrPairScreen({super.key});

  @override
  ConsumerState<QrPairScreen> createState() => _QrPairScreenState();
}

class _QrPairScreenState extends ConsumerState<QrPairScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final name = profile?.displayName ?? 'My Phone';
    final avatarIndex = profile?.avatarIndex ?? 0;
    final payload = 'karlshare://pair/${profile?.id ?? "unknown"}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: context.pop,
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Show My Code'),
            Tab(text: 'Scan Code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ShowMyCode(name: name, avatarIndex: avatarIndex, payload: payload),
          const _ScanCode(),
        ],
      ),
    );
  }
}

class _ShowMyCode extends StatelessWidget {
  const _ShowMyCode({
    required this.name,
    required this.avatarIndex,
    required this.payload,
  });

  final String name;
  final int avatarIndex;
  final String payload;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.space24),
      child: Column(
        children: [
          const SizedBox(height: AppConstants.space16),
          KarlshareAvatar(icon: AvatarPresets.byIndex(avatarIndex), size: 72),
          const SizedBox(height: AppConstants.space12),
          Text(name, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppConstants.space4),
          Text(
            'Have a friend point their camera at this code.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppConstants.space24),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: AppGradients.signature,
              borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.25),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(AppConstants.space16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusLarge - 4),
              ),
              child: QrImageView(
                data: payload,
                size: 240,
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
          ),
          const SizedBox(height: AppConstants.space24),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space16,
              vertical: AppConstants.space8,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              border: Border.all(color: colors.border, width: 1),
            ),
            child: Text(
              payload,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanCode extends ConsumerStatefulWidget {
  const _ScanCode();

  @override
  ConsumerState<_ScanCode> createState() => _ScanCodeState();
}

class _ScanCodeState extends ConsumerState<_ScanCode> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _scannerError;

  static final _payloadRegex =
      RegExp(r'^karlshare://pair/([0-9a-fA-F-]{6,})/?$');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    for (final code in capture.barcodes) {
      final value = code.rawValue;
      if (value == null) continue;
      final match = _payloadRegex.firstMatch(value.trim());
      if (match == null) continue;
      _handled = true;
      final deviceId = match.group(1)!;
      await _controller.stop();
      // Fire-and-forget connect — by the time the user gets to the picker,
      // group formation will (hopefully) have completed and the peer IP
      // will be on the device.
      await ref.read(discoveryServiceProvider).connect(deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connecting to ${deviceId.substring(0, 6)}…')),
      );
      Navigator.of(context).maybePop();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Padding(
      padding: const EdgeInsets.all(AppConstants.space24),
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusLarge),
                child: Container(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error, _) {
                          _scannerError = error.errorDetails?.message ??
                              error.errorCode.name;
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppConstants.space16),
                              child: Text(
                                "Camera unavailable\n($_scannerError)",
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          );
                        },
                      ),
                      const Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.all(AppConstants.space24),
                          child: CustomPaint(painter: _ScanFramePainter()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.space16),
          Text(
            'Align the QR code within the frame',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppConstants.space8),
          Text(
            "We'll auto-connect when we see a Karlshare code.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cornerLen = 32.0;
    final paint = Paint()
      ..shader = AppGradients.signature.createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset.zero, const Offset(cornerLen, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, cornerLen), paint);
    // Top-right
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width - cornerLen, 0), paint);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, cornerLen), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, size.height),
        Offset(cornerLen, size.height), paint);
    canvas.drawLine(Offset(0, size.height),
        Offset(0, size.height - cornerLen), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - cornerLen, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - cornerLen), paint);
  }

  @override
  bool shouldRepaint(_ScanFramePainter oldDelegate) => false;
}
