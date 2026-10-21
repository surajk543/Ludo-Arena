import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/analytics_providers.dart';
import '../protocol/protocol.dart';
import '../settings/app_settings.dart';
import '../telemetry/telemetry_reporter.dart';
import '../time/server_clock.dart';
import 'realtime_providers.dart';

const Object _unset = Object();

/// Typed view of the user's current room / matchmaking session.
@immutable
class ActiveRoomState {
  const ActiveRoomState({
    this.room,
    this.selfUid,
    this.matchmaking,
    this.syncing = false,
    this.lastErrorCode,
    this.rollInFlight = false,
    this.moveInFlight = false,
  });

  /// Server-confirmed room state (null when not in a room).
  final RoomSnapshot? room;

  /// The user's public id from `connection.ready`.
  final String? selfUid;

  /// Last `matchmaking.status` while searching (cleared when the game
  /// starts, on cancel, or on timeout).
  final MatchmakingStatusEvent? matchmaking;

  /// A `game.request_sync` is in flight; local state may be stale.
  final bool syncing;

  /// Last error code from a failed command or an unsolicited `error`.
  final String? lastErrorCode;

  /// A `game.roll_dice` / `game.make_move` is awaiting its reply.
  final bool rollInFlight;
  final bool moveInFlight;

  bool get hasRoom => room != null;

  RoomPlayer? get selfPlayer => room?.playerByUid(selfUid);

  /// The user's seat in [room], if seated.
  int? get selfSeat => selfPlayer?.seat;

  bool get isSearching => matchmaking?.isSearching ?? false;

  bool get isHost {
    final r = room;
    final seat = selfSeat;
    return r != null && seat != null && r.hostSeat == seat;
  }

  bool get isMyTurn {
    final r = room;
    final seat = selfSeat;
    return r != null && seat != null && r.isPlaying && r.turn.seat == seat;
  }

  /// UI hint: the roll button may be enabled (the server stays authoritative).
  bool get canRoll =>
      isMyTurn && room!.turn.awaitingRoll && !rollInFlight && !moveInFlight;

  /// UI hint: tokens in `room.turn.legal` may be tapped.
  /// The player chooses a token only when there are at least two legal
  /// tokens; with exactly one the server applies the move itself.
  bool get canMove =>
      isMyTurn &&
      room!.turn.awaitingMove &&
      room!.turn.legal.length >= 2 &&
      !moveInFlight;

  ActiveRoomState copyWith({
    Object? room = _unset,
    Object? selfUid = _unset,
    Object? matchmaking = _unset,
    bool? syncing,
    Object? lastErrorCode = _unset,
    bool? rollInFlight,
    bool? moveInFlight,
  }) => ActiveRoomState(
    room: identical(room, _unset) ? this.room : room as RoomSnapshot?,
    selfUid: identical(selfUid, _unset) ? this.selfUid : selfUid as String?,
    matchmaking: identical(matchmaking, _unset)
        ? this.matchmaking
        : matchmaking as MatchmakingStatusEvent?,
    syncing: syncing ?? this.syncing,
    lastErrorCode: identical(lastErrorCode, _unset)
        ? this.lastErrorCode
        : lastErrorCode as String?,
    rollInFlight: rollInFlight ?? this.rollInFlight,
    moveInFlight: moveInFlight ?? this.moveInFlight,
  );
}

// ---------------------------------------------------------------- events

/// Ordered, applied room events for animation sequencing. Subscribe with
/// `ref.read(activeRoomControllerProvider.notifier).events.listen(...)`.
sealed class RoomEvent {
  const RoomEvent();
}

/// A full snapshot replaced local state (join, game start, resync, rematch).
/// Screens should jump (not animate) to [room].
final class RoomSnapshotApplied extends RoomEvent {
  const RoomSnapshotApplied({
    required this.room,
    required this.source,
    this.previous,
  });

  final RoomSnapshot room;

