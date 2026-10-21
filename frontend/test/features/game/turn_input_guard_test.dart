import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/features/game/application/turn_input_guard.dart';

import 'support/play_test_support.dart';

void main() {
  group('roll', () {
    final mine = ludoRoom(turnSeat: 0, turnSeq: 7);

    test('allowed once per turnSeq (duplicate taps are ignored)', () {
      final g = TurnInputGuard();
      bool can() =>
          g.canRoll(live: mine, presented: mine, selfSeat: 0, busy: false);
      expect(can(), isTrue);
      g.markRollSent(7);
      expect(can(), isFalse, reason: 'second tap for the same turnSeq');
      // A new turnSeq (extra turn) allows a new roll.
      final next = ludoRoom(turnSeat: 0, turnSeq: 9);
      expect(
        g.canRoll(live: next, presented: next, selfSeat: 0, busy: false),
        isTrue,
      );
    });

    test('a failed roll can be retried', () {
      final g = TurnInputGuard()..markRollSent(7);
      g.rollFailed(7);
      expect(
        g.canRoll(live: mine, presented: mine, selfSeat: 0, busy: false),
        isTrue,
      );
    });

    test('blocked while animations run, a command is in flight, the '
        'presented board lags, or it is not my turn', () {
      final g = TurnInputGuard();
      expect(
        g.canRoll(live: mine, presented: mine, selfSeat: 0, busy: true),
        isFalse,
      );
      expect(
        g.canRoll(
          live: mine,
          presented: mine,
          selfSeat: 0,
          busy: false,
          commandInFlight: true,
        ),
        isFalse,
      );
      final lagging = ludoRoom(turnSeat: 0, turnSeq: 6);
      expect(
        g.canRoll(live: mine, presented: lagging, selfSeat: 0, busy: false),
        isFalse,
      );
      expect(
        g.canRoll(live: mine, presented: mine, selfSeat: 1, busy: false),
        isFalse,
      );
      final moving = ludoRoom(
        turnSeat: 0,
        turnSeq: 7,
        phase: TurnPhases.awaitingMove,
        legal: [0, 1],
      );
      expect(
        g.canRoll(live: moving, presented: moving, selfSeat: 0, busy: false),
        isFalse,
      );
    });
  });

  group('move', () {
    final choose = ludoRoom(
      turnSeat: 0,
      turnSeq: 8,
      phase: TurnPhases.awaitingMove,
      legal: [0, 2],
      dice: 6,
    );

    test('only legal tokens, once per turnSeq', () {
      final g = TurnInputGuard();
      bool can(int t) => g.canMove(
        live: choose,
        presented: choose,
        selfSeat: 0,
        busy: false,
        token: t,
      );
      expect(can(0), isTrue);
      expect(can(1), isFalse);
      expect(can(2), isTrue);
      g.markMoveSent(8);
      expect(can(0), isFalse);
      expect(can(2), isFalse);
      expect(
        g.canPickToken(
          live: choose,
          presented: choose,
          selfSeat: 0,
          busy: false,
        ),
        isFalse,
      );
    });

    test('a single legal token is never offered (the server auto-moves)', () {
      final single = ludoRoom(
        turnSeat: 0,
        turnSeq: 8,
        phase: TurnPhases.awaitingMove,
        legal: [3],
        dice: 4,
      );
      final g = TurnInputGuard();
      expect(TurnInputGuard.requiresChoice(single), isFalse);
      expect(
        g.canMove(
          live: single,
          presented: single,
          selfSeat: 0,
          busy: false,
          token: 3,
        ),
        isFalse,
      );
      expect(
        g.canPickToken(
          live: single,
          presented: single,
          selfSeat: 0,
          busy: false,
        ),
        isFalse,
      );
      expect(TurnInputGuard.requiresChoice(choose), isTrue);
    });

    test('reset forgets sent commands (new round)', () {
      final g = TurnInputGuard()
        ..markMoveSent(8)
        ..markRollSent(8)
        ..reset();
      expect(g.rollSentFor, isNull);
      expect(g.moveSentFor, isNull);
    });
  });
}
