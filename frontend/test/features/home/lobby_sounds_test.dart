import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/theme/theme_controller.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/home/application/play_options.dart';
import 'package:ludo_royale/features/home/presentation/home_screen.dart';

import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

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

/// Separate taps are further apart than the UI gesture window.
Future<void> nextGesture(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 300));

void main() {
  Future<(TestEnv, ProviderContainer)> pumpHome(
    WidgetTester tester, {
    List<Override> extra = const [],
  }) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    final c = await pumpScreen(
      tester,
      env,
      const SizedBox(),
      router: _router(),
      extra: extra,
      prepare: (c) =>
          c.read(sessionControllerProvider.notifier).continueAsGuest(),
    );
    // Opening the lobby makes no sound by itself.
    expect(env.audio.played, isEmpty);
    return (env, c);
  }

  testWidgets('Play Online: one sound per tap through the options sheet', (
    tester,
  ) async {
    final (env, _) = await pumpHome(tester);
    final audio = env.audio;

    // The button opens the sheet: the open sound replaces the click.
    await tester.tap(find.text('Play Online').first);
    await tester.pumpAndSettle();
    expect(audio.played, [Sfx.uiOpen]);

    // Player count and mode chips.
    await tester.tap(find.text('2 players'));
    await nextGesture(tester);
    expect(audio.played, [Sfx.uiOpen, Sfx.uiTab]);
    await tester.tap(find.text('Quick'));
    await nextGesture(tester);
    expect(audio.played, [Sfx.uiOpen, Sfx.uiTab, Sfx.uiTab]);
    // The current choice again: nothing changes, no sound.
    await tester.tap(find.text('Quick'));
    await nextGesture(tester);
    expect(audio.played, hasLength(3));

    // Find match closes the sheet and opens matchmaking: only the play cue.
    await tester.tap(find.text('Find match'));
    await tester.pumpAndSettle();
    expect(find.textContaining('AT /matchmaking'), findsOneWidget);
    expect(audio.played, [Sfx.uiOpen, Sfx.uiTab, Sfx.uiTab, Sfx.lobbyPlay]);
  });

  testWidgets('closing a sheet with its close button plays the close sound', (
    tester,
  ) async {
    final (env, _) = await pumpHome(tester);
    await tester.tap(find.text('Private Room'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(env.audio.played, [Sfx.uiOpen, Sfx.uiClose]);
  });

  testWidgets('a disabled Find match (not enough coins) is silent', (
    tester,
  ) async {
    final (env, _) = await pumpHome(
      tester,
      extra: [entryFeeProvider.overrideWith((ref, game) => 999999999)],
    );
    await tester.tap(find.text('Play Online').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find match'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('AT /matchmaking'), findsNothing);
    expect(env.audio.played, [Sfx.uiOpen]);
  });

  testWidgets('Quick Play is one play cue', (tester) async {
    final (env, _) = await pumpHome(tester);
    await tester.tap(find.text('Quick Play'));
    await tester.pumpAndSettle();
    expect(env.audio.played, [Sfx.lobbyPlay]);
  });

  testWidgets('explore tiles click once', (tester) async {
    final (env, _) = await pumpHome(tester);
    await reveal(tester, find.text('Collection Room'));
    await tester.tap(find.text('Collection Room'));
    await tester.pumpAndSettle();
    expect(find.text('AT /collection'), findsOneWidget);
    expect(env.audio.played, [Sfx.uiTap]);
  });

  testWidgets('rebuilds (theme change, balance refresh) never play', (
    tester,
  ) async {
    final (env, c) = await pumpHome(tester);
    await c.read(themeModeControllerProvider.notifier).setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    await c.read(themeModeControllerProvider.notifier).setMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(env.audio.played, isEmpty);
  });

  testWidgets('the lobby music is requested only by the app root', (
    tester,
  ) async {
    // Screens never start music on their own (lobbyMusicProvider does).
    final (env, _) = await pumpHome(tester);
    expect(env.audio.musicCalls, isEmpty);
  });
}
