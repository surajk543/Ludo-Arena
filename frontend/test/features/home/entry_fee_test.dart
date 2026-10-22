import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_arena/app/gate/app_gate_controller.dart';
import 'package:ludo_arena/app/routes.dart';
import 'package:ludo_arena/core/lifecycle/app_lifecycle.dart';
import 'package:ludo_arena/features/authentication/application/session_controller.dart';
import 'package:ludo_arena/features/game/application/play_config.dart';
import 'package:ludo_arena/features/home/application/play_options.dart';
import 'package:ludo_arena/features/home/presentation/home_screen.dart';
import 'package:ludo_arena/features/private_rooms/presentation/create_room_screen.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

/// Entry fees are server-configured (`entryFees` in `/app/config`, live from
/// the backend's app policy); the app only falls back to the backend's
/// built-in defaults (Ludo 1,00,000, Snakes & Ladders 50,000) until the
/// policy is known. Amounts are formatted per locale (en: `1 Lakh`).
void main() {
  /// An env whose `/app/config` serves [fees] and a stored session, so
  /// starting the gate loads the policy and reaches `ready`.
  Future<TestEnv> envWithFees(Map<String, int> fees) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend.json('GET', '/app/config', policyJson(entryFees: fees));
    env.seedSession();
    return env;
  }

  Future<void> startGate(ProviderContainer c) async {
    await c.read(appGateControllerProvider.notifier).start();
    await settle();
  }

  group('entryFeeProvider', () {
    test('falls back to 100,000 / 50,000 before the policy is known', () async {
      final env = await TestEnv.create();
      final c = env.container();
      addTearDown(c.dispose);
      expect(c.read(appGateControllerProvider).policy, isNull);
      expect(c.read(entryFeeProvider(GameId.ludo)), 100000);
      expect(c.read(entryFeeProvider(GameId.snakesLadders)), 50000);
      expect(kFallbackEntryFees, {
        GameId.ludo: 100000,
        GameId.snakesLadders: 50000,
      });
    });

    test('uses the fees served by /app/config', () async {
      final env = await envWithFees({'ludo': 150000, 'snakes_ladders': 70000});
      final c = env.container();
      addTearDown(c.dispose);
      await startGate(c);
      expect(c.read(appGateControllerProvider).phase, GatePhase.ready);
      expect(c.read(entryFeeProvider(GameId.ludo)), 150000);
      expect(c.read(entryFeeProvider(GameId.snakesLadders)), 70000);
    });

    test('a game missing from the server map uses its fallback', () async {
      final env = await envWithFees({'ludo': 120000});
      final c = env.container();
      addTearDown(c.dispose);
      await startGate(c);
      expect(c.read(entryFeeProvider(GameId.ludo)), 120000);
      expect(c.read(entryFeeProvider(GameId.snakesLadders)), 50000);
    });

    test('a later policy re-fetch picks up changed fees', () async {
      final env = await envWithFees({'ludo': 100000, 'snakes_ladders': 50000});
      final c = env.container();
      addTearDown(c.dispose);
      await startGate(c);
      expect(c.read(entryFeeProvider(GameId.ludo)), 100000);

      // The operator edits the backend policy; the app re-checks on resume.
      env.backend.json(
        'GET',
        '/app/config',
        policyJson(entryFees: {'ludo': 200000, 'snakes_ladders': 80000}),
      );
      env.clock.advance(AppGateController.resumeThrottle);
      c.read(appLifecycleProvider)
        ..emit(AppLifecycleState.paused)
        ..emit(AppLifecycleState.resumed);
      await settle();
      expect(env.backend.calls('GET', '/app/config'), hasLength(2));
      expect(c.read(entryFeeProvider(GameId.ludo)), 200000);
      expect(c.read(entryFeeProvider(GameId.snakesLadders)), 80000);
    });
  });

  GoRouter homeRouter() => GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
      for (final p in [
        AppRoutes.matchmaking,
        AppRoutes.createRoom,
        AppRoutes.joinRoom,
        AppRoutes.practice,
        AppRoutes.missions,
        AppRoutes.collection,
        AppRoutes.friends,
        AppRoutes.events,
        AppRoutes.profile,
        AppRoutes.settings,
        AppRoutes.linkAccount,
      ])
        GoRoute(
          path: p,
          builder: (_, state) => Scaffold(body: Text('AT ${state.uri}')),
        ),
    ],
  );

  testWidgets('home game cards show the fallback fees without a policy', (
    tester,
  ) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    await pumpScreen(
      tester,
      env,
      const SizedBox(),
      router: homeRouter(),
      prepare: (c) =>
          c.read(sessionControllerProvider.notifier).continueAsGuest(),
    );
    expect(find.text('Entry 1 Lakh'), findsOneWidget);
    await reveal(tester, find.text('Entry 50,000'));
    expect(find.text('Entry 50,000'), findsOneWidget);
  });

  testWidgets('home cards and play options show the server fees', (
    tester,
  ) async {
    final env = await envWithFees({'ludo': 150000, 'snakes_ladders': 70000});
    await pumpScreen(
      tester,
      env,
      const SizedBox(),
      router: homeRouter(),
      prepare: startGate,
    );
    expect(find.text('Entry 1.5 Lakh'), findsOneWidget);
    expect(find.text('Entry 1 Lakh'), findsNothing);
    await reveal(tester, find.text('Entry 70,000'));
    expect(find.text('Entry 70,000'), findsOneWidget);

    await reveal(tester, find.text('Play Online').first);
    await tester.tap(find.text('Play Online').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Entry fee 1.5 Lakh coins'),
      findsOneWidget,
      reason: 'the Ludo options sheet shows the server fee',
    );
  });

  testWidgets('create room shows the server fee per game', (tester) async {
    final env = await envWithFees({'ludo': 150000, 'snakes_ladders': 70000});
    await pumpScreen(
      tester,
      env,
      const CreateRoomScreen(request: PlayRequest()),
      prepare: startGate,
    );
    expect(
      find.textContaining('Entry fee: 1.5 Lakh coins per player'),
      findsOneWidget,
    );
    await tester.tap(find.text('Snakes & Ladders').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Entry fee: 70,000 coins per player'),
      findsOneWidget,
    );
    expect(find.textContaining('You need'), findsNothing);
  });

  testWidgets('create room warns when the fee exceeds the balance', (
    tester,
  ) async {
    // The fake wallet holds 10 Lakh (1,000,000) coins.
    final env = await envWithFees({'ludo': 2000000, 'snakes_ladders': 50000});
    await pumpScreen(
      tester,
      env,
      const CreateRoomScreen(request: PlayRequest()),
      prepare: startGate,
    );
    expect(find.textContaining('You need 20 Lakh coins'), findsOneWidget);
    await tester.tap(find.text('Snakes & Ladders').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('You need'), findsNothing);
  });
}
