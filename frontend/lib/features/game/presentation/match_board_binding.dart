import 'package:flutter/widgets.dart';

import '../../../core/protocol/protocol.dart';
import '../../../shared/game_visuals/game_visuals.dart';
import '../application/match_event_sequencer.dart';
import 'match_feedback.dart';

/// Everything the shared match scaffold needs to render the board.
@immutable
class MatchBoardArgs {
  const MatchBoardArgs({
    required this.presented,
    required this.reducedMotion,
    this.onTokenTap,
    this.ludoBoardTheme,
    this.snakesBoardTheme,
  });

  /// The state currently presented (lags the live state during animations).
  final RoomSnapshot presented;
  final bool reducedMotion;

  /// The viewer's equipped board cosmetics (boards are a personal view; the
  /// room snapshot does not carry them).
  final String? ludoBoardTheme;
  final String? snakesBoardTheme;

  /// Non-null only while the local player may pick a legal token (Ludo).
  final ValueChanged<int>? onTokenTap;
}

/// A game's board + dice wiring for one round of one room. Created by the
/// game screen (Ludo / Snakes & Ladders) and driven by the shared
/// [MatchEventSequencer] through the [MatchAnimator] interface.
abstract class MatchBoardBinding implements MatchAnimator {
  /// The die shown in the dice dock.
  DiceController get dice;

  /// Builds the board widget (sized by its parent; keeps its own aspect).
  Widget buildBoard(BuildContext context, MatchBoardArgs args);

  /// Width / height of the board widget, so the match layout can leave the
  /// board its full width (boards are a little taller than wide).
  double get boardAspectRatio => 1;

  /// Highlights the local player's legal tokens (no-op for games without
  /// choices).
  void showLegalMoves(RoomSnapshot room);

  /// Removes any local highlight (after a pick is sent).
  void clearLegalMoves();

  void dispose();
}

/// Creates the binding for [room] (new room or new round). [selfSeat] is
/// the local player's seat (null when not seated).
typedef MatchBoardBindingFactory =
    MatchBoardBinding Function(
      RoomSnapshot room, {
      required int? selfSeat,
      required MatchFeedback feedback,
    });

/// Seat colors for a room snapshot, by seat index 0..n-1, from
/// `players[].color` with the documented mapping as fallback.
List<SeatColor> seatColorsOf(RoomSnapshot room, int seats) {
  final fallback = SeatColor.forPlayerCount(seats);
  return [
    for (var s = 0; s < seats; s++)
      SeatColor.tryFromName(room.playerAtSeat(s)?.color) ??
          (s < fallback.length ? fallback[s] : SeatColor.values[s % 4]),
  ];
}

/// Clockwise quarter turns of the board view that put [selfSeat]'s color at
/// the bottom-left corner (0 for spectators).
int boardTurnsFor(RoomSnapshot room, int? selfSeat) {
  if (selfSeat == null || selfSeat < 0) return 0;
  final seats = seatCountOf(room);
  if (selfSeat >= seats) return 0;
  return seatColorsOf(room, seats)[selfSeat].turnsToBottomLeft;
}

/// Number of seats the board arrays cover.
int seatCountOf(RoomSnapshot room) {
  var n = room.players.length;
  for (final p in room.players) {
    if (p.seat + 1 > n) n = p.seat + 1;
  }
  final tokens = room.board.ludoTokens;
  if (tokens != null && tokens.length > n) n = tokens.length;
  final squares = room.board.snakesPositions;
  if (squares != null && squares.length > n) n = squares.length;
  return n.clamp(1, 4);
}

/// Seats whose player forfeited.
Set<int> forfeitedSeatsOf(RoomSnapshot room) => {
  for (final p in room.players)
    if (p.forfeited) p.seat,
};
