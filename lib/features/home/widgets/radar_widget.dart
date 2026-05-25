import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/karlshare_avatar.dart';
import '../../../models/device.dart';
import 'device_avatar.dart';
import 'radar_pulse_painter.dart';

/// The home-screen radar: pulsing rings, the user at the centre, and
/// discovered devices floating around (Section 6.3).
class RadarWidget extends StatefulWidget {
  const RadarWidget({
    super.key,
    required this.devices,
    required this.onDeviceTap,
    this.centerIcon,
    this.intensity = 1.0,
  });

  final List<Device> devices;
  final void Function(Device) onDeviceTap;
  final IconData? centerIcon;
  final double intensity;

  @override
  State<RadarWidget> createState() => _RadarWidgetState();
}

class _RadarWidgetState extends State<RadarWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final guideColor = colors.border.withValues(alpha: 0.6);
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = math.min(constraints.maxWidth, constraints.maxHeight);
          final center = size / 2;
          const avatarHalf = 26.0;
          final maxRadius = center - avatarHalf - 8;

          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Pulsing rings
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    size: Size(size, size),
                    painter: RadarPulsePainter(
                      progress: _controller.value,
                      intensity: widget.intensity,
                      guideColor: guideColor,
                    ),
                  ),
                ),
                // Devices around the radar
                for (final device in widget.devices)
                  Positioned(
                    left: center +
                        math.cos(device.angle) * device.distance * maxRadius -
                        avatarHalf,
                    top: center +
                        math.sin(device.angle) * device.distance * maxRadius -
                        avatarHalf,
                    child: DeviceAvatar(
                      device: device,
                      onTap: () => widget.onDeviceTap(device),
                    ),
                  ),
                // User at the centre
                KarlshareAvatar(
                  icon: widget.centerIcon ?? Icons.person,
                  size: 72,
                  borderWidth: 2,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
