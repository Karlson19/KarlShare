import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Karlshare gradients.
///
/// **Usage policy (v1 redesign):** the [signature] gradient is reserved for
/// hero moments — primary CTAs, the Sankofa mark, the splash logo, the
/// transfer animation's flowing packets, and the file-picker "Send" summary
/// card. Do NOT use it on chips, badges, list-row borders, toggles, icons,
/// or input borders. The single-color [AppColors.accent] handles those.
class AppGradients {
  AppGradients._();

  /// The signature brand gradient: orange → magenta → purple.
  static const LinearGradient signature = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.karlshareOrange,
      AppColors.royalMagenta,
      AppColors.electricPurple,
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Horizontal variant, used for text shaders so the sweep reads naturally.
  static const LinearGradient horizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      AppColors.karlshareOrange,
      AppColors.royalMagenta,
      AppColors.electricPurple,
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Hero callout backdrop — a quieter twilight wash for sections that want
  /// to feel "branded" without competing with a CTA. Use sparingly (max one
  /// per screen).
  static const LinearGradient heroCallout = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1F1238), Color(0xFF2A1545)],
  );
}
