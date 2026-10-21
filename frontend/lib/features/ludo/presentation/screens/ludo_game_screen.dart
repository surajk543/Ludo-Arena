import 'package:flutter/widgets.dart';

import '../../../../core/protocol/protocol.dart';
import '../../../../shared/game_visuals/game_visuals.dart';
import '../../../game/application/turn_input_guard.dart';
import '../../../game/presentation/match_board_binding.dart';
import '../../../game/presentation/match_feedback.dart';
import '../../../game/presentation/match_view.dart';
import '../board/board.dart';

/// The Ludo match screen: the shared match scaffold with the Ludo board.
class LudoGameScreen extends StatelessWidget {
  const LudoGameScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) =>
      MatchView(roomId: roomId, bindingFactory: LudoBoardBinding.create);
}

/// Wires [LudoBoardController] + [DiceController] to the match sequencer.
class LudoBoardBinding extends MatchBoardBinding {
  LudoBoardBinding._({
    required this.board,
    required this.dice,
    required this.selfSeat,
    required this._feedback,
  }) {
    board
      ..onStep = ((_, _, _) => _feedback.step())
      ..onCapture = ((_, _, _) => _feedback.capture())
      ..onHome = ((_, _) => _feedback.home());
    dice
      ..onTumbleStart = _feedback.diceTumble
      ..onSettle = ((_) => _feedback.diceSettled());
  }

  static MatchBoardBinding create(
    RoomSnapshot room, {
    required int? selfSeat,
    required MatchFeedback feedback,
  }) {
    final seats = seatCountOf(room);
    final tokens = room.board.ludoTokens ?? const <List<int>>[];
    final perPlayer = tokens.isNotEmpty && tokens.first.isNotEmpty
        ? tokens.first.length.clamp(1, 4)
        : (room.variant == GameVariants.quick ? 2 : 4);
    return LudoBoardBinding._(
      board: LudoBoardController(
        seatColors: seatColorsOf(room, seats),
        tokensPerPlayer: perPlayer,
        positions: tokens,
        // The local player's base is always drawn bottom-left.
        quarterTurns: boardTurnsFor(room, selfSeat),
      ),
      dice: DiceController(
        initialValue: room.turn.dice > 0 ? room.turn.dice : 1,
      ),
      selfSeat: selfSeat,
      feedback: feedback,
    );
  }

  final LudoBoardController board;
  @override
  final DiceController dice;
  final int? selfSeat;
  final MatchFeedback _feedback;

  /// Local highlight only: the local player's turn, choosing a token, and
  /// more than one option (a single legal move is applied by the server).
  bool _shouldHighlight(RoomSnapshot room) =>
      selfSeat != null &&
      room.isPlaying &&
      room.turn.seat == selfSeat &&
      TurnInputGuard.requiresChoice(room);

  @override
  void showLegalMoves(RoomSnapshot room) {
    if (_shouldHighlight(room)) {
      board.setInteraction(
        seat: selfSeat,
        legalTokens: room.turn.legal.toSet(),
      );
    } else {
      board.setInteraction();
    }
  }

  @override
  void clearLegalMoves() => board.setInteraction();

  @override
  void snapTo(RoomSnapshot room) {
    board
      ..setForfeitedSeats(forfeitedSeatsOf(room))
      ..setPositions(room.board.ludoTokens ?? const <List<int>>[])
      ..setTurnSeat(room.isPlaying ? room.turn.seat : null);
    showLegalMoves(room);
    if (room.turn.dice > 0) dice.show(room.turn.dice);
  }

  @override
  Future<void> playDice(
    DiceResultEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) async {
    board.setInteraction();
    await dice.roll(event.value.clamp(1, 6));
    showLegalMoves(room);
  }

  @override
  Future<void> playMove(
    MoveAppliedEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) {
    board.setInteraction();
    return board.animateMove(
      seat: event.seat,
      token: event.token,
      from: event.from,
      to: event.to,
      captures: [
        for (final c in event.captures) (seat: c.seat, token: c.token),
      ],
      reachedHome: event.home,
    );
  }

  @override
  Future<void> playTurnChange(TurnChangedEvent event, RoomSnapshot room) async {
    board
      ..setInteraction()
      ..setTurnSeat(room.isPlaying ? event.seat : null);
  }

  @override
  Future<void> playOther(
    RoomDeltaEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) async {
    switch (event) {
      case PlayerForfeitedEvent():
        board.setForfeitedSeats(forfeitedSeatsOf(room));
        showLegalMoves(room);
      case GameFinishedEvent():
        board
          ..setInteraction()
          ..setTurnSeat(null);
      default:
        break;
    }
  }

  @override
  void cancelAnimations() {
    board.cancelAndSnap();
    dice.cancel();
  }

  @override
  Widget buildBoard(BuildContext context, MatchBoardArgs args) {
    final room = args.presented;
    final seats = board.seatCount;
    return LudoBoard(
      controller: board,
      boardTheme: LudoBoardThemes.resolve(args.ludoBoardTheme),
      tokenSkins: [
        for (var s = 0; s < seats; s++)
          room.playerAtSeat(s)?.cosmetics.token ?? 'token_classic',
      ],
      trails: [
        for (var s = 0; s < seats; s++)
          room.playerAtSeat(s)?.cosmetics.trail ?? 'trail_none',
      ],
      onTokenTap: args.onTokenTap,
      reducedMotion: args.reducedMotion,
    );
  }

  @override
  void dispose() {
    board
      ..onStep = null
      ..onCapture = null
      ..onHome = null;
    dice
      ..onTumbleStart = null
      ..onSettle = null;
    board.dispose();
    dice.dispose();
  }
}
