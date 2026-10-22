import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/config/app_config.dart';
import 'package:ludo_arena/core/links/external_link_launcher.dart';

void main() {
  test('legal notices default to the studio website page, overridable', () {
    const base = AppConfig(
      apiBaseUrl: 'https://api.ludoarena.app',
      environment: AppEnvironment.production,
    );
    expect(
      base.legalNoticesUrl,
      'https://sungamestudio.com/ludo-arena/legal/',
    );
    expect(base.legalNoticesUrl, AppConfig.defaultLegalNoticesUrl);
    // The backend route stays available as an explicit fallback.
    const custom = AppConfig(
      apiBaseUrl: 'https://api.ludoarena.app',
      environment: AppEnvironment.production,
      legalNoticesUrlOverride: 'https://api.ludoarena.app/legal/open-source',
    );
    expect(
      custom.legalNoticesUrl,
      'https://api.ludoarena.app/legal/open-source',
    );
    // Not supplied at build time in tests: the website page is used.
    expect(
      AppConfig.fromEnvironment(isAndroid: false).legalNoticesUrl,
      'https://sungamestudio.com/ludo-arena/legal/',
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
