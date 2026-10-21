import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/analytics/analytics_providers.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/core/time/server_clock.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/game/application/match_result_view.dart';
import 'package:ludo_royale/features/game/presentation/game_route_screen.dart';
import 'package:ludo_royale/features/game/presentation/widgets/player_panel.dart';
import 'package:ludo_royale/features/game/presentation/widgets/results_panel.dart';
import 'package:ludo_royale/features/social/presentation/player_actions_sheet.dart';
import 'package:ludo_royale/shared/game_visuals/game_visuals.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';
import '../game/support/play_test_support.dart';
import '../progression/meta_test_support.dart'
    show friendJson, friendsJson, limitJson, reportJson, reportsJson, routeMeta;

/// A Ludo match: me (`u_0`, seat 0), a human opponent (`u_1`, "Ravi"), a
/// bot (seat 2, "Bolt") and another human (seat 3).
RoomSnapshot _room({int turnSeat = 0, String status = RoomStatuses.playing}) =>
    ludoRoom(
      turnSeat: turnSeat,
      status: status,
      players: [
        player(0),
        player(1, name: 'Ravi', level: 9),
        player(2, name: 'Bolt', bot: true),
        player(3, name: 'Meera'),
      ],
    );

class _Match {
  _Match(this.h, this.env);
  final PlayHarness h;
  final TestEnv env;
}

/// MatchView with the fake HTTP backend, signed in as a guest.
Future<_Match> _pumpMatch(
  WidgetTester tester, {
  RoomSnapshot? room,
  String selfUid = 'u_0',
  void Function(TestEnv env)? routes,
  Locale locale = const Locale('en'),
  Size size = const Size(360, 740),
  double textScale = 1.0,
}) async {
  final r = room ?? _room();
  final env = await TestEnv.create();
  env.routeHappyPath();
  routeMeta(env);
  routes?.call(env);
  final h = PlayHarness(
    initial: ActiveRoomState(room: r, selfUid: selfUid),
  );
  // The harness keeps its own clock / prefs / audio / analytics.
  final kept = {
    preferencesStoreProvider,
    analyticsServiceProvider,
    audioServiceProvider,
    clockProvider,
    serverClockProvider,
  };
  await h.pump(
    tester,
    GameRouteScreen(roomId: r.id),
    locale: locale,
    size: size,
    textScale: textScale,
    extra: [...env.overrides.where((o) => !kept.contains(o.origin))],
  );
  await tester.runAsync(() async {
    await h.container
        .read(sessionControllerProvider.notifier)
        .continueAsGuest();
    await settle();
  });
  await _settle(tester);
  return _Match(h, env);
}