  /// `RoomUpdatedEvent` (has `reason`), `GameStartedEvent`, `GameStateEvent`.
  final RoomSnapshotEvent source;
  final RoomSnapshot? previous;

  String? get reason => switch (source) {
    RoomUpdatedEvent(:final reason) => reason,
    _ => null,
  };
}

/// One versioned delta was applied. Switch on [delta]
/// (`DiceResultEvent`, `MoveAppliedEvent`, `TurnChangedEvent`,
/// `PlayerConnectionEvent`, `PlayerForfeitedEvent`, `GameFinishedEvent`,
/// `RoomRematchEvent`) to animate from [previous] to [room].
final class RoomDeltaApplied extends RoomEvent {
  const RoomDeltaApplied({
    required this.delta,
    required this.room,
    required this.previous,
    this.verified = true,
  });

  final RoomDeltaEvent delta;
  final RoomSnapshot room;
  final RoomSnapshot previous;

  /// False when the state hash did not match: a snapshot follows shortly.
  final bool verified;
}

/// A quick-chat bubble (suppressed when Settings → quick chat is muted,
/// except the user's own).
final class QuickChatReceived extends RoomEvent {
  const QuickChatReceived(this.chat, {required this.fromSelf});

  final QuickChatEvent chat;
  final bool fromSelf;
}

/// An emote (same muting rule as quick chat).
final class EmoteReceived extends RoomEvent {
  const EmoteReceived(this.emote, {required this.fromSelf});

  final EmoteEvent emote;
  final bool fromSelf;
}

/// `matchmaking.status` changed.
final class MatchmakingUpdated extends RoomEvent {
  const MatchmakingUpdated(this.status);

  final MatchmakingStatusEvent status;
}

/// An unsolicited server `error` (e.g. `bots_unavailable`).
final class RoomErrorReceived extends RoomEvent {
  const RoomErrorReceived(this.error);

  final ServerErrorEvent error;
}

enum RoomClearReason {
  /// The room was closed by the server.
  closed,

  /// The user left (or is no longer seated).
  left,

  /// Matchmaking was cancelled or timed out.
  matchmakingEnded,

  /// A sync answered `not_in_room` / `room_not_found`.
  notInRoom,
}

/// The user is no longer in a room; screens should navigate away.
final class RoomCleared extends RoomEvent {
  const RoomCleared({required this.reason, this.roomId});

  final RoomClearReason reason;
  final String? roomId;
}

// ------------------------------------------------------------ controller

/// Owns the current room state (via [RoomStateStore]), applies server
/// events, resynchronises on gaps / hash mismatches / reconnects, and
/// exposes the room commands.
///
/// Every command throws [RealtimeCommandException] (code = protocol error
/// code, `timeout`, `not_connected`, or `not_in_room` when no room is held).
class ActiveRoomController extends Notifier<ActiveRoomState> {
  late RealtimeConnection _connection;
  final RoomStateStore _store = RoomStateStore();
  StreamSubscription<ServerMessage>? _sub;
  StreamController<RoomEvent>? _eventsController;
  bool _syncInFlight = false;

  final _started = <String>{};
  final _ended = <String>{};
  final _startedAt = <String, DateTime>{};
  ({String game, int capacity})? _lastMatchmaking;

  static const _maxKeys = 64;

  /// Ordered applied room events (see [RoomEvent]).
  Stream<RoomEvent> get events =>
      (_eventsController ??= StreamController<RoomEvent>.broadcast()).stream;

