import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/features/game/presentation/game_route_screen.dart';
import 'package:ludo_royale/features/ludo/presentation/board/board.dart';
import 'package:ludo_royale/shared/game_visuals/game_visuals.dart';

import 'support/play_test_support.dart';

const _roomId = 'r_1';

Future<PlayHarness> _pumpGame(WidgetTester tester, RoomSnapshot room) async {
  final h = PlayHarness(
    initial: ActiveRoomState(room: room, selfUid: 'u_0'),
  );
  await h.pump(tester, GameRouteScreen(roomId: room.id));
  await flush(tester);
  return h;
}

/// Lets queued (reduced-motion) animations finish; also separates gestures.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

List<List<int>> _tokens(Map<int, List<int>> seats) => [
  for (var s = 0; s < 4; s++) seats[s] ?? const [-1, -1, -1, -1],
];

/// Pushes a `game.move_applied` for [seat]'s token 0 and waits for it.
Future<void> _move(
  PlayHarness h,
  WidgetTester tester, {
  required int seat,
  required int from,
  required int to,
  required Map<int, List<int>> after,
  List<CapturedToken> captures = const [],
  bool home = false,
}) async {
  final room = h.controller.state.room!;
  final next = room.copyWith(
    v: room.v + 1,
    board: room.board.withLudoTokens(_tokens(after)),
  );
  h.controller.pushDelta(
    MoveAppliedEvent(
      roomId: _roomId,
      v: next.v,
      seat: seat,
      from: from,
      to: to,
      captures: captures,
      home: home,
    ),
    next,
  );
  await settle(tester);
}

Future<void> _diceResult(
  PlayHarness h,
  WidgetTester tester, {
  required int seat,
  required int value,
}) async {
  final room = h.controller.state.room!;
  final next = room.copyWith(
    v: room.v + 1,
    turn: room.turn.copyWith(
      dice: value,
      turnSeq: room.turn.turnSeq + 1,
      phase: TurnPhases.awaitingMove,
    ),
  );
  h.controller.pushDelta(
    DiceResultEvent(
      roomId: _roomId,
      v: next.v,
      seat: seat,
      value: value,
      turnSeq: next.turn.turnSeq,
      phase: TurnPhases.awaitingMove,
    ),
    next,
  );
  await settle(tester);
}

