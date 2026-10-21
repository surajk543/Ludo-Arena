import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/features/game/application/match_event_sequencer.dart';

import 'support/play_test_support.dart';

/// Animator that records calls and lets the test finish each step.
class _ScriptedAnimator implements MatchAnimator {
  final List<String> log = [];
  final List<Completer<void>> pending = [];
  bool autoComplete = false;

  Future<void> _step(String name) {
    log.add(name);
    if (autoComplete) return Future<void>.value();
    final c = Completer<void>();
    pending.add(c);
    return c.future;
  }

  void completeNext() => pending.removeAt(0).complete();

  @override
  void snapTo(RoomSnapshot room) => log.add('snap:v${room.v}');

  @override
  void cancelAnimations() {
    log.add('cancel');
    for (final c in pending) {
      if (!c.isCompleted) c.complete();
    }
    pending.clear();
  }

  @override
  Future<void> playDice(
    DiceResultEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) => _step('dice:${event.value}');

  @override
  Future<void> playMove(
    MoveAppliedEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) => _step('move:${event.token}');

  @override
  Future<void> playTurnChange(TurnChangedEvent event, RoomSnapshot room) =>
      _step('turn:${event.seat}');

  @override
  Future<void> playOther(
    RoomDeltaEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) => _step('other:${event.type}');
}

RoomDeltaApplied _dice(RoomSnapshot prev, int v, int value) => RoomDeltaApplied(
  delta: DiceResultEvent(
    roomId: prev.id,
    v: v,
    seat: 0,
    value: value,
    turnSeq: v,
    phase: TurnPhases.awaitingMove,
  ),
  room: prev.copyWith(v: v),
  previous: prev,
);

RoomDeltaApplied _move(RoomSnapshot prev, int v, int token) => RoomDeltaApplied(
  delta: MoveAppliedEvent(
    roomId: prev.id,
    v: v,
    seat: 0,
    token: token,
    from: -1,
    to: 0,
  ),
  room: prev.copyWith(v: v),
  previous: prev,
);

RoomDeltaApplied _turn(RoomSnapshot prev, int v, int seat) => RoomDeltaApplied(
  delta: TurnChangedEvent(
    roomId: prev.id,
    v: v,
    seat: seat,
    turnSeq: v,
    phase: TurnPhases.awaitingRoll,
  ),
  room: prev.copyWith(v: v),
  previous: prev,
);

RoomSnapshotApplied _snapshot(RoomSnapshot room) => RoomSnapshotApplied(
  room: room,
  source: GameStateEvent(room: room),
);

void main() {
  final base = ludoRoom(v: 40);

  test('plays dice → move → turn strictly in order, awaiting each', () async {
    final a = _ScriptedAnimator();
    final s = MatchEventSequencer(animator: a, initial: base);
    expect(a.log, ['snap:v40']);

    s.add(_dice(base, 41, 6));
    s.add(_move(base.copyWith(v: 41), 42, 2));
    s.add(_turn(base.copyWith(v: 42), 43, 1));
    await Future<void>.delayed(Duration.zero);

    // Only the dice is playing; the move waits for it.
    expect(a.log, ['snap:v40', 'dice:6']);
    expect(s.busy.value, isTrue);
    expect(s.presented.value.v, 40);

    a.completeNext();
    await Future<void>.delayed(Duration.zero);
    expect(a.log.last, 'move:2');
    expect(s.presented.value.v, 41);

    a.completeNext();
    await Future<void>.delayed(Duration.zero);
    expect(a.log.last, 'turn:1');
    expect(s.presented.value.v, 42);

    a.completeNext();
    await Future<void>.delayed(Duration.zero);
    expect(s.presented.value.v, 43);
    expect(s.busy.value, isFalse);
    expect(a.log, ['snap:v40', 'dice:6', 'move:2', 'turn:1']);
    s.dispose();
  });

  test('a snapshot cancels the running animation, drops the queue and '
      'snaps', () async {
    final a = _ScriptedAnimator();
    final s = MatchEventSequencer(animator: a, initial: base);
    s.add(_dice(base, 41, 3));
    s.add(_move(base.copyWith(v: 41), 42, 1));
    await Future<void>.delayed(Duration.zero);
    expect(a.log.last, 'dice:3');

    final resync = ludoRoom(v: 50, turnSeat: 2);
    s.add(_snapshot(resync));
    expect(a.log.sublist(a.log.length - 2), ['cancel', 'snap:v50']);
    expect(s.presented.value.v, 50);

    await Future<void>.delayed(Duration.zero);
    // The queued move was superseded; the cancelled dice step does not
    // overwrite the newer snapshot.
    expect(a.log.where((l) => l.startsWith('move')), isEmpty);
    expect(s.presented.value.v, 50);
    expect(s.busy.value, isFalse);
    expect(s.snapshotsApplied, 1);

    // Deltas after the snapshot play normally.
    a.autoComplete = true;
    s.add(_turn(resync, 51, 3));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(a.log.last, 'turn:3');
    expect(s.presented.value.v, 51);
    s.dispose();
  });

  test('coalesces a large backlog into a single snap to the newest state', () {
    fakeAsync((async) {
      final a = _ScriptedAnimator();
      final s = MatchEventSequencer(animator: a, initial: base, maxBacklog: 3);
      var prev = base;
      // First delta starts playing; the rest pile up.
      for (var v = 41; v <= 48; v++) {
        s.add(_turn(prev, v, v % 4));
        prev = prev.copyWith(v: v);
      }
      async.flushMicrotasks();
      expect(a.log, ['snap:v40', 'turn:1']);
      a.completeNext();
      async.flushMicrotasks();
      expect(s.coalesced, 1);
      expect(a.log, contains('snap:v48'));
      expect(s.presented.value.v, 48);
      expect(s.busy.value, isFalse);
      s.dispose();
    });
  });

  test('a stuck step is cancelled after the step timeout', () {
    fakeAsync((async) {
      final a = _ScriptedAnimator();
      final s = MatchEventSequencer(
        animator: a,
        initial: base,
        stepTimeout: const Duration(seconds: 2),
      );
      s.add(_dice(base, 41, 5));
      async.flushMicrotasks();
      expect(s.busy.value, isTrue);
      async.elapse(const Duration(seconds: 3));
      expect(a.log, contains('cancel'));
      expect(s.presented.value.v, 41);
      expect(s.busy.value, isFalse);
      s.dispose();
    });
  });

  test('ignores deltas of another room and non-room events', () async {
    final a = _ScriptedAnimator()..autoComplete = true;
    final s = MatchEventSequencer(animator: a, initial: base);
    final other = ludoRoom(id: 'r_other', v: 40);
    s.add(_dice(other, 41, 2));
    s.add(
      const QuickChatReceived(
        QuickChatEvent(roomId: 'r_1', seat: 1, msg: 'gg'),
        fromSelf: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(a.log, ['snap:v40']);
    s.dispose();
  });
}
