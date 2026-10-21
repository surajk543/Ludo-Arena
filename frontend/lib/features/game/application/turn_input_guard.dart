import '../../../core/protocol/protocol.dart';

/// Duplicate-tap protection for turn actions.
///
/// The server stays authoritative (stale `turnSeq` actions are rejected),
/// but the UI must never send a second roll/move for the same `turnSeq`, nor
/// act while the presented board is still catching up with the live state.
///
/// A roll/move is allowed only when:
/// - it is the local player's turn in the **live** state and the phase
///   matches;
/// - the presented (animated) state has caught up (`turnSeq` equal) and no
///   animation is playing or queued;
/// - no roll/move command is in flight;
/// - nothing was already sent for this `turnSeq`.
class TurnInputGuard {
  int? _rollSentFor;
  int? _moveSentFor;

  /// `turnSeq` the last roll was sent for (null after [reset]).
  int? get rollSentFor => _rollSentFor;
  int? get moveSentFor => _moveSentFor;

  static bool _caughtUp(RoomSnapshot live, RoomSnapshot presented) =>
      presented.id == live.id &&
      presented.round == live.round &&
      presented.turn.turnSeq == live.turn.turnSeq;

  /// The player must choose a token: awaiting a move with ≥ 2 legal tokens.
  static bool requiresChoice(RoomSnapshot room) =>
      room.turn.awaitingMove && room.turn.legal.length >= 2;

  static bool _myTurn(RoomSnapshot live, int? selfSeat) =>
      selfSeat != null && live.isPlaying && live.turn.seat == selfSeat;

  bool canRoll({
    required RoomSnapshot? live,
    required RoomSnapshot? presented,
    required int? selfSeat,
    required bool busy,
    bool commandInFlight = false,
  }) {
    if (live == null || presented == null) return false;
    if (busy || commandInFlight) return false;
    if (!_myTurn(live, selfSeat) || !live.turn.awaitingRoll) return false;
    if (!_caughtUp(live, presented)) return false;
    return _rollSentFor != live.turn.turnSeq;
  }

  bool canMove({
    required RoomSnapshot? live,
    required RoomSnapshot? presented,
    required int? selfSeat,
    required bool busy,
    required int token,
    bool commandInFlight = false,
  }) {
    if (live == null || presented == null) return false;
    if (busy || commandInFlight) return false;
    if (!_myTurn(live, selfSeat) || !live.turn.awaitingMove) return false;
    // Exactly one legal token: the server applies it by itself (a
    // `game.move_applied` follows). Sending `game.make_move` would only earn
    // `stale_state` / `rate_limited`, so the user is never asked to pick.
    if (!requiresChoice(live)) return false;
    if (!live.turn.legal.contains(token)) return false;
    if (!_caughtUp(live, presented)) return false;
    return _moveSentFor != live.turn.turnSeq;
  }

  /// Whether the local player may pick a token right now (any legal one).
  bool canPickToken({
    required RoomSnapshot? live,
    required RoomSnapshot? presented,
    required int? selfSeat,
    required bool busy,
    bool commandInFlight = false,
  }) {
    if (live == null) return false;
    return live.turn.legal.any(
      (t) => canMove(
        live: live,
        presented: presented,
        selfSeat: selfSeat,
        busy: busy,
        token: t,
        commandInFlight: commandInFlight,
      ),
    );
  }

  void markRollSent(int turnSeq) => _rollSentFor = turnSeq;
  void markMoveSent(int turnSeq) => _moveSentFor = turnSeq;

  /// The command failed without changing the turn: allow a new attempt.
  void rollFailed(int turnSeq) {
    if (_rollSentFor == turnSeq) _rollSentFor = null;
  }

  void moveFailed(int turnSeq) {
    if (_moveSentFor == turnSeq) _moveSentFor = null;
  }

  /// New round / new room: forget everything.
  void reset() {
    _rollSentFor = null;
    _moveSentFor = null;
  }
}
