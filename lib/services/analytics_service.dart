import 'package:flutter/foundation.dart';

/// Abstraction over analytics + crash reporting so the app never hard-depends
/// on Firebase. Karlshare is offline-first; analytics is optional and
/// anonymised (spec §16 "Data Safety").
///
/// v1 ships with [NoopAnalyticsService]. Once a Firebase project +
/// `google-services.json` exist, add the `firebase_core` / `firebase_analytics`
/// / `firebase_crashlytics` packages, apply the Gradle plugins, and drop in a
/// `FirebaseAnalyticsService` implementing this interface — then point
/// `analyticsServiceProvider` at it. Nothing else in the app changes.
///
/// Reference Firebase implementation (enable once the packages are added):
/// ```dart
/// class FirebaseAnalyticsService implements AnalyticsService {
///   FirebaseAnalyticsService(this._analytics, this._crashlytics);
///   final FirebaseAnalytics _analytics;
///   final FirebaseCrashlytics _crashlytics;
///
///   @override
///   Future<void> logEvent(String name, {Map<String, Object>? parameters}) =>
///       _analytics.logEvent(name: name, parameters: parameters);
///
///   @override
///   Future<void> recordError(Object error, StackTrace? stack) =>
///       _crashlytics.recordError(error, stack);
///
///   @override
///   Future<void> setAnalyticsCollectionEnabled(bool enabled) async {
///     await _analytics.setAnalyticsCollectionEnabled(enabled);
///     await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
///   }
/// }
/// ```
abstract class AnalyticsService {
  /// Logs an anonymous usage event. Never include PII or file contents.
  Future<void> logEvent(String name, {Map<String, Object>? parameters});

  /// Reports a non-fatal error for crash analytics.
  Future<void> recordError(Object error, StackTrace? stack);

  /// Honours the user's opt-out — disables collection entirely when false.
  Future<void> setAnalyticsCollectionEnabled(bool enabled);
}

/// Default no-op implementation used until Firebase is configured. In debug
/// builds it echoes events to the console so the instrumentation is testable.
class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    if (kDebugMode) debugPrint('[analytics] $name ${parameters ?? ''}');
  }

  @override
  Future<void> recordError(Object error, StackTrace? stack) async {
    if (kDebugMode) debugPrint('[analytics] error: $error');
  }

  @override
  Future<void> setAnalyticsCollectionEnabled(bool enabled) async {}
}
