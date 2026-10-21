import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';

import 'fixtures.dart';

void main() {
  group('FNV-1a test vectors (backend/docs/game-rules.md)', () {
    test('L|7|1|-1,-1,5,56;0,-1,-1,-1', () {
      expect(StateHash.fnv1a32('L|7|1|-1,-1,5,56;0,-1,-1,-1'), 2902942580);
    });
    test('S|12|0|34,0,99', () {
      expect(StateHash.fnv1a32('S|12|0|34,0,99'), 1234224186);
    });
    test('L|0|0|-1,-1,-1,-1;-1,-1,-1,-1', () {
      expect(StateHash.fnv1a32('L|0|0|-1,-1,-1,-1;-1,-1,-1,-1'), 638091788);
    });
    test('empty string is the offset basis', () {
      expect(StateHash.fnv1a32(''), 2166136261);
    });
  });

  group('canonical string', () {
    test('ludo', () {
      final room = ludoRoom();
      expect(StateHash.canonical(room), 'L|7|1|-1,-1,5,56;0,-1,-1,-1');
      expect(StateHash.of(room), 2902942580);
    });

    test('ludo initial board', () {
      final room = ludoRoom(
        turnSeq: 0,
        turnSeat: 0,
        tokens: const [
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      expect(StateHash.of(room), 638091788);
    });

    test('snakes', () {
      final room = snakesRoom();
      expect(StateHash.canonical(room), 'S|12|0|34,0,99');
      expect(StateHash.of(room), 1234224186);
    });
  });
}