void main() {
  testWidgets('dice: the roll sound is the local player\'s only; every die '
      'lands with a soft cue (softer for others)', (tester) async {
    final room = ludoRoom(turnSeat: 0, turnSeq: 5);
    final h = await _pumpGame(tester, room);
    expect(h.audio.played, isEmpty, reason: 'opening a match is silent');

    h.controller.commandGate = Completer<void>();
    await tester.tap(find.byType(DiceView));
    await tester.pump();
    await tester.tap(find.byType(DiceView));
    await tester.pump();
    expect(h.audio.played, [Sfx.diceRoll], reason: 'one roll, one sound');
    h.controller.commandGate!.complete();
    await _diceResult(h, tester, seat: 0, value: 3);
    expect(h.audio.played, [Sfx.diceRoll, Sfx.diceLand]);
    final mine = h.audio.volumes.last;

    // Another player's roll: no roll sound, a softer landing.
    await _diceResult(h, tester, seat: 2, value: 5);
    expect(h.audio.played, [Sfx.diceRoll, Sfx.diceLand, Sfx.diceLand]);
    expect(h.audio.volumes.last, lessThan(mine));
  });

  testWidgets('moves: leaving base, steps, safe square and home column each '
      'get their own cue', (tester) async {
    final h = await _pumpGame(tester, ludoRoom(turnSeat: 0));
    await _move(
      h,
      tester,
      seat: 0,
      from: -1,
      to: 0,
      after: {
        0: [0, -1, -1, -1],
      },
    );
    expect(h.audio.played, [Sfx.tokenLeaveBase]);

    await _move(
      h,
      tester,
      seat: 0,
      from: 0,
      to: 3,
      after: {
        0: [3, -1, -1, -1],
      },
    );
    expect(h.audio.played.last, Sfx.tokenStep);

    // Progress 8 is a star (safe) square for every color.
    await _move(
      h,
      tester,
      seat: 0,
      from: 3,
      to: 8,
      after: {
        0: [8, -1, -1, -1],
      },
    );
    expect(h.audio.played.last, Sfx.tokenSafe);

    await _move(
      h,
      tester,
      seat: 0,
      from: 47,
      to: 51,
      after: {
        0: [51, -1, -1, -1],
      },
    );
    expect(h.audio.played.last, Sfx.tokenHomePath);
    expect(
      h.audio.played.where((s) => s == Sfx.tokenStep),
      hasLength(1),
      reason: 'special squares replace the step',
    );
  });

  testWidgets('captures: the attacker hears the hit, the victim a softer '
      'cue; reaching home plays the home jingle only', (tester) async {
    final h = await _pumpGame(tester, ludoRoom(turnSeat: 0));
    // Red (seat 0) at 4 → 10 hits green's token at progress 49 (absolute 10).
    await _move(
      h,
      tester,
      seat: 0,
      from: 4,
      to: 10,
      after: {
        0: [10, -1, -1, -1],
      },
      captures: const [CapturedToken(seat: 1, token: 0)],
    );
    expect(h.audio.played, [Sfx.tokenCapture]);

    // Green captures red: the local player is the victim.
    await _move(
      h,
      tester,
      seat: 1,
      from: 46,
      to: 49,
      after: {
        1: [49, -1, -1, -1],
      },
      captures: const [CapturedToken(seat: 0, token: 0)],
    );
    expect(h.audio.played, [Sfx.tokenCapture, Sfx.tokenCaptured]);

    await _move(
      h,
      tester,
      seat: 0,
      from: 50,
      to: 56,
      home: true,
      after: {
        0: [56, -1, -1, -1],
      },
    );
    expect(h.audio.played, [
      Sfx.tokenCapture,
      Sfx.tokenCaptured,
      Sfx.tokenHome,
    ]);
  });

  testWidgets('turn cue only for the local player', (tester) async {
    final room = ludoRoom(turnSeat: 3, turnSeq: 5);
    final h = await _pumpGame(tester, room);
    Future<void> turnTo(int seat) async {
      final r = h.controller.state.room!;
      final next = r.copyWith(
        v: r.v + 1,
        turn: r.turn.copyWith(
          seat: seat,
          turnSeq: r.turn.turnSeq + 1,
          phase: TurnPhases.awaitingRoll,
          dice: 0,
        ),
      );
      h.controller.pushDelta(
        TurnChangedEvent(
          roomId: _roomId,
          v: next.v,
          seat: seat,
          turnSeq: next.turn.turnSeq,
          phase: TurnPhases.awaitingRoll,
        ),
        next,
      );
      await settle(tester);
    }

    await turnTo(1);
    await turnTo(2);
    expect(h.audio.played, isEmpty);
    await turnTo(0);
    expect(h.audio.played, [Sfx.turnMine]);
  });

  testWidgets('token pick: one select sound per tap, none while sent', (
    tester,
  ) async {
    final room = ludoRoom(
      turnSeat: 0,
      phase: TurnPhases.awaitingMove,
      dice: 6,
      legal: const [0, 1],
    );
    final h = await _pumpGame(tester, room);
    h.controller.commandGate = Completer<void>();
    // Tap seat 0's token 0 where the board draws it.
    final paint = find.descendant(
      of: find.byType(LudoBoard),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is LudoTokenPainter,
      ),
    );
    final rect = tester.getRect(paint);
    final board = tester.widget<LudoBoard>(find.byType(LudoBoard));
    final at =
        rect.topLeft +
        LudoBoardLayout.fit(
          rect.size,
        ).toPx(board.controller.restingCenter(0, 0));
    await tester.tapAt(at);
    await tester.pump();
    await tester.tapAt(at);
    await tester.pump();
    expect(h.controller.calls, ['move:0:5']);
    expect(h.audio.played, [Sfx.tokenSelect]);
    h.controller.commandGate!.complete();
    await settle(tester);
  });

  Future<void> finish(PlayHarness h, WidgetTester tester, int winner) async {
    final room = h.controller.state.room!;
    final finished = room.copyWith(
      v: room.v + 1,
      status: RoomStatuses.finished,
      turn: room.turn.copyWith(phase: TurnPhases.finished),
      result: RoomResult(
        winnerSeat: winner,
        placements: [
          winner,
          for (var s = 0; s < 4; s++)
            if (s != winner) s,
        ],
        payout: 4000,
      ),
      rematch: RematchState(open: true, deadline: kNowMs + 30000),
    );
    h.controller.pushDelta(
      GameFinishedEvent(
        roomId: _roomId,
        v: finished.v,
        result: finished.result!,
        rematch: finished.rematch!,
      ),
      finished,
    );
    await settle(tester);
  }

  testWidgets('a live win plays the win jingle once', (tester) async {
    final h = await _pumpGame(tester, ludoRoom(turnSeat: 0));
    await finish(h, tester, 0);
    expect(h.audio.played, [Sfx.win]);
    // Rebuilds of the results never replay it.
    await settle(tester);
    expect(h.audio.played, [Sfx.win]);
  });

  testWidgets('a live loss plays the gentle lose jingle', (tester) async {
    final h = await _pumpGame(tester, ludoRoom(turnSeat: 1));
    await finish(h, tester, 2);
    expect(h.audio.played, [Sfx.lose]);
  });

  testWidgets('re-opening an already finished match is silent', (tester) async {
    final room = ludoRoom(
      status: RoomStatuses.finished,
      result: const RoomResult(
        winnerSeat: 0,
        placements: [0, 1, 2, 3],
        payout: 4000,
      ),
    );
    final h = await _pumpGame(tester, room);
    await settle(tester);
    expect(h.audio.played, isEmpty);
  });

  testWidgets('chat bubbles pop; a muted chat stays silent', (tester) async {
    final h = await _pumpGame(tester, ludoRoom(turnSeat: 1));
    h.controller.emit(
      const QuickChatReceived(
        QuickChatEvent(roomId: _roomId, seat: 1, msg: 'good_luck'),
        fromSelf: false,
      ),
    );
    await tester.pump();
    expect(h.audio.played, [Sfx.chatPop]);
    await tester.pump(const Duration(seconds: 3));
  });
}
