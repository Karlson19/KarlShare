import 'package:flutter/material.dart';
import '../theme/app_gradients.dart';

/// Circular avatar with a gradient border. Shows initials, or a gradient fill
/// with an optional [icon] when no name is given.
class KarlshareAvatar extends StatelessWidget {
  const KarlshareAvatar({
    super.key,
    this.name,
    this.icon,
    this.size = 56,
    this.borderWidth = 2,
  });

  final String? name;
  final IconData? icon;
  final double size;
  final double borderWidth;

  String get _initials {
    final n = name?.trim() ?? '';
    if (n.isEmpty) return '';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final innerSize = size - borderWidth * 2;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: AppGradients.signature,
        shape: BoxShape.circle,
      ),
      padding: EdgeInsets.all(borderWidth),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: _initials.isNotEmpty
            ? Text(
                _initials,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: innerSize * 0.36,
                    ),
              )
            : ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (b) =>
                    AppGradients.signature.createShader(b),
                child: Icon(
                  icon ?? Icons.person,
                  size: innerSize * 0.5,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
