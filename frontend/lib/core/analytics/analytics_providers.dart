import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_backend.dart';
import 'analytics_consent.dart';
import 'analytics_service.dart';
import 'gated_analytics_service.dart';

export 'analytics_backend.dart' show AnalyticsBackend, analyticsBackendProvider;
export 'analytics_consent.dart';
export 'analytics_service.dart';

/// The app-wide analytics entry point. Call methods directly; they never
/// throw or block:
///
/// ```dart
/// ref.read(analyticsServiceProvider).loginSucceeded(LoginMethod.google);
/// ```
///
/// Gate: Firebase configured (`analyticsBackendProvider` non-null) AND
/// consent granted (`analyticsConsentProvider`) AND the session layer called
/// `setActorType("human")`.
final analyticsServiceProvider = Provider<AnalyticsService>(
  (ref) => GatedAnalyticsService(
    backend: () => ref.read(analyticsBackendProvider),
    consent: () => ref.read(analyticsConsentProvider),
  ),
);
