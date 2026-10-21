import 'package:ludo_royale/core/protocol/protocol.dart';

/// Builds a minimal 2-seat Ludo room snapshot JSON.
Map<String, dynamic> ludoRoomJson({
  String id = 'r_1',
  int v = 40,
  int turnSeq = 7,
  int turnSeat = 1,
  List<List<int>> tokens = const [
    [-1, -1, 5, 56],
    [0, -1, -1, -1],
  ],
  String status = 'playing',
  int round = 1,
  String mode = 'public',
  List<bool> bots = const [false, false],
}) => {
  'id': id,
  'v': v,
  'game': 'ludo',
  'variant': 'classic',
  'mode': mode,
  'allowBots': false,
  'capacity': tokens.length,
  'status': status,
  'hostSeat': -1,
  'entryFee': 100000,
  'pot': 100000 * tokens.length,
  'round': round,
  'fillDeadline': 0,
  'players': [
    for (var i = 0; i < tokens.length; i++)
      {
        'seat': i,
        'uid': 'u_$i',
        'name': 'P$i',
        'avatar': i,
        'level': 3,
        'title': 'title_rookie',
        'cosmetics': {
          'dice': 'dice_classic',
          'token': 'token_classic',
          'frame': 'frame_none',
          'trail': 'trail_none',
          'victory': 'victory_confetti',
        },
        'color': i == 0 ? 'red' : 'yellow',
        'connected': true,
        'bot': bots.length > i && bots[i],
        'forfeited': false,
        'strikes': 0,
      },
  ],
  'turn': {
    'seat': turnSeat,
    'phase': 'awaiting_roll',
    'turnSeq': turnSeq,
    'deadline': 1761022800000,
    'dice': 0,
    'legal': <int>[],
    'sixStreak': 0,
  },
  'board': {'tokens': tokens},
};

RoomSnapshot ludoRoom({
  String id = 'r_1',
  int v = 40,
  int turnSeq = 7,
  int turnSeat = 1,
  List<List<int>> tokens = const [
    [-1, -1, 5, 56],
    [0, -1, -1, -1],
  ],
  String status = 'playing',
  int round = 1,
  String mode = 'public',
  List<bool> bots = const [false, false],
}) => RoomSnapshot.fromJson(
  ludoRoomJson(
    id: id,
    v: v,
    turnSeq: turnSeq,
    turnSeat: turnSeat,
    tokens: tokens,
    status: status,
    round: round,
    mode: mode,
    bots: bots,
  ),
);

RoomSnapshot snakesRoom({
  String id = 'r_s',
  int v = 10,
  int turnSeq = 12,
  int turnSeat = 0,
  List<int> positions = const [34, 0, 99],
}) {
  final json = ludoRoomJson(
    id: id,
    v: v,
    turnSeq: turnSeq,
    turnSeat: turnSeat,
    tokens: [for (final _ in positions) const <int>[]],
  );
  json['game'] = 'snakes_ladders';
  json['board'] = {'positions': positions};
  return RoomSnapshot.fromJson(json);
}
