import 'package:flutter/material.dart';
import '../theme/app_gradients.dart';

/// Stylized heart-form Sankofa Adinkra mark, filled with the signature
/// gradient. The Karlshare brand symbol (Section 2 / 15). Reused on the
/// splash and transfer-complete burst.
class SankofaMark extends StatelessWidget {
  const SankofaMark({super.key, this.size = 96, this.gradient});

  final double size;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SankofaPainter(gradient ?? AppGradients.signature),
      ),
    );
  }
}

class _SankofaPainter extends CustomPainter {
  _SankofaPainter(this.gradient);

  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fill = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Layer so the inner curl can be punched out with BlendMode.clear.
    canvas.saveLayer(rect, Paint());

    // Heart silhouette built from two top lobes meeting at a bottom point.
    final heart = Path()
      ..moveTo(w * 0.5, h * 0.32)
      ..cubicTo(w * 0.40, h * 0.10, w * 0.04, h * 0.18, w * 0.10, h * 0.46)
      ..cubicTo(w * 0.15, h * 0.70, w * 0.40, h * 0.82, w * 0.5, h * 0.95)
      ..cubicTo(w * 0.60, h * 0.82, w * 0.85, h * 0.70, w * 0.90, h * 0.46)
      ..cubicTo(w * 0.96, h * 0.18, w * 0.60, h * 0.10, w * 0.5, h * 0.32)
      ..close();
    canvas.drawPath(heart, fill);

    // Inner curl punched out, suggesting the Sankofa "return" spiral.
    final curl = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;
    final spiral = Path()
      ..moveTo(w * 0.5, h * 0.40)
      ..cubicTo(w * 0.36, h * 0.40, w * 0.36, h * 0.62, w * 0.52, h * 0.62)
      ..cubicTo(w * 0.64, h * 0.62, w * 0.62, h * 0.48, w * 0.5, h * 0.50);
    canvas.drawPath(spiral, curl);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SankofaPainter oldDelegate) => false;
}
