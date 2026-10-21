/// Message type constants for the `ludo-royale.v1` WebSocket protocol
/// (docs/websocket-protocol.md §5 and §6).
library;

/// The negotiated WebSocket subprotocol.
const String kProtocolName = 'ludo-royale.v1';

/// Application protocol version reported in `connection.ready`.
const int kProtocolVersion = 1;

/// Client → server message types (§5).
abstract final class ClientMessageTypes {
  static const ping = 'ping';
  static const matchmakingJoin = 'matchmaking.join';
  static const matchmakingCancel = 'matchmaking.cancel';
  static const roomCreate = 'room.create';
  static const roomJoin = 'room.join';
  static const roomLeave = 'room.leave';
  static const practiceStart = 'practice.start';
  static const roomAllowBots = 'room.allow_bots';
  static const roomAddBot = 'room.add_bot';
  static const roomRemoveBot = 'room.remove_bot';
  static const roomInvite = 'room.invite';
  static const gameStart = 'game.start';
  static const gameRollDice = 'game.roll_dice';
  static const gameMakeMove = 'game.make_move';
  static const gameRequestSync = 'game.request_sync';
  static const gameRematch = 'game.rematch';
  static const chatQuick = 'chat.quick';
  static const chatEmote = 'chat.emote';

  static const all = <String>{
    ping,
    matchmakingJoin,
    matchmakingCancel,
    roomCreate,
    roomJoin,
    roomLeave,
    practiceStart,
    roomAllowBots,
    roomAddBot,
    roomRemoveBot,
    roomInvite,
    gameStart,
    gameRollDice,
    gameMakeMove,
    gameRequestSync,
    gameRematch,
    chatQuick,
    chatEmote,
  };
}

/// Server → client message types (§6).
abstract final class ServerMessageTypes {
  static const connectionReady = 'connection.ready';
  static const pong = 'pong';
  static const ack = 'ack';
  static const error = 'error';
  static const matchmakingStatus = 'matchmaking.status';
  static const roomUpdated = 'room.updated';
  static const gameStarted = 'game.started';
  static const gameState = 'game.state';
  static const diceResult = 'game.dice_result';
  static const moveApplied = 'game.move_applied';
  static const turnChanged = 'game.turn_changed';
  static const playerConnected = 'player.connected';
  static const playerDisconnected = 'player.disconnected';
  static const playerForfeited = 'player.forfeited';
  static const gameFinished = 'game.finished';
  static const roomRematch = 'room.rematch';
  static const walletUpdated = 'wallet.updated';
  static const progressionUpdated = 'progression.updated';
  static const chatQuick = 'chat.quick';
  static const chatEmote = 'chat.emote';
  static const socialInvite = 'social.invite';
  static const socialFriendRequest = 'social.friend_request';

  /// Synthetic, client-local: emitted by `RealtimeConnection` when its
  /// bounded inbound buffer overflowed and versioned deltas were dropped.
  /// Never sent by the server.
  static const localResyncRequired = 'client.resync_required';

  /// Types that carry a full room snapshot.
  static const snapshots = <String>{roomUpdated, gameStarted, gameState};

  /// Versioned room deltas (§3).
  static const deltas = <String>{
    diceResult,
    moveApplied,
    turnChanged,
    playerConnected,
    playerDisconnected,
    playerForfeited,
    gameFinished,
    roomRematch,
  };
}

/// Predefined quick-chat ids (§5). Display text is localized by the UI.
abstract final class QuickChatIds {
  static const gg = 'gg';
  static const niceMove = 'nice_move';
  static const wellPlayed = 'well_played';
  static const rematch = 'rematch';
  static const again = 'again';
  static const goodLuck = 'good_luck';
  static const oops = 'oops';
  static const thanks = 'thanks';

  static const all = <String>[
    gg,
    niceMove,
    wellPlayed,
    rematch,
    again,
    goodLuck,
    oops,
    thanks,
  ];
}

/// `room.game` values.
abstract final class GameIds {
  static const ludo = 'ludo';
  static const snakesLadders = 'snakes_ladders';
}

/// `room.variant` values (Ludo only; Snakes uses `classic`).
abstract final class GameVariants {
  static const classic = 'classic';
  static const quick = 'quick';
}

/// `room.mode` values.
abstract final class RoomModes {
  static const public = 'public';
  static const private = 'private';
  static const practice = 'practice';
}

/// `room.status` values.
abstract final class RoomStatuses {
  static const lobby = 'lobby';
  static const playing = 'playing';
  static const finished = 'finished';
  static const closed = 'closed';
}

/// `turn.phase` values.
abstract final class TurnPhases {
  static const awaitingRoll = 'awaiting_roll';
  static const awaitingMove = 'awaiting_move';
  static const none = 'none';
  static const finished = 'finished';
}

/// `matchmaking.status.status` values.
abstract final class MatchmakingStatuses {
  static const searching = 'searching';
  static const cancelled = 'cancelled';
  static const timeout = 'timeout';
}

/// WebSocket close codes (§1).
abstract final class WsCloseCodes {
  static const normal = 1000;
  static const goingAway = 1001;
  static const policyViolation = 1008;
  static const protocolViolation = 4400;
  static const sessionRevoked = 4401;
  static const sessionReplaced = 4409;
  static const updateRequired = 4426;
  static const rateLimited = 4429;
  static const maintenance = 4503;
  static const slowConsumer = 4508;

  /// Client-local: the heartbeat (pong) timed out. Never received from the
  /// server.
  static const heartbeatTimeout = 4000;
}
