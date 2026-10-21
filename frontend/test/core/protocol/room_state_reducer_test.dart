import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';

import 'fixtures.dart';

int hashOf(String canonical) => StateHash.fnv1a32(canonical);

void main() {
  const reducer = RoomStateReducer();

  group('snapshots', () {
    test('replace when no local state', () {
      final room = ludoRoom(v: 40);
      final r = reducer.reduce(null, GameStateEvent(room: room));
      expect(r, isA<Applied>());
      expect((r as Applied).state, room);
      expect(r.replaced, isTrue);
    });

    test('replace when room.v >= local.v (newer and equal)', () {
      final local = ludoRoom(v: 40);
      final newer = ludoRoom(v: 45, turnSeq: 20);
      final equal = ludoRoom(v: 40, turnSeq: 99);
      expect(
        (reducer.reduce(local, GameStateEvent(room: newer)) as Applied).state.v,
        45,
      );
      final eq = reducer.reduce(local, RoomUpdatedEvent(room: equal));
      expect((eq as Applied).state.turn.turnSeq, 99);
    });

    test('older snapshot for the same room is ignored', () {
      final local = ludoRoom(v: 40);
      final r = reducer.reduce(local, GameStartedEvent(room: ludoRoom(v: 39)));
      expect(r, isA<Ignored>());
      expect((r as Ignored).reason, IgnoreReason.staleSnapshot);
    });

    test('snapshot for a different room replaces regardless of v', () {
      final local = ludoRoom(id: 'r_old', v: 90);
      final other = ludoRoom(id: 'r_new', v: 1);
      final r = reducer.reduce(local, RoomUpdatedEvent(room: other));
      expect((r as Applied).state.id, 'r_new');
    });
  });

  group('reconciliation', () {
    final local = ludoRoom(v: 40);

    test('v <= local.v is a duplicate', () {
      for (final v in [39, 40]) {
        final r = reducer.reduce(
          local,
          PlayerConnectionEvent(roomId: 'r_1', v: v, seat: 0, connected: false),
        );
        expect((r as Ignored).reason, IgnoreReason.duplicate);
      }
    });

    test('v > local.v + 1 is a gap → needsSync, nothing buffered', () {
      final r = reducer.reduce(
        local,
        PlayerConnectionEvent(roomId: 'r_1', v: 42, seat: 0, connected: false),
      );
      expect(r, isA<NeedsSync>());
      final n = r as NeedsSync;
      expect(n.reason, SyncReason.gap);
      expect(n.roomId, 'r_1');
      expect(n.state, local);
    });

    test('delta for another room is ignored when a room is held', () {
      final r = reducer.reduce(
        local,
        PlayerConnectionEvent(roomId: 'r_x', v: 41, seat: 0, connected: false),
      );
      expect((r as Ignored).reason, IgnoreReason.otherRoom);
    });

    test('delta with no local state → needsSync for that room', () {
      final r = reducer.reduce(
        null,
        PlayerConnectionEvent(roomId: 'r_x', v: 3, seat: 0, connected: false),
      );
      expect((r as NeedsSync).reason, SyncReason.noLocalState);
      expect(r.roomId, 'r_x');
      expect(r.state, isNull);
    });

    test('hash mismatch → needsSync with the applied state kept', () {
      final r = reducer.reduce(
        local,
        TurnChangedEvent(
          roomId: 'r_1',
          v: 41,
          h: 12345,
          seat: 0,
          turnSeq: 8,
          phase: 'awaiting_roll',
        ),
      );
      final n = r as NeedsSync;
      expect(n.reason, SyncReason.hashMismatch);
      expect(n.state!.v, 41);
      expect(n.state!.turn.seat, 0);
      expect(n.event, isA<TurnChangedEvent>());
    });

    test('delta without h is applied without verification', () {
      final r = reducer.reduce(
        local,
        PlayerConnectionEvent(roomId: 'r_1', v: 41, seat: 1, connected: false),
      );
      final a = r as Applied;
      expect(a.state.v, 41);
      expect(a.state.playerAtSeat(1)!.connected, isFalse);
      expect(a.replaced, isFalse);
    });

    test('unknown seat → needsSync(invalidDelta)', () {
      final r = reducer.reduce(
        local,
        PlayerConnectionEvent(roomId: 'r_1', v: 41, seat: 3, connected: true),
      );
      expect((r as NeedsSync).reason, SyncReason.invalidDelta);
    });

    test('non-room events are ignored', () {
      final r = reducer.reduce(local, const PongEvent(ts: 1));
      expect((r as Ignored).reason, IgnoreReason.notRoomEvent);
    });
  });

  group('typical Ludo turn (dice v41 → move v42 → turn v43)', () {
    test('applies in order with matching hashes', () {
      final store = RoomStateStore();
      store.apply(GameStateEvent(room: ludoRoom(v: 40)));
      expect(StateHash.of(store.state!), 2902942580);

      final dice = DiceResultEvent(
        roomId: 'r_1',
        v: 41,
        h: hashOf('L|8|1|-1,-1,5,56;0,-1,-1,-1'),
        seat: 1,
        value: 3,
        turnSeq: 8,
        phase: 'awaiting_move',
        deadline: 1761022820000,
        legal: const [0],
        sixStreak: 0,
        strikes: 0,
      );
      final r1 = store.apply(dice);
      expect(r1, isA<Applied>());
      expect(store.state!.turn.dice, 3);
      expect(store.state!.turn.phase, 'awaiting_move');
      expect(store.state!.turn.legal, [0]);
      expect(store.state!.turn.deadline, 1761022820000);

      final move = MoveAppliedEvent(
        roomId: 'r_1',
        v: 42,
        h: hashOf('L|8|1|-1,-1,5,56;3,-1,-1,-1'),
        seat: 1,
        token: 0,
        from: 0,
        to: 3,
        auto: true,
      );
      expect(store.apply(move), isA<Applied>());
      expect(store.state!.board.ludoTokens![1], [3, -1, -1, -1]);
      expect(store.state!.turn.legal, isEmpty);

      final turn = TurnChangedEvent(
        roomId: 'r_1',
        v: 43,
        h: hashOf('L|9|0|-1,-1,5,56;3,-1,-1,-1'),
        seat: 0,
        turnSeq: 9,
        phase: 'awaiting_roll',
        deadline: 1761022840000,
        sixStreak: 0,
      );
      expect(store.apply(turn), isA<Applied>());
      final s = store.state!;
      expect(s.v, 43);
      expect(s.turn.seat, 0);
      expect(s.turn.turnSeq, 9);
      expect(s.turn.dice, 0);
      expect(s.turn.legal, isEmpty);
      expect(s.h, turn.h);

      // Replaying any of them is a duplicate.
      expect(store.apply(dice), isA<Ignored>());
      expect(store.apply(move), isA<Ignored>());
      expect(store.state!.v, 43);
    });

    test('dice result updates strikes and six streak', () {
      final local = ludoRoom(v: 40);
      final r = reducer.reduce(
        local,
        const DiceResultEvent(
          roomId: 'r_1',
          v: 41,
          seat: 1,
          value: 6,
          turnSeq: 8,
          phase: 'awaiting_move',
          legal: [0, 1],
          sixStreak: 2,
          strikes: 1,
          auto: true,
        ),
      );
      final s = (r as Applied).state;
      expect(s.turn.sixStreak, 2);
      expect(s.playerAtSeat(1)!.strikes, 1);
      expect(s.playerAtSeat(0)!.strikes, 0);
    });

    test('capture sends captured tokens to base', () {
      final local = ludoRoom(
        v: 40,
        tokens: const [
          [-1, -1, 30, 56],
          [10, -1, -1, -1],
        ],
      );
      final r = reducer.reduce(
        local,
        const MoveAppliedEvent(
          roomId: 'r_1',
          v: 41,
          seat: 1,
          token: 0,
          from: 10,
          to: 4,
          captures: [CapturedToken(seat: 0, token: 2)],
        ),
      );
      final tokens = (r as Applied).state.board.ludoTokens!;
      expect(tokens[0], [-1, -1, -1, 56]);
      expect(tokens[1], [4, -1, -1, -1]);
      // The previous state was not mutated.
      expect(local.board.ludoTokens![0], [-1, -1, 30, 56]);
    });

    test('invalid token index → needsSync(invalidDelta)', () {
      final r = reducer.reduce(
        ludoRoom(v: 40),
        const MoveAppliedEvent(
          roomId: 'r_1',
          v: 41,
          seat: 1,
          token: 7,
          from: 0,
          to: 1,
        ),
      );
      expect((r as NeedsSync).reason, SyncReason.invalidDelta);
    });
  });

  group('forfeit / finish / rematch', () {
    test('ludo forfeit removes the seat tokens', () {
      final local = ludoRoom(
        v: 40,
        tokens: const [
          [-1, 12, 30, 56],
          [10, -1, -1, -1],
        ],
      );
      final r = reducer.reduce(
        local,
        PlayerForfeitedEvent(
          roomId: 'r_1',
          v: 41,
          h: hashOf('L|7|1|-1,-1,-1,-1;10,-1,-1,-1'),
          seat: 0,
          reason: 'timeouts',
        ),
      );
      final s = (r as Applied).state;
      expect(s.playerAtSeat(0)!.forfeited, isTrue);
      expect(s.board.ludoTokens![0], [-1, -1, -1, -1]);
      expect(s.board.ludoTokens![1], [10, -1, -1, -1]);
    });

    test('snakes forfeit keeps positions', () {
      final local = snakesRoom(v: 10);
      final r = reducer.reduce(
        local,
        PlayerForfeitedEvent(
          roomId: 'r_s',
          v: 11,
          h: hashOf('S|12|0|34,0,99'),
          seat: 1,
        ),
      );
      final s = (r as Applied).state;
      expect(s.playerAtSeat(1)!.forfeited, isTrue);
      expect(s.board.snakesPositions, [34, 0, 99]);
    });

    test('game.finished sets status, result, rematch and phase', () {
      final r = reducer.reduce(
        ludoRoom(v: 40),
        const GameFinishedEvent(
          roomId: 'r_1',
          v: 41,
          result: RoomResult(winnerSeat: 1, placements: [1, 0], payout: 2000),
          rematch: RematchState(open: true, deadline: 99),
        ),
      );
      final s = (r as Applied).state;
      expect(s.status, 'finished');
      expect(s.isFinished, isTrue);
      expect(s.result!.winnerSeat, 1);
      expect(s.rematch!.open, isTrue);
      expect(s.turn.phase, 'finished');
    });

    test('room.rematch replaces the rematch state', () {
      final finished = ludoRoom(v: 40, status: 'finished');
      final r = reducer.reduce(
        finished,
        const RoomRematchEvent(
          roomId: 'r_1',
          v: 41,
          rematch: RematchState(open: true, accepted: [0, 1]),
        ),
      );
      expect((r as Applied).state.rematch!.accepted, [0, 1]);
    });

    test('player reconnects', () {
      final s1 =
          (reducer.reduce(
                    ludoRoom(v: 40),
                    const PlayerConnectionEvent(
                      roomId: 'r_1',
                      v: 41,
                      seat: 0,
                      connected: false,
                    ),
                  )
                  as Applied)
              .state;
      final s2 =
          (reducer.reduce(
                    s1,
                    const PlayerConnectionEvent(
                      roomId: 'r_1',
                      v: 42,
                      seat: 0,
                      connected: true,
                    ),
                  )
                  as Applied)
              .state;
      expect(s1.playerAtSeat(0)!.connected, isFalse);
      expect(s2.playerAtSeat(0)!.connected, isTrue);
    });
  });

  group('snakes sequence', () {
    test('dice → move via ladder → turn change', () {
      final store = RoomStateStore();
      store.apply(
        GameStateEvent(room: snakesRoom(v: 10, positions: const [33, 0, 99])),
      );

      expect(
        store.apply(
          DiceResultEvent(
            roomId: 'r_s',
            v: 11,
            h: hashOf('S|12|0|33,0,99'),
            seat: 0,
            value: 3,
            turnSeq: 12,
            phase: 'awaiting_roll',
          ),
        ),
        isA<Applied>(),
      );
      expect(
        store.apply(
          MoveAppliedEvent(
            roomId: 'r_s',
            v: 12,
            h: hashOf('S|12|0|44,0,99'),
            seat: 0,
            from: 33,
            to: 44,
            landing: 36,
            transition: const BoardTransition(kind: 'ladder', from: 36, to: 44),
          ),
        ),
        isA<Applied>(),
      );
      expect(store.state!.board.snakesPositions, [44, 0, 99]);
      final r = store.apply(
        TurnChangedEvent(
          roomId: 'r_s',
          v: 13,
          h: hashOf('S|13|1|44,0,99'),
          seat: 1,
          turnSeq: 13,
          phase: 'awaiting_roll',
        ),
      );
      expect(r, isA<Applied>());
      expect(store.state!.turn.seat, 1);
      expect(store.state!.v, 13);
    });

    test('a gap after a hash mismatch keeps waiting for the snapshot', () {
      final store = RoomStateStore();
      store.apply(GameStateEvent(room: snakesRoom(v: 10)));
      final mismatch = store.apply(
        const TurnChangedEvent(
          roomId: 'r_s',
          v: 11,
          h: 1,
          seat: 1,
          turnSeq: 13,
          phase: 'awaiting_roll',
        ),
      );
      expect((mismatch as NeedsSync).reason, SyncReason.hashMismatch);
      expect(store.state!.v, 11);
      // The authoritative snapshot then replaces everything.
      final fresh = snakesRoom(v: 12, turnSeq: 13, turnSeat: 1);
      final r = store.apply(GameStateEvent(room: fresh));
      expect((r as Applied).state, fresh);
      store.clear();
      expect(store.state, isNull);
    });
  });
}
