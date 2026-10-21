import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/analytics/analytics_providers.dart';
import 'package:ludo_royale/core/localization/language_controller.dart';
import 'package:ludo_royale/core/settings/app_settings.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/core/theme/theme_controller.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/settings/presentation/settings_screen.dart';

import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

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
  }) async {
    final env = await TestEnv.create(analyticsBackend: analytics);
    env.routeHappyPath();
    final c = await pumpScreen(
      tester,
      env,
      const SizedBox(),
      router: router(),
      prepare: (c) =>
          c.read(sessionControllerProvider.notifier).continueAsGuest(),
    );
    return (env, c);
  }

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

  testWidgets('shows the version and the licenses entry', (tester) async {
    await pumpSettings(tester);
    await reveal(tester, find.text('Licenses'));
    expect(find.text('1.0.0 (1)'), findsOneWidget);
    expect(find.text('Open-source software and fonts'), findsOneWidget);
  });
}
