import 'package:flutter/foundation.dart';

import 'json_read.dart';
import 'message_types.dart';
import 'models.dart';

/// Typed payload of a server → client message (websocket-protocol.md §6).
///
/// Unknown message types decode to [UnknownEvent] (clients must ignore
/// unknown types and fields).
sealed class ServerEvent {
  const ServerEvent();

  /// The wire type (`t`).
  String get type;

  /// Parses [payload] for message [type]. Never throws for unknown types.
  static ServerEvent parse(String type, Map<String, dynamic> payload) {
    final p = payload;
    return switch (type) {
      ServerMessageTypes.connectionReady => ConnectionReadyEvent.fromJson(p),
      ServerMessageTypes.pong => PongEvent(ts: readInt(p['ts'])),
      ServerMessageTypes.ack => AckEvent(dup: readBool(p['dup'])),
      ServerMessageTypes.error => ServerErrorEvent.fromJson(p),
      ServerMessageTypes.matchmakingStatus => MatchmakingStatusEvent.fromJson(
        p,
      ),
      ServerMessageTypes.roomUpdated => RoomUpdatedEvent(
        room: RoomSnapshot.fromJson(readMap(p['room'])),
        reason: readStringOrNull(p['reason']),
      ),
      ServerMessageTypes.gameStarted => GameStartedEvent(
        room: RoomSnapshot.fromJson(readMap(p['room'])),
      ),
      ServerMessageTypes.gameState => GameStateEvent(
        room: RoomSnapshot.fromJson(readMap(p['room'])),
      ),
      ServerMessageTypes.diceResult => DiceResultEvent.fromJson(p),
      ServerMessageTypes.moveApplied => MoveAppliedEvent.fromJson(p),
      ServerMessageTypes.turnChanged => TurnChangedEvent.fromJson(p),
      ServerMessageTypes.playerConnected => PlayerConnectionEvent.fromJson(
        p,
        connected: true,
      ),
      ServerMessageTypes.playerDisconnected => PlayerConnectionEvent.fromJson(
        p,
        connected: false,
      ),
      ServerMessageTypes.playerForfeited => PlayerForfeitedEvent.fromJson(p),
      ServerMessageTypes.gameFinished => GameFinishedEvent.fromJson(p),
      ServerMessageTypes.roomRematch => RoomRematchEvent.fromJson(p),
      ServerMessageTypes.walletUpdated => WalletUpdatedEvent.fromJson(p),
      ServerMessageTypes.progressionUpdated => ProgressionUpdatedEvent.fromJson(
        p,
      ),
      ServerMessageTypes.chatQuick => QuickChatEvent.fromJson(p),
      ServerMessageTypes.chatEmote => EmoteEvent.fromJson(p),
      ServerMessageTypes.socialInvite => SocialInviteEvent.fromJson(p),
      ServerMessageTypes.socialFriendRequest => FriendRequestEvent.fromJson(p),
      ServerMessageTypes.localResyncRequired => const LocalResyncRequired(),
      _ => UnknownEvent(type),
    };
  }
}

/// A message type this client does not know. Ignored by everything.
final class UnknownEvent extends ServerEvent {
  const UnknownEvent(this.type);

  @override
  final String type;
}

/// Client-local signal (never from the server): inbound deltas were dropped
/// because the bounded inbound buffer overflowed; request a snapshot.
final class LocalResyncRequired extends ServerEvent {
  const LocalResyncRequired();

  @override
  String get type => ServerMessageTypes.localResyncRequired;
}

/// `connection.ready`.
@immutable
final class ConnectionReadyEvent extends ServerEvent {
  const ConnectionReadyEvent({
    required this.uid,
    this.protocol = kProtocolVersion,
    this.serverTime = 0,
    this.activeRoomId,
    this.compression = 'none',
    this.heartbeatSec = 20,
  });

  /// The user's public id (`u_…`), used to find the user's own seat.
  final String uid;
  final int protocol;

  /// Server unix ms.
  final int serverTime;

  /// The room the user is currently seated in (rejoin after restart).
  final String? activeRoomId;

  /// What was actually negotiated (`none` or the permessage-deflate params).
  final String compression;
  final int heartbeatSec;

  factory ConnectionReadyEvent.fromJson(Map<String, dynamic> j) =>
      ConnectionReadyEvent(
        uid: readString(j['uid']),
        protocol: readInt(j['protocol'], kProtocolVersion),
        serverTime: readInt(j['serverTime']),
        activeRoomId: readStringOrNull(j['activeRoomId']),
        compression: readString(j['compression'], 'none'),
        heartbeatSec: readInt(j['heartbeatSec'], 20),
      );

