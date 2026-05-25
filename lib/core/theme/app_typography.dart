import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Karlshare type scale (Section 3.2, refined).
///
/// Display: Bricolage Grotesque — modern grotesk with character; closer to
/// Clash Display's spirit than Space Grotesk and still on Google Fonts.
/// Body: Inter. Mono: JetBrains Mono for file sizes and transfer speeds.
class AppTypography {
  AppTypography._();

  static TextStyle _display(double size, FontWeight weight, double spacing) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.05,
      );

  static TextStyle _body(double size, FontWeight weight,
          {double height = 1.5}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, height: height);

  // Display
  static final TextStyle displayLarge = _display(48, FontWeight.w800, -1.5);
  static final TextStyle displayMedium = _display(36, FontWeight.w800, -1.0);

  // Headings
  static final TextStyle heading1 = _display(28, FontWeight.w700, -0.5);
  static final TextStyle heading2 = _body(22, FontWeight.w600, height: 1.2);
  static final TextStyle heading3 = _body(18, FontWeight.w600, height: 1.3);

  // Body
  static final TextStyle bodyLarge = _body(16, FontWeight.normal);
  static final TextStyle bodyRegular = _body(14, FontWeight.normal);
  static final TextStyle caption = _body(12, FontWeight.w500, height: 1.3);
  static final TextStyle overline = _body(11, FontWeight.w600, height: 1.2)
      .copyWith(letterSpacing: 1.4);

  // Mono — file sizes, transfer speeds
  static final TextStyle mono = GoogleFonts.jetBrainsMono(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  /// Builds a Material [TextTheme]. Primary text gets [primary], everything
  /// secondary (body medium, captions, overline) gets [secondary] so we don't
  /// have to thread color overrides through every screen.
  static TextTheme textTheme(Color primary, Color secondary) => TextTheme(
        displayLarge: displayLarge.copyWith(color: primary),
        displayMedium: displayMedium.copyWith(color: primary),
        headlineLarge: heading1.copyWith(color: primary),
        headlineMedium: heading2.copyWith(color: primary),
        headlineSmall: heading3.copyWith(color: primary),
        bodyLarge: bodyLarge.copyWith(color: primary),
        bodyMedium: bodyRegular.copyWith(color: secondary),
        labelLarge: bodyRegular.copyWith(
          color: primary,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: caption.copyWith(color: secondary),
        labelSmall: overline.copyWith(color: secondary),
      ).apply(decoration: TextDecoration.none);
}
