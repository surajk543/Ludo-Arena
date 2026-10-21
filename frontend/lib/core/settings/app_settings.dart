import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/number_format.dart';
import '../storage/preferences_store.dart';

/// User-adjustable, non-sensitive settings (persisted in SharedPreferences).
@immutable
class AppSettings {
  const AppSettings({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.reducedMotion = false,
    this.quickChatMuted = false,
    this.sfxVolume = defaultSfxVolume,
    this.musicVolume = defaultMusicVolume,
    this.numberSystem,
  });

  static const double defaultSfxVolume = 0.8;
  static const double defaultMusicVolume = 0.5;

  /// Master switch for all audio (sound effects and music).
  final bool soundEnabled;
  final bool hapticsEnabled;

  /// User preference; combined with the system setting by `ReducedMotion`.
  final bool reducedMotion;

  /// Hides incoming quick-chat and emote bubbles from other players.
  final bool quickChatMuted;

  /// Sound effects volume, 0..1 (persisted as a whole percentage).
  final double sfxVolume;

  /// Lobby music volume, 0..1 (persisted as a whole percentage).
  final double musicVolume;

  /// Indian (`1,00,000 · 10 Lakh`) or international (`100,000 · 1M`)
  /// grouping and compact words. Null until the user picks one: amounts then
  /// follow the language ([AppNumberFormat.defaultSystemFor]), which keeps
  /// the pre-setting behaviour (Indian for en/hi/ur).
  final NumberSystem? numberSystem;

  AppSettings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? reducedMotion,
    bool? quickChatMuted,
    double? sfxVolume,
    double? musicVolume,
    NumberSystem? numberSystem,
  }) => AppSettings(
    soundEnabled: soundEnabled ?? this.soundEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    quickChatMuted: quickChatMuted ?? this.quickChatMuted,
    sfxVolume: sfxVolume ?? this.sfxVolume,
    musicVolume: musicVolume ?? this.musicVolume,
    numberSystem: numberSystem ?? this.numberSystem,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.soundEnabled == soundEnabled &&
      other.hapticsEnabled == hapticsEnabled &&
      other.reducedMotion == reducedMotion &&
      other.quickChatMuted == quickChatMuted &&
      other.sfxVolume == sfxVolume &&
      other.musicVolume == musicVolume &&
      other.numberSystem == numberSystem;

  @override
  int get hashCode => Object.hash(
    soundEnabled,
    hapticsEnabled,
    reducedMotion,
    quickChatMuted,
    sfxVolume,
    musicVolume,
    numberSystem,
  );
}

/// Identifies a single setting (used for the `settings_changed` analytics
/// event, which only carries the setting name).
enum SettingKey { sound, haptics, reducedMotion, quickChatMute }

/// The two audio volume sliders.
enum VolumeKey { sfx, music }

class SettingsController extends Notifier<AppSettings> {
  PreferencesStore get _prefs => ref.read(preferencesStoreProvider);

  static double _volume(int? percent, double fallback) =>
      percent == null ? fallback : (percent.clamp(0, 100) / 100);

  @override
  AppSettings build() {
    final p = ref.read(preferencesStoreProvider);
    return AppSettings(
      soundEnabled: p.getBool(PrefKeys.soundEnabled) ?? true,
      hapticsEnabled: p.getBool(PrefKeys.hapticsEnabled) ?? true,
      reducedMotion: p.getBool(PrefKeys.reducedMotion) ?? false,
      quickChatMuted: p.getBool(PrefKeys.quickChatMuted) ?? false,
      sfxVolume: _volume(
        p.getInt(PrefKeys.sfxVolume),
        AppSettings.defaultSfxVolume,
      ),
      musicVolume: _volume(
        p.getInt(PrefKeys.musicVolume),
        AppSettings.defaultMusicVolume,
      ),
      numberSystem: NumberSystem.parse(p.getString(PrefKeys.numberSystem)),
    );
  }

  Future<void> set(SettingKey key, bool value) async {
    switch (key) {
      case SettingKey.sound:
        state = state.copyWith(soundEnabled: value);
        await _prefs.setBool(PrefKeys.soundEnabled, value);
      case SettingKey.haptics:
        state = state.copyWith(hapticsEnabled: value);
        await _prefs.setBool(PrefKeys.hapticsEnabled, value);
      case SettingKey.reducedMotion:
        state = state.copyWith(reducedMotion: value);
        await _prefs.setBool(PrefKeys.reducedMotion, value);
      case SettingKey.quickChatMute:
        state = state.copyWith(quickChatMuted: value);
        await _prefs.setBool(PrefKeys.quickChatMuted, value);
    }
  }

  /// Applies [system] at once (every visible amount reformats) and persists
  /// it.
  Future<void> setNumberSystem(NumberSystem system) async {
    state = state.copyWith(numberSystem: system);
    await _prefs.setString(PrefKeys.numberSystem, system.name);
  }

  /// Applies a volume (0..1) at once. Persists unless [persist] is false
  /// (sliders apply while dragging and persist when released).
  Future<void> setVolume(
    VolumeKey key,
    double value, {
    bool persist = true,
  }) async {
    final v = value.clamp(0.0, 1.0);
    state = switch (key) {
      VolumeKey.sfx => state.copyWith(sfxVolume: v),
      VolumeKey.music => state.copyWith(musicVolume: v),
    };
    if (!persist) return;
    await _prefs.setInt(switch (key) {
      VolumeKey.sfx => PrefKeys.sfxVolume,
      VolumeKey.music => PrefKeys.musicVolume,
    }, (v * 100).round());
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
