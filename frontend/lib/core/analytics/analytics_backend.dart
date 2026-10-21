import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The raw sink behind the analytics gate (Firebase Analytics in the app, a
/// fake in tests). Only ever receives validated, whitelisted events.
abstract interface class AnalyticsBackend {
  /// Logs one event. [params] contain only `String` / `num` values.
  Future<void> logEvent(String name, Map<String, Object> params);

  /// Turns native collection on/off (also applied at the SDK level so
  /// nothing is uploaded while disabled).
  Future<void> setCollectionEnabled(bool enabled);
}

/// `null` unless Firebase was configured and initialized at bootstrap
/// (`initFirebaseAnalytics`); a null backend makes analytics a no-op.
final analyticsBackendProvider = Provider<AnalyticsBackend?>((ref) => null);
