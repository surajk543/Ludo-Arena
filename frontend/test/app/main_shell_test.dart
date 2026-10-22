import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_arena/app/app.dart';
import 'package:ludo_arena/app/gate/app_gate_controller.dart';
import 'package:ludo_arena/app/router.dart';
import 'package:ludo_arena/app/routes.dart';
import 'package:ludo_arena/app/shell/main_shell.dart';
import 'package:ludo_arena/app/shell/tab_nav.dart';
import 'package:ludo_arena/core/audio_haptics/audio_service.dart';
import 'package:ludo_arena/core/storage/preferences_store.dart';
import 'package:ludo_arena/core/theme/theme_controller.dart';
import 'package:ludo_arena/features/home/presentation/games_screen.dart';
import 'package:ludo_arena/features/home/presentation/home_screen.dart';
import 'package:ludo_arena/features/missions/presentation/missions_screen.dart';
import 'package:ludo_arena/features/profile/presentation/profile_screen.dart';
import 'package:ludo_arena/features/settings/presentation/settings_screen.dart';
import 'package:ludo_arena/features/social/presentation/friends_screen.dart';
import 'package:ludo_arena/shared/widgets/widgets.dart';

import '../features/progression/meta_test_support.dart' show routeMeta;
import '../helpers/harness.dart';
import '../helpers/screen_harness.dart';

/// Boots the real app (router, gate, shell) signed in, on Home.
Future<ProviderContainer> _bootHome(WidgetTester tester) async {
  setViewportSize(tester, Viewports.phone);
  final env = await TestEnv.create(prefs: {PrefKeys.languageChosen: true});
  env.routeHappyPath();
  routeMeta(env);
  env.seedSession();
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
  await _settle(tester, 8);
  expect(container.read(appGateControllerProvider).phase, GatePhase.ready);
  expect(find.byType(HomeScreen), findsOneWidget);
  return container;
}

Future<void> _settle(WidgetTester tester, [int rounds = 4]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(settle);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps the bottom-navigation item labelled [label].
Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(AppBottomNav), matching: find.text(label)),
  );
  await _settle(tester);
}

GoRouter _router(ProviderContainer c) => c.read(appRouterProvider);

