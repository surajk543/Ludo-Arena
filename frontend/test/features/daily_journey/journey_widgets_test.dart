import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/core/state/in_match_provider.dart';
import 'package:ludo_arena/features/daily_journey/presentation/daily_journey_card.dart';
import 'package:ludo_arena/features/daily_journey/presentation/next_goal_row.dart';
import 'package:ludo_arena/features/daily_journey/presentation/playtime_toast_host.dart';
import 'package:ludo_arena/features/game/application/match_result_view.dart';
import 'package:ludo_arena/features/game/presentation/widgets/results_panel.dart';
import 'package:ludo_arena/features/missions/presentation/missions_screen.dart';
import 'package:ludo_arena/features/progression/application/level_up_controller.dart';

import '../game/support/play_test_support.dart' show ludoRoom, player, kNowMs;
import '../progression/meta_test_support.dart';
import 'journey_test_support.dart';

void main() {
  late TestEnv env;
  late JourneyFakes fakes;

  setUp(() async {
    env = await TestEnv.create();
    env.routeHappyPath();
    routeMeta(env);
    env.backend.json('GET', '/playtime', playtimeJson());
    fakes = JourneyFakes();
  });

  tearDown(() => fakes.close());

  Widget cardScreen() => const Scaffold(
    body: SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: DailyJourneyCard(),
    ),
  );

  /// Icons drawn inside a milestone marker.
  IconData markerIcon(WidgetTester tester, String id) => tester
      .widget<Icon>(
        find.descendant(
          of: byKeyString('playtime-marker-$id'),
          matching: find.byType(Icon),
        ),
      )
      .icon!;

  group('DailyJourneyCard', () {
    testWidgets('renders progress, milestone states, next reward and '
        'missions', (tester) async {
      await pumpMeta(tester, env, fakes, cardScreen());
      expect(find.text('DAILY PLAY JOURNEY'), findsOneWidget);
      expect(find.textContaining('18 / 60 min'), findsOneWidget);
      expect(
        find.text('12 more minutes to unlock 40 XP + 10,000 coins'),
        findsOneWidget,
      );
      expect(find.text('Daily missions: 1 / 3 completed'), findsOneWidget);
      expect(markerIcon(tester, 'playtime_10m'), Icons.check_rounded);
      expect(markerIcon(tester, 'playtime_30m'), Icons.timer_rounded);
      expect(markerIcon(tester, 'playtime_60m'), Icons.lock_rounded);
      expect(
        fakes.analytics.events.where(
          (e) => e == 'playtime_progress_viewed:home',
        ),
        hasLength(1),
      );
    });

    testWidgets('updates from a server push without a refetch', (tester) async {
      await pumpMeta(tester, env, fakes, cardScreen());
      fakes.push(playtimeJson(seconds: 31 * 60));
      await flush(tester);
      expect(find.textContaining('31 / 60 min'), findsOneWidget);
      expect(markerIcon(tester, 'playtime_30m'), Icons.check_rounded);
      expect(
        find.text('29 more minutes to unlock 60 XP + 20,000 coins'),
        findsOneWidget,
      );
      expect(env.backend.calls('GET', '/playtime'), hasLength(1));
    });

    testWidgets('all done: a calm message, no countdown', (tester) async {
      env.backend.json('GET', '/playtime', playtimeJson(seconds: 61 * 60));
      await pumpMeta(tester, env, fakes, cardScreen());
      expect(
        find.text("All of today's playtime rewards are yours. Nice playing!"),
        findsOneWidget,
      );
    });

    testWidgets('hidden while daily playtime is disabled', (tester) async {
      env.backend.on(
        'GET',
        '/playtime',
        (_) => FakeResponse.error(404, 'not_found'),
      );
      await pumpMeta(tester, env, fakes, cardScreen());
      expect(byKeyString('daily-journey-card'), findsNothing);
      expect(byKeyString('daily-journey-loading'), findsNothing);
      expect(byKeyString('daily-journey-failed'), findsNothing);
    });

    testWidgets('loading skeleton, then content', (tester) async {
      final gate = Completer<FakeResponse>();
      env.backend.on('GET', '/playtime', (_) => gate.future);
      await pumpMeta(tester, env, fakes, cardScreen());
      expect(byKeyString('daily-journey-loading'), findsOneWidget);
      gate.complete(FakeResponse(200, playtimeJson()));
      await flush(tester);
      expect(byKeyString('daily-journey-card'), findsOneWidget);
    });

    testWidgets('a failed first load offers retry', (tester) async {
      env.backend.offline = true;
      await pumpMeta(tester, env, fakes, cardScreen(), signedIn: false);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DailyJourneyCard)),
      );
      await tester.runAsync(() async {
        // Sign-in needs the network; go offline right after it.
        env.backend.offline = false;
        await signIn(c);
        env.backend.offline = true;
        await settle(40);
      });
      await flush(tester);
      expect(byKeyString('daily-journey-failed'), findsOneWidget);
      env.backend.offline = false;
      await tester.tap(byKeyString('daily-journey-failed'));
      await flush(tester);
      expect(byKeyString('daily-journey-card'), findsOneWidget);
    });

    testWidgets('tap opens the Missions tab', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => cardScreen()),
          GoRoute(
            path: '/missions',
            builder: (_, _) => const Scaffold(body: Text('missions-tab')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpMeta(tester, env, fakes, const SizedBox(), router: router);
      await tester.tap(byKeyString('daily-journey-card'));
      await settleRoute(tester);
      expect(find.text('missions-tab'), findsOneWidget);
    });

    for (final (name, size, theme, locale) in [
      ('dark', Viewports.phone, ThemeMode.dark, const Locale('en')),
      ('Arabic RTL', Viewports.phone, ThemeMode.light, const Locale('ar')),
      (
        'Urdu RTL dark, small',
        Viewports.small,
        ThemeMode.dark,
        const Locale('ur'),
      ),
      ('Hindi, tablet', Viewports.tablet, ThemeMode.light, const Locale('hi')),
      (
        'Indonesian, large text',
        Viewports.small,
        ThemeMode.light,
        const Locale('id'),
      ),
    ]) {
      testWidgets('lays out without overflow: $name', (tester) async {
        await pumpMeta(
          tester,
          env,
          fakes,
          cardScreen(),
          size: size,
          themeMode: theme,
          locale: locale,
          textScale: name.contains('large') ? 1.35 : 1.0,
        );
        expect(tester.takeException(), isNull);
        expect(byKeyString('daily-journey-card'), findsOneWidget);
        final dir = Directionality.of(
          tester.element(byKeyString('daily-journey-card')),
        );
        expect(
          dir,
          locale.languageCode == 'ar' || locale.languageCode == 'ur'
              ? TextDirection.rtl
              : TextDirection.ltr,
        );
      });
    }
  });

  group('Missions screen section', () {
    testWidgets('lists every milestone with reward, status and time left', (
      tester,
    ) async {
      await pumpMeta(tester, env, fakes, const MissionsScreen());
      expect(byKeyString('playtime-section'), findsOneWidget);
      expect(find.text('18 / 60 min'), findsOneWidget);
      expect(
        find.descendant(
          of: byKeyString('playtime-milestone-playtime_10m'),
          matching: find.text('Reward received'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byKeyString('playtime-milestone-playtime_30m'),
          matching: find.text('12 min to go'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byKeyString('playtime-milestone-playtime_60m'),
          matching: find.text('Locked · 42 min to go'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Only active time in a match'),
        findsOneWidget,
      );
      expect(
        fakes.analytics.events,
        contains('playtime_progress_viewed:missions'),
      );
      // The daily missions still follow.
      await scrollTo(tester, find.text('Daily missions'));
      expect(find.text('Daily missions'), findsOneWidget);
    });

    testWidgets('absent while disabled', (tester) async {
      env.backend.on(
        'GET',
        '/playtime',
        (_) => FakeResponse.error(404, 'not_found'),
      );
      await pumpMeta(tester, env, fakes, const MissionsScreen());
      expect(byKeyString('playtime-section'), findsNothing);
    });
  });

  group('PlaytimeToastHost', () {
    late GlobalKey<NavigatorState> navKey;
    late ProviderContainer c;

    Future<void> pumpHost(WidgetTester tester) async {
      env.backend.json('GET', '/playtime', playtimeJson(seconds: 0));
      navKey = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: navKey,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('roll'),
                  onPressed: () {},
                  child: const Text('Roll'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/missions',
            builder: (_, _) => const Scaffold(body: Text('missions-tab')),
          ),
        ],
      );
      addTearDown(router.dispose);
      c = await pumpMeta(
        tester,
        env,
        fakes,
        const SizedBox(),
        router: router,
        shell: (context, child) =>
            PlaytimeToastHost(navigatorKey: navKey, child: child!),
      );
    }

    Map<String, dynamic> granted(
      int seconds,
      List<(String, int, int, int)> ms,
    ) => playtimeJson(
      seconds: seconds,
      granted: [
        for (final m in ms)
          milestoneJson(m.$1, m.$2, coins: m.$3, xp: m.$4, status: 'completed'),
      ],
    );

    final toast = byKeyString('playtime-toast');

    testWidgets('appears from a server push and closes itself after 8 s', (
      tester,
    ) async {
      await pumpHost(tester);
      expect(toast, findsNothing);
      fakes.push(granted(10 * 60, [('playtime_10m', 10, 5000, 25)]));
      await flush(tester);
      expect(toast, findsOneWidget);
      expect(find.text('Daily milestone completed!'), findsOneWidget);
      expect(find.text('You played for 10 minutes today.'), findsOneWidget);
      expect(find.text('+25 XP'), findsOneWidget);
      // Non-blocking: game controls stay usable underneath.
      await tester.tap(byKeyString('roll'));
      await tester.pump(const Duration(seconds: 7));
      expect(toast, findsOneWidget);
      await tester.pump(const Duration(seconds: 1, milliseconds: 100));
      expect(toast, findsNothing);
      expect(fakes.analytics.events, contains('playtime_toast_dismissed:auto'));
    });

    testWidgets('the close button dismisses at once', (tester) async {
      await pumpHost(tester);
      fakes.push(granted(10 * 60, [('playtime_10m', 10, 5000, 25)]));
      await flush(tester);
      await tester.tap(byKeyString('playtime-toast-close'));
      await tester.pump();
      expect(toast, findsNothing);
      expect(
        fakes.analytics.events,
        contains('playtime_toast_dismissed:close'),
      );
    });

    testWidgets('View progress opens the Missions tab', (tester) async {
      await pumpHost(tester);
      fakes.push(granted(10 * 60, [('playtime_10m', 10, 5000, 25)]));
      await flush(tester);
      await tester.tap(byKeyString('playtime-toast-view'));
      await settleRoute(tester);
      expect(toast, findsNothing);
      expect(find.text('missions-tab'), findsOneWidget);
      expect(
        fakes.analytics.events,
        contains('playtime_toast_dismissed:action'),
      );
    });

    testWidgets('milestones completed together share one toast; a later one '
        'waits its turn', (tester) async {
      await pumpHost(tester);
      fakes.push(
        granted(31 * 60, [
          ('playtime_10m', 10, 5000, 25),
          ('playtime_30m', 30, 10000, 40),
        ]),
      );
      await flush(tester);
      expect(toast, findsOneWidget);
      expect(find.text('Daily milestones completed!'), findsOneWidget);
      expect(find.text('You played for 30 minutes today.'), findsOneWidget);
      expect(find.text('+65 XP'), findsOneWidget);

      fakes.push(granted(60 * 60, [('playtime_60m', 60, 20000, 60)]));
      await flush(tester);
      expect(toast, findsOneWidget, reason: 'never two toasts at once');
      expect(find.text('You played for 30 minutes today.'), findsOneWidget);

      await tester.tap(byKeyString('playtime-toast-close'));
      await flush(tester);
      expect(find.text('You played for 60 minutes today.'), findsOneWidget);
      await tester.tap(byKeyString('playtime-toast-close'));
      await tester.pump();
    });

    testWidgets('deferred during a match, shown after it', (tester) async {
      await pumpHost(tester);
      c.read(inMatchProvider.notifier).set(true);
      fakes.push(granted(10 * 60, [('playtime_10m', 10, 5000, 25)]));
      await flush(tester);
      expect(toast, findsNothing);
      c.read(inMatchProvider.notifier).set(false);
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pump();
      expect(toast, findsOneWidget);
      // A match starting under it takes it away (and keeps it for later).
      c.read(inMatchProvider.notifier).set(true);
      await tester.pump();
      expect(toast, findsNothing);
      c.read(inMatchProvider.notifier).set(false);
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pump();
      expect(toast, findsOneWidget);
      await tester.tap(byKeyString('playtime-toast-close'));
      // Lets the haptic pattern finish.
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('waits for a pending level-up celebration', (tester) async {
      await pumpHost(tester);
      final levelUp = c.read(levelUpControllerProvider.notifier)
        ..enqueue(5, const []);
      fakes.push(granted(10 * 60, [('playtime_10m', 10, 5000, 25)]));
      await flush(tester);
      expect(toast, findsNothing);
      levelUp
        ..takeNext()
        ..markShown();
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pump();
      expect(toast, findsOneWidget);
      await tester.tap(byKeyString('playtime-toast-close'));
      // Lets the haptic pattern finish.
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('dark theme and RTL', (tester) async {
      env.backend.json('GET', '/playtime', playtimeJson(seconds: 0));
      navKey = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: navKey,
        routes: [GoRoute(path: '/', builder: (_, _) => const Scaffold())],
      );
      addTearDown(router.dispose);
      await pumpMeta(
        tester,
        env,
        fakes,
        const SizedBox(),
        router: router,
        locale: const Locale('ar'),
        themeMode: ThemeMode.dark,
        size: Viewports.small,
        shell: (context, child) =>
            PlaytimeToastHost(navigatorKey: navKey, child: child!),
      );
      fakes.push(granted(10 * 60, [('playtime_10m', 10, 5000, 25)]));
      await flush(tester);
      expect(tester.takeException(), isNull);
      expect(toast, findsOneWidget);
      expect(find.text('اكتملت مرحلة يومية!'), findsOneWidget);
      await tester.tap(byKeyString('playtime-toast-close'));
      await tester.pump();
    });
  });

  group('Next goal', () {
    testWidgets('names one achievable goal and opens the Missions tab', (
      tester,
    ) async {
      String? opened;
      await pumpMeta(
        tester,
        env,
        fakes,
        Scaffold(body: NextGoalRow(onOpen: (l) => opened = l)),
      );
      expect(
        find.text('Play 12 more minutes to unlock 40 XP + 10,000 coins.'),
        findsOneWidget,
      );
      await tester.tap(byKeyString('next-goal-open'));
      expect(opened, '/missions');
      expect(
        fakes.analytics.events,
        containsAll(<String>[
          'next_goal_shown:playtime',
          'next_goal_tapped:playtime',
        ]),
      );
    });

    testWidgets('on the match results, only when the caller wires it', (
      tester,
    ) async {
      final room = ludoRoom(
        status: RoomStatuses.finished,
        players: [player(0), player(1)],
        result: const RoomResult(winnerSeat: 0, placements: [0, 1], payout: 0),
        rematch: RematchState(open: true, deadline: kNowMs + 30000),
      );
      Widget panel({ValueChanged<String>? onNextGoal}) => Scaffold(
        body: ResultsPanel(
          room: room,
          selfUid: 'u_0',
          rewards: const MatchRewards(),
          onRematch: (_) async {},
          onPlayAgain: () {},
          onHome: () {},
          onNextGoal: onNextGoal,
        ),
      );
      await pumpMeta(tester, env, fakes, panel(onNextGoal: (_) {}));
      expect(byKeyString('next-goal-playtime'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
