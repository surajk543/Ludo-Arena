import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/audio_haptics/haptics_service.dart';
import 'package:ludo_royale/core/settings/app_settings.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('sfx audio context', () {
    test(
      'is a valid iOS context (no assertion) that respects the silent switch',
      () {
        // Constructing runs AudioContextIOS' debug assertions; the previous
        // respectSilence + mixWithOthers config failed them at startup.
        final ctx = AudioPlayersService.sfxAudioContext();
        expect(ctx.iOS.category, AVAudioSessionCategory.ambient);
        expect(ctx.iOS.options, isEmpty);
      },
    );

    test('Android plays as game sonification without taking audio focus', () {
      final ctx = AudioPlayersService.sfxAudioContext();
      expect(ctx.android.usageType, AndroidUsageType.game);
      expect(ctx.android.contentType, AndroidContentType.sonification);
      expect(ctx.android.audioFocus, AndroidAudioFocus.none);
      expect(ctx.android.isSpeakerphoneOn, isFalse);
      expect(ctx.android.stayAwake, isFalse);
    });
  });

  test('every Sfx maps to a bundled wav asset path', () {
    for (final s in Sfx.values) {
      expect(s.assetPath, 'audio/${s.file}.wav');
    }
    expect(Sfx.values.where((s) => s.pooled), hasLength(3));
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
    final audio = AudioPlayersService(enabled: () => false);
    audio.play(Sfx.click);
    await audio.dispose();

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
}
