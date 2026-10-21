import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/app/gate/app_gate_controller.dart';
import 'package:ludo_royale/features/app_update/presentation/force_update_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/maintenance_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/not_found_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/splash_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/unreachable_screen.dart';
import 'package:ludo_royale/core/localization/number_format.dart';
import 'package:ludo_royale/core/settings/app_settings.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/authentication/presentation/language_onboarding_screen.dart';
import 'package:ludo_royale/features/authentication/presentation/link_account_screen.dart';
import 'package:ludo_royale/features/authentication/presentation/login_screen.dart';
import 'package:ludo_royale/features/home/presentation/games_screen.dart';
import 'package:ludo_royale/features/home/presentation/home_screen.dart';
import 'package:ludo_royale/features/profile/presentation/profile_screen.dart';
import 'package:ludo_royale/features/settings/presentation/settings_screen.dart';
import 'package:ludo_royale/features/store/application/shop_category.dart';
import 'package:ludo_royale/features/store/presentation/shop_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../features/progression/meta_test_support.dart' show collectionJson;
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
        'shop': (const ShopScreen(), signedIn, 'shop'),
      };

  // The Shop (every category) also at the largest text scale the app
  // allows, in every language and both themes.
  final shopConfigs = [
    for (final l in const ['en', 'hi', 'ur', 'id', 'ar'])
      for (final m in const [ThemeMode.light, ThemeMode.dark])
        (Locale(l), m, 1.35),
  ];

  for (final entry in screens.entries) {
    for (final (locale, mode, scale) in [
      ...configs,
      if (entry.key == 'shop') ...shopConfigs,
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
          case 'shop':
            routeStore(env);
            env.backend.json('GET', '/collection', collectionJson());
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

        if (entry.key == 'shop') {
          // Every Shop category: tap its pill, then scroll it through.
          final count = shopCategories(null).length;
          for (var i = 1; i < count; i++) {
            final pill = find
                .descendant(
                  of: find.byKey(
                    const ValueKey('shop-categories'),
                    skipOffstage: false,
                  ),
                  matching: find.byType(InkWell, skipOffstage: false),
                  skipOffstage: false,
                )
                .at(i);
            await tester.ensureVisible(pill);
            await tester.pump(const Duration(milliseconds: 300));
            await tester.tap(pill);
            await drain(tester);
            expect(tester.takeException(), isNull, reason: 'category $i');
            // The category's items are shown (not an error or spinner).
            expect(
              find.byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith('shop-item-'),
                skipOffstage: false,
              ),
              findsWidgets,
              reason: 'category $i',
            );
            await scrollThrough(tester);
            expect(tester.takeException(), isNull, reason: 'category $i');
          }
        }

        // Stop timers (maintenance auto-check) before teardown.
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  // Settings → Number format: the row (live example in its subtitle) and the
  // picker sheet, for each system, at the app's maximum text scale (1.35).
  for (final locale in const [
    Locale('en'),
    Locale('hi'),
    Locale('ur'),
    Locale('ar'),
    Locale('id'),
  ]) {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      for (final system in NumberSystem.values) {
        final name =
            'settings number format ${system.name} ${locale.languageCode} '
            '${mode.name} x1.35 @320x640';
        testWidgets(name, (tester) async {
          addTearDown(() => AppNumberFormat.preferredSystem = null);
          final env = await TestEnv.create();
          env.routeHappyPath();
          await pumpScreen(
            tester,
            env,
            const SettingsScreen(),
            locale: locale,
            themeMode: mode,
            size: Viewports.small,
            textScale: 1.35,
            prepare: (c) async {
              await signedIn(c);
              await c
                  .read(settingsControllerProvider.notifier)
                  .setNumberSystem(system);
            },
          );
          expect(tester.takeException(), isNull);
          await scrollThrough(tester);
          expect(tester.takeException(), isNull);

          final row = find.byKey(const ValueKey('settings.numberSystem'));
          // Back up to the Appearance section (the list builds lazily).
          await tester.scrollUntilVisible(
            row,
            -200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final s in NumberSystem.values) {
            final tile = find.byKey(ValueKey('numberSystem.${s.name}'));
            expect(tile, findsOneWidget);
            expect(
              tester.getSemantics(tile),
              isSemantics(isSelected: s == system, isButton: true),
            );
          }
          final dir = Directionality.of(
            tester.element(find.byKey(const ValueKey('numberSystem.indian'))),
          );
          final rtl =
              locale.languageCode == 'ar' || locale.languageCode == 'ur';
          expect(dir, rtl ? TextDirection.rtl : TextDirection.ltr);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
