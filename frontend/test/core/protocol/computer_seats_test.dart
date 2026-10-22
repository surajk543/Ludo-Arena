import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';

import 'fixtures.dart';

void main() {
  group('RoomPlayer has no bot flag', () {
    test('parses a seat without `bot` and never writes one', () {
      final json = ludoRoomJson();
      final seat = Map<String, dynamic>.from(
        (json['players'] as List).first as Map,
      );
      expect(seat.containsKey('bot'), isFalse);
      final p = RoomPlayer.fromJson(seat);
      expect(p.uid, 'u_0');
      expect(p.toJson().containsKey('bot'), isFalse);
      // A stray `bot` key (older servers) is ignored: the seat is identical.
      expect(RoomPlayer.fromJson({...seat, 'bot': true}), p);
      expect(p.copyWith(connected: false).toJson().containsKey('bot'), isFalse);
    });

    test('a snapshot round-trip carries no bot key anywhere', () {
      final room = RoomSnapshot.fromJson(
        ludoRoomJson(mode: 'private', computerSeats: const [1]),
      );
      bool hasBotKey(Object? v) => switch (v) {
        Map() => v.keys.contains('bot') || v.values.any(hasBotKey),
        List() => v.any(hasBotKey),
        _ => false,
      };
      expect(hasBotKey(room.toJson()), isFalse);
    });
  });

  group('RoomSnapshot.computerSeats', () {
    test('absent (public rooms) → empty, not serialized', () {
      final room = ludoRoom();
      expect(room.computerSeats, isEmpty);
      expect(room.hasComputerPlayers, isFalse);
      expect(room.isComputerSeat(1), isFalse);
      expect(room.toJson().containsKey('computerSeats'), isFalse);
    });

    test('practice / private rooms list their computer seats', () {
      final json = ludoRoomJson(mode: 'practice', computerSeats: const [1]);
      final room = RoomSnapshot.fromJson(json);
      expect(room.computerSeats, [1]);
      expect(room.hasComputerPlayers, isTrue);
      expect(room.isComputerSeat(1), isTrue);
      expect(room.isComputerSeat(0), isFalse);
      expect(room.toJson()['computerSeats'], [1]);
      expect(RoomSnapshot.fromJson(room.toJson()), room);
    });

    test('malformed entries are read defensively', () {
      final room = RoomSnapshot.fromJson({
        ...ludoRoomJson(mode: 'private'),
        'computerSeats': 'nope',
      });
      expect(room.computerSeats, isEmpty);
    });

    test('copyWith keeps or replaces the list; equality includes it', () {
      final room = ludoRoom(mode: 'private', computerSeats: const [1]);
      expect(room.copyWith(v: 99).computerSeats, [1]);
      final none = room.copyWith(computerSeats: const []);
      expect(none.computerSeats, isEmpty);
      expect(none == room, isFalse);
      expect(room.copyWith(), room);
    });
  });
}
