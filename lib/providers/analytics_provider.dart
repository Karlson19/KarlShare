import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/analytics_service.dart';
import 'theme_provider.dart' show sharedPreferencesProvider;

const _analyticsKey = 'analytics_enabled';

/// The active analytics backend. Swap this for a FirebaseAnalyticsService once
/// Firebase is configured (see `analytics_service.dart`).
final analyticsServiceProvider =
    Provider<AnalyticsService>((ref) => const NoopAnalyticsService());

/// User's analytics opt-in state, persisted and defaulting to on. The toggle
/// lives in Settings ▸ Privacy; flipping it also tells the backend to stop
/// collecting immediately.
class AnalyticsEnabledNotifier extends StateNotifier<bool> {
  AnalyticsEnabledNotifier(this._prefs, this._service)
      : super(_prefs.getBool(_analyticsKey) ?? true) {
    // Reconcile the backend with the persisted preference on startup.
    _service.setAnalyticsCollectionEnabled(state);
  }

  final SharedPreferences _prefs;
  final AnalyticsService _service;

  Future<void> set(bool enabled) async {
    state = enabled;
    await _prefs.setBool(_analyticsKey, enabled);
    await _service.setAnalyticsCollectionEnabled(enabled);
  }
}

final analyticsEnabledProvider =
    StateNotifierProvider<AnalyticsEnabledNotifier, bool>((ref) {
  return AnalyticsEnabledNotifier(
    ref.watch(sharedPreferencesProvider),
    ref.watch(analyticsServiceProvider),
  );
});