/// Lets HTTP (real async) and sheet transitions complete.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => settle(40));
    for (var j = 0; j < 4; j++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Finder _key(String k) => find.byKey(ValueKey(k));

Future<void> _openPod(WidgetTester tester, int seat) async {
  await tester.tap(_key('pod-$seat'));
  await _settle(tester);
}

String _buttonLabel(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(of: _key(key), matching: find.byType(Text)),
    )
    .map((t) => t.data)
    .join();

void main() {
  group('opponent pods', () {
    testWidgets('an opponent pod opens the sheet; my own pod does not', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpMatch(tester);
      // My pod is not a button.
      expect(_key('pod-0'), findsNothing);
      await tester.tap(
        find.byWidgetPredicate((w) => w is PlayerPanel && w.player.seat == 0),
      );
      await _settle(tester);
      expect(find.byType(PlayerActionsPanel), findsNothing);

      // Opponent pods announce themselves as buttons with a hint.
      expect(
        tester.getSemantics(_key('pod-1')),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          onTapHint: 'Show player options',
        ),
      );

      await _openPod(tester, 1);
      expect(find.byType(PlayerActionsPanel), findsOneWidget);
      final sheet = _key('player-sheet');
      expect(
        find.descendant(of: sheet, matching: find.text('Ravi')),
        findsOneWidget,
      );
      expect(find.text('Level 9'), findsOneWidget);
      expect(_buttonLabel(tester, 'sheet-friend-action'), 'Add friend');
      expect(_buttonLabel(tester, 'sheet-report'), 'Report player');
      expect(find.text('Reports left today: 2 of 2'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a bot pod shows the profile only (no actions, no bot note)', (
      tester,
    ) async {
      await _pumpMatch(tester);
      await _openPod(tester, 2);
      final sheet = _key('player-sheet');
      expect(
        find.descendant(of: sheet, matching: find.text('Bolt')),
        findsOneWidget,
      );
      expect(find.text('Level 4'), findsOneWidget);
      expect(_key('sheet-friend-action'), findsNothing);
      expect(_key('sheet-report'), findsNothing);
      expect(
        find.descendant(
          of: sheet,
          matching: find.textContaining(
            RegExp(r'\bbot|computer', caseSensitive: false),
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('spectators see the profile without actions', (tester) async {
      await _pumpMatch(tester, selfUid: 'u_spectator');
      await _openPod(tester, 1);
      expect(find.byType(PlayerActionsPanel), findsOneWidget);
      expect(_key('sheet-friend-action'), findsNothing);
      expect(_key('sheet-report'), findsNothing);
    });

    testWidgets('gameplay input still works once the sheet is closed', (
      tester,
    ) async {
      final m = await _pumpMatch(tester);
      await _openPod(tester, 1);
      await tester.tap(find.byTooltip('Close'));
      await _settle(tester);
      expect(find.byType(PlayerActionsPanel), findsNothing);
      await tester.tap(find.byType(DiceView));
      await tester.pump();
      expect(m.h.controller.calls, ['roll:5']);
    });

    testWidgets('the sheet survives the match ending', (tester) async {
      final m = await _pumpMatch(tester);
      await _openPod(tester, 1);
      m.h.controller.pushSnapshot(
        _room(status: RoomStatuses.finished).copyWith(
          v: 20,
          result: const RoomResult(winnerSeat: 1, placements: [1, 0, 3, 2]),
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(PlayerActionsPanel), findsOneWidget);
    });
  });

  group('add friend from a match', () {
    testWidgets('sends the opponent uid and shows "Request sent"', (
      tester,
    ) async {
      final m = await _pumpMatch(
        tester,
        routes: (env) => env.backend.json('POST', '/friends/requests', {
          'friend': friendJson('u_1', 'Ravi', status: 'outgoing'),
        }, status: 201),
      );
      await _openPod(tester, 1);
      await tester.tap(_key('sheet-friend-action'));
      await _settle(tester);
      expect(m.env.backend.calls('POST', '/friends/requests').single.json, {
        'friendCode': 'u_1',
      });
      expect(_buttonLabel(tester, 'sheet-friend-action'), 'Request sent');
      expect(m.h.analytics.events, contains('friend_request_sent:match'));
    });

    testWidgets('an incoming request shows Accept and accepts it', (
      tester,
    ) async {
      final m = await _pumpMatch(
        tester,
        routes: (env) => env.backend
          ..json(
            'GET',
            '/friends',
            friendsJson(
              incoming: [friendJson('u_1', 'Ravi', status: 'incoming')],
            ),
          )
          ..json('POST', '/friends/requests/u_1/accept', {
            'friend': friendJson('u_1', 'Ravi'),
          }),
      );
      await _openPod(tester, 1);
      expect(_buttonLabel(tester, 'sheet-friend-action'), 'Accept request');
      await tester.tap(_key('sheet-friend-action'));
      await _settle(tester);
      expect(
        m.env.backend.calls('POST', '/friends/requests/u_1/accept'),
        hasLength(1),
      );
      expect(_buttonLabel(tester, 'sheet-friend-action'), 'Friends');
    });

    testWidgets('existing friends are shown as such', (tester) async {
      await _pumpMatch(
        tester,
        routes: (env) => env.backend.json(
          'GET',
          '/friends',
          friendsJson(friends: [friendJson('u_1', 'Ravi', online: true)]),
        ),
      );
      await _openPod(tester, 1);
      expect(_buttonLabel(tester, 'sheet-friend-action'), 'Friends');
    });

    testWidgets('at the friend limit Add friend is disabled and explained', (
      tester,
    ) async {
      final m = await _pumpMatch(
        tester,
        routes: (env) => env.backend.json(
          'GET',
          '/friends',
          friendsJson(friendCount: 20, maxFriends: 20),
        ),
      );
      await _openPod(tester, 1);
      expect(
        find.text('You can have up to 20 friends — remove one to add more.'),
        findsOneWidget,
      );
      await tester.tap(_key('sheet-friend-action'));
      await _settle(tester);
      expect(m.env.backend.calls('POST', '/friends/requests'), isEmpty);
    });

    testWidgets('a 422 friend_limit is explained in the sheet', (tester) async {
      await _pumpMatch(
        tester,
        routes: (env) => env.backend.on(
          'POST',
          '/friends/requests',
          (_) => FakeResponse.error(422, 'friend_limit'),
        ),
      );
      await _openPod(tester, 1);
      await tester.tap(_key('sheet-friend-action'));
      await _settle(tester);
      expect(
        find.text(
          'You can have up to 20 friends. Remove a friend to add someone new.',
        ),
        findsOneWidget,
      );
    });
  });

  group('report from a match', () {
    Future<void> pickAndSend(WidgetTester tester, String reason) async {
      await tester.tap(_key('sheet-report'));
      await _settle(tester);
      // Nothing is sent before a reason is picked.
      await tester.tap(_key('send-report'));
      await _settle(tester);
      await tester.tap(_key('report-reason-$reason'));
      await tester.pump();
      await tester.ensureVisible(_key('send-report'));
      await tester.tap(_key('send-report'));
      await _settle(tester);
    }

    testWidgets('sends uid, roomId and reason, then confirms with the '
        'remaining count', (tester) async {
      final m = await _pumpMatch(
        tester,
        routes: (env) => env.backend.on('POST', '/reports', (_) {
          final report = reportJson(
            'rep_1',
            uid: 'u_1',
            name: 'Ravi',
            ago: Duration.zero,
          );
          // The server now lists it.
          env.backend.json(
            'GET',
            '/reports',
            reportsJson(reports: [report], remaining: 1),
          );
          return FakeResponse(201, {
            'report': report,
            'limit': limitJson(remaining: 1),
          });
        }),
      );
      await _openPod(tester, 1);
      await pickAndSend(tester, 'offensive_name');
      final calls = m.env.backend.calls('POST', '/reports');
      expect(calls, hasLength(1));
      expect(calls.single.json, {
        'uid': 'u_1',
        'roomId': 'r_1',
        'reason': 'offensive_name',
      });
      expect(find.byType(PlayerActionsPanel), findsNothing);
      expect(
        find.text('Report sent. 1 of 2 reports left today.'),
        findsOneWidget,
      );
      expect(m.h.analytics.events, contains('player_reported:offensive_name'));

      // Reopening: this player is now marked as reported.
      await _openPod(tester, 1);
      expect(_buttonLabel(tester, 'sheet-report'), 'Reported');
      expect(
        find.text('You reported this player in the last 24 hours.'),
        findsOneWidget,
      );
    });

    testWidgets('409 already_reported disables Report', (tester) async {
      final m = await _pumpMatch(
        tester,
        routes: (env) => env.backend.on(
          'POST',
          '/reports',
          (_) => FakeResponse.error(409, 'already_reported'),
        ),
      );
      await _openPod(tester, 1);
      await pickAndSend(tester, 'cheating');
      expect(
        find.text('You reported this player in the last 24 hours.'),
        findsOneWidget,
      );
      expect(_buttonLabel(tester, 'sheet-report'), 'Reported');
      await tester.tap(_key('sheet-report'));
      await _settle(tester);
      expect(_key('report-step'), findsNothing);
      expect(m.env.backend.calls('POST', '/reports'), hasLength(1));
      expect(m.h.analytics.events, isNot(contains('player_reported:cheating')));
    });

    for (final (code, status, text) in [
      ('cannot_report_bot', 422, "This player can't be reported."),
      ('cannot_report_self', 422, "You can't report yourself."),
      (
        'not_in_room',
        422,
        "You can only report players from a match you're in.",
      ),
      (
        'room_not_found',
        404,
        "This match can't be found anymore, so the report wasn't sent.",
      ),
    ]) {
      testWidgets('$status $code is explained', (tester) async {
        await _pumpMatch(
          tester,
          routes: (env) => env.backend.on(
            'POST',
            '/reports',
            (_) => FakeResponse.error(status, code),
          ),
        );
        await _openPod(tester, 3);
        await pickAndSend(tester, 'other');
        expect(find.text(text), findsOneWidget);
        // Still on the reason step: the user can go back or retry.
        expect(_key('report-step'), findsOneWidget);
      });
    }

    testWidgets('429 report_limit disables Report and shows the reset time', (
      tester,
    ) async {
      final resetsAt = kNowMs + const Duration(hours: 3).inMilliseconds;
      final m = await _pumpMatch(
        tester,
        routes: (env) => env.backend.on(
          'POST',
          '/reports',
          (_) => FakeResponse.error(
            429,
            'report_limit',
            details: {'resetsAt': resetsAt},
          ),
        ),
      );
      await _openPod(tester, 1);
      await pickAndSend(tester, 'leaving_or_stalling');
      final note = tester
          .widgetList<Text>(
            find.descendant(
              of: _key('sheet-report-note'),
              matching: find.byType(Text),
            ),
          )
          .single
          .data!;
      expect(note, startsWith("You've used today's 2 reports."));
      expect(note, contains('You can report again at 3:00'));
      await tester.tap(_key('sheet-report'));
      await _settle(tester);
      expect(_key('report-step'), findsNothing);
      expect(m.env.backend.calls('POST', '/reports'), hasLength(1));
    });

    testWidgets('no reports left today: Report is disabled up front', (
      tester,
    ) async {
      final m = await _pumpMatch(
        tester,
        routes: (env) => env.backend.json(
          'GET',
          '/reports',
          reportsJson(
            remaining: 0,
            resetsAt: kNowMs + const Duration(hours: 5).inMilliseconds,
          ),
        ),
      );
      await _openPod(tester, 1);
      expect(find.textContaining('You can report again at 5:00'), findsOne);
      await tester.tap(_key('sheet-report'));
      await _settle(tester);
      expect(_key('report-step'), findsNothing);
      expect(m.env.backend.calls('POST', '/reports'), isEmpty);
    });
  });

  group('layout', () {
    for (final (locale, mode) in [
      (const Locale('ar'), 'ar'),
      (const Locale('ur'), 'ur'),
    ]) {
      testWidgets('the sheet fits 320×640 in $mode (RTL) at 1.35× text', (
        tester,
      ) async {
        await expectNoOverflow(tester, () async {
          await _pumpMatch(
            tester,
            locale: locale,
            size: const Size(320, 640),
            textScale: 1.35,
            routes: (env) => env.backend.json(
              'GET',
              '/reports',
              reportsJson(remaining: 0, resetsAt: kNowMs + 3600000),
            ),
          );
          await _openPod(tester, 1);
          expect(find.byType(PlayerActionsPanel), findsOneWidget);
          expect(
            Directionality.of(tester.element(find.byType(PlayerActionsPanel))),
            TextDirection.rtl,
          );
        });
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the reason step fits 320×640 in ar at 1.35× (dark)', (
      tester,
    ) async {
      await expectNoOverflow(tester, () async {
        await _pumpMatch(
          tester,
          locale: const Locale('ar'),
          size: const Size(320, 640),
          textScale: 1.35,
        );
        await _openPod(tester, 1);
        await tester.tap(_key('sheet-report'));
        await _settle(tester);
        expect(_key('report-step'), findsOneWidget);
      });
      expect(tester.takeException(), isNull);
    });
  });

  group('results panel', () {
    testWidgets('opponent rows open player options; my row does not', (
      tester,
    ) async {
      final tapped = <String>[];
      final room = _room(status: RoomStatuses.finished).copyWith(
        result: const RoomResult(winnerSeat: 1, placements: [1, 0, 3, 2]),
      );
      final h = PlayHarness(
        initial: ActiveRoomState(room: room, selfUid: 'u_0'),
      );
      await h.pump(
        tester,
        Scaffold(
          body: ResultsPanel(
            room: room,
            selfUid: 'u_0',
            rewards: const MatchRewards(),
            onRematch: (_) async {},
            onPlayAgain: () {},
            onHome: () {},
            onPlayerTap: (p) => tapped.add(p.uid),
          ),
        ),
      );
      expect(_key('placement-0'), findsNothing);
      await tester.tap(_key('placement-1'));
      await tester.pump();
      expect(tapped, ['u_1']);
    });
  });
}
