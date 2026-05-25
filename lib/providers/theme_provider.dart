import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides the [SharedPreferences] instance. Overridden in main() once loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main() with the loaded instance'),
);

const _themeModeKey = 'theme_mode';

/// Holds the user's selected [ThemeMode], persisted to SharedPreferences.
/// Defaults to system (Auto) on first launch so the app matches each phone's
/// own light/dark setting. A user's explicit choice is always remembered.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static ThemeMode _load(SharedPreferences prefs) {
    final stored = prefs.getString(_themeModeKey);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_themeModeKey, mode.name);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(sharedPreferencesProvider));
});
