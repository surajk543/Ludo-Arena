import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio_haptics/audio_service.dart';
import '../core/state/in_match_provider.dart';
import 'gate/app_gate_controller.dart';
import 'launch_intro.dart';

/// Whether the lobby music should loop: the launch intro is over (its
/// jingle plays alone), the user is past the gate (home, meta and pre-game
/// screens) and no match screen is open.
bool lobbyMusicWanted({
  required GatePhase phase,
  required bool inMatch,
  bool introPlaying = false,
}) => !introPlaying && phase == GatePhase.ready && !inMatch;

/// Plays the lobby loop on lobby / meta screens and fades it out while a
/// match screen is open (`inMatchProvider`). The service itself handles the
/// Sound switch, the music volume, the fades and the app lifecycle.
///
/// Watched once by the root widget.
final lobbyMusicProvider = Provider<void>((ref) {
  final audio = ref.watch(audioServiceProvider);
  void sync() {
    final wanted = lobbyMusicWanted(
      phase: ref.read(appGateControllerProvider).phase,
      inMatch: ref.read(inMatchProvider),
      introPlaying: ref.read(launchIntroPlayingProvider),
    );
    if (wanted) {
      audio.playMusic(MusicTrack.lobby);
    } else {
      audio.stopMusic();
    }
  }

  ref.listen(appGateControllerProvider.select((s) => s.phase), (_, _) {
    sync();
  });
  ref.listen<bool>(inMatchProvider, (_, _) => sync());
  ref.listen<bool>(launchIntroPlayingProvider, (_, _) => sync());
  sync();
  ref.onDispose(audio.stopMusic);
});
