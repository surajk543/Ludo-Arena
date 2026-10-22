import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';

import 'fixtures.dart';

/// `player.forfeited.strikes` and `room.players[].forfeitWhy`
/// (docs/websocket-protocol.md §4 and §6).
void main() {
  const reducer = RoomStateReducer();

  group('parsing', () {
    test('player.forfeited carries the reason and the strikes', () {
      final m = decodeServerMessage(
        '{"t":"player.forfeited","p":{"roomId":"r_1","v":41,"h":7,"seat":1,'
        '"reason":"timeouts","strikes":5}}',
      );
      final e = m.event as PlayerForfeitedEvent;
      expect(e.seat, 1);
      expect(e.reason, ForfeitReasons.timeouts);
      expect(e.strikes, 5);
    });

    test('an older server without strikes / reason decodes with defaults', () {
      final e =
          decodeServerMessage(
                '{"t":"player.forfeited","p":{"roomId":"r_1","v":41,"seat":0}}',
              ).event
              as PlayerForfeitedEvent;
      expect(e.reason, ForfeitReasons.left);
      expect(e.strikes, 0);
    });

    test('snapshot players carry forfeitWhy (omitted when playing)', () {
      final json = ludoRoomJson();
      final players = json['players'] as List;
      (players[0] as Map<String, dynamic>)
        ..['forfeited'] = true
        ..['forfeitWhy'] = 'timeouts'
        ..['strikes'] = 5;
      final room = RoomSnapshot.fromJson(json);
      expect(room.playerAtSeat(0)!.forfeitWhy, ForfeitReasons.timeouts);
      expect(room.playerAtSeat(0)!.strikes, 5);
      expect(room.playerAtSeat(1)!.forfeitWhy, isEmpty);

      final back = jsonDecode(jsonEncode(room.toJson())) as Map;
      final out = back['players'] as List;
      expect((out[0] as Map)['forfeitWhy'], 'timeouts');
      expect((out[1] as Map).containsKey('forfeitWhy'), isFalse);
      expect(RoomSnapshot.fromJson(back.cast<String, dynamic>()), room);
    });
  });

  group('reducer', () {
    final local = ludoRoom(
      v: 40,
      tokens: const [
        [-1, 12, 30, 56],
        [10, -1, -1, -1],
      ],
    );

    for (final (reason, strikes) in [
      (ForfeitReasons.timeouts, 5),
      (ForfeitReasons.left, 2),
    ]) {
      test(
        '$reason: forfeited, forfeitWhy and strikes set; hash unchanged',
        () {
          final r = reducer.reduce(
            local,
            PlayerForfeitedEvent(
              roomId: 'r_1',
              v: 41,
              // forfeitWhy / strikes are not part of the canonical string.
              h: StateHash.fnv1a32('L|7|1|-1,-1,-1,-1;10,-1,-1,-1'),
              seat: 0,
              reason: reason,
              strikes: strikes,
            ),
          );
          expect(r, isA<Applied>());
          final s = (r as Applied).state;
          final p = s.playerAtSeat(0)!;
          expect(p.forfeited, isTrue);
          expect(p.forfeitWhy, reason);
          expect(p.strikes, strikes);
          final other = s.playerAtSeat(1)!;
          expect(other.forfeited, isFalse);
          expect(other.forfeitWhy, isEmpty);
          expect(s.board.ludoTokens![0], [-1, -1, -1, -1]);
        },
      );
    }

    test('hash test vectors are unchanged', () {
      expect(StateHash.fnv1a32('L|7|1|-1,-1,5,56;0,-1,-1,-1'), 2902942580);
      expect(StateHash.fnv1a32('S|12|0|34,0,99'), 1234224186);
      expect(StateHash.fnv1a32('L|0|0|-1,-1,-1,-1;-1,-1,-1,-1'), 638091788);
    });
  });
}
