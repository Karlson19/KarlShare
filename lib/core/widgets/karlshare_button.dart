import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import '../theme/app_gradients.dart';
import '../theme/app_theme.dart';

enum KarlshareButtonVariant { primary, secondary, tertiary }

/// Karlshare button (Section 3.9).
///
/// * Primary keeps the brand gradient — this is the screen's hero CTA.
/// * Secondary now uses a clean accent border (the gradient-ring variant
///   was distracting next to a gradient-filled primary).
/// * Tertiary is a text-style button in the accent color.
/// * 200ms scale-to-0.96 on press.
class KarlshareButton extends StatefulWidget {
  const KarlshareButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = KarlshareButtonVariant.primary,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final KarlshareButtonVariant variant;
  final IconData? icon;
  final bool expand;

  @override
  State<KarlshareButton> createState() => _KarlshareButtonState();
}

class _KarlshareButtonState extends State<KarlshareButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (!_enabled) return;
    if (value) HapticFeedback.lightImpact();
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final isTertiary = widget.variant == KarlshareButtonVariant.tertiary;
    final height = isTertiary
        ? AppConstants.buttonHeightTertiary
        : AppConstants.buttonHeightPrimary;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? AppConstants.buttonPressScale : 1.0,
        duration: AppConstants.microInteraction,
        curve: AppConstants.easeOutKarlshare,
        child: Opacity(
          opacity: _enabled ? 1.0 : 0.4,
          child: SizedBox(
            height: height,
            width: widget.expand ? double.infinity : null,
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;

    switch (widget.variant) {
      case KarlshareButtonVariant.primary:
        return _PrimaryFill(
          colors: colors,
          enabled: _enabled,
          child: _label(Colors.white),
        );
      case KarlshareButtonVariant.secondary:
        return _SecondaryBorder(
          colors: colors,
          child: _label(colors.textPrimary),
        );
      case KarlshareButtonVariant.tertiary:
        return Center(
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                ),
          ),
        );
    }
  }

  Widget _label(Color color) {
    final text = Text(
      widget.label,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
    );
    if (widget.icon == null) return Center(child: text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(widget.icon, color: color, size: 20),
        const SizedBox(width: AppConstants.space8),
        text,
      ],
    );
  }
}

class _PrimaryFill extends StatelessWidget {
  const _PrimaryFill({
    required this.colors,
    required this.enabled,
    required this.child,
  });

  final KarlshareColors colors;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.signature,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class _SecondaryBorder extends StatelessWidget {
  const _SecondaryBorder({required this.colors, required this.child});

  final KarlshareColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      child: Center(child: child),
    );
  }
}
