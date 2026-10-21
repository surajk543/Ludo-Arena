import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/app/app.dart';
import 'package:ludo_royale/app/match_resume.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/realtime_providers.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/features/home/presentation/home_screen.dart';
import 'package:ludo_royale/features/ludo/presentation/screens/ludo_game_screen.dart';

import '../core/protocol/fixtures.dart';
import '../core/realtime/fakes.dart';
import '../helpers/harness.dart';
import '../helpers/screen_harness.dart';

void Function()? _stop;

/// Unmounts the app and closes the socket (its timers must not outlive the
/// test).
Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  _stop?.call();
  await tester.pump(const Duration(seconds: 1));
}

/// Boots the real app with a restored session and a scripted socket.
Future<FakeConnector> _boot(WidgetTester tester) async {
  setViewportSize(tester, Viewports.phone);
  final env = await TestEnv.create(prefs: {PrefKeys.languageChosen: true});
  env.routeHappyPath();
  env.seedSession();
  final connector = FakeConnector();
  env.wsConnector = connector.call;
  final container = env.container();
  addTearDown(container.dispose);
  _stop = () => container.read(realtimeConnectionProvider).stop();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: LudoRoyaleApp(),
      ),
    ),
  );
  await _settle(tester);
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(connector.sockets, hasLength(1), reason: 'socket opened when ready');
  return connector;
}

Future<void> _settle(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(settle);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The server's launch sequence: `connection.ready` naming the active room,
/// then the snapshot answering the client's `game.request_sync`.
Future<void> _serverHasRoom(
  WidgetTester tester,
  FakeSocket s,
  Map<String, dynamic> room,
) async {
  s.ready(activeRoomId: room['id'] as String);
  await _settle(tester, 2);
  final req = s.sentOfType('game.request_sync').last;
  expect(req['p'], {'roomId': room['id']});
  s.serverSend('game.state', {'room': room}, req['id'] as String);
  await _settle(tester, 4);
}

void main() {
  group('resumeLocationFor', () {
    ActiveRoomState stateFor(Map<String, dynamic> room) =>
        ActiveRoomState(room: RoomSnapshot.fromJson(room), selfUid: 'u_0');

    test('playing → game; lobbies → lobby or game; otherwise nothing', () {
      expect(
        resumeLocationFor(stateFor(ludoRoomJson())),
        AppRoutes.game('r_1'),
      );
      expect(
        resumeLocationFor(
          stateFor(ludoRoomJson(status: 'lobby', mode: 'private')),
        ),
        AppRoutes.roomLobby('r_1'),
      );
      expect(
        resumeLocationFor(
          stateFor(ludoRoomJson(status: 'lobby', mode: 'practice')),
        ),
        AppRoutes.roomLobby('r_1'),
      );
      expect(
        resumeLocationFor(stateFor(ludoRoomJson(status: 'lobby'))),
        AppRoutes.game('r_1'),
      );
      expect(
        resumeLocationFor(stateFor(ludoRoomJson(status: 'finished'))),
        isNull,
      );
      expect(
        resumeLocationFor(stateFor(ludoRoomJson(status: 'closed'))),
        isNull,
      );
      expect(resumeLocationFor(const ActiveRoomState(selfUid: 'u_0')), isNull);
    });

    test('a forfeited or unseated player is not resumed', () {
      final forfeited = ludoRoomJson();
      (forfeited['players'] as List).first['forfeited'] = true;
      expect(resumeLocationFor(stateFor(forfeited)), isNull);
      expect(
        resumeLocationFor(
          ActiveRoomState(
            room: RoomSnapshot.fromJson(ludoRoomJson()),
            selfUid: 'u_9',
          ),
        ),
        isNull,
      );
    });
  });

  group('after a force close', () {
    testWidgets('launch reopens the running match', (tester) async {
      final connector = await _boot(tester);
      await _serverHasRoom(tester, connector.last, ludoRoomJson(turnSeat: 0));
      expect(find.byType(LudoGameScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      await _end(tester);
    });

    testWidgets('no active room: stays on Home', (tester) async {
      final connector = await _boot(tester);
      connector.last.ready();
      await _settle(tester, 4);
      expect(connector.last.sentOfType('game.request_sync'), isEmpty);
      expect(find.byType(HomeScreen), findsOneWidget);
      await _end(tester);
    });

    testWidgets('a match lost by timeouts is not reopened', (tester) async {
      final connector = await _boot(tester);
      final room = ludoRoomJson();
      (room['players'] as List).first['forfeited'] = true;
      await _serverHasRoom(tester, connector.last, room);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LudoGameScreen), findsNothing);
      await _end(tester);
    });

    testWidgets('removed for missed turns while closed: notice on Home, '
        'the room is left', (tester) async {
      final connector = await _boot(tester);
      final room = ludoRoomJson();
      ((room['players'] as List).first as Map<String, dynamic>)
        ..['forfeited'] = true
        ..['forfeitWhy'] = 'timeouts'
        ..['strikes'] = 5;
      await _serverHasRoom(tester, connector.last, room);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LudoGameScreen), findsNothing);
      expect(
        find.text(
          'You were removed from the match because you missed 5 turns in '
          'a row.',
        ),
        findsOneWidget,
      );
      final leaves = connector.last.sentOfType('room.leave');
      expect(leaves, hasLength(1));
      expect(leaves.single['p'], {'roomId': 'r_1'});
      await _end(tester);
    });

    testWidgets('only the first connection after launch navigates', (
      tester,
    ) async {
      final connector = await _boot(tester);
      connector.last
        ..ready()
        ..serverClose(1006); // drop → reconnect
      await _settle(tester, 4);
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester, 4);
      expect(connector.sockets.length, greaterThan(1));
      await _serverHasRoom(tester, connector.last, ludoRoomJson(turnSeat: 0));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LudoGameScreen), findsNothing);
      await _end(tester);
    });
  });
}