  @override
  String get type => ServerMessageTypes.connectionReady;
}

/// `pong`.
final class PongEvent extends ServerEvent {
  const PongEvent({required this.ts});

  /// Server unix ms.
  final int ts;

  @override
  String get type => ServerMessageTypes.pong;
}

/// `ack` (`dup: true` when the command id was already processed).
final class AckEvent extends ServerEvent {
  const AckEvent({this.dup = false});

  final bool dup;

  @override
  String get type => ServerMessageTypes.ack;
}

/// `error` — a reply to a command or unsolicited.
final class ServerErrorEvent extends ServerEvent {
  const ServerErrorEvent({
    required this.code,
    this.msg = '',
    this.retry = false,
  });

  /// Protocol error code (§9). Localize with `localizedErrorMessage`.
  final String code;

  /// English text for logs; show the localized text for [code] instead.
  final String msg;

  /// The same command may succeed later without user action.
  final bool retry;

  factory ServerErrorEvent.fromJson(Map<String, dynamic> j) => ServerErrorEvent(
    code: readString(j['code'], 'internal'),
    msg: readString(j['msg']),
    retry: readBool(j['retry']),
  );

  @override
  String get type => ServerMessageTypes.error;
}

/// `matchmaking.status`.
final class MatchmakingStatusEvent extends ServerEvent {
  const MatchmakingStatusEvent({
    required this.status,
    this.game = GameIds.ludo,
    this.variant = GameVariants.classic,
    this.capacity = 4,
    this.roomId,
  });

  /// [MatchmakingStatuses]: `searching` | `cancelled` | `timeout`.
  final String status;
  final String game;
  final String variant;
  final int capacity;
  final String? roomId;

  bool get isSearching => status == MatchmakingStatuses.searching;

  factory MatchmakingStatusEvent.fromJson(Map<String, dynamic> j) =>
      MatchmakingStatusEvent(
        status: readString(j['status']),
        game: readString(j['game'], GameIds.ludo),
        variant: readString(j['variant'], GameVariants.classic),
        capacity: readInt(j['capacity'], 4),
        roomId: readStringOrNull(j['roomId']),
      );

  @override
  String get type => ServerMessageTypes.matchmakingStatus;
}

// ------------------------------------------------------------- snapshots

/// An event carrying a full room snapshot (replaces local state, §3).
sealed class RoomSnapshotEvent extends ServerEvent {
  const RoomSnapshotEvent({required this.room});

  final RoomSnapshot room;
}

/// `room.updated` — `reason`: created | joined | left | host_changed |
/// rematch_started | …
final class RoomUpdatedEvent extends RoomSnapshotEvent {
  const RoomUpdatedEvent({required super.room, this.reason});

  final String? reason;

  @override
  String get type => ServerMessageTypes.roomUpdated;
}

/// `game.started`.
final class GameStartedEvent extends RoomSnapshotEvent {
  const GameStartedEvent({required super.room});

  @override
  String get type => ServerMessageTypes.gameStarted;
}

/// `game.state` (reply to `game.request_sync`, or after a stale action /
/// outbound-queue overflow).
final class GameStateEvent extends RoomSnapshotEvent {
  const GameStateEvent({required super.room});

  @override
  String get type => ServerMessageTypes.gameState;
}

// ----------------------------------------------------------------- deltas

/// A versioned room delta (§3/§6): carries `roomId`, the NEW `v`, and `h`
/// when the event changes the hashed position.
sealed class RoomDeltaEvent extends ServerEvent {
  const RoomDeltaEvent({required this.roomId, required this.v, this.h});

  final String roomId;
  final int v;

  /// FNV-1a state hash after this event (see `state_hash.dart`).
  final int? h;
}

/// `game.dice_result`.
final class DiceResultEvent extends RoomDeltaEvent {
  const DiceResultEvent({
    required super.roomId,
    required super.v,
    super.h,
    required this.seat,
    required this.value,
    required this.turnSeq,
    required this.phase,
    this.deadline = 0,
    this.legal = const [],
    this.sixStreak = 0,
    this.voided = false,
    this.auto = false,
    this.strikes = 0,
  });

