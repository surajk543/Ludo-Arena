import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/config/app_config.dart';
import 'package:ludo_royale/core/links/external_link_launcher.dart';

void main() {
  test('legal notices default to the backend page, overridable', () {
    const base = AppConfig(
      apiBaseUrl: 'https://api.ludoroyale.app',
      environment: AppEnvironment.production,
    );
    expect(
      base.legalNoticesUrl,
      'https://api.ludoroyale.app/legal/open-source',
    );
    const custom = AppConfig(
      apiBaseUrl: 'https://api.ludoroyale.app',
      environment: AppEnvironment.production,
      legalNoticesUrlOverride: 'https://ludoroyale.app/legal',
    );
    expect(custom.legalNoticesUrl, 'https://ludoroyale.app/legal');
    // Not supplied at build time in tests: the backend page is used.
    expect(
      AppConfig.fromEnvironment(isAndroid: false).legalNoticesUrl,
      'http://localhost:8080/legal/open-source',
    );
  });

  test('the external launcher only opens absolute http(s) URLs', () {
    expect(UrlExternalLinkLauncher.parse('https://a.b/legal'), isNotNull);
    expect(
      UrlExternalLinkLauncher.parse(' http://10.0.2.2:8080/x '),
      isNotNull,
    );
    expect(UrlExternalLinkLauncher.parse('javascript:alert(1)'), isNull);
    expect(UrlExternalLinkLauncher.parse('file:///etc/passwd'), isNull);
    expect(UrlExternalLinkLauncher.parse('/legal/open-source'), isNull);
    expect(UrlExternalLinkLauncher.parse('https:///nohost'), isNull);
  });
}
