import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

/// Karlshare bottom sheet: 24px top radius, centered drag handle, and a
/// spring present animation (Section 3.9).
class KarlshareBottomSheet extends StatelessWidget {
  const KarlshareBottomSheet({super.key, required this.child});

  final Widget child;

  /// Presents [builder] as a Karlshare-styled modal bottom sheet.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => KarlshareBottomSheet(child: builder(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusLarge),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppConstants.space8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary,
                  borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppConstants.space24),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
