import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/active_room_controller.dart';

/// Presentation port implemented by each game board binding (Ludo, Snakes &
/// Ladders). The [MatchEventSequencer] calls it strictly in server order and
/// awaits every returned future before presenting the next event.
///
/// Implementations only animate server-confirmed state; they never decide
/// rules or outcomes.
abstract interface class MatchAnimator {
  /// Jumps (no animation) to [room]: board positions, turn emphasis, dice
  /// face, forfeited seats and local interaction.
  void snapTo(RoomSnapshot room);

  /// `game.dice_result`: tumble and settle on the server value.
  Future<void> playDice(
    DiceResultEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  );

  /// `game.move_applied`: token movement incl. captures, home, snakes and
  /// ladders.
  Future<void> playMove(
    MoveAppliedEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  );

  /// `game.turn_changed`.
  Future<void> playTurnChange(TurnChangedEvent event, RoomSnapshot room);

  /// Any other delta (connection, forfeit, finish, rematch).
  Future<void> playOther(
    RoomDeltaEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  );

  /// Stops every running animation so its future completes now (board
  /// `cancelAndSnap`, dice `cancel`).
  void cancelAnimations();
}

/// Plays the ActiveRoomController's ordered, applied room events one at a
/// time:
///
/// dice tumble → settle on the server value → move animation → turn change.
///
/// - Every step is awaited before the next one starts.
/// - A full snapshot ([RoomSnapshotApplied]) cancels the running animation,
///   drops everything queued before it and snaps to the snapshot.
/// - When more than [maxBacklog] deltas are waiting (e.g. after the app was
///   paused), the skippable presentation work is coalesced: the board snaps
///   to the newest state instead of replaying each animation.
/// - A step that does not finish within [stepTimeout] (e.g. animations
///   paused while the route is covered) is cancelled and snapped.
///
/// [presented] is the room state currently shown on screen; it lags the
/// live controller state while animations play. [busy] is true while
/// anything is playing or queued (inputs must be disabled meanwhile).
class MatchEventSequencer {
  MatchEventSequencer({
    required this._animator,
    required RoomSnapshot initial,
    this.maxBacklog = 6,
    this.stepTimeout = const Duration(seconds: 8),
  }) : presented = ValueNotifier<RoomSnapshot>(initial) {
    _animator.snapTo(initial);
  }

  final MatchAnimator _animator;

  /// Above this many queued deltas, presentation snaps to the newest state.
  final int maxBacklog;

  /// Upper bound for one animation step.
  final Duration stepTimeout;

  /// The state currently presented on screen.
  final ValueNotifier<RoomSnapshot> presented;

  final ValueNotifier<bool> _busy = ValueNotifier<bool>(false);

  /// True while an animation plays or events are queued.
  ValueListenable<bool> get busy => _busy;

  final Queue<RoomDeltaApplied> _queue = Queue<RoomDeltaApplied>();
  bool _running = false;
  bool _disposed = false;
  int _epoch = 0;

  /// Number of snapshots applied (tests / diagnostics).
  int snapshotsApplied = 0;

  /// Number of times a backlog was coalesced into one snap.
  int coalesced = 0;

  bool get isDisposed => _disposed;

  /// Feeds one event from `ActiveRoomController.events`. Chat, matchmaking
  /// and clear events are ignored here.
  void add(RoomEvent event) {
    if (_disposed) return;
    switch (event) {
      case RoomSnapshotApplied(:final room):
        _snap(room);
      case RoomDeltaApplied():
        if (event.room.id != presented.value.id) return;
        _queue.add(event);
        _setBusy(true);
        unawaited(_pump());
      default:
        break;
    }
  }

  /// Immediately presents [room] (full snapshot / resync).
  void _snap(RoomSnapshot room) {
    _epoch++;
    _queue.clear();
    _animator.cancelAnimations();
    _animator.snapTo(room);
    snapshotsApplied++;
    presented.value = room;
    if (!_running) _setBusy(false);
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        if (_queue.length > maxBacklog) {
          final latest = _queue.last.room;
          _queue.clear();
          _epoch++;
          coalesced++;
          _animator.cancelAnimations();
          _animator.snapTo(latest);
          presented.value = latest;
          continue;
        }
        final event = _queue.removeFirst();
        final epoch = _epoch;
        await _play(event);
        if (_disposed) return;
        // A snapshot arrived while this step played: it already presented a
        // newer state.
        if (epoch != _epoch) continue;
        presented.value = event.room;
      }
    } finally {
      _running = false;
      if (!_disposed) _setBusy(_queue.isNotEmpty);
      if (!_disposed && _queue.isNotEmpty) unawaited(_pump());
    }
  }

  Future<void> _play(RoomDeltaApplied e) async {
    final Future<void> step = switch (e.delta) {
      final DiceResultEvent d => _animator.playDice(d, e.room, e.previous),
      final MoveAppliedEvent m => _animator.playMove(m, e.room, e.previous),
      final TurnChangedEvent t => _animator.playTurnChange(t, e.room),
      final RoomDeltaEvent other => _animator.playOther(
        other,
        e.room,
        e.previous,
      ),
    };
    try {
      await step.timeout(
        stepTimeout,
        onTimeout: () {
          _animator.cancelAnimations();
        },
      );
    } catch (error, stack) {
      // Presentation must never stall the match: snap past a failed step.
      debugPrint('match animation failed: $error\n$stack');
      _animator.cancelAnimations();
    }
  }

  void _setBusy(bool value) {
    if (_busy.value != value) _busy.value = value;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    _animator.cancelAnimations();
    presented.dispose();
    _busy.dispose();
  }
}
