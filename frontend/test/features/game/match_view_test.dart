import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:ludo_royale/core/assets/profile_picture_cache.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/core/state/in_match_provider.dart';
import 'package:ludo_royale/features/game/application/owned_emotes.dart';
import 'package:ludo_royale/features/game/presentation/game_route_screen.dart';
import 'package:ludo_royale/features/game/presentation/widgets/player_panel.dart';
import 'package:ludo_royale/features/ludo/presentation/board/board.dart';
import 'package:ludo_royale/features/ludo/presentation/screens/ludo_game_screen.dart';
import 'package:ludo_royale/features/snakes_ladders/presentation/screens/snakes_game_screen.dart';
import 'package:ludo_royale/shared/game_visuals/game_visuals.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import '../../helpers/picture_fixtures.dart';
import 'support/play_test_support.dart';

const _roomId = 'r_1';

Future<PlayHarness> _pumpGame(
  WidgetTester tester,
  RoomSnapshot room, {
  String selfUid = 'u_0',
}) async {
  final h = PlayHarness(
    initial: ActiveRoomState(room: room, selfUid: selfUid),
  );
  await h.pump(tester, GameRouteScreen(roomId: room.id));
  await flush(tester);
  return h;
}

/// Lets queued animations (reduced motion) finish.
Future<void> settleAnimations(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

RoomSnapshot _diceResult(
  RoomSnapshot room, {
  required int value,
  required int v,
  String phase = TurnPhases.awaitingMove,
  List<int> legal = const [],
}) => room.copyWith(
  v: v,
  turn: room.turn.copyWith(
    dice: value,
    turnSeq: room.turn.turnSeq + 1,
    phase: phase,
    legal: legal,
  ),
);

void main() {
  testWidgets('routes to the Ludo or Snakes screen and marks in-match', (
    tester,
  ) async {
    final h = await _pumpGame(tester, ludoRoom());
    expect(find.byType(LudoGameScreen), findsOneWidget);
    expect(h.container.read(inMatchProvider), isTrue);
  });

  testWidgets('routes Snakes & Ladders rooms to the Snakes screen', (
    tester,
  ) async {
    await _pumpGame(tester, snakesRoom());
    expect(find.byType(SnakesGameScreen), findsOneWidget);
  });

  testWidgets('duplicate dice taps send a single roll with the live turnSeq', (
    tester,
  ) async {
    final room = ludoRoom(turnSeat: 0, turnSeq: 5);
    final h = await _pumpGame(tester, room);
    expect(find.text('Your turn — tap the dice!'), findsOneWidget);

    h.controller.commandGate = Completer<void>();
    await tester.tap(find.byType(DiceView));
    await tester.pump();
    await tester.tap(find.byType(DiceView));
    await tester.pump();
    await tester.tap(find.byType(DiceView));
    await tester.pump();
    expect(h.controller.calls, ['roll:5']);

    // The server answers with the dice result; the reply completes the roll.
    final rolled = _diceResult(room, value: 6, v: 11, legal: const [0, 1]);
    h.controller.pushDelta(
      DiceResultEvent(
        roomId: _roomId,
        v: 11,
        seat: 0,
        value: 6,
        turnSeq: rolled.turn.turnSeq,
        phase: TurnPhases.awaitingMove,
        legal: const [0, 1],
      ),
      rolled,
    );
    h.controller.commandGate!.complete();
    await settleAnimations(tester);

    expect(find.text('Pick a glowing token to move'), findsOneWidget);
    // Rolling again for the same turn is impossible.
    await tester.tap(find.byType(DiceView));
    await tester.pump();
    expect(h.controller.calls, ['roll:5']);
  });

  testWidgets('a single legal move is never offered (server auto-moves)', (
    tester,
  ) async {
    final room = ludoRoom(turnSeat: 0, turnSeq: 5);
    final h = await _pumpGame(tester, room);
    final rolled = _diceResult(room, value: 6, v: 11, legal: const [2]);
    h.controller.pushDelta(
      DiceResultEvent(
        roomId: _roomId,
        v: 11,
        seat: 0,
        value: 6,
        turnSeq: rolled.turn.turnSeq,
        phase: TurnPhases.awaitingMove,
        legal: const [2],
      ),
      rolled,
    );
    await settleAnimations(tester);
    expect(find.text('Pick a glowing token to move'), findsNothing);
    expect(find.text('Your turn'), findsOneWidget);

    // The automatic move and the turn change animate in order.
    final moved = rolled.copyWith(
      v: 12,
      board: rolled.board.withLudoTokens([
        [-1, -1, 0, -1],
        for (var s = 1; s < 4; s++) [-1, -1, -1, -1],
      ]),
      turn: rolled.turn.copyWith(legal: const []),
    );
    h.controller.pushDelta(
      MoveAppliedEvent(
        roomId: _roomId,
        v: 12,
        seat: 0,
        token: 2,
        from: -1,
        to: 0,
        auto: true,
      ),
      moved,
    );
    final passed = moved.copyWith(
      v: 13,
      turn: moved.turn.copyWith(
        seat: 1,
        turnSeq: moved.turn.turnSeq + 1,
        phase: TurnPhases.awaitingRoll,
        dice: 0,
      ),
    );
    h.controller.pushDelta(
      TurnChangedEvent(
        roomId: _roomId,
        v: 13,
        seat: 1,
        turnSeq: passed.turn.turnSeq,
        phase: TurnPhases.awaitingRoll,
      ),
      passed,
    );
    await settleAnimations(tester);
    expect(find.text("Player1's turn"), findsOneWidget);
    expect(h.controller.calls.where((c) => c.startsWith('move')), isEmpty);
  });

  testWidgets('bots are never labelled or announced as bots', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpGame(
      tester,
      ludoRoom(
        turnSeat: 1,
        players: [
          player(0),
          player(1, name: 'Bolt'),
        ],
      ),
    );
    expect(find.text("Bolt's turn"), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'\bbot\b', caseSensitive: false)),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(RegExp('bot|computer', caseSensitive: false)),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('quick chat: predefined message, throttle, bubbles and local '
      'mute', (tester) async {
    final h = await _pumpGame(tester, ludoRoom(turnSeat: 1));
    await tester.tap(find.byTooltip('Quick chat'));
    await settleAnimations(tester);
    expect(find.text('Good game!'), findsOneWidget);
    await tester.tap(find.text('Good game!'));
    await settleAnimations(tester);
    expect(h.controller.calls, ['chat.quick:gg']);

    // Throttled: the panel shows the cooldown and sends nothing.
    await tester.tap(find.byTooltip('Quick chat'));
    await settleAnimations(tester);
    expect(find.text('Next message in 3s'), findsOneWidget);
    await tester.tap(find.text('Thanks!'));
    await tester.pump();
    expect(h.controller.calls, ['chat.quick:gg']);

    // Mute other players for this match.
    await tester.tap(find.text('Mute other players'));
    await tester.pump();
    Navigator.of(tester.element(find.text('Thanks!'))).pop();
    await settleAnimations(tester);

    h.controller.emit(
      const QuickChatReceived(
        QuickChatEvent(roomId: _roomId, seat: 1, msg: 'nice_move'),
        fromSelf: false,
      ),
    );
    await tester.pump();
    expect(find.text('Nice move!'), findsNothing);

    // The user's own messages always show.
    h.controller.emit(
      const QuickChatReceived(
        QuickChatEvent(roomId: _roomId, seat: 0, msg: 'gg'),
        fromSelf: true,
      ),
    );
    await tester.pump();
    expect(find.text('Good game!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Good game!'), findsNothing);
  });

  testWidgets('presence follows player.disconnected / player.connected '
      'deltas on every pod, mine included', (tester) async {
    final room = ludoRoom(turnSeat: 1);
    final h = await _pumpGame(tester, room);
    Finder online(int seat) => find.byKey(ValueKey('pod-online-$seat'));
    Finder offline(int seat) => find.byKey(ValueKey('pod-offline-$seat'));
    for (final seat in [0, 1, 2, 3]) {
      expect(online(seat), findsOneWidget, reason: 'seat $seat');
      expect(offline(seat), findsNothing, reason: 'seat $seat');
    }

    RoomSnapshot withSeat(RoomSnapshot r, int seat, int v, bool connected) =>
        r.copyWith(
          v: v,
          players: [
            for (final p in r.players)
              p.seat == seat ? p.copyWith(connected: connected) : p,
          ],
        );

    final gone = withSeat(room, 2, room.v + 1, false);
    h.controller.pushDelta(
      PlayerConnectionEvent(
        roomId: _roomId,
        v: gone.v,
        seat: 2,
        connected: false,
      ),
      gone,
    );
    await settleAnimations(tester);
    expect(offline(2), findsOneWidget);
    expect(online(2), findsNothing);
    expect(online(1), findsOneWidget);

    final back = withSeat(gone, 2, gone.v + 1, true);
    h.controller.pushDelta(
      PlayerConnectionEvent(
        roomId: _roomId,
        v: back.v,
        seat: 2,
        connected: true,
      ),
      back,
    );
    await settleAnimations(tester);
    expect(online(2), findsOneWidget);
    expect(offline(2), findsNothing);

    // My own pod too.
    final meGone = withSeat(back, 0, back.v + 1, false);
    h.controller.pushDelta(
      PlayerConnectionEvent(
        roomId: _roomId,
        v: meGone.v,
        seat: 0,
        connected: false,
      ),
      meGone,
    );
    await settleAnimations(tester);
    expect(offline(0), findsOneWidget);
  });

  testWidgets('incoming bubbles appear near the sender when not muted', (
    tester,
  ) async {
    final h = await _pumpGame(tester, ludoRoom(turnSeat: 1));
    h.controller.emit(
      const EmoteReceived(
        EmoteEvent(roomId: _roomId, seat: 2, emote: 'emote_wave'),
        fromSelf: false,
      ),
    );
    h.controller.emit(
      const QuickChatReceived(
        QuickChatEvent(roomId: _roomId, seat: 1, msg: 'good_luck'),
        fromSelf: false,
      ),
    );
    await tester.pump();
    expect(find.text('Good luck!'), findsOneWidget);
    expect(find.byType(EmoteIcon), findsOneWidget);
    expect(h.audio.played, isNotEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the picker lists bought Store emotes with their art; sending '
      'one sends its em_ id', (tester) async {
    final h = PlayHarness(
      initial: ActiveRoomState(room: ludoRoom(turnSeat: 1), selfUid: 'u_0'),
    );
    h.emotes.ready['emotes/angry.json'] = LoadedLottiePicture(
      testComposition(),
    );
    await h.pump(
      tester,
      GameRouteScreen(roomId: ludoRoom().id),
      extra: [
        ownedEmotesProvider.overrideWith(
          (ref) async => [
            ...kStarterOwnedEmotes,
            OwnedEmote('em_angry', asset: emoteAsset(), name: 'Angry'),
            OwnedEmote('em_woozy', asset: emoteAsset('woozy'), name: 'Woozy'),
          ],
        ),
      ],
    );
    await flush(tester);
    await tester.tap(find.byTooltip('Quick chat'));
    await settleAnimations(tester);
    expect(find.byKey(const ValueKey('chat-emote-emote_wave')), findsOneWidget);
    final angry = find.byKey(const ValueKey('chat-emote-em_angry'));
    expect(angry, findsOneWidget);
    // Cached art animates; art still downloading shows the generic glyph.
    expect(
      find.descendant(of: angry, matching: find.byType(Lottie)),
      findsOneWidget,
    );
    final woozy = find.byKey(const ValueKey('chat-emote-em_woozy'));
    expect(
      find.descendant(of: woozy, matching: find.byType(EmoteIcon)),
      findsOneWidget,
    );
    expect(h.emotes.requested, contains('emotes/woozy.json'));
    expect(find.bySemanticsLabel(RegExp('Angry')), findsOneWidget);

    await tester.tap(angry);
    await settleAnimations(tester);
    expect(h.controller.calls, ['chat.emote:em_angry']);
  });

  testWidgets('a received Store emote animates in the sender\'s bubble; a '
      'malformed asset falls back to the built-in glyph', (tester) async {
    final h = await _pumpGame(tester, ludoRoom(turnSeat: 1));
    h.emotes.ready['emotes/angry.json'] = LoadedLottiePicture(
      testComposition(),
    );
    h.controller.emit(
      EmoteReceived(
        EmoteEvent.fromJson({
          'roomId': _roomId,
          'seat': 2,
          'emote': 'em_angry',
          'asset': {'path': 'emotes/angry.json', 'format': 'lottie'},
        }),
        fromSelf: false,
      ),
    );
    await tester.pump();
    final bubble = find.byKey(const ValueKey('bubble-2'));
    expect(bubble, findsOneWidget);
    expect(
      find.descendant(of: bubble, matching: find.byType(Lottie)),
      findsOneWidget,
    );

    h.controller.emit(
      EmoteReceived(
        EmoteEvent.fromJson({
          'roomId': _roomId,
          'seat': 3,
          'emote': 'em_angry',
          'asset': {'path': '../../etc/passwd', 'format': 'lottie'},
        }),
        fromSelf: false,
      ),
    );
    await tester.pump();
    final fallback = find.byKey(const ValueKey('bubble-3'));
    expect(
      find.descendant(of: fallback, matching: find.byType(EmoteIcon)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fallback, matching: find.byType(Lottie)),
      findsNothing,
    );
    expect(h.emotes.requested, isNot(contains('../../etc/passwd')));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('game.finished → victory → results with server payout and '
      'late XP; Play again leaves and re-queues', (tester) async {
    final room = ludoRoom(turnSeat: 0);
    final h = await _pumpGame(tester, room);
    final finished = room.copyWith(
      v: 11,
      status: RoomStatuses.finished,
      turn: room.turn.copyWith(phase: TurnPhases.finished),
      result: const RoomResult(
        winnerSeat: 0,
        placements: [0, 1, 2, 3],
        payout: 4000,
      ),
      rematch: RematchState(open: true, deadline: kNowMs + 30000),
    );
    h.controller.pushDelta(
      GameFinishedEvent(
        roomId: _roomId,
        v: 11,
        result: finished.result!,
        rematch: finished.rematch!,
      ),
      finished,
    );
    await settleAnimations(tester);
    expect(find.byType(VictoryOverlay), findsNothing);
    expect(find.text('You won!'), findsOneWidget);
    expect(find.text('+4,000 coins'), findsOneWidget);
    expect(find.text('Calculating XP…'), findsOneWidget);
    // Public seats carry no bot flag: the opponent mix is unknown.
    expect(h.analytics.events, ['game_result_viewed:ludo:public:unknown']);

    h.progression.add(
      const ProgressionUpdatedEvent(xp: 140, level: 2, xpGained: 35),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('+35 XP'), findsOneWidget);

    await scrollTo(tester, find.text('Play again'));
    await tester.tap(find.text('Play again'));
    await flush(tester, 8);
    expect(h.controller.calls, contains('room.leave'));
    expect(find.textContaining('MATCHMAKING'), findsOneWidget);
    expect(find.textContaining('capacity=4'), findsOneWidget);
  });

  for (final (capacity, bots) in [(4, 3), (3, 2), (2, 1)]) {
    testWidgets('practice Play again asks for $bots computer players '
        '(capacity $capacity)', (tester) async {
      final room = ludoRoom(
        turnSeat: 0,
        mode: RoomModes.practice,
        capacity: capacity,
        players: [for (var s = 0; s < capacity; s++) player(s)],
        computerSeats: [for (var s = 1; s < capacity; s++) s],
        pot: 0,
      );
      final h = await _pumpGame(tester, room);
      final finished = room.copyWith(
        v: 11,
        status: RoomStatuses.finished,
        turn: room.turn.copyWith(phase: TurnPhases.finished),
        result: RoomResult(
          winnerSeat: 0,
          placements: [for (var s = 0; s < capacity; s++) s],
          payout: 0,
        ),
        rematch: RematchState(open: true, deadline: kNowMs + 30000),
      );
      h.controller.pushDelta(
        GameFinishedEvent(
          roomId: _roomId,
          v: 11,
          result: finished.result!,
          rematch: finished.rematch!,
        ),
        finished,
      );
      await settleAnimations(tester);
      expect(h.analytics.events, ['game_result_viewed:ludo:practice:bot_only']);
      await scrollTo(tester, find.text('Play again'));
      await tester.tap(find.text('Play again'));
      await flush(tester, 8);
      expect(h.controller.calls, contains('room.leave'));
      expect(find.textContaining('PRACTICE'), findsOneWidget);
      expect(find.textContaining('bots=$bots'), findsOneWidget);
    });
  }

  testWidgets('a snapshot (resync) mid-animation snaps the board', (
    tester,
  ) async {
    final room = ludoRoom(turnSeat: 0);
    final h = await _pumpGame(tester, room);
    final rolled = _diceResult(room, value: 3, v: 11, legal: const [0, 1]);
    h.controller.pushDelta(
      DiceResultEvent(
        roomId: _roomId,
        v: 11,
        seat: 0,
        value: 3,
        turnSeq: rolled.turn.turnSeq,
        phase: TurnPhases.awaitingMove,
        legal: const [0, 1],
      ),
      rolled,
    );
    await tester.pump();
    final resync = ludoRoom(v: 30, turnSeat: 3, turnSeq: 20);
    h.controller.pushSnapshot(resync);
    await settleAnimations(tester);
    expect(find.text("Player3's turn"), findsOneWidget);
  });

  testWidgets('leaving a running match asks for confirmation', (tester) async {
    final h = await _pumpGame(tester, ludoRoom(turnSeat: 1));
    await tester.tap(find.byTooltip('Leave match'));
    await settleAnimations(tester);
    expect(find.text('Leave the match?'), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await settleAnimations(tester);
    expect(h.controller.calls, isNot(contains('room.leave')));

    await tester.tap(find.byTooltip('Leave match'));
    await settleAnimations(tester);
    await tester.tap(find.text('Leave'));
    await flush(tester, 8);
    expect(h.controller.calls, contains('room.leave'));
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('disconnected / forfeited players are marked', (tester) async {
    await _pumpGame(
      tester,
      ludoRoom(
        turnSeat: 0,
        players: [
          player(0),
          player(1, connected: false),
          player(2, forfeited: true),
          player(3, strikes: 2),
        ],
      ),
    );
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
  });

  testWidgets('a private rematch that resets to the lobby opens the lobby', (
    tester,
  ) async {
    final room = ludoRoom(
      mode: RoomModes.private,
      status: RoomStatuses.finished,
      hostSeat: 0,
      result: const RoomResult(winnerSeat: 1, placements: [1, 0, 2, 3]),
      rematch: RematchState(
        open: true,
        deadline: kNowMs + 30000,
        accepted: const [1],
      ),
    );
    final h = await _pumpGame(tester, room);
    await settleAnimations(tester);
    expect(find.text('Player1 wants a rematch!'), findsOneWidget);
    await scrollTo(tester, find.text('Accept'));
    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(h.controller.calls, contains('game.rematch:true'));

    h.controller.pushSnapshot(
      ludoRoom(
        mode: RoomModes.private,
        status: RoomStatuses.lobby,
        round: 2,
        v: 40,
      ),
      reason: 'rematch_started',
    );
    await flush(tester, 6);
    expect(find.text('LOBBY r_1'), findsOneWidget);
  });

  group('the local player sits bottom-left', () {
    Rect panelOf(WidgetTester tester, int seat) => tester.getRect(
      find.byWidgetPredicate((w) => w is PlayerPanel && w.player.seat == seat),
    );

    /// Which screen quadrant [r] is in, relative to the board's center.
    String quadrant(WidgetTester tester, Rect r) {
      final c = tester.getCenter(
        find.byType(LudoBoard).evaluate().isEmpty
            ? find.byType(SnakesGameScreen)
            : find.byType(LudoBoard),
      );
      final v = r.center.dy < c.dy ? 'top' : 'bottom';
      final h = r.center.dx < c.dx ? 'Left' : 'Right';
      return '$v$h';
    }

    for (final self in [0, 1, 2, 3]) {
      testWidgets('4 players, self ${SeatColor.values[self].name}', (
        tester,
      ) async {
        await _pumpGame(tester, ludoRoom(), selfUid: 'u_$self');
        expect(quadrant(tester, panelOf(tester, self)), 'bottomLeft');
        // Opponents keep the clockwise order around the board.
        expect(quadrant(tester, panelOf(tester, (self + 1) % 4)), 'topLeft');
        expect(quadrant(tester, panelOf(tester, (self + 2) % 4)), 'topRight');
        expect(
          quadrant(tester, panelOf(tester, (self + 3) % 4)),
          'bottomRight',
        );
        // The board turns with the pods: the local base is bottom-left.
        final board = tester.widget<LudoBoard>(find.byType(LudoBoard));
        final base = board.controller.restingCenter(self, 0);
        expect(base.dx, lessThan(6));
        expect(base.dy, greaterThan(9));
        expect(
          board.controller.quarterTurns,
          SeatColor.values[self].turnsToBottomLeft,
        );
      });
    }

    testWidgets('2 players: the opponent faces from the top-right', (
      tester,
    ) async {
      await _pumpGame(
        tester,
        ludoRoom(
          players: [
            player(0, color: 'red'),
            player(1, color: 'yellow'),
          ],
        ),
        selfUid: 'u_1',
      );
      expect(quadrant(tester, panelOf(tester, 1)), 'bottomLeft');
      expect(quadrant(tester, panelOf(tester, 0)), 'topRight');
    });

    testWidgets('Snakes & Ladders pods rotate the same way', (tester) async {
      await _pumpGame(tester, snakesRoom(), selfUid: 'u_2');
      expect(quadrant(tester, panelOf(tester, 2)), 'bottomLeft');
      expect(quadrant(tester, panelOf(tester, 0)), 'topRight');
    });

    testWidgets('spectators see the board unturned', (tester) async {
      await _pumpGame(tester, ludoRoom(), selfUid: 'u_spectator');
      expect(quadrant(tester, panelOf(tester, 0)), 'topLeft');
      expect(quadrant(tester, panelOf(tester, 3)), 'bottomLeft');
      final board = tester.widget<LudoBoard>(find.byType(LudoBoard));
      expect(board.controller.quarterTurns, 0);
    });
  });
}
