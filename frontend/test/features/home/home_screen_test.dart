import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/app/gate/app_gate_controller.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/realtime/realtime_status.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/core/theme/theme_controller.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/home/application/play_options.dart';
import 'package:ludo_royale/features/home/presentation/home_screen.dart';
import 'package:ludo_royale/features/home/presentation/join_code_sheet.dart';
import 'package:ludo_royale/features/home/presentation/widgets/game_card.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

/// Counts pages pushed onto the root navigator (double-tap guards).
class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) pushes++;
  }
}

/// Records where Home navigates (feature screens are built by others).
GoRouter _router({List<NavigatorObserver> observers = const []}) => GoRouter(
  initialLocation: AppRoutes.home,
  observers: observers,
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

/// The Quick Play selector whose accessibility hint is [hint].
Finder _selector(String hint) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.hint == hint);

/// The Play Now button.
Finder get _playNow => find.ancestor(
  of: find.text('Play Now'),
  matching: find.byType(PremiumButton),
);

void main() {
  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    bool linked = false,
    Size size = Viewports.phone,
    List<NavigatorObserver> observers = const [],
  }) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    if (linked) {
      env.backend.json(
        'POST',
        '/auth/guest',
        authJson(isGuest: false, providers: ['google'], guestSecret: 'gs'),
        status: 201,
      );
    }
    return pumpScreen(
      tester,
      env,
      const SizedBox(),
      router: _router(observers: observers),
      size: size,
      prepare: (c) =>
          c.read(sessionControllerProvider.notifier).continueAsGuest(),
    );
  }

  testWidgets(
    'header shows the server profile: name, level, title, XP, balances',
    (tester) async {
      await pumpHome(tester);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'\bLevel 4\b')), findsOneWidget);
      expect(find.text('Rookie'), findsOneWidget);
      // levelXp 450, xp 520, nextLevelXp 250 → 70 / 250 into level 4.
      expect(find.bySemanticsLabel(RegExp('70.*250')), findsOneWidget);
      expect(find.text('10 Lakh'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.byTooltip('Save progress'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.text('Ludo'), findsWidgets);
      await reveal(tester, find.text('Snakes & Ladders'));
      expect(find.text('Snakes & Ladders'), findsOneWidget);
    },
  );

  testWidgets('header shows the live connection status', (tester) async {
    final c = await pumpHome(tester);
    expect(find.text('Connecting…'), findsOneWidget);
    c.read(realtimeStatusProvider.notifier).set(RealtimeStatus.connected);
    await tester.pump();
    expect(find.text('Online'), findsOneWidget);
    c.read(realtimeStatusProvider.notifier).set(RealtimeStatus.offline);
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('Save Progress icon is hidden once a provider is linked', (
    tester,
  ) async {
    await pumpHome(tester, linked: true);
    expect(find.byTooltip('Save progress'), findsNothing);
  });

  testWidgets('avatar switches to the Profile tab', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('AT /profile'), findsOneWidget);
  });

  testWidgets('Play Online → options → Find match navigates to matchmaking', (
    tester,
  ) async {
    await pumpHome(tester);
    await reveal(tester, find.text('Play Online').first);
    await tester.tap(find.text('Play Online').first);
    await tester.pumpAndSettle();
    expect(find.text('Ludo online'), findsOneWidget);
    await tester.tap(find.text('2 players'));
    await tester.tap(find.text('Quick'));
    await tester.pump();
    expect(find.textContaining('Entry fee 1 Lakh coins'), findsOneWidget);
    await tester.tap(find.text('Find match'));
    await tester.pumpAndSettle();
    expect(
      find.text('AT /matchmaking?game=ludo&variant=quick&capacity=2'),
      findsOneWidget,
    );
  });

  // Each game card's three buttons open the existing flow for that game.
  for (final (game, button, sheetTitle, confirm, route) in [
    (
      'Ludo',
      'Play with Friends',
      'Ludo with friends',
      'Create room',
      '/rooms/create?game=ludo&variant=classic&capacity=4',
    ),
    (
      'Ludo',
      'Practice vs Bots',
      'Practice Ludo',
      'Start practice',
      '/practice?game=ludo&variant=classic&bots=3',
    ),
    (
      'Snakes & Ladders',
      'Play Online',
      'Snakes & Ladders online',
      'Find match',
      '/matchmaking?game=snakes_ladders&variant=classic&capacity=4',
    ),
    (
      'Snakes & Ladders',
      'Play with Friends',
      'Snakes & Ladders with friends',
      'Create room',
      '/rooms/create?game=snakes_ladders&variant=classic&capacity=4',
    ),
  ]) {
    testWidgets('$game card: $button opens its flow', (tester) async {
      await pumpHome(tester);
      final tagline = game == 'Ludo'
          ? 'Race all four tokens home'
          : 'Climb ladders, dodge snakes';
      await reveal(tester, find.text(tagline));
      final target = find.descendant(
        of: find.ancestor(
          of: find.text(tagline),
          matching: find.byType(GameCard),
        ),
        matching: find.text(button),
      );
      await reveal(tester, target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text(sheetTitle), findsOneWidget);
      await tester.tap(find.text(confirm));
      await tester.pumpAndSettle();
      expect(find.text('AT $route'), findsOneWidget);
    });
  }

  testWidgets('Snakes practice uses bots and the classic variant', (
    tester,
  ) async {
    await pumpHome(tester);
    await reveal(tester, find.text('Practice vs Bots').last);
    await tester.tap(find.text('Practice vs Bots').last);
    await tester.pumpAndSettle();
    expect(find.text('Practice Snakes & Ladders'), findsOneWidget);
    expect(find.text('Mode'), findsNothing); // no variants for S&L
    await tester.tap(find.text('1 bot'));
    await tester.tap(find.text('Start practice'));
    await tester.pumpAndSettle();
    expect(
      find.text('AT /practice?game=snakes_ladders&variant=classic&bots=1'),
      findsOneWidget,
    );
  });

  testWidgets('Private Room lets the user pick the game', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Private Room'));
    await tester.pumpAndSettle();
    expect(find.text('Create a private room'), findsOneWidget);
    await tester.tap(find.text('Snakes & Ladders').last);
    await tester.tap(find.text('3 players'));
    await tester.tap(find.text('Create room'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'AT /rooms/create?game=snakes_ladders&variant=classic&capacity=3',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Join with Code validates and normalizes the code', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('Join with Code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'k7q2');
    await tester.pump();
    await tester.tap(find.text('Join room'));
    await tester.pump();
    expect(find.text('Room codes have 6 letters or numbers.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'k7q2mx');
    await tester.pump();
    await tester.tap(find.text('Join room'));
    await tester.pumpAndSettle();
    expect(find.text('AT /rooms/join?code=K7Q2MX'), findsOneWidget);
  });

  testWidgets('Quick Play shows the remembered game and player count', (
    tester,
  ) async {
    final c = await pumpHome(tester);
    await c
        .read(quickPlayProvider.notifier)
        .remember(const PlayConfig(game: GameId.snakesLadders, capacity: 3));
    await tester.pump();
    final game = _selector('Change game');
    final players = _selector('Change number of players');
    expect(
      find.descendant(of: game, matching: find.text('Snakes & Ladders')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: players, matching: find.text('3 players')),
      findsOneWidget,
    );
    await tester.tap(find.text('Play Now'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'AT /matchmaking?game=snakes_ladders&variant=classic&capacity=3',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Quick Play selectors persist the choice; Play Now matches once',
    (tester) async {
      final pushes = _PushCounter();
      final c = await pumpHome(tester, observers: [pushes]);

      await tester.tap(_selector('Change game'));
      await tester.pumpAndSettle();
      expect(find.text('Quick Ludo'), findsOneWidget);
      await tester.tap(find.text('Quick Ludo'));
      await tester.pumpAndSettle();

      await tester.tap(_selector('Change number of players'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 players'));
      await tester.pumpAndSettle();

      const chosen = PlayConfig(variant: 'quick', capacity: 2);
      expect(c.read(quickPlayProvider), chosen);
      expect(
        c.read(preferencesStoreProvider).getString(PrefKeys.lastQuickPlay),
        chosen.encode(),
      );
      expect(
        find.descendant(
          of: _selector('Change game'),
          matching: find.text('Quick Ludo'),
        ),
        findsOneWidget,
      );

      // A double tap (same frame) starts matchmaking exactly once.
      final before = pushes.pushes;
      await tester.tap(find.text('Play Now'));
      await tester.tap(find.text('Play Now'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(pushes.pushes - before, 1);
      expect(
        find.text('AT /matchmaking?game=ludo&variant=quick&capacity=2'),
        findsOneWidget,
      );

      // Back on Home, Play Now works again.
      GoRouter.of(tester.element(find.textContaining('AT /'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play Now'));
      await tester.pumpAndSettle();
      expect(pushes.pushes - before, 2);
    },
  );

  testWidgets('Play Now is disabled when coins cannot cover the entry fee', (
    tester,
  ) async {
    // The fake wallet holds 10 Lakh coins; the server fee is 20 Lakh.
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend.json(
      'GET',
      '/app/config',
      policyJson(entryFees: {'ludo': 2000000, 'snakes_ladders': 50000}),
    );
    env.seedSession();
    await pumpScreen(
      tester,
      env,
      const SizedBox(),
      router: _router(),
      prepare: (c) async {
        await c.read(appGateControllerProvider.notifier).start();
        await settle();
      },
    );
    expect(
      find.text('You need at least 20 Lakh coins for this match.'),
      findsOneWidget,
    );
    expect(tester.widget<PremiumButton>(_playNow).onPressed, isNull);
    await tester.tap(find.text('Play Now'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('AT /matchmaking'), findsNothing);
  });

  for (final (tile, route) in [
    ('Missions', '/missions'),
    ('Collection', '/collection'),
    ('Friends', '/friends'),
    ('Events', '/events'),
  ]) {
    testWidgets('More to Explore: $tile opens $route', (tester) async {
      await pumpHome(tester);
      final finder = find.bySemanticsLabel(tile);
      await reveal(tester, finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(find.text('AT $route'), findsOneWidget);
    });
  }

  testWidgets('theme shortcut flips and persists the theme', (tester) async {
    final c = await pumpHome(tester);
    await tester.tap(find.byTooltip('Switch light/dark theme'));
    await tester.pump();
    expect(c.read(themeModeControllerProvider), ThemeMode.dark);
    expect(
      c.read(preferencesStoreProvider).getString(PrefKeys.themeMode),
      'dark',
    );
  });

  testWidgets('wallet sheet shows exact balance and the virtual notice', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('10 Lakh').first);
    await tester.pumpAndSettle();
    expect(find.text('Your wallet'), findsOneWidget);
    expect(find.text('Exact balance: 10,00,000'), findsOneWidget);
    expect(find.textContaining("can't be sold"), findsOneWidget);
  });

  test('room code normalization', () {
    expect(JoinCodeSheet.normalize(' k7-q2 mx '), 'K7Q2MX');
    expect(JoinCodeSheet.codePattern.hasMatch('K7Q2MX'), isTrue);
    expect(JoinCodeSheet.codePattern.hasMatch('K7Q2M'), isFalse);
  });

  test('play config encodes routes and survives persistence', () {
    const cfg = PlayConfig(
      game: GameId.ludo,
      variant: 'quick',
      capacity: 2,
      bots: 1,
    );
    expect(PlayConfig.decode(cfg.encode()), cfg);
    expect(PlayConfig.decode('garbage'), const PlayConfig());
    expect(
      const PlayConfig(
        game: GameId.snakesLadders,
        variant: 'quick',
      ).routeFor(PlayMode.online),
      AppRoutes.matchmakingFor(game: 'snakes_ladders', capacity: 4),
    );
    expect(AppRoutes.game('r_1'), '/game/r_1');
    expect(AppRoutes.roomLobby('r_1'), '/rooms/r_1/lobby');
  });
}
