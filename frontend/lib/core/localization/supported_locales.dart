import 'dart:ui';

/// The single list of languages the app ships. Adding a language: add it
/// here, add `<code>.arb` to every `lib/l10n/parts/<area>/`, add the code to
/// `tool/merge_arb.dart`'s `locales`, then merge + gen-l10n.
abstract final class SupportedLocales {
  static const Locale english = Locale('en');
  static const Locale hindi = Locale('hi');
  static const Locale urdu = Locale('ur');
  static const Locale indonesian = Locale('id');
  static const Locale arabic = Locale('ar');

  /// Display order in language pickers.
  static const List<Locale> all = [english, hindi, urdu, arabic, indonesian];

  static const Locale fallback = english;

  static const Set<String> rtlLanguages = {'ar', 'ur'};

  static bool isRtl(Locale locale) =>
      rtlLanguages.contains(locale.languageCode);

  /// Exact language match against [all], ignoring region/script.
  static Locale? match(Locale? locale) {
    if (locale == null) return null;
    for (final l in all) {
      if (l.languageCode == locale.languageCode) return l;
    }
    return null;
  }

  /// First supported locale from the device preference list, else English.
  static Locale resolveDevice(List<Locale> deviceLocales) {
    for (final l in deviceLocales) {
      final m = match(l);
      if (m != null) return m;
    }
    return fallback;
  }

  static Locale? parse(String? code) {
    if (code == null || code.isEmpty) return null;
    return match(Locale(code.split(RegExp('[-_]')).first));
  }
}