void main() {
  testWidgets('bottom navigation switches between the five tabs', (
    tester,
  ) async {
    await _bootHome(tester);
    expect(find.byType(AppBottomNav), findsOneWidget);
    for (final label in ['Home', 'Games', 'Missions', 'Friends', 'Profile']) {
      expect(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }

    await _tapTab(tester, 'Games');
    expect(find.byType(GamesScreen), findsOneWidget);
    expect(find.text('Choose a Game'), findsNothing); // Home is offstage
    expect(find.text('Race all four tokens home'), findsOneWidget);

    await _tapTab(tester, 'Missions');
    expect(find.byType(MissionsScreen), findsOneWidget);

    await _tapTab(tester, 'Friends');
    expect(find.byType(FriendsScreen), findsOneWidget);

    await _tapTab(tester, 'Profile');
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    await _tapTab(tester, 'Home');
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tab change plays one tab sound; the current tab is silent', (
    tester,
  ) async {
    final c = await _bootHome(tester);
    final audio = c.read(audioServiceProvider) as SilentAudioService;
    final before = audio.played.length;
    await _tapTab(tester, 'Missions');
    expect(audio.played.skip(before).toList(), [Sfx.uiTab]);
    await _tapTab(tester, 'Missions');
    expect(audio.played.skip(before).toList(), [Sfx.uiTab]);
  });

  testWidgets('tabs keep their state while switching', (tester) async {
    await _bootHome(tester);
    // Scroll Home down.
    final homeScroll = find
        .descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(homeScroll, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 300));
    final offset = tester.state<ScrollableState>(homeScroll).position.pixels;
    expect(offset, greaterThan(100));

    // Friends: open the Requests tab.
    await _tapTab(tester, 'Friends');
    await tester.tap(find.text('Requests'));
    await _settle(tester);
    expect(find.text('Received'), findsOneWidget);

    await _tapTab(tester, 'Home');
    expect(
      tester.state<ScrollableState>(homeScroll).position.pixels,
      offset,
      reason: 'Home keeps its scroll position',
    );
    await _tapTab(tester, 'Friends');
    expect(find.text('Received'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('system back on another tab returns to Home first', (
    tester,
  ) async {
    final c = await _bootHome(tester);
    await _tapTab(tester, 'Missions');
    expect(find.byType(MissionsScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_router(c).state.uri.path, AppRoutes.home);

    // A page pushed over a tab pops back to that tab.
    await _tapTab(tester, 'Profile');
    _router(c).push(AppRoutes.settings);
    await _settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(AppBottomNav), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deep links open the right tab (incl. /friends?tab=…)', (
    tester,
  ) async {
    final c = await _bootHome(tester);
    _router(c).go('/friends?tab=requests');
    await _settle(tester);
    expect(find.byType(FriendsScreen), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.byType(AppBottomNav), findsOneWidget);

    _router(c).go(AppRoutes.games);
    await _settle(tester);
    expect(find.byType(GamesScreen), findsOneWidget);

    _router(c).go(AppRoutes.profile);
    await _settle(tester);
    expect(find.byType(ProfileScreen), findsOneWidget);

    _router(c).go(AppRoutes.missions);
    await _settle(tester);
    expect(find.byType(MissionsScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a sheet opened on a tab covers the bottom bar', (tester) async {
    final c = await _bootHome(tester);
    await tester.tap(find.text('Join with Code'));
    await _settle(tester);
    final sheet = find.byType(AppBottomSheetFrame);
    expect(sheet, findsOneWidget);
    // On the root navigator (above the shell), not inside the Home tab.
    expect(
      Navigator.of(tester.element(sheet)),
      same(_router(c).routerDelegate.navigatorKey.currentState),
    );
    // The bar sits under the sheet's barrier: tapping it switches nothing.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Games'),
      ),
      warnIfMissed: false,
    );
    await _settle(tester);
    expect(find.byType(GamesScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the bar is hidden in matchmaking, practice and the lobby', (
    tester,
  ) async {
    final c = await _bootHome(tester);
    final router = _router(c);

    router.push(AppRoutes.matchmakingFor(game: 'ludo', capacity: 4));
    await _settle(tester);
    expect(find.byType(AppBottomNav), findsNothing);
    expect(
      tabOpenModeFor(router.routerDelegate.currentConfiguration),
      TabOpenMode.overlay,
    );
    router.pop();
    await _settle(tester);
    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(
      tabOpenModeFor(router.routerDelegate.currentConfiguration),
      TabOpenMode.go,
    );

    router.push(AppRoutes.practiceFor(game: 'snakes_ladders'));
    await _settle(tester);
    expect(find.byType(AppBottomNav), findsNothing);
    router.pop();
    await _settle(tester);

    router.go(AppRoutes.roomLobby('r_1'));
    await _settle(tester);
    expect(find.byType(AppBottomNav), findsNothing);
    expect(
      tabOpenModeFor(router.routerDelegate.currentConfiguration),
      TabOpenMode.push,
    );

    router.go(AppRoutes.home);
    await _settle(tester);
    expect(find.byType(AppBottomNav), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the theme shortcut switches the whole app', (tester) async {
    final c = await _bootHome(tester);
    Brightness brightnessOf(Type screen) =>
        Theme.of(tester.element(find.byType(screen))).brightness;
    await tester.runAsync(
      () =>
          c.read(themeModeControllerProvider.notifier).setMode(ThemeMode.light),
    );
    await _settle(tester, 6);
    expect(brightnessOf(HomeScreen), Brightness.light);

    await tester.tap(find.byTooltip('Switch light/dark theme'));
    await _settle(tester, 6);
    expect(c.read(themeModeControllerProvider), ThemeMode.dark);
    expect(brightnessOf(HomeScreen), Brightness.dark);
    expect(brightnessOf(AppBottomNav), Brightness.dark);
    await _tapTab(tester, 'Profile');
    expect(brightnessOf(ProfileScreen), Brightness.dark);
    await tester.pumpWidget(const SizedBox());
  });
}
