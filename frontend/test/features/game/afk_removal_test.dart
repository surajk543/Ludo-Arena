import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/features/game/presentation/game_route_screen.dart';
import 'package:ludo_royale/features/game/presentation/widgets/results_panel.dart';
import 'package:ludo_royale/features/ludo/presentation/screens/ludo_game_screen.dart';

import 'support/play_test_support.dart';

/// The server removes a player after MAX_STRIKES (5) missed turns in a row
/// (`player.forfeited` reason `timeouts`). The removed player is told why
/// and taken Home; nobody else is.
const _removedText =
    'You were removed from the match because you missed 5 turns in a row.';

Future<PlayHarness> _pumpGame(
  WidgetTester tester,
  RoomSnapshot room, {
  Locale locale = const Locale('en'),
}) async {
  final h = PlayHarness(
    initial: ActiveRoomState(room: room, selfUid: 'u_0'),
  );
  await h.pump(tester, GameRouteScreen(roomId: room.id), locale: locale);
  await flush(tester);
  return h;
}

/// [room] after the server removed [seat] (the reducer sets forfeitWhy and
/// strikes from the event).
RoomSnapshot _forfeited(
  RoomSnapshot room,
  int seat, {
  required int v,
  String why = ForfeitReasons.timeouts,
  int strikes = 5,
}) => room.copyWith(
  v: v,
  players: [
    for (final p in room.players)
      p.seat == seat
          ? p.copyWith(forfeited: true, forfeitWhy: why, strikes: strikes)
          : p,
  ],
);

PlayerForfeitedEvent _event(
  int seat, {
  required int v,
  String reason = ForfeitReasons.timeouts,
  int strikes = 5,
}) => PlayerForfeitedEvent(
  roomId: 'r_1',
  v: v,
  seat: seat,
  reason: reason,
  strikes: strikes,
);

List<String> _leaves(PlayHarness h) =>
    h.controller.calls.where((c) => c == 'room.leave').toList();

void main() {
  testWidgets('removed for missed turns (live): toast, Home, one room.leave', (
    tester,
  ) async {
    final room = ludoRoom(turnSeat: 0);
    final h = await _pumpGame(tester, room);
    expect(find.byType(LudoGameScreen), findsOneWidget);

    h.controller.pushDelta(_event(0, v: 11), _forfeited(room, 0, v: 11));
    await flush(tester, 8);

    expect(find.text(_removedText), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byType(LudoGameScreen), findsNothing);
    expect(_leaves(h), hasLength(1));
  });

  testWidgets('a two-player game ended by the removal: Home, no results', (
    tester,
  ) async {
    final room = ludoRoom(players: [player(0), player(1)], capacity: 2);
    final h = await _pumpGame(tester, room);
    final removed = _forfeited(room, 0, v: 11);
    h.controller.pushDelta(_event(0, v: 11), removed);
    // game.finished follows in the same commit; it must not show results.
    const result = RoomResult(
      winnerSeat: 1,
      reason: 'forfeit',
      placements: [1, 0],
    );
    const rematch = RematchState(open: true);
    final finished = removed.copyWith(
      v: 12,
      status: RoomStatuses.finished,
      result: result,
      rematch: rematch,
    );
    h.controller.emit(
      RoomDeltaApplied(
        delta: const GameFinishedEvent(
          roomId: 'r_1',
          v: 12,
          result: result,
          rematch: rematch,
        ),
        room: finished,
        previous: removed,
      ),
    );
    await flush(tester, 8);

    expect(find.text(_removedText), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byType(ResultsPanel), findsNothing);
    expect(_leaves(h), hasLength(1));
    expect(h.analytics.events, isNot(contains(startsWith('game_result'))));
  });

  testWidgets('after a resync snapshot (app was in the background)', (
    tester,
  ) async {
    final room = ludoRoom(turnSeat: 2);
    final h = await _pumpGame(tester, room);

    h.controller.pushSnapshot(
      _forfeited(
        room,
        0,
        v: 30,
      ).copyWith(turn: room.turn.copyWith(seat: 1, turnSeq: 20)),
    );
    await flush(tester, 8);

    expect(find.text(_removedText), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    expect(_leaves(h), hasLength(1));
  });

  testWidgets('opening a match you were already removed from leaves it', (
    tester,
  ) async {
    final h = await _pumpGame(tester, _forfeited(ludoRoom(), 0, v: 10));
    await flush(tester, 8);

    expect(find.text(_removedText), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    expect(_leaves(h), hasLength(1));
  });

  testWidgets('an opponent removed for missed turns: caption only', (
    tester,
  ) async {
    final room = ludoRoom(turnSeat: 2);
    final h = await _pumpGame(tester, room);

    h.controller.pushDelta(_event(2, v: 11), _forfeited(room, 2, v: 11));
    await flush(tester, 8);

    expect(
      find.text('Player2 was removed after 5 missed turns in a row'),
      findsOneWidget,
    );
    expect(find.text(_removedText), findsNothing);
    expect(find.byType(LudoGameScreen), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(_leaves(h), isEmpty);
  });

  testWidgets('leaving on your own (left) shows no removal notice', (
    tester,
  ) async {
    final room = ludoRoom(turnSeat: 2);
    final h = await _pumpGame(tester, room);

    h.controller.pushDelta(
      _event(0, v: 11, reason: ForfeitReasons.left, strikes: 0),
      _forfeited(room, 0, v: 11, why: ForfeitReasons.left, strikes: 0),
    );
    await flush(tester, 8);

    expect(find.textContaining('You were removed'), findsNothing);
    expect(find.text('HOME'), findsNothing);
    expect(_leaves(h), isEmpty);
  });

  testWidgets('Arabic: the notice is translated', (tester) async {
    final room = ludoRoom(turnSeat: 0);
    final h = await _pumpGame(tester, room, locale: const Locale('ar'));

    h.controller.pushDelta(_event(0, v: 11), _forfeited(room, 0, v: 11));
    await flush(tester, 8);

    expect(
      find.text('أُخرجت من المباراة بسبب تفويت 5 أدوار متتالية.'),
      findsOneWidget,
    );
    expect(find.text('HOME'), findsOneWidget);
    expect(_leaves(h), hasLength(1));
  });
}