  final int seat;
  final int value;
  final int turnSeq;
  final String phase;
  final int deadline;
  final List<int> legal;
  final int sixStreak;

  /// Third six: no move; the turn passes in a following `turn_changed`.
  final bool voided;

  /// Rolled by the server on timeout.
  final bool auto;
  final int strikes;

  factory DiceResultEvent.fromJson(Map<String, dynamic> j) => DiceResultEvent(
    roomId: readString(j['roomId']),
    v: readInt(j['v']),
    h: readIntOrNull(j['h']),
    seat: readInt(j['seat']),
    value: readInt(j['value']),
    turnSeq: readInt(j['turnSeq']),
    phase: readString(j['phase'], TurnPhases.awaitingRoll),
    deadline: readInt(j['deadline']),
    legal: readIntList(j['legal']),
    sixStreak: readInt(j['sixStreak']),
    voided: readBool(j['voided']),
    auto: readBool(j['auto']),
    strikes: readInt(j['strikes']),
  );

  @override
  String get type => ServerMessageTypes.diceResult;
}

/// A captured token in `game.move_applied`.
@immutable
class CapturedToken {
  const CapturedToken({required this.seat, required this.token});

  final int seat;
  final int token;

  @override
  bool operator ==(Object other) =>
      other is CapturedToken && other.seat == seat && other.token == token;

  @override
  int get hashCode => Object.hash(seat, token);
}

/// Snake / ladder transition in a Snakes & Ladders move.
@immutable
class BoardTransition {
  const BoardTransition({
    required this.kind,
    required this.from,
    required this.to,
  });

  /// `snake` | `ladder`.
  final String kind;
  final int from;
  final int to;

  bool get isSnake => kind == 'snake';
  bool get isLadder => kind == 'ladder';
}

/// `game.move_applied`.
final class MoveAppliedEvent extends RoomDeltaEvent {
  const MoveAppliedEvent({
    required super.roomId,
    required super.v,
    super.h,
    required this.seat,
    this.token = 0,
    required this.from,
    required this.to,
    this.captures = const [],
    this.landing,
    this.transition,
    this.home = false,
    this.auto = false,
  });

  final int seat;

  /// Ludo token index (Snakes: 0).
  final int token;
  final int from;
  final int to;
  final List<CapturedToken> captures;

  /// Snakes: square reached before a snake/ladder transition (animation only).
  final int? landing;
  final BoardTransition? transition;

  /// Ludo: the token reached home (56).
  final bool home;

  /// Applied by the server (single legal move or timeout).
  final bool auto;

  factory MoveAppliedEvent.fromJson(Map<String, dynamic> j) {
    final t = readMapOrNull(j['transition']);
    return MoveAppliedEvent(
      roomId: readString(j['roomId']),
      v: readInt(j['v']),
      h: readIntOrNull(j['h']),
      seat: readInt(j['seat']),
      token: readInt(j['token']),
      from: readInt(j['from']),
      to: readInt(j['to']),
      captures: List<CapturedToken>.unmodifiable(
        readList(j['captures']).map((c) {
          final m = readMap(c);
          return CapturedToken(
            seat: readInt(m['seat']),
            token: readInt(m['token']),
          );
        }),
      ),
      landing: readIntOrNull(j['landing']),
      transition: t == null
          ? null
          : BoardTransition(
              kind: readString(t['kind']),
              from: readInt(t['from']),
              to: readInt(t['to']),
            ),
      home: readBool(j['home']),
      auto: readBool(j['auto']),
    );
  }

  @override
  String get type => ServerMessageTypes.moveApplied;
}

/// `game.turn_changed`.
final class TurnChangedEvent extends RoomDeltaEvent {
  const TurnChangedEvent({
    required super.roomId,
    required super.v,
    super.h,
    required this.seat,
    required this.turnSeq,
    required this.phase,
    this.deadline = 0,
    this.sixStreak = 0,
  });

  final int seat;
  final int turnSeq;
  final String phase;
  final int deadline;
  final int sixStreak;

  factory TurnChangedEvent.fromJson(Map<String, dynamic> j) => TurnChangedEvent(
    roomId: readString(j['roomId']),
    v: readInt(j['v']),
    h: readIntOrNull(j['h']),
    seat: readInt(j['seat']),
    turnSeq: readInt(j['turnSeq']),
    phase: readString(j['phase'], TurnPhases.awaitingRoll),
    deadline: readInt(j['deadline']),
    sixStreak: readInt(j['sixStreak']),
  );

