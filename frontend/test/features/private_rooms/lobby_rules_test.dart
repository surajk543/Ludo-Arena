import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/features/private_rooms/application/lobby_rules.dart';

import '../game/support/play_test_support.dart';

RoomSnapshot _lobby({
  List<RoomPlayer>? players,
  bool allowBots = false,
  int capacity = 4,
}) => ludoRoom(
  status: RoomStatuses.lobby,
  mode: RoomModes.private,
  hostSeat: 0,
  code: 'K7Q2MX',
  allowBots: allowBots,
  capacity: capacity,
  players: players ?? [player(0), player(1)],
);

void main() {
  test('host can start with ≥ 2 connected players and no pending bots', () {
    final p = LobbyPermissions.of(_lobby(), selfSeat: 0);
    expect(p.isHost, isTrue);
    expect(p.canStart, isTrue);
    expect(p.canToggleBots, isTrue);
    expect(p.canInvite, isTrue);
  });

  test('guest never gets host controls', () {
    final p = LobbyPermissions.of(_lobby(allowBots: true), selfSeat: 1);
    expect(p.isHost, isFalse);
    expect(p.startBlocker, StartBlocker.notHost);
    expect(p.canToggleBots, isFalse);
    expect(p.canAddBot, isFalse);
    expect(p.canRemoveBots, isFalse);
  });

  test('start blockers: players, connections, pending bots', () {
    expect(
      LobbyPermissions.of(
        _lobby(players: [player(0)]),
        selfSeat: 0,
      ).startBlocker,
      StartBlocker.needPlayers,
    );
    expect(
      LobbyPermissions.of(
        _lobby(players: [player(0), player(1, connected: false)]),
        selfSeat: 0,
      ).startBlocker,
      StartBlocker.waitingForConnections,
    );
    expect(
      LobbyPermissions.of(
        _lobby(allowBots: true),
        selfSeat: 0,
        pendingBots: 1,
      ).startBlocker,
      StartBlocker.botsJoining,
    );
  });

  test('add bot needs allowBots and a free seat (incl. pending bots)', () {
    expect(
      LobbyPermissions.of(_lobby(), selfSeat: 0).canAddBot,
      isFalse,
      reason: 'bots not allowed',
    );
    expect(
      LobbyPermissions.of(_lobby(allowBots: true), selfSeat: 0).canAddBot,
      isTrue,
    );
    expect(
      LobbyPermissions.of(
        _lobby(allowBots: true, capacity: 3),
        selfSeat: 0,
        pendingBots: 1,
      ).canAddBot,
      isFalse,
      reason: 'the last seat is already requested',
    );
  });
}
