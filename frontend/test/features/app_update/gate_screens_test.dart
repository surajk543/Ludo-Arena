import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/app/gate/app_gate_controller.dart';
import 'package:ludo_royale/app/launch_intro.dart';
import 'package:ludo_royale/core/audio_haptics/reduced_motion.dart';
import 'package:ludo_royale/core/theme/app_theme.dart';
import 'package:ludo_royale/features/app_update/presentation/force_update_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/maintenance_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/optional_update_dialog.dart';
import 'package:ludo_royale/features/app_update/presentation/splash_screen.dart';
import 'package:ludo_royale/features/app_update/presentation/studio_intro.dart';
import 'package:ludo_royale/features/app_update/presentation/unreachable_screen.dart';
import 'package:ludo_royale/core/app_policy/app_policy.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());

  Future<void> startGate(ProviderContainer c) =>
      c.read(appGateControllerProvider.notifier).start();

  testWidgets('force update shows versions and opens the store', (
    tester,
  ) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend.json(
      'GET',
      '/app/config',
      policyJson(
        mode: 'force_update',
        minimumVersion: '1.4.0',
        minimumBuild: 140,
      ),
    );
    await pumpScreen(
      tester,
      env,
      const ForceUpdateScreen(),
      prepare: startGate,
    );
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('1.0.0 (1)'), findsOneWidget);
    expect(find.text('1.4.0 (140)'), findsOneWidget);
    await tester.tap(find.text('Update now'));
    await tester.pump();
    expect(env.store.opened, [
      'https://play.google.com/store/apps/details?id=com.ludoroyale.app',
    ]);
  });

  testWidgets('force update without a store link explains and offers Retry', (
    tester,
  ) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend.json(
      'GET',
      '/app/config',
      policyJson(mode: 'force_update', storeUrl: '', storeAvailable: false),
    );
    await pumpScreen(
      tester,
      env,
      const ForceUpdateScreen(),
      prepare: startGate,
    );
    expect(find.text('Update not yet available in the store'), findsOneWidget);
    expect(find.text('Update now'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('server-localized title/message win over app strings', (
    tester,
  ) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend.json(
      'GET',
      '/app/config',
      policyJson(
        mode: 'force_update',
        title: 'अपडेट करें',
        message: 'नया वर्ज़न',
      ),
    );
    await pumpScreen(
      tester,
      env,
      const ForceUpdateScreen(),
      locale: const Locale('hi'),
      prepare: startGate,
    );
    expect(find.text('अपडेट करें'), findsOneWidget);
    expect(find.text('नया वर्ज़न'), findsOneWidget);
  });

  testWidgets('force update cannot be dismissed with back', (tester) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend.json('GET', '/app/config', policyJson(mode: 'force_update'));
    final container = env.container();
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await startGate(container);
      await settle();
    });
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navKey,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              ReducedMotion(reduce: true, child: child!),
          home: const Scaffold(body: Text('beneath')),
        ),
      ),
    );
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const ForceUpdateScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ForceUpdateScreen), findsOneWidget);

    // System back (Android) and programmatic maybePop are both refused.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ForceUpdateScreen), findsOneWidget);
    expect(await navKey.currentState!.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(ForceUpdateScreen), findsOneWidget);
  });

  testWidgets('maintenance shows estimated end (local time) as an estimate', (
    tester,
  ) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend.json(
      'GET',
      '/app/config',
      policyJson(
        mode: 'maintenance',
        maintenance: {
          'enabled': true,
          'message': 'Upgrading servers',
          'startsAtUtc': null,
          'scheduledEndUtc': '2026-11-02T02:00:00Z',
        },
      ),
    );
    final c = await pumpScreen(
      tester,
      env,
      const MaintenanceScreen(),
      prepare: startGate,
    );
    expect(find.text('Upgrading servers'), findsOneWidget);
    expect(find.textContaining('Estimated end'), findsOneWidget);
    expect(
      find.text('This is only an estimate and may change.'),
      findsOneWidget,
    );
    expect(find.text('Game service reachable'), findsOneWidget);

    final before = env.backend.calls('GET', '/app/config').length;
    await tester.tap(find.text('Retry'));
    await drain(tester);
    expect(env.backend.calls('GET', '/app/config').length, before + 1);
    expect(c.read(appGateControllerProvider).phase, GatePhase.maintenance);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unreachable explains online play and shows cached context', (
    tester,
  ) async {
    final env = await TestEnv.create(
      prefs: {'policy.cached': '{"mode":"maintenance"}'},
    );
    env.routeHappyPath();
    env.backend.offline = true;
    await pumpScreen(
      tester,
      env,
      const ServiceUnreachableScreen(),
      prepare: startGate,
    );
    expect(find.text("Can't reach the game service"), findsOneWidget);
    expect(
      find.text(
        'The last status we received said the servers were under maintenance.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('optional update dialog returns the choice', (tester) async {
    final env = await TestEnv.create();
    late BuildContext ctx;
    await pumpScreen(
      tester,
      env,
      Builder(
        builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        },
      ),
    );
    final policy = AppPolicy.fromJson(
      policyJson(mode: 'optional_update', latestVersion: '1.4.0'),
    );
    final result = OptionalUpdateDialog.show(ctx, policy);
    await tester.pumpAndSettle();
    expect(find.text('A new version is available'), findsOneWidget);
    expect(find.textContaining('1.4.0'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(await result, OptionalUpdateChoice.later);
  });

  testWidgets('splash: the studio intro first, then the game icon with '
      'loading while the gate still signs in', (tester) async {
    final env = await TestEnv.create();
    final c = await pumpScreen(
      tester,
      env,
      const ReducedMotion(reduce: false, child: SplashScreen()),
    );
    expect(c.read(launchIntroPlayingProvider), isTrue);
    expect(find.byType(StudioIntro), findsOneWidget);
    expect(find.byType(BrandLogo), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    c.read(launchIntroPlayingProvider.notifier).finish();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(StudioIntro), findsNothing);
    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('splash: with reduced motion the intro is skipped', (
    tester,
  ) async {
    final env = await TestEnv.create();
    final c = await pumpScreen(tester, env, const SplashScreen());
    expect(c.read(launchIntroPlayingProvider), isFalse);
    expect(find.byType(StudioIntro), findsNothing);
    expect(find.byType(BrandLogo), findsOneWidget);
  });
}
