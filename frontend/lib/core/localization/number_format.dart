import 'dart:ui';

import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart';

/// Locale-aware number / coin / date formatting.
///
/// - **en, hi, ur**: Indian grouping (`12,34,567`) and lakh/crore words for
///   large values (`10 Lakh`, `10 लाख`, `10 لاکھ`, `1.5 Crore`).
/// - **id, ar** (and anything else): the locale's own grouping and compact
///   formats (`1 jt`, `1 مليون`).
/// - Digits follow the locale's default numbering system in `intl`.
abstract final class AppNumberFormat {
  static const int lakh = 100000;
  static const int crore = 10000000;

  static bool usesIndianSystem(Locale locale) =>
      const {'en', 'hi', 'ur'}.contains(locale.languageCode);

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

  /// Full precision with locale grouping: `12,34,567` (en/hi/ur),
  /// `1.234.567` (id), `1,234,567` (ar).
  static String full(int value, Locale locale) {
    if (usesIndianSystem(locale)) return _indianGrouping(value, locale);
    return NumberFormat.decimalPattern(_tag(locale)).format(value);
  }

  /// Large **round** values use words (`10 Lakh`); anything that would lose
  /// precision is shown in full (`12,34,567`). id/ar use compact formats for
  /// values ≥ 1,000,000 when exact (`1 jt`).
  static String coins(int value, Locale locale) {
    final abs = value.abs();
    if (usesIndianSystem(locale)) {
      if (abs >= crore && _exactIn(abs, crore)) {
        return _indianWords(value, crore, locale);
      }
      if (abs >= lakh && _exactIn(abs, lakh)) {
        return _indianWords(value, lakh, locale);
      }
      return full(value, locale);
    }
    if (abs >= 1000000) {
      final compact = NumberFormat.compact(locale: _tag(locale))
        ..maximumFractionDigits = 2;
      final s = compact.format(value);
      // Only use compact when it round-trips exactly.
      if (_exactIn(abs, _compactUnit(abs))) return s;
    }
    return full(value, locale);
  }

  /// Always compact for tight spaces (balance chips): floors to two decimals
  /// so a balance is never overstated (`12,34,567` → `12.34 Lakh`).
  static String coinsCompact(int value, Locale locale) {
    final abs = value.abs();
    if (usesIndianSystem(locale)) {
      if (abs >= crore) return _indianWords(value, crore, locale, floor: true);
      if (abs >= lakh) return _indianWords(value, lakh, locale, floor: true);
      return full(value, locale);
    }
    if (abs >= 10000) {
      final unit = _compactUnit(abs);
      final floored = (value ~/ (unit ~/ 100)) * (unit ~/ 100);
      final compact = NumberFormat.compact(locale: _tag(locale))
        ..maximumFractionDigits = 2;
      return compact.format(floored);
    }
    return full(value, locale);
  }

  static int _compactUnit(int abs) {
    if (abs >= 1000000000) return 1000000000;
    if (abs >= 1000000) return 1000000;
    return 1000;
  }

  /// True when [value] / [unit] has at most two decimals.
  static bool _exactIn(int value, int unit) => value % (unit ~/ 100) == 0;

  static String _indianWords(
    int value,
    int unit,
    Locale locale, {
    bool floor = false,
  }) {
    final hundredths = floor
        ? (value.abs() * 100) ~/ unit
        : ((value.abs() * 100) / unit).round();
    final whole = hundredths ~/ 100;
    final frac = hundredths % 100;
    var number = full(whole, locale);
    if (frac != 0) {
      final f = frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '');
      final sep = NumberFormat.decimalPattern(_tag(locale)).symbols.DECIMAL_SEP;
      number = '$number$sep$f';
    }
    if (value < 0) number = '-$number';
    final l10n = lookupAppLocalizations(_l10nLocale(locale));
    return unit == crore ? l10n.numberCrore(number) : l10n.numberLakh(number);
  }

  static Locale _l10nLocale(Locale locale) {
    for (final l in AppLocalizations.supportedLocales) {
      if (l.languageCode == locale.languageCode) return l;
    }
    return const Locale('en');
  }

  /// `12,34,567`: last three digits, then groups of two.
  static String _indianGrouping(int value, Locale locale) {
    final symbols = NumberFormat.decimalPattern(_tag(locale)).symbols;
    final negative = value < 0;
    final digits = value.abs().toString();
    String grouped;
    if (digits.length <= 3) {
      grouped = digits;
    } else {
      final last3 = digits.substring(digits.length - 3);
      var rest = digits.substring(0, digits.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      grouped = '${parts.join(symbols.GROUP_SEP)}${symbols.GROUP_SEP}$last3';
    }
    grouped = _localizeDigits(grouped, symbols.ZERO_DIGIT);
    return negative ? '${symbols.MINUS_SIGN}$grouped' : grouped;
  }

  static String _localizeDigits(String s, String zeroDigit) {
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
String formatCoins(int value, Locale locale) =>
    AppNumberFormat.coins(value, locale);

/// Compact coin formatting for chips. See [AppNumberFormat.coinsCompact].
String formatCoinsCompact(int value, Locale locale) =>
    AppNumberFormat.coinsCompact(value, locale);

/// Full-precision grouping. See [AppNumberFormat.full].
String formatNumberFull(int value, Locale locale) =>
    AppNumberFormat.full(value, locale);
