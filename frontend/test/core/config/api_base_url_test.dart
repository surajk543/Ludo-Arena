import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/config/app_config.dart';

void main() {
  test('production builds default to the production backend', () {
    for (final android in [true, false]) {
      expect(
        AppConfig.defaultApiBaseUrl(
          AppEnvironment.production,
          android: android,
        ),
        'https://ludo.sungamestudio.com',
      );
    }
  });

  test('other environments default to the local backend', () {
    for (final env in [
      AppEnvironment.development,
      AppEnvironment.preproduction,
    ]) {
      expect(
        AppConfig.defaultApiBaseUrl(env, android: true),
        'http://10.0.2.2:8080',
      );
      expect(
        AppConfig.defaultApiBaseUrl(env, android: false),
        'http://localhost:8080',
      );
    }
  });

  test('production builds offer Sign in with Apple on Android', () {
    const env = AppEnvironment.production;
    expect(AppConfig.defaultAppleServiceId(env), 'com.ludoroyale.app.signin');
    expect(
      AppConfig.defaultAppleRedirectUri(env),
      'https://ludo.sungamestudio.com/api/v1/auth/apple/callback',
    );
    final config = AppConfig(
      apiBaseUrl: AppConfig.productionApiBaseUrl,
      environment: env,
      appleServiceId: AppConfig.defaultAppleServiceId(env),
      appleRedirectUri: AppConfig.defaultAppleRedirectUri(env),
    );
    expect(config.appleEnabledFor('android'), isTrue);
    expect(config.appleEnabledFor('ios'), isTrue);
    // Elsewhere Apple on Android needs explicit dart-defines.
    expect(AppConfig.defaultAppleServiceId(AppEnvironment.development), '');
    expect(AppConfig.defaultAppleRedirectUri(AppEnvironment.development), '');
  });

  test('without dart-defines the app targets the local backend', () {
    expect(
      AppConfig.fromEnvironment(isAndroid: true).apiBaseUrl,
      'http://10.0.2.2:8080',
    );
    expect(
      AppConfig.fromEnvironment(isAndroid: false).apiBaseUrl,
      'http://localhost:8080',
    );
  });
}
