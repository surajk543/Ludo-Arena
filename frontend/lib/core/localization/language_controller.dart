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

  /// Whether the user has explicitly picked a language (first-run onboarding
  /// shows the picker until they do).
  bool get hasExplicitChoice =>
      ref.read(preferencesStoreProvider).getBool(PrefKeys.languageChosen) ??
      false;

  Future<void> setLocale(Locale locale) async {
    final supported =
        SupportedLocales.match(locale) ?? SupportedLocales.fallback;
    final prefs = ref.read(preferencesStoreProvider);
    state = supported;
    await prefs.setString(PrefKeys.locale, supported.languageCode);
    await prefs.setBool(PrefKeys.languageChosen, true);
  }

  /// Marks the current (default) language as confirmed without changing it.
  Future<void> confirmCurrent() => setLocale(state);
}

final languageControllerProvider = NotifierProvider<LanguageController, Locale>(
  LanguageController.new,
);
