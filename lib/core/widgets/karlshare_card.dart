import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

/// Surface card. Clean hairline border + soft shadow (light) or hairline
/// only (dark). The gradient-border halo from the original draft proved
/// muddy on small screens and has been retired — gradient now lives only on
/// hero moments (see [AppGradients] policy in `app_gradients.dart`).
class KarlshareCard extends StatelessWidget {
  const KarlshareCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppConstants.space16),
    this.onTap,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// When true, sits on a higher-shadow tier — for cards that should feel
  /// "lifted" against the scaffold. Default cards use the subtle tier.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final radius = BorderRadius.circular(AppConstants.radiusMedium);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: radius,
        border: Border.all(color: colors.border, width: 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: elevated ? colors.shadowStrong : colors.shadow,
                  blurRadius: elevated ? 28 : 16,
                  offset: Offset(0, elevated ? 10 : 4),
                ),
              ],
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: card,
      ),
    );
  }
}
