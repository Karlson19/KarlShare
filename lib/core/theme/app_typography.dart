import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Karlshare type scale.
///
/// Pairing rationale:
/// * Display — **Bricolage Grotesque**: a grotesk with visible personality
///   (ink traps, tight apertures) that reads "designed", not "defaulted".
///   It owns headlines and hero numbers. Chosen over Space Grotesk for more
///   character at large sizes, and it ships on Google Fonts.
/// * Body — **Inter**: the most legible UI workhorse at small sizes; its
///   neutrality lets the display face and the gold palette carry the brand.
/// * Numerals — **JetBrains Mono**: tabular figures, so live-updating speeds
///   and counters never jitter in width mid-transfer. Big stats are the
///   product's jewelry; they get their own scale below.
/// No Roboto, no system defaults, anywhere.
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

  // Stats — the big, beautiful numerals (aggregate speed, files done, totals).
  // Monospaced so a value ticking from 9.9 to 10.0 MB/s never shifts layout.
  static final TextStyle statLarge = GoogleFonts.jetBrainsMono(
    fontSize: 44,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: -1.0,
  );
  static final TextStyle statMedium = GoogleFonts.jetBrainsMono(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: -0.5,
  );
  static final TextStyle statSmall = GoogleFonts.jetBrainsMono(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.1,
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
