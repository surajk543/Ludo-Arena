import 'package:flutter/foundation.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/protocol/protocol.dart';

/// The local player's result.
enum MatchOutcome { won, lost, forfeited, spectator }

/// One row of the finishing order.
@immutable
class PlacementRow {
  const PlacementRow({
    required this.place,
    required this.player,
    required this.isSelf,
    required this.isWinner,
  });

  /// 1-based finishing position (forfeited players after the finishers).
  final int place;
  final RoomPlayer player;
  final bool isSelf;
  final bool isWinner;
}

/// Read model of a finished room for the results screen. Everything comes
/// from the server snapshot (`result.placements`, `result.payout`).
@immutable
class MatchResultView {
  const MatchResultView({
    required this.rows,
    required this.outcome,
    required this.winner,
    required this.payout,
    required this.byForfeit,
    required this.noCoinMatch,
  });

  final List<PlacementRow> rows;
  final MatchOutcome outcome;
  final RoomPlayer? winner;

  /// Coins paid to the winner by the server (0 when the match pays none).
  final int payout;

  /// The game ended because the others forfeited.
  final bool byForfeit;

  /// The match pays no coins at all (the server's pot is empty, e.g.
  /// practice): nobody wins coins, not only the losers.
  final bool noCoinMatch;

  bool get selfWon => outcome == MatchOutcome.won;

  /// Coins the local player received from this match, as confirmed by the
  /// server result (never computed on the client).
  int get selfPayout => selfWon ? payout : 0;

  factory MatchResultView.from(RoomSnapshot room, String? selfUid) {
    final result = room.result;
    final self = room.playerByUid(selfUid);
    final winnerSeat = result?.winnerSeat ?? -1;
    final order = <int>[...?result?.placements];
    // Anyone missing from the placements (e.g. forfeited) goes last, in seat
    // order, so every seated player is listed exactly once.
    final rest = [...room.players]..sort((a, b) => a.seat - b.seat);
    for (final p in rest) {
      if (!order.contains(p.seat)) order.add(p.seat);
    }
    final rows = <PlacementRow>[];
    for (final seat in order) {
      final p = room.playerAtSeat(seat);
      if (p == null) continue;
      rows.add(
        PlacementRow(
          place: rows.length + 1,
          player: p,
          isSelf: p.uid == selfUid,
          isWinner: seat == winnerSeat,
        ),
      );
    }
    final MatchOutcome outcome;
    if (self == null) {
      outcome = MatchOutcome.spectator;
    } else if (self.seat == winnerSeat) {
      outcome = MatchOutcome.won;
    } else if (self.forfeited) {
      outcome = MatchOutcome.forfeited;
    } else {
      outcome = MatchOutcome.lost;
    }
    return MatchResultView(
      rows: rows,
      outcome: outcome,
      winner: room.playerAtSeat(winnerSeat),
      payout: result?.payout ?? 0,
      byForfeit: result?.reason == 'forfeit',
      // The server's pot decides: bots pay the entry fee like people, so a
      // match only pays no coins when nobody paid (practice).
      noCoinMatch: room.pot <= 0,
    );
  }
}

/// Server-confirmed rewards that arrive after `game.finished`.
@immutable
class MatchRewards {
  const MatchRewards({
    this.payout,
    this.progression,
    this.progressionTimedOut = false,
  });

  /// `wallet.updated` with reason `payout` (winner only).
  final WalletUpdatedEvent? payout;

  /// `progression.updated` for this match (may arrive late or never).
  final ProgressionUpdatedEvent? progression;

  /// No `progression.updated` arrived within the grace period.
  final bool progressionTimedOut;

  MatchRewards copyWith({
    WalletUpdatedEvent? payout,
    ProgressionUpdatedEvent? progression,
    bool? progressionTimedOut,
  }) => MatchRewards(
    payout: payout ?? this.payout,
    progression: progression ?? this.progression,
    progressionTimedOut: progressionTimedOut ?? this.progressionTimedOut,
  );

  /// Applies a server account event. Only a payout wallet update and the
  /// first progression update are kept.
  MatchRewards apply(Object event) => switch (event) {
    final WalletUpdatedEvent w when w.reason == 'payout' => copyWith(payout: w),
    final ProgressionUpdatedEvent p when progression == null => copyWith(
      progression: p,
    ),
    _ => this,
  };
}

/// Non-identifying analytics description of [room] for the local player
/// (no codes, names or ids; [AnalyticsGameContext.dedupeKey] stays local).
AnalyticsGameContext matchAnalyticsContext(
  RoomSnapshot room,
  String? selfUid,
) => AnalyticsGameContext(
  gameType: AnalyticsGameType.parse(room.game),
  matchType: AnalyticsMatchType.parse(room.mode),
  seatCount: room.players.length,
  opponentMix: OpponentMix.forRoom(
    mode: room.mode,
    opponentIsComputer: room.players
        .where((p) => p.uid != selfUid)
        .map((p) => room.isComputerSeat(p.seat)),
  ),
  variant: room.isLudo ? room.variant : null,
  dedupeKey: '${room.id}#${room.round}',
);
