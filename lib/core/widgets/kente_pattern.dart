import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A subtle, geometric Kente-inspired background texture (Section 3.7).
/// Renders interlocking diagonal blocks at low opacity — used behind splash,
/// empty states and the premium upgrade screen. Not literal Kente cloth.
class KentePattern extends StatelessWidget {
  const KentePattern({
    super.key,
    this.opacity = 0.06,
    this.cell = 48,
  });

  /// 5–8% per the spec.
  final double opacity;

  /// Size of one weave cell in logical pixels.
  final double cell;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(
        size: Size.infinite,
        painter: _KentePainter(cell: cell),
      ),
    );
  }
}

class _KentePainter extends CustomPainter {
  _KentePainter({required this.cell});

  final double cell;

  static const _palette = [
    AppColors.karlshareOrange,
    AppColors.royalMagenta,
    AppColors.electricPurple,
    AppColors.ashantiGold,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final color = _palette[(r + c) % _palette.length];
        final left = c * cell;
        final top = r * cell;
        paint.color = color;

        // Alternate triangle orientation to mimic a handwoven weave.
        final path = Path();
        if ((r + c).isEven) {
          path.moveTo(left, top);
          path.lineTo(left + cell, top);
          path.lineTo(left, top + cell);
        } else {
          path.moveTo(left + cell, top);
          path.lineTo(left + cell, top + cell);
          path.lineTo(left, top + cell);
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_KentePainter oldDelegate) => oldDelegate.cell != cell;
}