  @override
  ActiveRoomState build() {
    _connection = ref.watch(realtimeConnectionProvider);
    _eventsController ??= StreamController<RoomEvent>.broadcast();
    _sub = _connection.events.listen(_onMessage);
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
      _eventsController?.close();
      _eventsController = null;
      _store.clear();
      _syncInFlight = false;
    });
    return ActiveRoomState(selfUid: _connection.lastReady?.uid);
  }

  // ------------------------------------------------------------ inbound

  void _onMessage(ServerMessage m) {
    if (!ref.mounted) return;
    final e = m.event;
    switch (e) {
      case ConnectionReadyEvent():
        _syncInFlight = false;
        state = state.copyWith(selfUid: e.uid, syncing: false);
        final roomId = state.room?.id ?? e.activeRoomId;
        if (roomId != null) unawaited(requestSync(roomId: roomId));
      case LocalResyncRequired():
        if (state.room != null) unawaited(requestSync());
      case MatchmakingStatusEvent():
        _onMatchmakingStatus(e);
      case RoomSnapshotEvent():
        _applyRoomEvent(e);
      case RoomDeltaEvent():
        _applyRoomEvent(e);
      case QuickChatEvent():
        if (e.roomId != state.room?.id) return;
        final self = e.seat == state.selfSeat;
        if (!self && _muted) return;
        _emit(QuickChatReceived(e, fromSelf: self));
      case EmoteEvent():
        if (e.roomId != state.room?.id) return;
        final self = e.seat == state.selfSeat;
        if (!self && _muted) return;
        _emit(EmoteReceived(e, fromSelf: self));
      case ServerErrorEvent():
        if (m.replyTo != null) return; // handled by the command's future
        state = state.copyWith(lastErrorCode: e.code);
        _emit(RoomErrorReceived(e));
      default:
        break;
    }
  }

  bool get _muted {
    try {
      return ref.read(settingsControllerProvider).quickChatMuted;
    } catch (_) {
      return false;
    }
  }

  void _onMatchmakingStatus(MatchmakingStatusEvent e) {
    _emit(MatchmakingUpdated(e));
    if (e.isSearching) {
      state = state.copyWith(matchmaking: e);
      return;
    }
    state = state.copyWith(matchmaking: null);
    final room = state.room;
    if (room != null && room.isLobby && room.mode == RoomModes.public) {
      _clear(RoomClearReason.matchmakingEnded, room.id);
    }
  }

  void _applyRoomEvent(ServerEvent e) {
    final previous = _store.state;
    final result = _store.apply(e);
    switch (result) {
      case Applied(:final state, :final event):
        _afterApplied(previous, state, event, verified: true);
      case NeedsSync(:final reason, :final roomId, :final state, :final event):
        if (reason == SyncReason.hashMismatch) {
          _telemetry(TelemetryKind.hashMismatch);
          if (state != null && previous != null && event is RoomDeltaEvent) {
            _afterApplied(previous, state, event, verified: false);
          }
        }
        unawaited(requestSync(roomId: roomId));
      case Ignored():
        break;
    }
  }

  void _afterApplied(
    RoomSnapshot? previous,
    RoomSnapshot room,
    ServerEvent event, {
    required bool verified,
  }) {
    final selfUid = state.selfUid;
    if (event is RoomSnapshotEvent &&
        selfUid != null &&
        room.playerByUid(selfUid) == null) {
      // A snapshot that no longer seats the user: we are out of this room.
      _clear(RoomClearReason.left, room.id);
      return;
    }

    final wasSearching = state.isSearching;
    state = state.copyWith(
      room: room,
      syncing: event is GameStateEvent ? false : state.syncing,
      matchmaking: room.isLobby ? state.matchmaking : null,
    );

    if (event is RoomSnapshotEvent) {
      _emit(RoomSnapshotApplied(room: room, source: event, previous: previous));
    } else if (event is RoomDeltaEvent && previous != null) {
      _emit(
        RoomDeltaApplied(
          delta: event,
          room: room,
          previous: previous,
          verified: verified,
        ),
      );
    }

    _trackAnalytics(room, wasSearching: wasSearching);

    if (room.isClosed) _clear(RoomClearReason.closed, room.id);
  }

  void _clear(RoomClearReason reason, String? roomId) {
    _store.clear();
    state = state.copyWith(
      room: null,
      syncing: false,
      rollInFlight: false,
      moveInFlight: false,
      matchmaking: reason == RoomClearReason.matchmakingEnded
          ? null
          : state.matchmaking,
    );
    _emit(RoomCleared(reason: reason, roomId: roomId));
  }

  void _emit(RoomEvent e) {
    final c = _eventsController;
    if (c != null && !c.isClosed) c.add(e);
  }

  void _telemetry(TelemetryKind kind) {
    try {
      ref.read(telemetryReporterProvider).record(kind);
    } catch (_) {}
  }

  // ---------------------------------------------------------- analytics

  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  DateTime _now() => ref.read(clockProvider)();

  AnalyticsGameContext _context(RoomSnapshot room) => AnalyticsGameContext(
    gameType: AnalyticsGameType.parse(room.game),
    matchType: AnalyticsMatchType.parse(room.mode),
    seatCount: room.players.length,
    opponentMix: OpponentMix.forRoom(
      mode: room.mode,
      opponentIsComputer: room.players
          .where((p) => p.uid != state.selfUid)
          .map((p) => room.isComputerSeat(p.seat)),
    ),
    variant: room.isLudo ? room.variant : null,
    dedupeKey: '${room.id}#${room.round}',
  );

  void _remember(Set<String> set, String key) {
    set.add(key);
    while (set.length > _maxKeys) {
      final oldest = set.first;
      set.remove(oldest);
      _startedAt.remove(oldest);
    }
  }

  void _trackAnalytics(RoomSnapshot room, {required bool wasSearching}) {
    try {
      final key = '${room.id}#${room.round}';
      if (room.isPlaying && !_started.contains(key)) {
        _remember(_started, key);
        _startedAt[key] = _now();
        _analytics.gameStarted(_context(room));
        if (wasSearching && room.mode == RoomModes.public) {
          _analytics.matchmakingSucceeded(
            AnalyticsGameType.parse(room.game),
            room.capacity,
          );
        }
      }
      if (room.isFinished && _started.contains(key) && !_ended.contains(key)) {
        final self = room.playerByUid(state.selfUid);
        if (self == null) return;
        _remember(_ended, key);
        final outcome = self.forfeited
            ? GameOutcome.forfeit
            : (room.result?.winnerSeat == self.seat
                  ? GameOutcome.win
                  : GameOutcome.loss);
        final started = _startedAt[key];
        _analytics.gameCompleted(
          _context(room),
          outcome: outcome,
          duration: started == null
              ? Duration.zero
              : _now().difference(started),
        );
      }
    } catch (e) {
      debugPrint('room analytics failed: $e');
    }
  }

  // ----------------------------------------------------------- commands

  Future<ServerMessage> _send(String type, Map<String, dynamic> payload) async {
    try {
      return await _connection.send(type, payload);
    } on RealtimeCommandException catch (e) {
      if (ref.mounted) state = state.copyWith(lastErrorCode: e.code);
      rethrow;
    }
  }

  String _roomId() {
    final id = state.room?.id;
    if (id == null) throw const RealtimeCommandException('not_in_room');
    return id;
  }

  /// Clears [ActiveRoomState.lastErrorCode] after the UI showed it.
  void clearError() {
    if (state.lastErrorCode != null) {
      state = state.copyWith(lastErrorCode: null);
    }
  }

  /// `matchmaking.join` — seats the user in an open public lobby.
  Future<void> joinMatchmaking({
    required String game,
    String variant = GameVariants.classic,
    required int capacity,
  }) async {
    await _send(ClientMessageTypes.matchmakingJoin, {
      'game': game,
      'variant': variant,
      'capacity': capacity,
    });
    _lastMatchmaking = (game: game, capacity: capacity);
    _safe(
      () => _analytics.matchmakingStarted(
        AnalyticsGameType.parse(game),
        capacity,
      ),
    );
  }

  /// `matchmaking.cancel` (only while the lobby has not started).
  Future<void> cancelMatchmaking() async {
    await _send(ClientMessageTypes.matchmakingCancel, const {});
    final last = _lastMatchmaking;
    if (last != null) {
      _safe(
        () => _analytics.matchmakingCancelled(
          AnalyticsGameType.parse(last.game),
          last.capacity,
        ),
      );
    }
    if (!ref.mounted) return;
    final room = state.room;
    if (room != null && room.isLobby) {
      _clear(RoomClearReason.matchmakingEnded, room.id);
    } else {
      state = state.copyWith(matchmaking: null);
    }
  }

  /// `room.create` — private room; the user is host (seat 0). Resolves with
  /// the created room (its `code` can be shared).
  Future<RoomSnapshot?> createRoom({
    required String game,
    String variant = GameVariants.classic,
    required int capacity,
  }) async {
    final reply = await _send(ClientMessageTypes.roomCreate, {
      'game': game,
      'variant': variant,
      'capacity': capacity,
    });
    _safe(
      () => _analytics.privateRoomCreated(
        AnalyticsGameType.parse(game),
        capacity,
      ),
    );
    return _replyRoom(reply);
  }

  /// `room.join` with a private room code.
  Future<RoomSnapshot?> joinRoom(String code) async {
    try {
      final reply = await _send(ClientMessageTypes.roomJoin, {
        'code': code.trim().toUpperCase(),
      });
      final room = _replyRoom(reply);
      _safe(
        () => _analytics.privateRoomJoined(
          AnalyticsGameType.parse(room?.game ?? GameIds.ludo),
        ),
      );
      return room;
    } on RealtimeCommandException catch (e) {
      _safe(() => _analytics.privateRoomJoinFailed(e.code));
      rethrow;
    }
  }

  RoomSnapshot? _replyRoom(ServerMessage reply) => switch (reply.event) {
    RoomSnapshotEvent(:final room) => room,
    _ => state.room,
  };

  /// `room.leave` — lobby: frees the seat; playing: forfeit; finished:
  /// leaves. The local room is cleared either way.
  Future<void> leaveRoom() async {
    final room = state.room;
    if (room == null) return;
    final key = '${room.id}#${room.round}';
    if (room.isPlaying && !_ended.contains(key)) {
      _remember(_ended, key);
      final started = _startedAt[key];
      _safe(
        () => _analytics.gameAbandoned(
          _context(room),
          duration: started == null
              ? Duration.zero
              : _now().difference(started),
        ),
      );
    }
    try {
      await _send(ClientMessageTypes.roomLeave, {'roomId': room.id});
    } on RealtimeCommandException catch (e) {
      if (e.code != 'not_in_room' &&
          e.code != 'room_not_found' &&
          e.code != 'room_closed') {
        rethrow;
      }
    }
    if (ref.mounted && state.room?.id == room.id) {
      _clear(RoomClearReason.left, room.id);
    }
  }

  /// `practice.start` — the user + [bots] (1–3) computer players.
  Future<RoomSnapshot?> startPractice({
    required String game,
    String variant = GameVariants.classic,
    required int bots,
  }) async {
    final reply = await _send(ClientMessageTypes.practiceStart, {
      'game': game,
      'variant': variant,
      'bots': bots.clamp(1, 3),
    });
    return _replyRoom(reply);
  }

  /// `room.allow_bots` (private host, lobby).
  Future<void> allowBots(bool allow) async {
    await _send(ClientMessageTypes.roomAllowBots, {
      'roomId': _roomId(),
      'allow': allow,
    });
  }

  /// `room.add_bot` (private host; requires allowBots).
  Future<void> addBot() async {
    await _send(ClientMessageTypes.roomAddBot, {'roomId': _roomId()});
  }

  /// `room.remove_bot` (private host, lobby).
  Future<void> removeBot(int seat) async {
    await _send(ClientMessageTypes.roomRemoveBot, {
      'roomId': _roomId(),
      'seat': seat,
    });
  }

  /// `room.invite` — sends `social.invite` to an online friend.
  Future<void> invite(String friendUid) async {
    await _send(ClientMessageTypes.roomInvite, {
      'roomId': _roomId(),
      'friendUid': friendUid,
    });
  }

  /// `game.start` (private host; ≥ 2 connected players).
  Future<void> startGame() async {
    await _send(ClientMessageTypes.gameStart, {'roomId': _roomId()});
  }

  /// `game.roll_dice` with the current `turnSeq`. Returns false (without
  /// sending) when a roll or move is already in flight.
  Future<bool> rollDice() async {
    final room = state.room;
    if (room == null) throw const RealtimeCommandException('not_in_room');
    if (state.rollInFlight || state.moveInFlight) return false;
    state = state.copyWith(rollInFlight: true);
    try {
      await _send(ClientMessageTypes.gameRollDice, {
        'roomId': room.id,
        'turnSeq': room.turn.turnSeq,
      });
      return true;
    } finally {
      if (ref.mounted) state = state.copyWith(rollInFlight: false);
    }
  }

  /// `game.make_move` (Ludo) for [token] with the current `turnSeq`. Returns
  /// false (without sending) when a roll or move is already in flight.
  Future<bool> makeMove(int token) async {
    final room = state.room;
    if (room == null) throw const RealtimeCommandException('not_in_room');
    if (state.moveInFlight || state.rollInFlight) return false;
    state = state.copyWith(moveInFlight: true);
    try {
      await _send(ClientMessageTypes.gameMakeMove, {
        'roomId': room.id,
        'turnSeq': room.turn.turnSeq,
        'token': token,
      });
      return true;
    } finally {
      if (ref.mounted) state = state.copyWith(moveInFlight: false);
    }
  }

  /// `game.request_sync` (coalesced: one in flight). Without [roomId] the
  /// server uses the user's active room. Never throws.
  Future<void> requestSync({String? roomId}) async {
    if (_syncInFlight) return;
    _syncInFlight = true;
    if (ref.mounted) state = state.copyWith(syncing: true);
    try {
      await _connection.send(ClientMessageTypes.gameRequestSync, {
        'roomId': ?roomId,
      });
    } on RealtimeCommandException catch (e) {
      if (!ref.mounted) return;
      if (e.code == 'not_in_room' || e.code == 'room_not_found') {
        if (state.room != null) {
          _clear(RoomClearReason.notInRoom, state.room!.id);
        }
      }
      // not_connected / timeout: the next connection.ready resyncs.
    } finally {
      _syncInFlight = false;
      if (ref.mounted && state.syncing) state = state.copyWith(syncing: false);
    }
  }

  /// `game.rematch` — accept or decline while `rematch.open`.
  Future<void> rematch({required bool accept}) async {
    final room = state.room;
    if (room == null) throw const RealtimeCommandException('not_in_room');
    final othersAccepted = room.rematch?.accepted ?? const <int>[];
    await _send(ClientMessageTypes.gameRematch, {
      'roomId': room.id,
      'accept': accept,
    });
    if (!accept) return;
    _safe(() {
      final ctx = _context(room);
      if (othersAccepted.isEmpty) {
        _analytics.rematchRequested(ctx);
      } else {
        _analytics.rematchAccepted(ctx);
      }
    });
  }

  /// `chat.quick` with a predefined id ([QuickChatIds]).
  Future<void> sendQuickChat(String msgId) async {
    await _send(ClientMessageTypes.chatQuick, {
      'roomId': _roomId(),
      'msg': msgId,
    });
  }

  /// `chat.emote` with an owned emote id (`emote_wave`, …).
  Future<void> sendEmote(String emoteId) async {
    await _send(ClientMessageTypes.chatEmote, {
      'roomId': _roomId(),
      'emote': emoteId,
    });
  }

  void _safe(void Function() f) {
    try {
      f();
    } catch (e) {
      debugPrint('room analytics failed: $e');
    }
  }
}
