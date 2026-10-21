import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/app/gate/app_gate_controller.dart';
import 'package:ludo_royale/features/app_update/presentation/force_update_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/maintenance_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/not_found_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/splash_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/unreachable_screen.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/authentication/presentation/language_onboarding_screen.dart';
import 'package:ludo_royale/features/authentication/presentation/link_account_screen.dart';
import 'package:ludo_royale/features/authentication/presentation/login_screen.dart';
import 'package:ludo_royale/features/home/presentation/games_screen.dart';
import 'package:ludo_royale/features/home/presentation/home_screen.dart';
import 'package:ludo_royale/features/profile/presentation/profile_screen.dart';
import 'package:ludo_royale/features/settings/presentation/settings_screen.dart';
import 'package:ludo_royale/features/store/presentation/store_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../features/store/store_test_support.dart';
import '../helpers/fake_backend.dart';
import '../helpers/harness.dart';
import '../helpers/screen_harness.dart';

/// Every screen I own × {en, hi, ur, ar, id} × {light, dark} at 320×640
/// (plus a 1.3× text scale pass) must lay out without overflow and render
/// RTL for ar/ur.
void main() {
  setUpAll(() async => initializeDateFormatting());

  final configs = <(Locale, ThemeMode, double)>[
    (const Locale('en'), ThemeMode.light, 1.0),
    (const Locale('en'), ThemeMode.dark, 1.0),
    (const Locale('hi'), ThemeMode.light, 1.0),
    (const Locale('hi'), ThemeMode.dark, 1.3),
    (const Locale('ar'), ThemeMode.light, 1.0),
    (const Locale('ar'), ThemeMode.dark, 1.3),
    (const Locale('ur'), ThemeMode.dark, 1.0),
    (const Locale('id'), ThemeMode.light, 1.3),
  ];

  Future<void> signedIn(ProviderContainer c) async {
    await c.read(sessionControllerProvider.notifier).continueAsGuest();
  }

  Future<void> Function(ProviderContainer) gateIn(String mode) => (c) async {
    await c.read(appGateControllerProvider.notifier).start();
  };

  final screens =
      <String, (Widget, Future<void> Function(ProviderContainer)?, String?)>{
        'splash': (const SplashScreen(), null, null),
        'onboarding': (const LanguageOnboardingScreen(), null, null),
        'login': (const LoginScreen(), null, null),
        'home': (const HomeScreen(), signedIn, null),
        'games': (const GamesScreen(), signedIn, null),
        'settings': (const SettingsScreen(), signedIn, null),
        'profile': (const ProfileScreen(), signedIn, null),
        'link': (const LinkAccountScreen(), signedIn, null),
        'force': (
          const ForceUpdateScreen(),
          gateIn('force_update'),
          'force_update',
        ),
        'force-no-store': (
          const ForceUpdateScreen(),
          gateIn('force_update'),
          'force_no_store',
        ),
        'maintenance': (
          const MaintenanceScreen(),
          gateIn('maintenance'),
          'maintenance',
        ),
        'unreachable': (
          const ServiceUnreachableScreen(),
          gateIn('offline'),
          'offline',
        ),
        'not-found': (const NotFoundScreen(location: '/missions'), null, null),
        'store': (const StoreScreen(), signedIn, 'store'),
      };

  // The Store also at the largest text scale the app allows, in every
  // language and both themes.
  final storeConfigs = [
    for (final l in const ['en', 'hi', 'ur', 'id', 'ar'])
      for (final m in const [ThemeMode.light, ThemeMode.dark])
        (Locale(l), m, 1.35),
  ];

  for (final entry in screens.entries) {
    for (final (locale, mode, scale) in [
      ...configs,
      if (entry.key == 'store') ...storeConfigs,
    ]) {
      final name =
          '${entry.key} ${locale.languageCode} ${mode.name} x$scale @320x640';
      testWidgets(name, (tester) async {
        final env = await TestEnv.create();
        env.routeHappyPath();
        final policyMode = entry.value.$3;
        switch (policyMode) {
          case 'force_update':
            env.backend.json(
              'GET',
              '/app/config',
              policyJson(
                mode: 'force_update',
                minimumVersion: '1.4.0',
                minimumBuild: 140,
              ),
            );
          case 'force_no_store':
            env.backend.json(
              'GET',
              '/app/config',
              policyJson(
                mode: 'force_update',
                minimumVersion: '1.4.0',
                storeUrl: '',
                storeAvailable: false,
              ),
            );
          case 'maintenance':
            env.backend.json(
              'GET',
              '/app/config',
              policyJson(
                mode: 'maintenance',
                maintenance: {
                  'enabled': true,
                  'message': '',
                  'startsAtUtc': '2026-11-02T01:00:00Z',
                  'scheduledEndUtc': '2026-11-02T02:00:00Z',
                },
              ),
            );
          case 'offline':
            env.backend.offline = true;
          case 'store':
            routeStore(env);
        }
        await pumpScreen(
          tester,
          env,
          entry.value.$1,
          locale: locale,
          themeMode: mode,
          size: Viewports.small,
          textScale: scale,
          prepare: entry.value.$2,
        );
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);

        final dir = Directionality.of(
          tester.element(find.byWidget(entry.value.$1)),
        );
        final rtl = locale.languageCode == 'ar' || locale.languageCode == 'ur';
        expect(dir, rtl ? TextDirection.rtl : TextDirection.ltr);

        // Stop timers (maintenance auto-check) before teardown.
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
