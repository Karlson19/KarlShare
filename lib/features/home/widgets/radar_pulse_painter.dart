import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Draws 3 concentric gradient rings pulsing outward, each staggered by
/// ~600ms over a 2s cycle (Section 6.3). The signature gradient sweep
/// remains here — the radar IS the brand hero on the home screen, so it
/// gets the full chromatic moment.
class RadarPulsePainter extends CustomPainter {
  RadarPulsePainter({
    required this.progress,
    required this.intensity,
    required this.guideColor,
  });

  /// 0–1 loop position from the driving controller.
  final double progress;

  /// 1.0 normally; raised briefly when connecting to emphasise pulses.
  final double intensity;

  /// Color of the static guide rings — sourced from the theme so it tracks
  /// light vs dark mode (previously hardcoded magenta, which fought the
  /// warm scaffold in light mode).
  final Color guideColor;

  static const _phases = [0.0, 0.3, 0.6];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;

    for (final phase in _phases) {
      final local = (progress + phase) % 1.0;
      final radius = local * maxRadius;
      if (radius <= 0) continue;
      final opacity = (1.0 - local).clamp(0.0, 1.0) * 0.55 * intensity;

      // Opacity is baked into the gradient colors — a Paint.shader ignores
      // Paint.color, so fading has to happen in the stops themselves.
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = SweepGradient(
          colors: [
            AppColors.karlshareOrange.withValues(alpha: opacity),
            AppColors.royalMagenta.withValues(alpha: opacity),
            AppColors.electricPurple.withValues(alpha: opacity),
            AppColors.karlshareOrange.withValues(alpha: opacity),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);

      // Soft fill toward the leading edge.
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = AppColors.accent.withValues(alpha: opacity * 0.04);
      canvas.drawCircle(center, radius, fill);
    }

    // Static guide rings — theme-driven so they read in both modes.
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = guideColor;
    for (final f in [0.4, 0.7, 1.0]) {
      canvas.drawCircle(center, maxRadius * f, guide);
    }
  }

  @override
  bool shouldRepaint(RadarPulsePainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.guideColor != guideColor;
}
