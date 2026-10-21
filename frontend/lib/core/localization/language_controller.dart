import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_store.dart';
import 'supported_locales.dart';

/// Provides the device locale list (overridable in tests).
final deviceLocalesProvider = Provider<List<Locale>>(
  (ref) => WidgetsBinding.instance.platformDispatcher.locales,
);

/// Owns the app language.
///
/// - Default: the device locale if supported, otherwise English.
/// - Persisted and restored before the first frame.
/// - Applying a language only rebuilds UI; it never signs out or touches the
///   session, wallet, socket or a running match.
class LanguageController extends Notifier<Locale> {
  @override
  Locale build() {
    final stored = SupportedLocales.parse(
      ref.read(preferencesStoreProvider).getString(PrefKeys.locale),
    );
    return stored ??
        SupportedLocales.resolveDevice(ref.read(deviceLocalesProvider));
  }

  /// Whether the user has explicitly picked a language (the first-launch
  /// language screen shows until they do, signed in or not).
  bool get hasExplicitChoice =>
      ref.read(preferencesStoreProvider).getBool(PrefKeys.languageChosen) ??
      false;

  /// Applies and saves [locale]. With [confirm] it also counts as the user's
  /// explicit choice; the first-launch screen previews taps with
  /// `confirm: false` and confirms on Continue ([confirmCurrent]).
  Future<void> setLocale(Locale locale, {bool confirm = true}) async {
    final supported =
        SupportedLocales.match(locale) ?? SupportedLocales.fallback;
    final prefs = ref.read(preferencesStoreProvider);
    final wasChosen = hasExplicitChoice;
    state = supported;
    await prefs.setString(PrefKeys.locale, supported.languageCode);
    if (!confirm) return;
    await prefs.setBool(PrefKeys.languageChosen, true);
    // Listeners (the router, startup dialogs) react to the first choice even
    // when it keeps the current language.
    if (!wasChosen) ref.notifyListeners();
  }

  /// Marks the current (default) language as confirmed without changing it.
  Future<void> confirmCurrent() => setLocale(state);
}

final languageControllerProvider = NotifierProvider<LanguageController, Locale>(
  LanguageController.new,
);
