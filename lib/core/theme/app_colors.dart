import 'package:flutter/material.dart';

/// Karlshare color palette (Section 3.1, refined).
///
/// Tuning notes from the v1 redesign:
/// * Light background shifted off pure white to a warm cream (#FAF8F5) so
///   surfaces can elevate with real depth. Cards stay true white.
/// * Dark surface ladder lifted and widened (#0D0D0F / #161618 / #1E1E22)
///   so cards visibly sit above the scaffold without needing a gradient
///   border halo.
/// * Electric purple is the single UI accent (tabs, active states, links).
///   The full signature gradient is reserved for hero moments (CTAs, brand
///   mark, transfer animation) — see [AppGradients] policy.
class AppColors {
  AppColors._();

  // Primary brand colors
  static const Color karlshareOrange = Color(0xFFFF6B1A);
  static const Color royalMagenta = Color(0xFFD81E5B);
  static const Color electricPurple = Color(0xFF7B2CBF);
  static const Color ashantiGold = Color(0xFFFFB627);

  /// Single non-gradient accent. Deep, premium, less abrasive than magenta
  /// when sitting on a white background.
  static const Color accent = Color(0xFF6B21D9);

  // Dark mode (lifted ladder for better elevation)
  static const Color darkBackground = Color(0xFF0D0D0F);
  static const Color darkSurface = Color(0xFF161618);
  static const Color darkSurfaceElevated = Color(0xFF1E1E22);
  static const Color darkBorder = Color(0xFF2A2A2E);
  static const Color darkBorderStrong = Color(0xFF3A3A40);
  static const Color darkTextPrimary = Color(0xFFF5F4F1);
  static const Color darkTextSecondary = Color(0xFF9A9AA0);
  static const Color darkTextTertiary = Color(0xFF5A5A60);

  // Light mode (warm cream scaffold, true-white cards)
  static const Color lightBackground = Color(0xFFFAF8F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFFFFFFF);
  static const Color lightSurfaceSunken = Color(0xFFF2EFEA);
  static const Color lightBorder = Color(0xFFEBEAE7);
  static const Color lightBorderStrong = Color(0xFFD7D4CE);
  static const Color lightTextPrimary = Color(0xFF15131F);
  static const Color lightTextSecondary = Color(0xFF6B6776);
  static const Color lightTextTertiary = Color(0xFFA09BAA);

  // Semantic (both modes)
  static const Color success = Color(0xFF1FBA66);
  static const Color warning = Color(0xFFE8A317);
  static const Color error = Color(0xFFE5483E);
  static const Color info = Color(0xFF3AA9F0);
}
