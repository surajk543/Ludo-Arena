import 'package:audioplayers/audioplayers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/audio_haptics/audio_backend.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/audio_haptics/haptics_service.dart';
import 'package:ludo_royale/core/lifecycle/app_lifecycle.dart';
import 'package:ludo_royale/core/settings/app_settings.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A service over a [RecordingAudioBackend] with a manual clock.
class _Rig {
  _Rig({
    Set<String> missing = const {},
    Duration musicFade = const Duration(milliseconds: 400),
  }) : backend = RecordingAudioBackend(missingAssets: missing) {
    audio = AudioService(
      backend: backend,
      clock: () => now,
      musicFade: musicFade,
      log: logs.add,
    );
  }

  final RecordingAudioBackend backend;
  final List<String> logs = [];
  Duration now = Duration.zero;
  late final AudioService audio;

  void advance(int ms) => now += Duration(milliseconds: ms);
}

void main() {
  group('audio contexts', () {
    test('effects: a valid iOS context (no assertion) that respects the silent '
        'switch', () {
      // Constructing runs AudioContextIOS' debug assertions; the previous
      // respectSilence + mixWithOthers config failed them at startup.
      final ctx = AudioPlayersBackend.sfxAudioContext();
      expect(ctx.iOS.category, AVAudioSessionCategory.ambient);
      expect(ctx.iOS.options, isEmpty);
    });

    test('effects play as game sonification without taking audio focus', () {
      final ctx = AudioPlayersBackend.sfxAudioContext();
      expect(ctx.android.usageType, AndroidUsageType.game);
      expect(ctx.android.contentType, AndroidContentType.sonification);
      expect(ctx.android.audioFocus, AndroidAudioFocus.none);
      expect(ctx.android.isSpeakerphoneOn, isFalse);
      expect(ctx.android.stayAwake, isFalse);
    });

    test(
      'music mixes with other apps: ambient on iOS, no focus on Android',
      () {
        final ctx = AudioPlayersBackend.musicAudioContext();
        expect(ctx.iOS.category, AVAudioSessionCategory.ambient);
        expect(ctx.iOS.options, isEmpty);
        expect(ctx.android.audioFocus, AndroidAudioFocus.none);
        expect(ctx.android.contentType, AndroidContentType.music);
        expect(ctx.android.usageType, AndroidUsageType.game);
        expect(ctx.android.stayAwake, isFalse);
      },
    );
  });

  test('every Sfx maps to a bundled wav and the music to an m4a', () {
    for (final s in Sfx.values) {
      expect(s.assetPath, 'audio/sfx/${s.file}.wav');
      expect(s.gain, inInclusiveRange(0.1, 1.0), reason: s.name);
      expect(s.voices, greaterThanOrEqualTo(1), reason: s.name);
    }
    expect(Sfx.values.map((s) => s.file).toSet(), hasLength(Sfx.values.length));
    expect(MusicTrack.lobby.assetPath, 'audio/music/lobby_loop.m4a');
    expect(Sfx.values.where((s) => s.preload), isNotEmpty);
  });

  test('audio and haptics honor the Settings toggles', () async {
    SharedPreferences.setMockInitialValues({
      PrefKeys.soundEnabled: false,
      PrefKeys.hapticsEnabled: false,
    });
    final prefs = PreferencesStore(await SharedPreferences.getInstance());
    final c = ProviderContainer(
      overrides: [preferencesStoreProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    final settings = c.read(settingsControllerProvider);
    expect(settings.soundEnabled, isFalse);
    expect(settings.hapticsEnabled, isFalse);

    // Disabled sound: play() is a no-op and never touches the platform.
    final rig = _Rig();
    rig.audio.applySettings(
      enabled: settings.soundEnabled,
      sfxVolume: settings.sfxVolume,
      musicVolume: settings.musicVolume,
    );
    rig.audio.play(Sfx.uiTap);
    rig.audio.play(Sfx.diceRoll);
    rig.audio.playMusic(MusicTrack.lobby);
    await pumpEventQueue();
    expect(rig.backend.played, isEmpty);
    expect(rig.backend.musicCalls, isEmpty);
    await rig.audio.dispose();

    var calls = 0;
    final haptics = HapticsService(
      enabled: () {
        calls++;
        return false;
      },
    );
    haptics.light();
    expect(calls, 1);
  });

  group('effects', () {
    test('final volume = effects volume × per-sound gain × call volume', () {
      final rig = _Rig();
      rig.audio.applySettings(enabled: true, sfxVolume: 0.5, musicVolume: 0);
      rig.audio.play(Sfx.diceRoll);
      rig.advance(1000);
      rig.audio.play(Sfx.tokenCapture, volume: 0.5);
      expect(rig.backend.played, [Sfx.diceRoll, Sfx.tokenCapture]);
      expect(rig.backend.volumes[0], closeTo(0.5 * Sfx.diceRoll.gain, 1e-9));
      expect(
        rig.backend.volumes[1],
        closeTo(0.5 * Sfx.tokenCapture.gain * 0.5, 1e-9),
      );

      // Effects volume 0: nothing is started at all.
      rig.audio.applySettings(enabled: true, sfxVolume: 0, musicVolume: 0);
      rig.advance(1000);
      rig.audio.play(Sfx.diceRoll);
      expect(rig.backend.played, hasLength(2));
    });

    test('a cooldown prevents a double play of the same event', () {
      final rig = _Rig();
      rig.audio.play(Sfx.win);
      rig.audio.play(Sfx.win);
      rig.advance(500);
      rig.audio.play(Sfx.win);
      expect(rig.backend.played, [Sfx.win]);
      rig.advance(Sfx.win.cooldown.inMilliseconds);
      rig.audio.play(Sfx.win);
      expect(rig.backend.played, [Sfx.win, Sfx.win]);
    });

    test('a reward claim and the coin update right after it: one sound', () {
      final rig = _Rig();
      rig.audio.play(Sfx.rewardClaim);
      rig.advance(150);
      rig.audio.play(Sfx.coin);
      expect(rig.backend.played, [Sfx.rewardClaim]);
      rig.advance(2000);
      rig.audio.play(Sfx.coin);
      expect(rig.backend.played, [Sfx.rewardClaim, Sfx.coin]);
    });

    test('token-step bursts never pile up (cooldown + voice limit)', () {
      final rig = _Rig();
      // A frame hiccup fires 6 steps at once: one sound.
      for (var i = 0; i < 6; i++) {
        rig.audio.play(Sfx.tokenStep);
      }
      expect(rig.backend.played, [Sfx.tokenStep]);
      // Every 20 ms for 200 ms: limited by the cooldown and the voices.
      for (var i = 0; i < 10; i++) {
        rig.advance(20);
        rig.audio.play(Sfx.tokenStep);
      }
      final steps = rig.backend.played.where((s) => s == Sfx.tokenStep);
      expect(steps.length, lessThanOrEqualTo(Sfx.tokenStep.voices));
      // A normal hop rhythm (~140 ms) plays every square.
      rig.backend.played.clear();
      rig.advance(1000);
      for (var i = 0; i < 6; i++) {
        rig.audio.play(Sfx.tokenStep);
        rig.advance(140);
      }
      expect(rig.backend.played, List.filled(6, Sfx.tokenStep));
    });

    test('UI: everything one tap triggers coalesces into one sound', () async {
      final rig = _Rig();
      // Button click + the sheet it opens, in the same tap.
      rig.audio.play(Sfx.uiTap);
      rig.audio.play(Sfx.uiOpen);
      expect(rig.backend.played, isEmpty, reason: 'flushed in a microtask');
      await pumpEventQueue();
      expect(rig.backend.played, [Sfx.uiOpen]);

      // Find match closes the sheet: the close sound right after the play
      // sound belongs to the same gesture.
      rig.advance(1000);
      rig.audio.play(Sfx.lobbyPlay);
      await pumpEventQueue();
      rig.advance(5);
      rig.audio.play(Sfx.uiClose);
      await pumpEventQueue();
      expect(rig.backend.played, [Sfx.uiOpen, Sfx.lobbyPlay]);

      // A failure right after a tap still gets its (more important) cue.
      rig.advance(1000);
      rig.audio.play(Sfx.uiTap);
      await pumpEventQueue();
      rig.advance(40);
      rig.audio.play(Sfx.uiError);
      await pumpEventQueue();
      expect(rig.backend.played.skip(2), [Sfx.uiTap, Sfx.uiError]);

      // Two separate taps (beyond the gesture window) both sound.
      rig.advance(1000);
      rig.audio.play(Sfx.uiTab);
      await pumpEventQueue();
      rig.advance(200);
      rig.audio.play(Sfx.uiTab);
      await pumpEventQueue();
      expect(rig.backend.played.skip(4), [Sfx.uiTab, Sfx.uiTab]);
    });

    test('a reward moment keeps the dialog it opens quiet', () async {
      final rig = _Rig();
      // Claim succeeded → reward cue, then the "new items" dialog opens.
      rig.audio.play(Sfx.rewardClaim);
      rig.audio.play(Sfx.uiOpen);
      await pumpEventQueue();
      expect(rig.backend.played, [Sfx.rewardClaim]);
      // An error right after still sounds.
      rig.advance(20);
      rig.audio.play(Sfx.uiError);
      await pumpEventQueue();
      expect(rig.backend.played, [Sfx.rewardClaim, Sfx.uiError]);
    });

    test('a missing asset never throws, is logged once and then skipped', () {
      fakeAsync((async) {
        final rig = _Rig(missing: {Sfx.diceRoll.assetPath});
        expect(() => rig.audio.play(Sfx.diceRoll), returnsNormally);
        async.flushMicrotasks();
        rig.advance(1000);
        rig.audio.play(Sfx.diceRoll);
        async.flushMicrotasks();
        expect(rig.backend.played, isEmpty);
        expect(rig.logs.where((l) => l.contains('dice_roll')), hasLength(1));
        // Other sounds are unaffected.
        rig.audio.play(Sfx.diceLand);
        expect(rig.backend.played, [Sfx.diceLand]);
      });
    });

    test('warm-up preloads the frequent effects and tolerates failures', () {
      fakeAsync((async) {
        final rig = _Rig(missing: {Sfx.uiTap.assetPath});
        rig.audio.warmUp();
        async.flushMicrotasks();
        expect(
          rig.backend.preloaded,
          Sfx.values.where((s) => s.preload && s != Sfx.uiTap),
        );
        expect(rig.logs.where((l) => l.contains('ui_tap')), hasLength(1));
      });
    });

    test('effects are dropped while the app is in the background', () {
      final rig = _Rig();
      rig.audio.setForeground(false);
      rig.audio.play(Sfx.turnMine);
      expect(rig.backend.played, isEmpty);
      rig.audio.setForeground(true);
      rig.audio.play(Sfx.turnMine);
      expect(rig.backend.played, [Sfx.turnMine]);
    });
  });

  group('music', () {
    test('plays looping with a fade-in and stops with a fade-out', () {
      fakeAsync((async) {
        final rig = _Rig();
        rig.audio.playMusic(MusicTrack.lobby);
        async.flushMicrotasks();
        expect(rig.backend.musicCalls, ['load:lobby', 'resume']);
        expect(rig.audio.isMusicPlaying, isTrue);
        expect(rig.audio.musicLevel, 0);

        async.elapse(const Duration(milliseconds: 200));
        expect(rig.audio.musicLevel, closeTo(0.25, 0.01), reason: 'halfway');
        async.elapse(const Duration(milliseconds: 250));
        expect(rig.audio.musicLevel, AppSettings.defaultMusicVolume);
        expect(rig.backend.musicVolumes.last, 0.5);

        rig.audio.stopMusic();
        async.flushMicrotasks();
        expect(rig.backend.musicCalls.last, 'resume', reason: 'fading out');
        async.elapse(const Duration(milliseconds: 450));
        expect(rig.audio.musicLevel, 0);
        expect(rig.backend.musicCalls, ['load:lobby', 'resume', 'pause']);
        expect(rig.audio.isMusicPlaying, isFalse);

        // Back to the lobby: resumes (no reload) and fades in again.
        rig.audio.playMusic(MusicTrack.lobby);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 450));
        expect(rig.backend.musicCalls, [
          'load:lobby',
          'resume',
          'pause',
          'resume',
        ]);
        expect(rig.audio.musicLevel, 0.5);
      });
    });

    test('a quick stop/start reverses the fade instead of pausing', () {
      fakeAsync((async) {
        final rig = _Rig();
        rig.audio.playMusic(MusicTrack.lobby);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        rig.audio.stopMusic();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 120));
        rig.audio.playMusic(MusicTrack.lobby);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rig.backend.musicCalls, ['load:lobby', 'resume']);
        expect(rig.audio.musicLevel, 0.5);
        expect(rig.audio.isMusicPlaying, isTrue);
      });
    });

    test('the music volume applies live; 0 or mute pauses it', () {
      fakeAsync((async) {
        final rig = _Rig();
        rig.audio.playMusic(MusicTrack.lobby);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));

        rig.audio.applySettings(
          enabled: true,
          sfxVolume: 0.8,
          musicVolume: 0.3,
        );
        async.flushMicrotasks();
        expect(rig.audio.musicLevel, 0.3, reason: 'no fade for the slider');
        expect(rig.backend.musicVolumes.last, 0.3);

        rig.audio.applySettings(
          enabled: false,
          sfxVolume: 0.8,
          musicVolume: 0.3,
        );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rig.backend.musicCalls.last, 'pause');

        rig.audio.applySettings(enabled: true, sfxVolume: 0.8, musicVolume: 0);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rig.audio.isMusicPlaying, isFalse);

        rig.audio.applySettings(
          enabled: true,
          sfxVolume: 0.8,
          musicVolume: 0.6,
        );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rig.audio.isMusicPlaying, isTrue);
        expect(rig.audio.musicLevel, 0.6);
      });
    });

    test('pauses at once in the background and fades back in on return', () {
      fakeAsync((async) {
        final rig = _Rig();
        rig.audio.playMusic(MusicTrack.lobby);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));

        rig.audio.setForeground(false);
        async.flushMicrotasks();
        expect(rig.backend.musicCalls.last, 'pause');
        expect(rig.audio.musicLevel, 0);

        rig.audio.setForeground(true);
        async.flushMicrotasks();
        expect(rig.backend.musicCalls.last, 'resume');
        async.elapse(const Duration(milliseconds: 200));
        expect(rig.audio.musicLevel, inExclusiveRange(0, 0.5));
        async.elapse(const Duration(milliseconds: 300));
        expect(rig.audio.musicLevel, 0.5);
      });
    });

    test('a missing track never throws, is logged once, never retried', () {
      fakeAsync((async) {
        final rig = _Rig(missing: {MusicTrack.lobby.assetPath});
        rig.audio.playMusic(MusicTrack.lobby);
        async.flushMicrotasks();
        rig.audio.stopMusic();
        rig.audio.playMusic(MusicTrack.lobby);
        rig.audio.applySettings(enabled: true, sfxVolume: 1, musicVolume: 1);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        expect(rig.backend.musicCalls, isEmpty);
        expect(rig.logs.where((l) => l.contains('lobby_loop')), hasLength(1));
        expect(rig.audio.isMusicPlaying, isFalse);
      });
    });

    test('dispose releases the backend and silences everything', () {
      fakeAsync((async) {
        final rig = _Rig();
        rig.audio.playMusic(MusicTrack.lobby);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));
        rig.audio.dispose();
        async.flushMicrotasks();
        expect(rig.backend.disposed, isTrue);
        expect(async.pendingTimers, isEmpty, reason: 'fade timer cancelled');
        rig.audio.play(Sfx.uiTap);
        rig.audio.play(Sfx.diceRoll);
        async.flushMicrotasks();
        expect(rig.backend.played, isEmpty);
      });
    });
  });

  group('settings binder', () {
    test('applies the master switch and volumes live, and the lifecycle', () {
      fakeAsync((async) {
        SharedPreferences.setMockInitialValues({PrefKeys.sfxVolume: 40});
        late PreferencesStore prefs;
        SharedPreferences.getInstance().then(
          (p) => prefs = PreferencesStore(p),
        );
        async.flushMicrotasks();
        final audio = SilentAudioService(clock: () => Duration.zero);
        final c = ProviderContainer(
          overrides: [
            preferencesStoreProvider.overrideWithValue(prefs),
            audioServiceProvider.overrideWithValue(audio),
          ],
        );
        c.read(audioSettingsBinderProvider);
        expect(audio.sfxVolume, 0.4);
        expect(audio.musicVolume, AppSettings.defaultMusicVolume);

        final settings = c.read(settingsControllerProvider.notifier);
        settings.setVolume(VolumeKey.music, 0.2, persist: false);
        expect(audio.musicVolume, 0.2);
        settings.set(SettingKey.sound, false);
        expect(audio.enabled, isFalse);
        async.flushMicrotasks();
        expect(prefs.getBool(PrefKeys.soundEnabled), isFalse);
        settings.setVolume(VolumeKey.sfx, 0.65);
        async.flushMicrotasks();
        expect(prefs.getInt(PrefKeys.sfxVolume), 65);
        expect(prefs.getInt(PrefKeys.musicVolume), isNull, reason: 'drag');

        final bus = c.read(appLifecycleProvider);
        bus.emit(AppLifecycleState.paused);
        expect(audio.isForeground, isFalse);
        bus.emit(AppLifecycleState.resumed);
        expect(audio.isForeground, isTrue);
        c.dispose();
      });
    });
  });
}
