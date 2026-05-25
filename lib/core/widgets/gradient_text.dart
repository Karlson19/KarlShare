import 'package:flutter/material.dart';
import '../theme/app_gradients.dart';

/// Renders text filled with the Karlshare signature gradient.
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final Gradient? gradient;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ?? const TextStyle()).copyWith(
      color: Colors.white,
    );
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          (gradient ?? AppGradients.horizontal).createShader(bounds),
      child: Text(text, style: effectiveStyle, textAlign: textAlign),
    );
  }
}
