import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/features/game/application/rematch_view.dart';

import 'support/play_test_support.dart';

RoomSnapshot _finished({RematchState? rematch, List<RoomPlayer>? players}) =>
    ludoRoom(
      status: RoomStatuses.finished,
      players: players ?? [player(0), player(1), player(2)],
      result: const RoomResult(
        winnerSeat: 1,
        placements: [1, 0, 2],
        payout: 3000,
      ),
      rematch: rematch ?? RematchState(open: true, deadline: kNowMs + 30000),
    );

void main() {
  test('nobody answered → the local player can request', () {
    final v = RematchView.from(_finished(), 0, nowMs: kNowMs);
    expect(v.stage, RematchStage.canRequest);
    expect(v.seats.map((s) => s.answer), everyElement(RematchAnswer.pending));
  });

  test('another player accepted → incoming request with accept/decline', () {
    final v = RematchView.from(
      _finished(
        rematch: RematchState(
          open: true,
          deadline: kNowMs + 30000,
          accepted: const [1],
        ),
      ),
      0,
      nowMs: kNowMs,
    );
    expect(v.stage, RematchStage.incomingRequest);
    expect(v.requester?.seat, 1);
    expect(v.acceptedCount, 1);
  });

  test('local player accepted → waiting; per-seat consent states', () {
    final v = RematchView.from(
      _finished(
        rematch: RematchState(
          open: true,
          deadline: kNowMs + 30000,
          accepted: const [0, 1],
          declined: const [2],
        ),
      ),
      0,
      nowMs: kNowMs,
    );
    expect(v.stage, RematchStage.waitingForOthers);
    expect(
      {for (final s in v.seats) s.player.seat: s.answer},
      {
        0: RematchAnswer.accepted,
        1: RematchAnswer.accepted,
        2: RematchAnswer.declined,
      },
    );
  });

  test('declined stays declined; closed or expired offers are closed', () {
    expect(
      RematchView.from(
        _finished(
          rematch: RematchState(
            open: true,
            deadline: kNowMs + 30000,
            declined: const [0],
          ),
        ),
        0,
        nowMs: kNowMs,
      ).stage,
      RematchStage.declined,
    );
    expect(
      RematchView.from(
        _finished(rematch: const RematchState(open: false)),
        0,
        nowMs: kNowMs,
      ).stage,
      RematchStage.closed,
    );
    expect(
      RematchView.from(_finished(), 0, nowMs: kNowMs + 31000).stage,
      RematchStage.closed,
      reason: 'past the server deadline',
    );
  });

  test('forfeited / disconnected players are not eligible', () {
    final v = RematchView.from(
      _finished(
        players: [
          player(0, forfeited: true),
          player(1),
          player(2, connected: false),
        ],
      ),
      0,
      nowMs: kNowMs,
    );
    expect(v.stage, RematchStage.notEligible);
    expect(v.seats[2].answer, RematchAnswer.ineligible);
    expect(v.eligible.map((s) => s.player.seat), [1]);
  });

  test('a room that is not finished has no rematch', () {
    expect(RematchView.from(ludoRoom(), 0).stage, RematchStage.closed);
  });
}
