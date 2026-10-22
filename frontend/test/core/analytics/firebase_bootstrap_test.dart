import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/analytics/analytics_consent.dart';
import 'package:ludo_arena/core/analytics/firebase_bootstrap.dart';
import 'package:ludo_arena/core/config/app_config.dart';
import 'package:ludo_arena/core/config/app_info.dart';

void main() {
  const info = AppInfo(platform: 'android', version: '1.0.0', build: 1);

  test(
    'no Firebase config → null backend (no-op), Firebase untouched',
    () async {
      const config = AppConfig(
        apiBaseUrl: 'http://localhost:8080',
        environment: AppEnvironment.development,
      );
      final backend = await initFirebaseAnalytics(
        config: config,
        info: info,
        consent: AnalyticsConsent.granted,
      );
      expect(backend, isNull);
    },
  );

  test('missing API key or placeholder → null backend', () async {
    for (final key in ['', 'REPLACE_WITH_ANDROID_API_KEY']) {
      final config = AppConfig(
        apiBaseUrl: 'http://localhost:8080',
        environment: AppEnvironment.development,
        firebase: FirebaseAnalyticsConfig(
          apiKey: key,
          projectId: FirebaseAnalyticsConfig.defaultProjectId,
          messagingSenderId: FirebaseAnalyticsConfig.defaultMessagingSenderId,
          androidAppId: FirebaseAnalyticsConfig.defaultAndroidAppId,
          iosAppId: FirebaseAnalyticsConfig.defaultIosAppId,
        ),
      );
      expect(config.firebase!.isCompleteFor('android'), isFalse);
      expect(
        await initFirebaseAnalytics(
          config: config,
          info: info,
          consent: AnalyticsConsent.granted,
        ),
        isNull,
      );
    }
  });
}
