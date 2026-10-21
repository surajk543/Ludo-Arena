import 'events.dart';
import 'message_types.dart';
import 'models.dart';
import 'state_hash.dart';

/// Why an event was not applied.
enum IgnoreReason {
  /// `v <= local.v` — duplicate or old delta.
  duplicate,

  /// Snapshot older than the local state (`room.v < local.v`).
  staleSnapshot,

  /// Delta for a room other than the one held.
  otherRoom,

  /// Not a room snapshot or delta (wallet, chat, …).
  notRoomEvent,
}

/// Why a full snapshot must be requested (`game.request_sync`).
enum SyncReason {
  /// `v > local.v + 1`.
  gap,

  /// Applied, but the locally computed `h` differs from the server's.
  hashMismatch,

  /// A delta arrived while no room is held.
  noLocalState,

  /// The delta referenced a seat/token that does not exist locally.
  invalidDelta,
}

/// Outcome of [RoomStateReducer.reduce].
sealed class ReduceResult {
  const ReduceResult();
}

/// The event was applied; [state] is the new local state.
final class Applied extends ReduceResult {
  const Applied(this.state, this.event);

  final RoomSnapshot state;
  final ServerEvent event;

  /// True when a full snapshot replaced the state.
  bool get replaced => event is RoomSnapshotEvent;
}

/// The event was ignored; local state unchanged.
final class Ignored extends ReduceResult {
  const Ignored(this.reason);

  final IgnoreReason reason;
}

/// Local state can no longer be trusted: request a snapshot for [roomId].
/// [state] is the state to keep meanwhile (the applied state for a hash
/// mismatch; otherwise the unchanged previous state, possibly null).
final class NeedsSync extends ReduceResult {
  const NeedsSync(this.reason, {required this.roomId, this.state, this.event});

  final SyncReason reason;
  final String roomId;
  final RoomSnapshot? state;

  /// For [SyncReason.hashMismatch]: the delta that was applied anyway.
  final ServerEvent? event;
}

/// Pure implementation of websocket-protocol.md §3 (reconciliation) and §6
/// (delta application). No I/O, no clocks.
class RoomStateReducer {
  const RoomStateReducer();

  ReduceResult reduce(RoomSnapshot? local, ServerEvent event) {
    return switch (event) {
      RoomSnapshotEvent e => _snapshot(local, e),
      RoomDeltaEvent e => _delta(local, e),
      _ => const Ignored(IgnoreReason.notRoomEvent),
    };
  }

  ReduceResult _snapshot(RoomSnapshot? local, RoomSnapshotEvent e) {
    final room = e.room;
    if (local == null || local.id != room.id || room.v >= local.v) {
      return Applied(room, e);
    }
    return const Ignored(IgnoreReason.staleSnapshot);
  }

  ReduceResult _delta(RoomSnapshot? local, RoomDeltaEvent e) {
    if (local == null) {
      return NeedsSync(SyncReason.noLocalState, roomId: e.roomId);
    }
    if (e.roomId != local.id) return const Ignored(IgnoreReason.otherRoom);
    if (e.v <= local.v) return const Ignored(IgnoreReason.duplicate);
    if (e.v > local.v + 1) {
      return NeedsSync(SyncReason.gap, roomId: local.id, state: local);
    }

    final next = _apply(local, e);
    if (next == null) {
      return NeedsSync(SyncReason.invalidDelta, roomId: local.id, state: local);
    }
    final applied = next.copyWith(v: e.v, h: e.h ?? local.h);
    final h = e.h;
    if (h != null && StateHash.of(applied) != h) {
      return NeedsSync(
        SyncReason.hashMismatch,
        roomId: local.id,
        state: applied,
        event: e,
      );
    }
    return Applied(applied, e);
  }

