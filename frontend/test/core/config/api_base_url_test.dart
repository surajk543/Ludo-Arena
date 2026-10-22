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
