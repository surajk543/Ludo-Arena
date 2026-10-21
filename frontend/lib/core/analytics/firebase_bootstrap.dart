import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../config/app_info.dart';
import 'analytics_backend.dart';
import 'analytics_consent.dart';
import 'firebase_analytics_backend.dart';

/// Initializes Firebase **for Analytics only** from Dart options supplied via
/// `--dart-define-from-file=config/firebase.json`.
///
/// Returns `null` (analytics becomes a no-op) when the config is incomplete
/// or initialization fails; never throws. Native collection starts disabled
/// (AndroidManifest / Info.plist defaults) and is enabled here only when the
/// user already granted consent.
Future<AnalyticsBackend?> initFirebaseAnalytics({
  required AppConfig config,
  required AppInfo info,
  required AnalyticsConsent consent,
  Duration timeout = const Duration(seconds: 6),
}) async {
  final fb = config.firebase;
  if (fb == null || !fb.isCompleteFor(info.platform)) return null;
  try {
    final app = Firebase.apps.isNotEmpty
        ? Firebase.app()
        : await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: fb.apiKeyFor(info.platform),
              appId: fb.appIdFor(info.platform),
              messagingSenderId: fb.messagingSenderId,
              projectId: fb.projectId,
              storageBucket: fb.storageBucket.isEmpty ? null : fb.storageBucket,
              iosBundleId: info.isIOS ? 'com.ludoroyale.app' : null,
            ),
          ).timeout(timeout);
    final backend = FirebaseAnalyticsBackend(
      FirebaseAnalytics.instanceFor(app: app),
    );
    await backend
        .setCollectionEnabled(consent == AnalyticsConsent.granted)
        .timeout(timeout);
    return backend;
  } catch (e) {
    if (kDebugMode) debugPrint('analytics: Firebase unavailable ($e)');
    return null;
  }
}
