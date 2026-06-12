import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Karlshare gradients — the gold "ember" sweep.
///
/// **Usage policy:** [signature] is reserved for hero moments — the primary
/// CTA, the brand mark, the splash logo, the transfer animation's flowing
/// packets, and the file-picker Send bar. Never on chips, badges, list-row
/// borders, toggles, icons, or input borders; the flat gold accent handles
/// those. One gradient moment per screen, maximum.
class AppGradients {
  AppGradients._();

  /// The signature brand gradient: bright gold → gold → deep gold. Reads as
  /// embers/woven metal thread, not as a "colorful app" rainbow.
  static const LinearGradient signature = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.goldBright,
      AppColors.gold,
      AppColors.goldDeep,
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Horizontal variant, used for text shaders so the sweep reads naturally.
  static const LinearGradient horizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      AppColors.goldBright,
      AppColors.gold,
      AppColors.goldDeep,
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Hero callout backdrop — a quiet warm-dark wash for sections that want to
  /// feel "branded" without competing with a CTA. Max one per screen.
  static const LinearGradient heroCallout = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF221C12), Color(0xFF2C2415)],
  );
}
