import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for non-sensitive preferences. Never store tokens, secrets, room
/// codes or identifiers here (those belong in `SecureSessionStore`).
abstract final class PrefKeys {
  static const themeMode = 'ui.theme_mode';
  static const locale = 'ui.locale';
  static const languageChosen = 'ui.language_chosen';
  static const soundEnabled = 'settings.sound';
  static const hapticsEnabled = 'settings.haptics';
  static const reducedMotion = 'settings.reduced_motion';
  static const quickChatMuted = 'settings.quick_chat_muted';
  static const analyticsConsent = 'analytics.consent';
  static const cachedPolicy = 'policy.cached';
  static const optionalUpdateDeferredUntil = 'policy.optional_deferred_until';
  static const optionalUpdateDeferredVersion =
      'policy.optional_deferred_version';
  static const lastQuickPlay = 'home.last_quick_play';
}

/// Thin typed wrapper over [SharedPreferences] (loaded once before the first
/// frame so reads are synchronous).
class PreferencesStore {
  PreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PreferencesStore> load() async =>
      PreferencesStore(await SharedPreferences.getInstance());

  String? getString(String key) => _prefs.getString(key);
  bool? getBool(String key) => _prefs.getBool(key);
  int? getInt(String key) => _prefs.getInt(key);

  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}

/// Overridden in `bootstrap.dart` with the loaded store (and in tests, after
/// `SharedPreferences.setMockInitialValues`).
final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => throw UnimplementedError(
    'preferencesStoreProvider must be overridden at bootstrap',
  ),
);
