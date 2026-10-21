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
      ..onStep = _onStep
      ..onCapture = ((seat, _, captured) => _feedback.capture(
        mine: seat == selfSeat,
        victim: captured.any((c) => c.seat == selfSeat),
      ))
      ..onHome = ((seat, _) => _feedback.home(mine: seat == selfSeat));
    // The local roll sound plays on the tap (MatchView); every settle gets a
    // soft landing cue.
    dice.onSettle = ((_) => _feedback.diceSettled(mine: _rollSeat == selfSeat));
  }

  /// The move being animated (moves play one at a time).
  ({int to, bool captures, bool home})? _move;

  /// Seat of the die being animated.
  int? _rollSeat;

  /// One sound per square; special squares replace the step: leaving base
  /// (progress 0 is only reachable from base), entering the home column, a
  /// safe landing. The landing square of a capture / home move stays silent
  /// (the capture / home cue plays there).
  void _onStep(int seat, int token, int progress) {
    final mine = seat == selfSeat;
    final move = _move;
    final last = move != null && progress == move.to;
    if (last && (move.captures || move.home)) return;
    if (progress == 0) {
      _feedback.leftBase(mine: mine);
    } else if (progress == LudoGeometry.firstHomeColumnProgress &&
        !(move?.home ?? false)) {
      _feedback.enteredHomePath(mine: mine);
    } else if (last && _isSafeProgress(progress)) {
      _feedback.safeLanding(mine: mine);
    } else {
      _feedback.step(mine: mine);
    }
  }

  /// Safe track squares (starts and stars) in progress terms: the safe set
  /// repeats every quarter of the track, so it is the same for every color.
  static bool _isSafeProgress(int progress) =>
      progress >= 0 &&
      progress <= LudoGeometry.lastTrackProgress &&
      LudoGeometry.isSafeTrackIndex(progress);

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
    _rollSeat = event.seat;
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
    _move = (
      to: event.to,
      captures: event.captures.isNotEmpty,
      home: event.home || event.to == LudoGeometry.homeProgress,
    );
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
  double get boardAspectRatio => LudoBoardLayout.aspectRatio;

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
    dice.onSettle = null;
    board.dispose();
    dice.dispose();
  }
}
