import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';

/// Sound + haptic cues for board hooks. Both services honor the user's
/// Sound / Haptics settings; board hooks never fire for snapped moves.
class MatchFeedback {
  MatchFeedback({required this._audio, required this._haptics});

  final AudioService _audio;
  final HapticsService _haptics;

  void diceTumble() => _audio.play(Sfx.diceRoll, volume: 0.9);
  void diceSettled() => _haptics.medium();
  void step() => _audio.play(Sfx.tokenStep, volume: 0.55);
  void capture() {
    _audio.play(Sfx.capture);
    _haptics.heavy();
  }

  void home() {
    _audio.play(Sfx.home);
    _haptics.success();
  }

  void snake() {
    _audio.play(Sfx.snakeSlide);
    _haptics.medium();
  }

  void ladder() {
    _audio.play(Sfx.ladderClimb);
    _haptics.light();
  }

  void myTurn() {
    _audio.play(Sfx.turn, volume: 0.8);
    _haptics.selection();
  }

  void tap() => _haptics.light();
  void chat() => _audio.play(Sfx.chatPop, volume: 0.6);
  void win() {
    _audio.play(Sfx.win);
    _haptics.success();
  }

  void lose() => _audio.play(Sfx.lose, volume: 0.8);
  void coins() => _audio.play(Sfx.coin);
  void levelUp() {
    _audio.play(Sfx.levelUp);
    _haptics.success();
  }
}
