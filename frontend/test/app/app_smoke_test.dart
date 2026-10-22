import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/app/app.dart';
import 'package:ludo_arena/app/gate/app_gate_controller.dart';
import 'package:ludo_arena/core/storage/preferences_store.dart';
import 'package:ludo_arena/features/app_update/presentation/force_update_screen.dart';
import 'package:ludo_arena/features/app_update/presentation/splash_screen.dart';
import 'package:ludo_arena/features/authentication/presentation/language_onboarding_screen.dart';
import 'package:ludo_arena/features/authentication/presentation/login_screen.dart';
import 'package:ludo_arena/features/home/presentation/home_screen.dart';

import '../helpers/fake_backend.dart';
import '../helpers/harness.dart';
import '../helpers/screen_harness.dart';

/// Boots the real app shell (router, gate, theme, l10n) against fakes.
Future<ProviderContainer> _boot(WidgetTester tester, TestEnv env) async {
  setViewportSize(tester, Viewports.phone);
  final container = env.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: LudoArenaApp(),
      ),
    ),
  );
  // First frame is always the branded splash.
  expect(find.byType(SplashScreen), findsOneWidget);
  expect(find.byType(HomeScreen), findsNothing);
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(settle);
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

void main() {
  testWidgets('restored session boots to Home', (tester) async {
    final env = await TestEnv.create(prefs: {PrefKeys.languageChosen: true});
    env.routeHappyPath();
    env.seedSession();
    final c = await _boot(tester, env);
    expect(c.read(appGateControllerProvider).phase, GatePhase.ready);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reinstall on a bound device: language first (fresh install), '
      'then straight to Home as the restored guest', (tester) async {
    // Fresh storage and preferences, as after a reinstall.
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.device.id = 'abcdef0123456789';
    env.backend.json(
      'POST',
      '/auth/device/resume',
      authJson(uid: 'u_dev', coins: 4321),
    );
    final c = await _boot(tester, env);
    // The guest is restored underneath while the language is chosen.
    expect(c.read(appGateControllerProvider).phase, GatePhase.ready);
    expect(find.byType(LanguageOnboardingScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(env.backend.calls('POST', '/auth/device/resume').single.json, {
      'deviceId': 'abcdef0123456789',
    });
    expect(env.backend.calls('POST', '/auth/guest'), isEmpty);

    await tester.tap(find.text('Continue'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(settle);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('first launch shows the language picker, then login', (
    tester,
  ) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    await _boot(tester, env);
    expect(find.byType(LanguageOnboardingScreen), findsOneWidget);
    await tester.tap(find.text('Continue'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(settle);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('force update blocks before any session work', (tester) async {
    final env = await TestEnv.create(prefs: {PrefKeys.languageChosen: true});
    env.routeHappyPath(mode: 'force_update');
    env.seedSession();
    await _boot(tester, env);
    expect(find.byType(ForceUpdateScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(env.backend.calls('POST', '/auth/refresh'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('optional update dialog over the splash, Later continues', (
    tester,
  ) async {
    final env = await TestEnv.create(prefs: {PrefKeys.languageChosen: true});
    env.routeHappyPath();
    env.backend.json(
      'GET',
      '/app/config',
      policyJson(mode: 'optional_update', latestVersion: '1.4.0'),
    );
    env.seedSession();
    await _boot(tester, env);
    expect(find.text('A new version is available'), findsOneWidget);
    await tester.tap(find.text('Later'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(settle);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
