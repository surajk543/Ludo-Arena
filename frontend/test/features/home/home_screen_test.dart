import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/core/theme/theme_controller.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/home/application/play_options.dart';
import 'package:ludo_royale/features/home/presentation/home_screen.dart';
import 'package:ludo_royale/features/home/presentation/join_code_sheet.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

/// Records where Home navigates (feature screens are built by others).
GoRouter _router() => GoRouter(
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

void main() {
  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    bool linked = false,
    Size size = Viewports.phone,
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
      router: _router(),
      size: size,
      prepare: (c) =>
          c.read(sessionControllerProvider.notifier).continueAsGuest(),
    );
  }

  testWidgets(
    'header shows profile, level, balances and Save Progress for guests',
    (tester) async {
      await pumpHome(tester);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.byTooltip('Save progress'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.text('Ludo'), findsWidgets);
      expect(find.text('Snakes & Ladders'), findsWidgets);
    },
  );

  testWidgets('Save Progress icon is hidden once a provider is linked', (
    tester,
  ) async {
    await pumpHome(tester, linked: true);
    expect(find.byTooltip('Save progress'), findsNothing);
  });

  testWidgets('Play Online → options → Find match navigates to matchmaking', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('Play Online').first);
    await tester.pumpAndSettle();
    expect(find.text('Ludo online'), findsOneWidget);
    await tester.tap(find.text('2 players'));
    await tester.tap(find.text('Quick'));
    await tester.pump();
    expect(find.textContaining('Entry fee 1,000 coins'), findsOneWidget);
    await tester.tap(find.text('Find match'));
    await tester.pumpAndSettle();
    expect(
      find.text('AT /matchmaking?game=ludo&variant=quick&capacity=2'),
      findsOneWidget,
    );
  });

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

  testWidgets(
    'Quick Play goes straight to matchmaking with the remembered setup',
    (tester) async {
      final c = await pumpHome(tester);
      await c
          .read(quickPlayProvider.notifier)
          .remember(const PlayConfig(game: GameId.snakesLadders, capacity: 3));
      await tester.pump();
      expect(
        find.textContaining('Snakes & Ladders · Classic · 3 players'),
        findsOneWidget,
      );
      await tester.tap(find.text('Quick Play'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'AT /matchmaking?game=snakes_ladders&variant=classic&capacity=3',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('entry tiles navigate to their feature routes', (tester) async {
    await pumpHome(tester);
    await reveal(tester, find.text('Collection Room'));
    await tester.tap(find.text('Collection Room'));
    await tester.pumpAndSettle();
    expect(find.text('AT /collection'), findsOneWidget);
  });

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