  @override
  String get type => ServerMessageTypes.turnChanged;
}

/// `player.connected` / `player.disconnected`.
final class PlayerConnectionEvent extends RoomDeltaEvent {
  const PlayerConnectionEvent({
    required super.roomId,
    required super.v,
    super.h,
    required this.seat,
    required this.connected,
  });

  final int seat;
  final bool connected;

  factory PlayerConnectionEvent.fromJson(
    Map<String, dynamic> j, {
    required bool connected,
  }) => PlayerConnectionEvent(
    roomId: readString(j['roomId']),
    v: readInt(j['v']),
    h: readIntOrNull(j['h']),
    seat: readInt(j['seat']),
    connected: connected,
  );

  @override
  String get type => connected
      ? ServerMessageTypes.playerConnected
      : ServerMessageTypes.playerDisconnected;
}

/// `player.forfeited`.
final class PlayerForfeitedEvent extends RoomDeltaEvent {
  const PlayerForfeitedEvent({
    required super.roomId,
    required super.v,
    super.h,
    required this.seat,
    this.reason = ForfeitReasons.left,
    this.strikes = 0,
  });

  final int seat;

  /// [ForfeitReasons]: `left` | `timeouts`.
  final String reason;

  /// The seat's consecutive missed turns; for `timeouts`, the count that
  /// removed the player (`MAX_STRIKES`).
  final int strikes;

  factory PlayerForfeitedEvent.fromJson(Map<String, dynamic> j) =>
      PlayerForfeitedEvent(
        roomId: readString(j['roomId']),
        v: readInt(j['v']),
        h: readIntOrNull(j['h']),
        seat: readInt(j['seat']),
        reason: readString(j['reason'], ForfeitReasons.left),
        strikes: readInt(j['strikes']),
      );

  @override
  String get type => ServerMessageTypes.playerForfeited;
}

/// `game.finished`.
final class GameFinishedEvent extends RoomDeltaEvent {
  const GameFinishedEvent({
    required super.roomId,
    required super.v,
    super.h,
    required this.result,
    required this.rematch,
  });

  final RoomResult result;
  final RematchState rematch;

  factory GameFinishedEvent.fromJson(Map<String, dynamic> j) =>
      GameFinishedEvent(
        roomId: readString(j['roomId']),
        v: readInt(j['v']),
        h: readIntOrNull(j['h']),
        result: RoomResult.fromJson(readMap(j['result'])),
        rematch: RematchState.fromJson(readMap(j['rematch'])),
      );

  @override
  String get type => ServerMessageTypes.gameFinished;
}

/// `room.rematch`.
final class RoomRematchEvent extends RoomDeltaEvent {
  const RoomRematchEvent({
    required super.roomId,
    required super.v,
    super.h,
    required this.rematch,
  });

  final RematchState rematch;

  factory RoomRematchEvent.fromJson(Map<String, dynamic> j) => RoomRematchEvent(
    roomId: readString(j['roomId']),
    v: readInt(j['v']),
    h: readIntOrNull(j['h']),
    rematch: RematchState.fromJson(readMap(j['rematch'])),
  );

  @override
  String get type => ServerMessageTypes.roomRematch;
}

// ---------------------------------------------------------------- account

/// `wallet.updated` (server-confirmed balances).
final class WalletUpdatedEvent extends ServerEvent {
  const WalletUpdatedEvent({
    required this.coins,
    required this.diamonds,
    this.deltaCoins = 0,
    this.deltaDiamonds = 0,
    this.reason = '',
  });

  final int coins;
  final int diamonds;
  final int deltaCoins;
  final int deltaDiamonds;

  /// `entry_fee` | `payout` | `mission` | `purchase` | `level`.
  final String reason;

  factory WalletUpdatedEvent.fromJson(Map<String, dynamic> j) {
    final d = readMap(j['delta']);
    return WalletUpdatedEvent(
      coins: readInt(j['coins']),
      diamonds: readInt(j['diamonds']),
      deltaCoins: readInt(d['coins']),
      deltaDiamonds: readInt(d['diamonds']),
      reason: readString(j['reason']),
    );
  }

  @override
  String get type => ServerMessageTypes.walletUpdated;
}

/// Mission progress inside `progression.updated`.
@immutable
class MissionProgress {
  const MissionProgress({
    required this.id,
    required this.progress,
    required this.target,
    required this.completed,
  });

