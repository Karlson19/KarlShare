import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Drives a stream of file "packets" flowing along a Bézier path from sender
/// to receiver. Each packet leaves a fading gradient trail (Section 6.5).
class FileParticlePainter extends CustomPainter {
  FileParticlePainter({
    required this.t,
    required this.particles,
    required this.reversed,
  });

  /// Repeats 0–1 — used to position particles along their path.
  final double t;
  final List<FileParticle> particles;
  final bool reversed;

  // Particle budget capped per Section 16 (low-end perf guardrail).
  static const int maxParticles = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Offset(size.width * 0.12, size.height * 0.5);
    final p2 = Offset(size.width * 0.88, size.height * 0.5);
    final control1 = Offset(size.width * 0.35, size.height * 0.15);
    final control2 = Offset(size.width * 0.65, size.height * 0.85);

    Offset along(double f) {
      final u = 1 - f;
      return p1 * (u * u * u) +
          control1 * (3 * u * u * f) +
          control2 * (3 * u * f * f) +
          p2 * (f * f * f);
    }

    final shown = particles.take(maxParticles);
    for (final particle in shown) {
      var local = (t + particle.phase) % 1.0;
      if (reversed) local = 1.0 - local;

      // Trail: 12 fading echo dots behind the head.
      const trailLen = 12;
      for (var i = 0; i < trailLen; i++) {
        final back = (local - i * 0.018 * (reversed ? -1 : 1));
        if (back < 0 || back > 1) continue;
        final pos = along(back);
        final fade = 1.0 - i / trailLen;
        final paint = Paint()
          ..color = particle.color.withValues(alpha: 0.18 * fade)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, 3.0 * fade, paint);
      }

      // Head: a small chip with the file glyph.
      final head = along(local);
      final chip = Paint()
        ..color = particle.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(head, 10, chip);

      final glyphPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: String.fromCharCode(particle.icon.codePoint),
          style: TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontFamily: particle.icon.fontFamily,
            package: particle.icon.fontPackage,
          ),
        ),
      )..layout();
      glyphPainter.paint(
        canvas,
        head - Offset(glyphPainter.width / 2, glyphPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(FileParticlePainter old) =>
      old.t != t || old.particles != particles || old.reversed != reversed;
}

class FileParticle {
  const FileParticle({
    required this.icon,
    required this.color,
    required this.phase,
  });

  final IconData icon;
  final Color color;

  /// 0–1 offset along the animation cycle, so packets don't overlap.
  final double phase;

  static List<FileParticle> generate({
    required int count,
    required List<IconData> icons,
    int seed = 0,
  }) {
    final rnd = math.Random(seed);
    const palette = [
      AppColors.karlshareOrange,
      AppColors.royalMagenta,
      AppColors.electricPurple,
      AppColors.ashantiGold,
    ];
    return List.generate(count, (i) {
      return FileParticle(
        icon: icons[i % icons.length],
        color: palette[i % palette.length],
        phase: i / count + rnd.nextDouble() * 0.05,
      );
    });
  }
}
