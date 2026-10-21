import 'dart:convert';

import 'models.dart';

/// State hash (`h`) — backend/docs/game-rules.md → "State hash".
///
/// Canonical string (ASCII, no spaces):
/// - Ludo: `L|{turnSeq}|{turnSeat}|{tokens}` — each seat's four token
///   progress values joined by `,`, seats joined by `;`.
/// - Snakes & Ladders: `S|{turnSeq}|{turnSeat}|{positions}` — each seat's
///   square joined by `,`.
abstract final class StateHash {
  static const int _offsetBasis = 2166136261;
  static const int _mask32 = 0xFFFFFFFF;

  /// 32-bit FNV-1a over the UTF-8 bytes of [input].
  static int fnv1a32(String input) {
    var h = _offsetBasis;
    for (final b in utf8.encode(input)) {
      h ^= b;
      // h * 16777619 == h * 2^24 + h * 403, kept within 53 bits.
      h = (((h << 24) & _mask32) + h * 403) & _mask32;
    }
    return h;
  }

  /// Canonical position string for [room].
  static String canonical(RoomSnapshot room) {
    final seq = room.turn.turnSeq;
    final seat = room.turn.seat;
    if (room.isSnakes) {
      final positions = room.board.snakesPositions ?? const <int>[];
      return 'S|$seq|$seat|${positions.join(',')}';
    }
    final tokens = room.board.ludoTokens ?? const <List<int>>[];
    return 'L|$seq|$seat|${tokens.map((t) => t.join(',')).join(';')}';
  }

  /// Hash of [room]'s canonical string.
  static int of(RoomSnapshot room) => fnv1a32(canonical(room));
}
