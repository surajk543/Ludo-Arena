import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_store.dart';

/// User-adjustable, non-sensitive settings (persisted in SharedPreferences).
@immutable
class AppSettings {
  const AppSettings({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.reducedMotion = false,
    this.quickChatMuted = false,
  });

  final bool soundEnabled;
  final bool hapticsEnabled;

  /// User preference; combined with the system setting by `ReducedMotion`.
  final bool reducedMotion;

  /// Hides incoming quick-chat and emote bubbles from other players.
  final bool quickChatMuted;

  AppSettings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? reducedMotion,
    bool? quickChatMuted,
  }) => AppSettings(
    soundEnabled: soundEnabled ?? this.soundEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    quickChatMuted: quickChatMuted ?? this.quickChatMuted,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.soundEnabled == soundEnabled &&
      other.hapticsEnabled == hapticsEnabled &&
      other.reducedMotion == reducedMotion &&
      other.quickChatMuted == quickChatMuted;

  @override
  int get hashCode =>
      Object.hash(soundEnabled, hapticsEnabled, reducedMotion, quickChatMuted);
}

/// Identifies a single setting (used for the `settings_changed` analytics
/// event, which only carries the setting name).
enum SettingKey { sound, haptics, reducedMotion, quickChatMute }

class SettingsController extends Notifier<AppSettings> {
  PreferencesStore get _prefs => ref.read(preferencesStoreProvider);

  @override
  AppSettings build() {
    final p = ref.read(preferencesStoreProvider);
    return AppSettings(
      soundEnabled: p.getBool(PrefKeys.soundEnabled) ?? true,
      hapticsEnabled: p.getBool(PrefKeys.hapticsEnabled) ?? true,
      reducedMotion: p.getBool(PrefKeys.reducedMotion) ?? false,
      quickChatMuted: p.getBool(PrefKeys.quickChatMuted) ?? false,
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
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
