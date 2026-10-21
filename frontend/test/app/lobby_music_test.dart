import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/app/gate/app_gate_controller.dart';
import 'package:ludo_royale/app/launch_intro.dart';
import 'package:ludo_royale/app/lobby_music.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/state/in_match_provider.dart';
import 'package:ludo_royale/features/game/presentation/in_match_scope.dart';

class _Gate extends AppGateController {
  @override
  GateState build() => const GateState(phase: GatePhase.signedOut);

  void go(GatePhase phase) => state = GateState(phase: phase);
}

void main() {
  test('wanted only past the gate and outside matches', () {
    for (final phase in GatePhase.values) {
      expect(
        lobbyMusicWanted(phase: phase, inMatch: false),
        phase == GatePhase.ready,
        reason: phase.name,
      );
      expect(lobbyMusicWanted(phase: phase, inMatch: true), isFalse);
      expect(
        lobbyMusicWanted(phase: phase, inMatch: false, introPlaying: true),
        isFalse,
        reason: 'the launch intro plays its jingle alone',
      );
    }
  });

  test('waits for the launch intro, then loops', () async {
    final audio = SilentAudioService();
    final c = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(audio),
        appGateControllerProvider.overrideWith(_Gate.new),
      ],
    );
    addTearDown(c.dispose);
    c.read(lobbyMusicProvider);
    // The gate signs in while the intro still plays: no music yet.
    (c.read(appGateControllerProvider.notifier) as _Gate).go(GatePhase.ready);
    await pumpEventQueue();
    expect(audio.musicCalls, isEmpty);

    c.read(launchIntroPlayingProvider.notifier).finish();
    await pumpEventQueue();
    expect(audio.musicCalls, ['load:lobby', 'resume']);
  });

  test('loops in the lobby, stops in a match, resumes after it', () async {
    final audio = SilentAudioService();
    final c = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(audio),
        appGateControllerProvider.overrideWith(_Gate.new),
      ],
    );
    addTearDown(c.dispose);
    c.read(launchIntroPlayingProvider.notifier).finish();
    c.read(lobbyMusicProvider);
    await pumpEventQueue();
    expect(audio.musicCalls, isEmpty, reason: 'login / splash: no music');

    (c.read(appGateControllerProvider.notifier) as _Gate).go(GatePhase.ready);
    await pumpEventQueue();
    expect(audio.musicTrack, MusicTrack.lobby);
    expect(audio.musicCalls, ['load:lobby', 'resume']);
    expect(audio.isMusicPlaying, isTrue);
    expect(audio.musicLevel, audio.musicVolume);

    c.read(inMatchProvider.notifier).set(true);
    await pumpEventQueue();
    expect(audio.musicCalls.last, 'pause');
    expect(audio.isMusicPlaying, isFalse);

    c.read(inMatchProvider.notifier).set(false);
    await pumpEventQueue();
    expect(audio.musicCalls, ['load:lobby', 'resume', 'pause', 'resume']);

    // Muted: no music even in the lobby.
    audio.applySettings(enabled: false, sfxVolume: 0.8, musicVolume: 0.5);
    await pumpEventQueue();
    expect(audio.musicCalls.last, 'pause');
  });

  testWidgets('a match screen (InMatchScope) fades the lobby music out', (
    tester,
  ) async {
    final audio = SilentAudioService();
    final showMatch = ValueNotifier(false);
    addTearDown(showMatch.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          appGateControllerProvider.overrideWith(_Gate.new),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(lobbyMusicProvider);
            return ValueListenableBuilder<bool>(
              valueListenable: showMatch,
              builder: (_, inMatch, _) => inMatch
                  ? const InMatchScope(child: SizedBox())
                  : const SizedBox(),
            );
          },
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Consumer)),
    );
    container.read(launchIntroPlayingProvider.notifier).finish();
    (container.read(appGateControllerProvider.notifier) as _Gate).go(
      GatePhase.ready,
    );
    await tester.pump();
    expect(audio.isMusicPlaying, isTrue);

    showMatch.value = true;
    await tester.pump();
    await tester.pump();
    expect(audio.isMusicPlaying, isFalse);
    expect(audio.musicCalls.last, 'pause');

    showMatch.value = false;
    await tester.pump();
    await tester.pump();
    expect(audio.isMusicPlaying, isTrue);
  });
}