  /// Returns null when the delta does not fit the local state.
  RoomSnapshot? _apply(RoomSnapshot s, RoomDeltaEvent e) {
    switch (e) {
      case DiceResultEvent d:
        final players = _updatePlayer(
          s.players,
          d.seat,
          (p) => p.copyWith(strikes: d.strikes),
        );
        if (players == null) return null;
        return s.copyWith(
          players: players,
          turn: s.turn.copyWith(
            dice: d.value,
            turnSeq: d.turnSeq,
            phase: d.phase,
            deadline: d.deadline,
            legal: d.legal,
            sixStreak: d.sixStreak,
          ),
        );

      case MoveAppliedEvent m:
        BoardState board;
        if (s.isSnakes) {
          final positions = [...?s.board.snakesPositions];
          if (m.seat < 0 || m.seat >= positions.length) return null;
          positions[m.seat] = m.to;
          board = s.board.withSnakesPositions(positions);
        } else {
          final tokens = [
            for (final seat in s.board.ludoTokens ?? const <List<int>>[])
              [...seat],
          ];
          if (!_validToken(tokens, m.seat, m.token)) return null;
          tokens[m.seat][m.token] = m.to;
          for (final c in m.captures) {
            if (!_validToken(tokens, c.seat, c.token)) return null;
            tokens[c.seat][c.token] = -1;
          }
          board = s.board.withLudoTokens(tokens);
        }
        return s.copyWith(
          board: board,
          turn: s.turn.copyWith(legal: const []),
        );

      case TurnChangedEvent t:
        return s.copyWith(
          turn: s.turn.copyWith(
            seat: t.seat,
            turnSeq: t.turnSeq,
            phase: t.phase,
            deadline: t.deadline,
            sixStreak: t.sixStreak,
            dice: 0,
            legal: const [],
          ),
        );

      case PlayerConnectionEvent c:
        final players = _updatePlayer(
          s.players,
          c.seat,
          (p) => p.copyWith(connected: c.connected),
        );
        return players == null ? null : s.copyWith(players: players);

      case PlayerForfeitedEvent f:
        final players = _updatePlayer(
          s.players,
          f.seat,
          (p) => p.copyWith(forfeited: true),
        );
        if (players == null) return null;
        var board = s.board;
        final ludo = s.board.ludoTokens;
        if (s.isLudo && ludo != null && f.seat >= 0 && f.seat < ludo.length) {
          final tokens = [
            for (final seat in ludo) [...seat],
          ];
          tokens[f.seat] = List<int>.filled(tokens[f.seat].length, -1);
          board = s.board.withLudoTokens(tokens);
        }
        return s.copyWith(players: players, board: board);

      case GameFinishedEvent g:
        return s.copyWith(
          status: RoomStatuses.finished,
          result: g.result,
          rematch: g.rematch,
          turn: s.turn.copyWith(phase: TurnPhases.finished),
        );

      case RoomRematchEvent r:
        return s.copyWith(rematch: r.rematch);
    }
  }

  static bool _validToken(List<List<int>> tokens, int seat, int token) =>
      seat >= 0 &&
      seat < tokens.length &&
      token >= 0 &&
      token < tokens[seat].length;

  static List<RoomPlayer>? _updatePlayer(
    List<RoomPlayer> players,
    int seat,
    RoomPlayer Function(RoomPlayer) update,
  ) {
    final index = players.indexWhere((p) => p.seat == seat);
    if (index < 0) return null;
    return [...players]..[index] = update(players[index]);
  }
}

/// Holds the current room state and applies events through
/// [RoomStateReducer].
class RoomStateStore {
  RoomStateStore({this._reducer = const RoomStateReducer()});

  final RoomStateReducer _reducer;
  RoomSnapshot? _state;

  RoomSnapshot? get state => _state;

  /// Applies [event]; updates [state] for [Applied] and for [NeedsSync] with
  /// a state (hash mismatch keeps the applied state).
  ReduceResult apply(ServerEvent event) {
    final result = _reducer.reduce(_state, event);
    switch (result) {
      case Applied(:final state):
        _state = state;
      case NeedsSync(:final state?):
        _state = state;
      case NeedsSync():
      case Ignored():
        break;
    }
    return result;
  }

  void replace(RoomSnapshot room) => _state = room;

  void clear() => _state = null;
}
