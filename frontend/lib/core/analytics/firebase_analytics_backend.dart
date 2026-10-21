import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics_backend.dart';

/// [AnalyticsBackend] on top of Firebase Analytics. This is the ONLY Firebase
/// product the app uses (no Auth, Firestore, Remote Config or Functions).
class FirebaseAnalyticsBackend implements AnalyticsBackend {
  FirebaseAnalyticsBackend(this._analytics);

  final FirebaseAnalytics _analytics;

  @override
  Future<void> logEvent(String name, Map<String, Object> params) => _analytics
      .logEvent(name: name, parameters: params.isEmpty ? null : params);

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    await _analytics.setAnalyticsCollectionEnabled(enabled);
    try {
      // Consent mode: analytics storage follows the user's choice; ads-related
      // signals are never granted (the app has no ads).
      await _analytics.setConsent(
        analyticsStorageConsentGranted: enabled,
        adStorageConsentGranted: false,
        adUserDataConsentGranted: false,
        adPersonalizationSignalsConsentGranted: false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('analytics: setConsent failed ($e)');
    }
  }
}
