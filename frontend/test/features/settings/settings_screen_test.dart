import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/analytics/analytics_providers.dart';
import 'package:ludo_royale/core/links/external_link_launcher.dart';
import 'package:ludo_royale/core/localization/language_controller.dart';
import 'package:ludo_royale/core/settings/app_settings.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/core/theme/theme_controller.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/settings/presentation/settings_screen.dart';

import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

class _FakeLinkLauncher implements ExternalLinkLauncher {
  final List<String> opened = [];
  bool result = true;

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return result;
  }
}

class _FakeBackend implements AnalyticsBackend {
  final enabled = <bool>[];
  @override
  Future<void> logEvent(String name, Map<String, Object> params) async {}
  @override
  Future<void> setCollectionEnabled(bool value) async => enabled.add(value);
}

void main() {
  GoRouter router() => GoRouter(
    initialLocation: AppRoutes.settings,
    routes: [
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.linkAccount,
        builder: (_, _) => const Scaffold(body: Text('LINK')),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const Scaffold(body: Text('PROFILE')),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );

  Future<(TestEnv, ProviderContainer)> pumpSettings(
    WidgetTester tester, {
    AnalyticsBackend? analytics,
    ExternalLinkLauncher? links,
    Locale locale = const Locale('en'),
    Size size = Viewports.phone,
  }) async {
    final env = await TestEnv.create(analyticsBackend: analytics);
    env.routeHappyPath();
    final c = await pumpScreen(
      tester,
      env,
      const SizedBox(),
      router: router(),
      locale: locale,
      size: size,
      extra: [
        externalLinkLauncherProvider.overrideWithValue(
          links ?? _FakeLinkLauncher(),
        ),
      ],
      prepare: (c) =>
          c.read(sessionControllerProvider.notifier).continueAsGuest(),
    );
    return (env, c);
  }

  /// Every string painted on screen (all Text widgets build a RichText).
  List<String> visibleTexts(WidgetTester tester) => [
    for (final e in find.byType(RichText).evaluate())
      (e.widget as RichText).text.toPlainText(),
  ];

  testWidgets('toggles persist and report settings_changed', (tester) async {
    final (env, c) = await pumpSettings(tester);
    await tester.tap(find.text('Sound effects'));
    await tester.pump();
    expect(c.read(settingsControllerProvider).soundEnabled, isFalse);
    expect(
      c.read(preferencesStoreProvider).getBool(PrefKeys.soundEnabled),
      isFalse,
    );
    expect(env.analytics.events, contains('settings_changed:sound:false'));

    await tester.tap(find.text('Mute quick chat'));
    await tester.pump();
    expect(c.read(settingsControllerProvider).quickChatMuted, isTrue);
  });

  testWidgets('theme choice applies immediately and persists', (tester) async {
    final (env, c) = await pumpSettings(tester);
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(c.read(themeModeControllerProvider), ThemeMode.dark);
    expect(
      c.read(preferencesStoreProvider).getString(PrefKeys.themeMode),
      'dark',
    );
    expect(env.analytics.events, contains('theme_changed:dark'));
  });

  testWidgets('language change keeps the session and applies at once', (
    tester,
  ) async {
    final (env, c) = await pumpSettings(tester);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();
    expect(c.read(languageControllerProvider), const Locale('hi'));
    expect(c.read(sessionControllerProvider).isSignedIn, isTrue);
    expect(env.analytics.events, contains('language_changed:hi'));
  });

  testWidgets('analytics toggle is disabled when Firebase is not configured', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.text('Not available in this build'), findsOneWidget);
  });

  testWidgets('analytics consent toggle grants and withdraws', (tester) async {
    final backend = _FakeBackend();
    final (_, c) = await pumpSettings(tester, analytics: backend);
    await reveal(tester, find.text('Share anonymous usage stats'));
    await tester.tap(find.text('Share anonymous usage stats'));
    await drain(tester);
    expect(c.read(analyticsConsentProvider), AnalyticsConsent.granted);
    await tester.tap(find.text('Share anonymous usage stats'));
    await drain(tester);
    expect(c.read(analyticsConsentProvider), AnalyticsConsent.denied);
    expect(backend.enabled, [true, false]);
  });

  testWidgets('guest sign-out warns before losing progress', (tester) async {
    final (env, c) = await pumpSettings(tester);
    await reveal(tester, find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out of your guest account?'), findsOneWidget);
    expect(find.text('Save progress first'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.read(sessionControllerProvider).isSignedIn, isTrue);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out and lose progress'));
    await drain(tester);
    expect(c.read(sessionControllerProvider).isSignedIn, isFalse);
    expect(env.secure.values.containsKey('session.guest_secret'), isFalse);
  });

  testWidgets('About shows the version and a Legal notices entry', (
    tester,
  ) async {
    await pumpSettings(tester);
    await reveal(tester, find.text('Legal notices'));
    expect(find.text('1.0.0 (1)'), findsOneWidget);
    expect(
      find.text('Open-source licenses · opens in your browser'),
      findsOneWidget,
    );
    expect(find.text('Licenses'), findsNothing);
  });

  testWidgets('Legal notices opens the backend page in the browser', (
    tester,
  ) async {
    final links = _FakeLinkLauncher();
    await pumpSettings(tester, links: links);
    await reveal(tester, find.text('Legal notices'));
    await tester.tap(find.text('Legal notices'));
    await drain(tester);
    expect(links.opened, ['http://test.local/legal/open-source']);
    // Nothing is pushed inside the app: no framework license page.
    expect(find.byType(LicensePage), findsNothing);
    expect(find.byType(AboutDialog), findsNothing);
    expect(find.text('Legal notices'), findsOneWidget);
  });

  testWidgets('a failed launch shows a toast instead of an in-app page', (
    tester,
  ) async {
    final links = _FakeLinkLauncher()..result = false;
    await pumpSettings(tester, links: links);
    await reveal(tester, find.text('Legal notices'));
    await tester.tap(find.text('Legal notices'));
    await drain(tester);
    expect(links.opened, hasLength(1));
    expect(
      find.text("Couldn't open the page. Please try again later."),
      findsOneWidget,
    );
    expect(find.byType(LicensePage), findsNothing);
  });

  for (final locale in const ['en', 'hi', 'ur', 'id', 'ar']) {
    testWidgets('settings never mention the UI framework ($locale)', (
      tester,
    ) async {
      final links = _FakeLinkLauncher();
      // Tall viewport: the whole list (incl. About) is built at once.
      await pumpSettings(
        tester,
        links: links,
        locale: Locale(locale),
        size: const Size(390, 2400),
      );
      final texts = visibleTexts(tester);
      expect(texts, isNotEmpty);
      for (final t in texts) {
        expect(t.toLowerCase(), isNot(contains('flutter')), reason: t);
        expect(t.toLowerCase(), isNot(contains('dart')), reason: t);
      }
      // Tapping the legal entry stays out of the app.
      final legal = find.byIcon(Icons.gavel_rounded);
      expect(legal, findsOneWidget);
      await tester.tap(legal);
      await drain(tester);
      expect(links.opened, ['http://test.local/legal/open-source']);
      expect(find.byType(LicensePage), findsNothing);
      for (final t in visibleTexts(tester)) {
        expect(t.toLowerCase(), isNot(contains('flutter')), reason: t);
      }
    });
  }
}
