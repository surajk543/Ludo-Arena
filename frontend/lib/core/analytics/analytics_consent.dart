import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_store.dart';
import 'analytics_backend.dart';

/// The user's analytics choice. Analytics is opt-in: [unknown] behaves like
/// [denied] until the user grants consent.
enum AnalyticsConsent {
  unknown,
  granted,
  denied;

  static AnalyticsConsent parse(String? raw) => switch (raw) {
    'granted' => granted,
    'denied' => denied,
    _ => unknown,
  };
}

/// Persisted consent. Granting enables native collection; withdrawing
/// disables it immediately (`setAnalyticsCollectionEnabled(false)`) and the
/// denial survives restarts (bootstrap initializes Firebase with collection
/// off unless consent was granted).
class AnalyticsConsentController extends Notifier<AnalyticsConsent> {
  @override
  AnalyticsConsent build() => readPersisted(ref.read(preferencesStoreProvider));

  /// Reads the stored choice without a container (used by bootstrap before
  /// Firebase is initialized).
  static AnalyticsConsent readPersisted(PreferencesStore prefs) =>
      AnalyticsConsent.parse(prefs.getString(PrefKeys.analyticsConsent));

  bool get isGranted => state == AnalyticsConsent.granted;

  Future<void> grant() => _set(AnalyticsConsent.granted);

  Future<void> deny() => _set(AnalyticsConsent.denied);

  Future<void> _set(AnalyticsConsent value) async {
    // State first: the gate closes synchronously, before any await.
    state = value;
    final enabled = value == AnalyticsConsent.granted;
    try {
      await ref
          .read(preferencesStoreProvider)
          .setString(PrefKeys.analyticsConsent, value.name);
    } catch (e) {
      if (kDebugMode) debugPrint('analytics: consent not persisted ($e)');
    }
    try {
      await ref.read(analyticsBackendProvider)?.setCollectionEnabled(enabled);
    } catch (e) {
      if (kDebugMode) debugPrint('analytics: collection toggle failed ($e)');
    }
  }
}

final analyticsConsentProvider =
    NotifierProvider<AnalyticsConsentController, AnalyticsConsent>(
      AnalyticsConsentController.new,
    );
