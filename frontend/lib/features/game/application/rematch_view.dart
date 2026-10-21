import 'package:flutter/foundation.dart';

import '../../../core/protocol/protocol.dart';

/// One player's answer to the rematch offer.
enum RematchAnswer {
  /// Accepted (`rematch.accepted`).
  accepted,

  /// Declined (`rematch.declined`).
  declined,

  /// Eligible and has not answered yet.
  pending,

  /// Forfeited or disconnected: cannot take part (counts as declined).
  ineligible,
}

/// What the local player can do / sees in the rematch section.
enum RematchStage {
  /// No rematch offer (not finished, closed or expired).
  closed,

  /// Nobody accepted yet; the local player may request one.
  canRequest,

  /// Someone else accepted; the local player is asked to accept or decline.
  incomingRequest,

  /// The local player accepted and waits for the others.
  waitingForOthers,

  /// The local player declined.
  declined,

  /// The local player cannot take part (forfeited / spectating).
  notEligible,
}

@immutable
class RematchSeat {
  const RematchSeat({required this.player, required this.answer});

  final RoomPlayer player;
  final RematchAnswer answer;
}

/// Read model of `room.rematch` for the results screen (§8 rematch policy).
/// Pure: derived only from the server snapshot. No rematch ever starts
/// without each participant's explicit acceptance; the client never answers
/// on the user's behalf.
@immutable
class RematchView {
  const RematchView({
    required this.stage,
    required this.seats,
    required this.deadline,
    this.requester,
  });

  final RematchStage stage;

  /// Every seated player with their answer, in seat order.
  final List<RematchSeat> seats;

  /// Server unix ms (0 when unknown).
  final int deadline;

  /// For [RematchStage.incomingRequest]: the first other player who accepted.
  final RoomPlayer? requester;

  bool get isOpen =>
      stage != RematchStage.closed && stage != RematchStage.notEligible;

  /// Players that may still take part.
  Iterable<RematchSeat> get eligible =>
      seats.where((s) => s.answer != RematchAnswer.ineligible);

  int get acceptedCount =>
      seats.where((s) => s.answer == RematchAnswer.accepted).length;

  static RematchAnswer _answerOf(RoomPlayer p, RematchState r) {
    if (r.accepted.contains(p.seat)) return RematchAnswer.accepted;
    if (r.declined.contains(p.seat)) return RematchAnswer.declined;
    if (p.forfeited || !p.connected) return RematchAnswer.ineligible;
    return RematchAnswer.pending;
  }

  /// Builds the view for the local player at [selfSeat] (null = not seated).
  /// [nowMs] (server clock) closes an offer whose deadline passed.
  factory RematchView.from(RoomSnapshot room, int? selfSeat, {int? nowMs}) {
    final r = room.rematch;
    final players = [...room.players]..sort((a, b) => a.seat - b.seat);
    if (r == null || !room.isFinished) {
      return RematchView(
        stage: RematchStage.closed,
        seats: [
          for (final p in players)
            RematchSeat(player: p, answer: RematchAnswer.pending),
        ],
        deadline: 0,
      );
    }
    final seats = [
      for (final p in players) RematchSeat(player: p, answer: _answerOf(p, r)),
    ];
    final expired = nowMs != null && r.deadline > 0 && nowMs >= r.deadline;
    final mine = selfSeat == null
        ? null
        : seats.where((s) => s.player.seat == selfSeat).firstOrNull;

    RoomPlayer? requester;
    for (final seat in r.accepted) {
      if (seat == selfSeat) continue;
      requester = room.playerAtSeat(seat);
      if (requester != null) break;
    }

    final RematchStage stage;
    if (mine == null) {
      stage = RematchStage.notEligible;
    } else if (mine.answer == RematchAnswer.declined) {
      stage = RematchStage.declined;
    } else if (!r.open || expired) {
      stage = RematchStage.closed;
    } else if (mine.answer == RematchAnswer.accepted) {
      stage = RematchStage.waitingForOthers;
    } else if (mine.answer == RematchAnswer.ineligible) {
      stage = RematchStage.notEligible;
    } else if (requester != null) {
      stage = RematchStage.incomingRequest;
    } else {
      stage = RematchStage.canRequest;
    }

    return RematchView(
      stage: stage,
      seats: seats,
      deadline: r.deadline,
      requester: stage == RematchStage.incomingRequest ? requester : null,
    );
  }
}
