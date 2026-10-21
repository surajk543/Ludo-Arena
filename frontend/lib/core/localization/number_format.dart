import 'dart:ui';

import 'package:intl/intl.dart';
import 'package:intl/number_symbols.dart';

import '../../l10n/generated/app_localizations.dart';

/// How large numbers are grouped and abbreviated (Settings → Number format).
enum NumberSystem {
  /// `12,34,567`, `10 Lakh`, `1.5 Crore`.
  indian,

  /// `1,234,567`, `1M`, `1.5B`.
  international;

  static NumberSystem? parse(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Locale-aware number / coin / date formatting.
///
/// The [NumberSystem] decides grouping and the compact words; the locale
/// decides digits, separators and the words' language:
///
/// - **Indian**: `12,34,567` and lakh/crore words for large values
///   (`10 Lakh`, `10 लाख`, `10 لاکھ`, `1.5 Crore`).
/// - **International**: `1,234,567` and thousand/million/billion words
///   (`1M`, `1 jt`, `1 مليون`).
///
/// The system is the user's choice ([preferredSystem], kept in sync with the
/// setting by `NumberSystemDelegate`) or, until they pick one, follows the
/// language: Indian for en/hi/ur, international otherwise. Every formatter
/// also takes an explicit `system` (previews in Settings, tests).
///
/// Digits follow the locale's default numbering system in `intl`.
abstract final class AppNumberFormat {
  static const int thousand = 1000;
  static const int lakh = 100000;
  static const int million = 1000000;
  static const int crore = 10000000;
  static const int billion = 1000000000;

  /// The user's explicit choice; null follows the language
  /// ([defaultSystemFor]). Set only by `NumberSystemDelegate`, which also
  /// rebuilds every widget that reads the app locale when it changes.
  static NumberSystem? preferredSystem;

  /// The system used when the user has not chosen one: Indian for en/hi/ur
  /// (the behaviour before the setting existed), international otherwise.
  static NumberSystem defaultSystemFor(Locale locale) =>
      const {'en', 'hi', 'ur'}.contains(locale.languageCode)
      ? NumberSystem.indian
      : NumberSystem.international;

  /// The effective system: [system] if given, else the user's choice, else
  /// the language default.
  static NumberSystem systemFor(Locale locale, [NumberSystem? system]) =>
      system ?? preferredSystem ?? defaultSystemFor(locale);

  static String _tag(Locale locale) => switch (locale.languageCode) {
    'en' => 'en_IN',
    final code =>
      Intl.verifiedLocale(
            code,
            NumberFormat.localeExists,
            onFailure: (_) => 'en',
          ) ??
          'en',
  };

  static NumberSymbols _symbols(Locale locale) =>
      NumberFormat.decimalPattern(_tag(locale)).symbols;

  /// A whole percentage in the locale's format (`80%`, `80 %`, `٨٠٪`).
  static String percent(int value, Locale locale) =>
      NumberFormat.percentPattern(_tag(locale)).format(value / 100);

  /// Full precision with the system's grouping and the locale's symbols:
  /// Indian `12,34,567` (id: `12.34.567`), international `1,234,567`
  /// (id: `1.234.567`).
  static String full(int value, Locale locale, {NumberSystem? system}) =>
      _group(
        value,
        locale,
        indian: systemFor(locale, system) == NumberSystem.indian,
      );

  /// Large **round** values use words (`10 Lakh`, `1M`); anything that
  /// would lose precision is shown in full (`12,34,567`). Indian words start
  /// at one lakh, international ones at one million.
  static String coins(int value, Locale locale, {NumberSystem? system}) {
    final s = systemFor(locale, system);
    final abs = value.abs();
    if (s == NumberSystem.indian) {
      if (abs >= crore && _exactIn(abs, crore)) {
        return _words(value, crore, locale, s);
      }
      if (abs >= lakh && _exactIn(abs, lakh)) {
        return _words(value, lakh, locale, s);
      }
    } else if (abs >= million) {
      final unit = abs >= billion ? billion : million;
      if (_exactIn(abs, unit)) return _words(value, unit, locale, s);
    }
    return full(value, locale, system: s);
  }

  /// Always compact for tight spaces (balance chips): floors to two decimals
  /// so a balance is never overstated (`12,34,567` → `12.34 Lakh`,
  /// `1,234,567` → `1.23M`). Indian stays exact below one lakh (`54,321`),
  /// international below ten thousand (`9,999`, then `54.32K`).
  static String coinsCompact(int value, Locale locale, {NumberSystem? system}) {
    final s = systemFor(locale, system);
    final abs = value.abs();
    if (s == NumberSystem.indian) {
      if (abs >= crore) return _words(value, crore, locale, s, floor: true);
      if (abs >= lakh) return _words(value, lakh, locale, s, floor: true);
      return full(value, locale, system: s);
    }
    if (abs >= 10 * thousand) {
      final unit = abs >= billion
          ? billion
          : abs >= million
          ? million
          : thousand;
      return _words(value, unit, locale, s, floor: true);
    }
    return full(value, locale, system: s);
  }

  /// True when [value] / [unit] has at most two decimals.
  static bool _exactIn(int value, int unit) => value % (unit ~/ 100) == 0;

  /// `value / unit` with up to two decimals plus the unit word
  /// (`12.5 Lakh`, `1.23M`, `1,23 jt`).
  static String _words(
    int value,
    int unit,
    Locale locale,
    NumberSystem system, {
    bool floor = false,
  }) {
    final hundredths = floor
        ? (value.abs() * 100) ~/ unit
        : ((value.abs() * 100) / unit).round();
    final whole = hundredths ~/ 100;
    final frac = hundredths % 100;
    final symbols = _symbols(locale);
    var number = full(whole, locale, system: system);
    if (frac != 0) {
      final f = frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '');
      number = '$number${symbols.DECIMAL_SEP}${_localizeDigits(f, symbols)}';
    }
    if (value < 0) number = '${symbols.MINUS_SIGN}$number';
    final l10n = lookupAppLocalizations(_l10nLocale(locale));
    return switch (unit) {
      crore => l10n.numberCrore(number),
      lakh => l10n.numberLakh(number),
      billion => l10n.numberBillion(number),
      million => l10n.numberMillion(number),
      _ => l10n.numberThousand(number),
    };
  }

  static Locale _l10nLocale(Locale locale) {
    for (final l in AppLocalizations.supportedLocales) {
      if (l.languageCode == locale.languageCode) return l;
    }
    return const Locale('en');
  }

  /// Indian: last three digits, then groups of two (`12,34,567`).
  /// International: groups of three (`1,234,567`).
  static String _group(int value, Locale locale, {required bool indian}) {
    final symbols = _symbols(locale);
    final digits = value.abs().toString();
    final parts = <String>[];
    var rest = digits;
    var size = 3;
    while (rest.length > size) {
      parts.insert(0, rest.substring(rest.length - size));
      rest = rest.substring(0, rest.length - size);
      if (indian) size = 2;
    }
    parts.insert(0, rest);
    final grouped = _localizeDigits(parts.join(symbols.GROUP_SEP), symbols);
    return value < 0 ? '${symbols.MINUS_SIGN}$grouped' : grouped;
  }

  static String _localizeDigits(String s, NumberSymbols symbols) {
    final zeroDigit = symbols.ZERO_DIGIT;
    if (zeroDigit == '0') return s;
    final zero = zeroDigit.codeUnitAt(0);
    return String.fromCharCodes(
      s.codeUnits.map((c) => c >= 48 && c <= 57 ? zero + (c - 48) : c),
    );
  }

  static String _dateTag(Locale locale) {
    try {
      return Intl.verifiedLocale(
            locale.languageCode,
            DateFormat.localeExists,
            onFailure: (_) => 'en',
          ) ??
          'en';
    } catch (_) {
      // Locale data not initialized (bootstrap calls initializeDateFormatting).
      return 'en';
    }
  }

  /// Medium date + short time in the app locale, e.g. `21 Oct 2026, 3:30 pm`.
  static String dateTime(DateTime t, Locale locale) {
    final tag = _dateTag(locale);
    return '${DateFormat.yMMMd(tag).format(t)}, ${DateFormat.jm(tag).format(t)}';
  }

  /// Short time only, e.g. `3:30 pm`.
  static String time(DateTime t, Locale locale) =>
      DateFormat.jm(_dateTag(locale)).format(t);
}

/// Spec helper: exact-or-words coin formatting. See [AppNumberFormat.coins].
String formatCoins(int value, Locale locale, {NumberSystem? system}) =>
    AppNumberFormat.coins(value, locale, system: system);

/// Compact coin formatting for chips. See [AppNumberFormat.coinsCompact].
String formatCoinsCompact(int value, Locale locale, {NumberSystem? system}) =>
    AppNumberFormat.coinsCompact(value, locale, system: system);

/// Full-precision grouping. See [AppNumberFormat.full].
String formatNumberFull(int value, Locale locale, {NumberSystem? system}) =>
    AppNumberFormat.full(value, locale, system: system);
