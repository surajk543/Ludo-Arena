import 'package:flutter/foundation.dart';

import '../../../core/protocol/protocol.dart';

/// Why the host cannot start yet (null = can start).
enum StartBlocker {
  /// Not the host.
  notHost,

  /// Fewer than 2 players seated.
  needPlayers,

  /// Someone is disconnected.
  waitingForConnections,

  /// A requested bot has not sat down yet.
  botsJoining,

  /// The room is no longer a lobby.
  notLobby,
}

/// What the local player may do in a private room lobby. Pure: derived from
/// the server snapshot plus the number of bots the host requested that have
/// not been seated yet.
@immutable
class LobbyPermissions {
  const LobbyPermissions({
    required this.isHost,
    required this.startBlocker,
    required this.canToggleBots,
    required this.canAddBot,
    required this.canRemoveBots,
    required this.canInvite,
  });

  final bool isHost;

  /// Null when Start is enabled.
  final StartBlocker? startBlocker;
  final bool canToggleBots;
  final bool canAddBot;
  final bool canRemoveBots;
  final bool canInvite;

  bool get canStart => startBlocker == null;

  factory LobbyPermissions.of(
    RoomSnapshot room, {
    required int? selfSeat,
    int pendingBots = 0,
  }) {
    final isHost =
        selfSeat != null && room.hostSeat >= 0 && room.hostSeat == selfSeat;
    final lobby = room.isLobby;
    final seated = room.players.length;
    final hasFreeSeat = seated + pendingBots < room.capacity;

    StartBlocker? blocker;
    if (!isHost) {
      blocker = StartBlocker.notHost;
    } else if (!lobby) {
      blocker = StartBlocker.notLobby;
    } else if (pendingBots > 0) {
      blocker = StartBlocker.botsJoining;
    } else if (seated < 2) {
      blocker = StartBlocker.needPlayers;
    } else if (room.players.any((p) => !p.connected)) {
      blocker = StartBlocker.waitingForConnections;
    }

    final hostLobby = isHost && lobby && room.isPrivate;
    return LobbyPermissions(
      isHost: isHost,
      startBlocker: blocker,
      canToggleBots: hostLobby,
      canAddBot: hostLobby && room.allowBots && hasFreeSeat,
      canRemoveBots: hostLobby,
      canInvite: lobby && hasFreeSeat,
    );
  }
}
