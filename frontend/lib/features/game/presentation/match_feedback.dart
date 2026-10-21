import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';

/// Sound + haptic cues for the match screen. Every cue follows a
/// server-confirmed event (board / dice hooks driven by the sequencer) or the
/// local player's own input; both services honor the Sound / Haptics
/// settings, and board hooks never fire for snapped moves.
class MatchFeedback {
  MatchFeedback({required this._audio, required this._haptics});

  final AudioService _audio;
  final HapticsService _haptics;

  /// Other players' cues are a little softer than the local player's.
  static const double _othersVolume = 0.6;

  /// The local player tapped the dice (the die starts tumbling at once).
  /// Other players' rolls are never announced with this sound.
  void rollTapped() {
    _audio.play(Sfx.diceRoll);
    _haptics.light();
  }

  /// A die settled on its server value ([mine]: the local player's roll).
  void diceSettled({required bool mine}) {
    _audio.play(Sfx.diceLand, volume: mine ? 1 : _othersVolume);
    _haptics.medium();
  }

  /// The local player picked a token (the move is sent to the server).
  void tokenTapped() {
    _audio.play(Sfx.tokenSelect);
    _haptics.light();
  }

  /// One square of a move (soft; bursts are capped by the service).
  void step({required bool mine}) =>
      _audio.play(Sfx.tokenStep, volume: mine ? 1 : 0.8);

  void leftBase({required bool mine}) =>
      _audio.play(Sfx.tokenLeaveBase, volume: mine ? 1 : _othersVolume);

  void safeLanding({required bool mine}) =>
      _audio.play(Sfx.tokenSafe, volume: mine ? 1 : _othersVolume);

  void enteredHomePath({required bool mine}) =>
      _audio.play(Sfx.tokenHomePath, volume: mine ? 1 : _othersVolume);

  /// A capture: the attacker's punch ([mine]), a softer descending cue when
  /// one of the local player's tokens is the [victim], a quieter punch for
  /// onlookers.
  void capture({required bool mine, required bool victim}) {
    if (victim && !mine) {
      _audio.play(Sfx.tokenCaptured);
    } else {
      _audio.play(Sfx.tokenCapture, volume: mine ? 1 : _othersVolume);
    }
    _haptics.heavy();
  }

  void home({required bool mine}) {
    _audio.play(Sfx.tokenHome, volume: mine ? 1 : _othersVolume);
    _haptics.success();
  }

  void snake({required bool mine}) {
    _audio.play(Sfx.snakeSlide, volume: mine ? 1 : _othersVolume);
    _haptics.medium();
  }

  void ladder({required bool mine}) {
    _audio.play(Sfx.ladderClimb, volume: mine ? 1 : _othersVolume);
    _haptics.light();
  }

  /// The turn passed to the local player (nothing for other players).
  void myTurn() {
    _audio.play(Sfx.turnMine);
    _haptics.selection();
  }

  /// A new round started (rematch / next round).
  void matchStart() => _audio.play(Sfx.matchStart);

  void chat() => _audio.play(Sfx.chatPop);

  void win() {
    _audio.play(Sfx.win);
    _haptics.success();
  }

  void lose() => _audio.play(Sfx.lose);
  void coins() => _audio.play(Sfx.coin);
  void levelUp() {
    _audio.play(Sfx.levelUp);
    _haptics.success();
  }
}
