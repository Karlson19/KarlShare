import 'package:flutter/material.dart';

/// Elevation tokens.
///
/// Dark mode (the default) elevates through the warm surface ladder
/// (background → surface → surfaceElevated), NOT through shadows — shadows on
/// near-black read as smudges. These shadow tokens therefore apply to the
/// LIGHT theme; pass the theme's `KarlshareColors.shadow` colors in.
///
/// Scale: card (resting) → raised (hover/drag/sheet) → overlay (dialogs).
class AppShadows {
  AppShadows._();

  static List<BoxShadow> card(Color shadow) => [
        BoxShadow(color: shadow, blurRadius: 12, offset: const Offset(0, 4)),
      ];

  static List<BoxShadow> raised(Color shadowStrong) => [
        BoxShadow(
            color: shadowStrong, blurRadius: 24, offset: const Offset(0, 8)),
      ];

  static List<BoxShadow> overlay(Color shadowStrong) => [
        BoxShadow(
            color: shadowStrong, blurRadius: 40, offset: const Offset(0, 16)),
      ];
}
