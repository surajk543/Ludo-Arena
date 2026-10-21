import 'package:flutter/widgets.dart';

import '../../../../core/protocol/protocol.dart';
import '../../../../shared/game_visuals/game_visuals.dart';
import '../../../game/presentation/match_board_binding.dart';
import '../../../game/presentation/match_feedback.dart';
import '../../../game/presentation/match_view.dart';
import '../board/board.dart';

/// The Snakes & Ladders match screen: the shared match scaffold with the
/// Snakes & Ladders board (not square: it keeps its own aspect ratio).
class SnakesGameScreen extends StatelessWidget {
  const SnakesGameScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) =>
      MatchView(roomId: roomId, bindingFactory: SnakesBoardBinding.create);
}

/// Wires [SnakesBoardController] + [DiceController] to the match sequencer.
/// There are no move choices: the server applies the move with the roll.
class SnakesBoardBinding extends MatchBoardBinding {
  SnakesBoardBinding._({
    required this.board,
    required this.dice,
    required this.selfSeat,
    required this._feedback,
  }) {
    board
      // The finish square stays silent: the finish cue plays there.
      ..onStep = ((seat, square) {
        if (square < 100) _feedback.step(mine: seat == selfSeat);
      })
      ..onSnake = ((seat, _, _) => _feedback.snake(mine: seat == selfSeat))
      ..onLadder = ((seat, _, _) => _feedback.ladder(mine: seat == selfSeat))
      ..onFinish = ((seat) => _feedback.home(mine: seat == selfSeat));
    // The local roll sound plays on the tap (MatchView); every settle gets a
    // soft landing cue.
    dice.onSettle = ((_) => _feedback.diceSettled(mine: _rollSeat == selfSeat));
  }

  static MatchBoardBinding create(
    RoomSnapshot room, {
    required int? selfSeat,
    required MatchFeedback feedback,
  }) {
    final seats = seatCountOf(room);
    return SnakesBoardBinding._(
      board: SnakesBoardController(
        seatColors: seatColorsOf(room, seats),
        positions: room.board.snakesPositions ?? const <int>[],
      ),
      dice: DiceController(
        initialValue: room.turn.dice > 0 ? room.turn.dice : 1,
      ),
      selfSeat: selfSeat,
      feedback: feedback,
    );
  }

  final SnakesBoardController board;
  @override
  final DiceController dice;
  final int? selfSeat;
  final MatchFeedback _feedback;

  /// Seat of the die being animated.
  int? _rollSeat;

  @override
  void showLegalMoves(RoomSnapshot room) {}

  @override
  void clearLegalMoves() {}

  @override
  void snapTo(RoomSnapshot room) {
    board
      ..setPositions(room.board.snakesPositions ?? const <int>[])
      ..setTurnSeat(room.isPlaying ? room.turn.seat : null);
    if (room.turn.dice > 0) dice.show(room.turn.dice);
  }

  @override
  Future<void> playDice(
    DiceResultEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) {
    _rollSeat = event.seat;
    return dice.roll(event.value.clamp(1, 6));
  }

  @override
  Future<void> playMove(
    MoveAppliedEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) {
    final t = event.transition;
    return board.animateMove(
      seat: event.seat,
      from: event.from,
      to: event.to,
      landing: event.landing,
      transition: t == null ? null : (kind: t.kind, from: t.from, to: t.to),
    );
  }

  @override
  Future<void> playTurnChange(TurnChangedEvent event, RoomSnapshot room) async {
    board.setTurnSeat(room.isPlaying ? event.seat : null);
  }

  @override
  Future<void> playOther(
    RoomDeltaEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) async {
    if (event is GameFinishedEvent) board.setTurnSeat(null);
  }

  @override
  void cancelAnimations() {
    board.cancelAndSnap();
    dice.cancel();
  }

  @override
  double get boardAspectRatio => SnakesGeometry.aspectRatio;

  @override
  Widget buildBoard(BuildContext context, MatchBoardArgs args) {
    final room = args.presented;
    final seats = board.seatCount;
    return SnakesBoard(
      controller: board,
      boardTheme: SnakesBoardThemes.resolve(args.snakesBoardTheme),
      tokenSkins: [
        for (var s = 0; s < seats; s++)
          room.playerAtSeat(s)?.cosmetics.token ?? 'token_classic',
      ],
      trails: [
        for (var s = 0; s < seats; s++)
          room.playerAtSeat(s)?.cosmetics.trail ?? 'trail_none',
      ],
      reducedMotion: args.reducedMotion,
    );
  }

  @override
  void dispose() {
    board
      ..onStep = null
      ..onSnake = null
      ..onLadder = null
      ..onFinish = null;
    dice.onSettle = null;
    board.dispose();
    dice.dispose();
  }
}