  final String id;
  final int progress;
  final int target;
  final bool completed;

  factory MissionProgress.fromJson(Map<String, dynamic> j) => MissionProgress(
    id: readString(j['id']),
    progress: readInt(j['progress']),
    target: readInt(j['target'], 1),
    completed: readBool(j['completed']),
  );
}

/// `progression.updated`.
final class ProgressionUpdatedEvent extends ServerEvent {
  const ProgressionUpdatedEvent({
    required this.xp,
    required this.level,
    this.xpGained = 0,
    this.levelUp = false,
    this.unlocked = const [],
    this.missions = const [],
  });

  final int xp;
  final int level;
  final int xpGained;
  final bool levelUp;

  /// Cosmetic item ids unlocked by this update.
  final List<String> unlocked;
  final List<MissionProgress> missions;

  factory ProgressionUpdatedEvent.fromJson(Map<String, dynamic> j) =>
      ProgressionUpdatedEvent(
        xp: readInt(j['xp']),
        level: readInt(j['level'], 1),
        xpGained: readInt(j['xpGained']),
        levelUp: readBool(j['levelUp']),
        unlocked: readStringList(j['unlocked']),
        missions: List<MissionProgress>.unmodifiable(
          readList(
            j['missions'],
          ).map((m) => MissionProgress.fromJson(readMap(m))),
        ),
      );

  @override
  String get type => ServerMessageTypes.progressionUpdated;
}

// ---------------------------------------------------------- chat / social

/// `chat.quick` (not versioned).
final class QuickChatEvent extends ServerEvent {
  const QuickChatEvent({
    required this.roomId,
    required this.seat,
    required this.msg,
  });

  final String roomId;
  final int seat;

  /// A predefined id from [QuickChatIds]; localize for display.
  final String msg;

  factory QuickChatEvent.fromJson(Map<String, dynamic> j) => QuickChatEvent(
    roomId: readString(j['roomId']),
    seat: readInt(j['seat']),
    msg: readString(j['msg']),
  );

  @override
  String get type => ServerMessageTypes.chatQuick;
}

/// `chat.emote` (not versioned).
final class EmoteEvent extends ServerEvent {
  const EmoteEvent({
    required this.roomId,
    required this.seat,
    required this.emote,
    this.asset,
  });

  final String roomId;
  final int seat;

  /// Emote item id: a built-in `emote_wave`, … or a Store emote `em_…`.
  final String emote;

  /// The art of a Store emote (downloaded once and cached); null for
  /// built-in emotes and for a missing or malformed `asset`.
  final EmoteAsset? asset;

  factory EmoteEvent.fromJson(Map<String, dynamic> j) => EmoteEvent(
    roomId: readString(j['roomId']),
    seat: readInt(j['seat']),
    emote: readString(j['emote']),
    asset: EmoteAsset.tryParse(j['asset']),
  );

  @override
  String get type => ServerMessageTypes.chatEmote;
}

/// `social.invite` — a friend invited the user to a room.
final class SocialInviteEvent extends ServerEvent {
  const SocialInviteEvent({
    required this.inviteId,
    required this.fromUid,
    required this.fromName,
    required this.roomId,
    required this.code,
    required this.game,
    required this.expiresAt,
  });

  final String inviteId;
  final String fromUid;
  final String fromName;
  final String roomId;

  /// Room code to pass to `room.join`. Never log or send to analytics.
  final String code;
  final String game;

  /// Unix ms, server clock.
  final int expiresAt;

  factory SocialInviteEvent.fromJson(Map<String, dynamic> j) =>
      SocialInviteEvent(
        inviteId: readString(j['inviteId']),
        fromUid: readString(j['fromUid']),
        fromName: readString(j['fromName']),
        roomId: readString(j['roomId']),
        code: readString(j['code']),
        game: readString(j['game'], GameIds.ludo),
        expiresAt: readInt(j['expiresAt']),
      );

  @override
  String get type => ServerMessageTypes.socialInvite;
}

/// `social.friend_request`.
final class FriendRequestEvent extends ServerEvent {
  const FriendRequestEvent({required this.fromUid, required this.fromName});

  final String fromUid;
  final String fromName;

  factory FriendRequestEvent.fromJson(Map<String, dynamic> j) =>
      FriendRequestEvent(
        fromUid: readString(j['fromUid']),
        fromName: readString(j['fromName']),
      );

  @override
  String get type => ServerMessageTypes.socialFriendRequest;
}
