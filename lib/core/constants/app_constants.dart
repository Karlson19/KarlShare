import 'package:flutter/animation.dart';

/// App-wide constants: spacing, radii, animation timings (Sections 3.3–3.8).
class AppConstants {
  AppConstants._();

  static const String appName = 'Karlshare';
  static const String tagline = 'Share. Instantly.';

  // Spacing — 4px grid (Section 3.3)
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;
  static const double space64 = 64;
  static const double space96 = 96;

  // Border radius (Section 3.4)
  static const double radiusSmall = 8;
  static const double radiusMedium = 16;
  static const double radiusLarge = 24;
  static const double radiusPill = 999;

  // Animation durations (Section 3.8)
  static const Duration microInteraction = Duration(milliseconds: 200);
  static const Duration transition = Duration(milliseconds: 400);
  static const Duration heroMoment = Duration(milliseconds: 800);

  // Easing — custom Karlshare curve (Section 3.8)
  static const Cubic easeOutKarlshare = Cubic(0.16, 1, 0.3, 1);

  // Component sizing (Section 3.9)
  static const double buttonHeightPrimary = 56;
  static const double buttonHeightTertiary = 48;
  static const double inputHeight = 56;
  static const double buttonPressScale = 0.96;
}
