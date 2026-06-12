import 'package:flutter/material.dart';

/// Karlshare color tokens — the "modern Kente" system.
///
/// Identity rules:
/// * DARK IS THE DEFAULT. The base is a near-black with a warm, earthen
///   undertone (#141210 family) — never a cold blue-black. Light mode is the
///   secondary theme: warm paper, true-white cards.
/// * GOLD is the primary. One saturated gold/amber carries every interactive
///   moment (CTAs, tabs, progress, the brand mark). Gold demands DARK
///   foreground text — never white-on-gold.
/// * FOREST GREEN is the single sharp accent, drawn from the Kente palette.
///   It marks success and "receive" energy. Red exists only as semantic
///   error. Nothing else gets a hue: restraint is the brand.
/// * No purple anywhere. The old purple-gradient identity is retired.
class AppColors {
  AppColors._();

  // ---- Brand: gold primary --------------------------------------------------
  /// The primary. Interactive gold — saturated, warm, neither neon nor mustard.
  static const Color gold = Color(0xFFE6A532);

  /// Gradient high / shimmer top. Use inside [AppGradients], not as a fill.
  static const Color goldBright = Color(0xFFF4C159);

  /// Pressed states, and the interactive gold on LIGHT surfaces (plain [gold]
  /// fails contrast on white).
  static const Color goldDeep = Color(0xFFB27C1D);

  // ---- Brand: the one Kente accent ------------------------------------------
  /// Forest green — success, received files, connection-established.
  static const Color forest = Color(0xFF2E9E63);

  /// Forest on light surfaces / pressed.
  static const Color forestDeep = Color(0xFF1E6B43);

  /// Single non-gradient accent used by the Material scheme. Dark theme uses
  /// [gold]; light theme swaps to [goldDeep] for contrast (see AppTheme).
  static const Color accent = gold;

  // ---- Dark mode (DEFAULT): warm near-black ladder ---------------------------
  static const Color darkBackground = Color(0xFF141210);
  static const Color darkSurface = Color(0xFF1B1814);
  static const Color darkSurfaceElevated = Color(0xFF242019);
  static const Color darkBorder = Color(0xFF322C22);
  static const Color darkBorderStrong = Color(0xFF463D2E);
  static const Color darkTextPrimary = Color(0xFFF6F1E6); // warm ivory
  static const Color darkTextSecondary = Color(0xFFA99F8C);
  static const Color darkTextTertiary = Color(0xFF6E6452);

  // ---- Light mode (secondary): warm paper, true-white cards ------------------
  static const Color lightBackground = Color(0xFFFAF6ED);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFFFFFFF);
  static const Color lightSurfaceSunken = Color(0xFFF1EBDE);
  static const Color lightBorder = Color(0xFFE9E2D2);
  static const Color lightBorderStrong = Color(0xFFD4C9B1);
  static const Color lightTextPrimary = Color(0xFF1C170E);
  static const Color lightTextSecondary = Color(0xFF6E6452);
  static const Color lightTextTertiary = Color(0xFFA39A87);

  // ---- Semantic (both modes) -------------------------------------------------
  static const Color success = forest;
  static const Color warning = Color(0xFFE8A317);
  static const Color error = Color(0xFFE5483E);
  static const Color info = Color(0xFF3AA9F0);

  // ---- Legacy aliases (Phase 2 removes the remaining references) -------------
  // These names survive so every existing reference re-skins into the new
  // identity instead of breaking. Do NOT use them in new code.
  static const Color karlshareOrange = gold;
  static const Color royalMagenta = forest;
  static const Color electricPurple = goldDeep;
  static const Color ashantiGold = goldBright;
}
