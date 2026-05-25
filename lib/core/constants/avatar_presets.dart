import 'package:flutter/material.dart';

/// 12 preset avatar glyphs (Section 6.2 screen 4 / 15.3).
///
/// Adinkra-style symbols aren't bundled as art, so we stand in with distinct
/// rounded Material glyphs rendered inside the signature gradient ring.
class AvatarPresets {
  AvatarPresets._();

  static const List<IconData> icons = [
    Icons.bolt_rounded,
    Icons.favorite_rounded,
    Icons.star_rounded,
    Icons.local_fire_department_rounded,
    Icons.diamond_rounded,
    Icons.public_rounded,
    Icons.rocket_launch_rounded,
    Icons.auto_awesome_rounded,
    Icons.waves_rounded,
    Icons.eco_rounded,
    Icons.shield_rounded,
    Icons.brightness_5_rounded,
  ];

  static const int count = 12;

  static IconData byIndex(int index) => icons[index % count];
}
