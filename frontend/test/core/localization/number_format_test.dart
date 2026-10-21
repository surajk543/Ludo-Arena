import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:ludo_royale/core/localization/number_format.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());
  tearDown(() => AppNumberFormat.preferredSystem = null);

  const en = Locale('en');
  const hi = Locale('hi');
  const ur = Locale('ur');
  const id = Locale('id');
  const ar = Locale('ar');

  group('formatCoins (en/hi/ur: Indian system)', () {
    test('round lakh values use words', () {
      expect(formatCoins(1000000, en), '10 Lakh');
      expect(formatCoins(1000000, hi), '10 लाख');
      expect(formatCoins(1000000, ur), '10 لاکھ');
      expect(formatCoins(150000, en), '1.5 Lakh');
      expect(formatCoins(1250000, en), '12.5 Lakh');
    });

    test('round crore values use words', () {
      expect(formatCoins(10000000, en), '1 Crore');
      expect(formatCoins(25000000, hi), '2.5 करोड़');
      expect(formatCoins(120000000, ur), '12 کروڑ');
    });

    test('non-round values keep full precision with Indian grouping', () {
      expect(formatCoins(1234567, en), '12,34,567');
      expect(formatCoins(1234567, hi), '12,34,567');
      expect(formatCoins(99999, en), '99,999');
      expect(formatCoins(500, en), '500');
      expect(formatCoins(0, en), '0');
      expect(formatCoins(-1500, en), '-1,500');
    });

    test('compact floors and never overstates', () {
      expect(formatCoinsCompact(1234567, en), '12.34 Lakh');
      expect(formatCoinsCompact(1239999, en), '12.39 Lakh');
      expect(formatCoinsCompact(1000000, hi), '10 लाख');
      expect(formatCoinsCompact(54321, en), '54,321');
      expect(formatCoinsCompact(123456789, en), '12.34 Crore');
    });
  });

  group('formatCoins (id/ar: locale compact)', () {
    test('round millions use compact', () {
      expect(formatCoins(1000000, id), '1\u00a0jt');
      expect(formatCoins(1000000, ar), '1\u00a0مليون');
    });

    test('non-round values use full locale grouping', () {
      expect(formatCoins(1234567, id), '1.234.567');
      expect(formatCoins(1234567, ar), '1,234,567');
      expect(formatCoins(1500, id), '1.500');
    });

    test('compact for chips', () {
      expect(formatCoinsCompact(1234567, id), '1,23\u00a0jt');
      expect(formatCoinsCompact(5000, id), '5.000');
    });
  });

  test('full grouping', () {
    expect(formatNumberFull(1000000, en), '10,00,000');
    expect(formatNumberFull(1000000, id), '1.000.000');
    expect(formatNumberFull(1000000, ar), '1,000,000');
  });

  group('number system choice', () {
    const indian = NumberSystem.indian;
    const intl = NumberSystem.international;

    test('defaults follow the language (the pre-setting behaviour)', () {
      for (final l in [en, hi, ur]) {
        expect(AppNumberFormat.defaultSystemFor(l), indian, reason: '$l');
        expect(AppNumberFormat.systemFor(l), indian, reason: '$l');
      }
      for (final l in [id, ar]) {
        expect(AppNumberFormat.defaultSystemFor(l), intl, reason: '$l');
        expect(AppNumberFormat.systemFor(l), intl, reason: '$l');
      }
    });

    test(
      'the user choice applies to every locale; an explicit system wins',
      () {
        AppNumberFormat.preferredSystem = intl;
        expect(formatCoins(1000000, en), '1M');
        expect(formatCoinsCompact(1234567, hi), '1.23 मिलियन');
        expect(formatNumberFull(100000, ur), '100,000');
        expect(formatCoins(1000000, en, system: indian), '10 Lakh');

        AppNumberFormat.preferredSystem = indian;
        expect(formatCoins(1000000, id), '10 lakh');
        expect(formatNumberFull(1234567, ar), '12,34,567');
        expect(formatCoins(1000000, id, system: intl), '1 jt');

        AppNumberFormat.preferredSystem = null;
        expect(formatCoins(1000000, en), '10 Lakh');
        expect(formatCoins(1000000, id), '1 jt');
      },
    );

    test('NumberSystem.parse', () {
      expect(NumberSystem.parse('indian'), indian);
      expect(NumberSystem.parse('international'), intl);
      expect(NumberSystem.parse(null), isNull);
      expect(NumberSystem.parse('roman'), isNull);
    });
  });

  group('Indian system across sizes', () {
    const s = NumberSystem.indian;
    String full(int v, [Locale l = en]) => formatNumberFull(v, l, system: s);
    String coins(int v, [Locale l = en]) => formatCoins(v, l, system: s);
    String compact(int v, [Locale l = en]) =>
        formatCoinsCompact(v, l, system: s);

    test('full grouping: last three, then pairs', () {
      expect(full(0), '0');
      expect(full(999), '999');
      expect(full(1000), '1,000');
      expect(full(99999), '99,999');
      expect(full(100000), '1,00,000');
      expect(full(1000000), '10,00,000');
      expect(full(10000000), '1,00,00,000');
      expect(full(1000000000), '1,00,00,00,000');
      expect(full(-1500), '-1,500');
    });

    test('coins: words only for round lakh/crore values', () {
      expect(coins(999), '999');
      expect(coins(1000), '1,000');
      expect(coins(99999), '99,999');
      expect(coins(100000), '1 Lakh');
      expect(coins(1000000), '10 Lakh');
      expect(coins(10000000), '1 Crore');
      expect(coins(1000000000), '100 Crore');
      expect(coins(1234567), '12,34,567');
      expect(coins(-1000000), '-10 Lakh');
    });

    test('compact: exact below a lakh, floored words above', () {
      expect(compact(999), '999');
      expect(compact(99999), '99,999');
      expect(compact(100000), '1 Lakh');
      expect(compact(1234567), '12.34 Lakh');
      expect(compact(10000000), '1 Crore');
      expect(compact(1000000000), '100 Crore');
      expect(compact(123456789012), '12,345.67 Crore');
      expect(compact(-1234567), '-12.34 Lakh');
    });

    test('other locales keep their digits, separators and words', () {
      expect(full(1234567, hi), '12,34,567');
      expect(coins(1000000, hi), '10 लाख');
      expect(coins(1000000, ur), '10 لاکھ');
      expect(full(1234567, id), '12.34.567');
      expect(coins(150000, id), '1,5 lakh');
      expect(compact(1234567, id), '12,34 lakh');
      expect(full(1234567, ar), '12,34,567');
      expect(coins(10000000, ar), '1 كرور');
      expect(compact(1234567, ar), '12.34 لك');
    });
  });

  group('International system across sizes', () {
    const s = NumberSystem.international;
    String full(int v, [Locale l = en]) => formatNumberFull(v, l, system: s);
    String coins(int v, [Locale l = en]) => formatCoins(v, l, system: s);
    String compact(int v, [Locale l = en]) =>
        formatCoinsCompact(v, l, system: s);

    test('full grouping: groups of three', () {
      expect(full(0), '0');
      expect(full(999), '999');
      expect(full(1000), '1,000');
      expect(full(99999), '99,999');
      expect(full(100000), '100,000');
      expect(full(1000000), '1,000,000');
      expect(full(10000000), '10,000,000');
      expect(full(1000000000), '1,000,000,000');
      expect(full(-1500), '-1,500');
    });

    test('coins: words only for round millions/billions', () {
      expect(coins(999), '999');
      expect(coins(1000), '1,000');
      expect(coins(99999), '99,999');
      expect(coins(100000), '100,000');
      expect(coins(1000000), '1M');
      expect(coins(1500000), '1.5M');
      expect(coins(10000000), '10M');
      expect(coins(1000000000), '1B');
      expect(coins(2500000000), '2.5B');
      expect(coins(1234567), '1,234,567');
      expect(coins(-1000000), '-1M');
    });

    test('compact: exact below ten thousand, floored K/M/B above', () {
      expect(compact(999), '999');
      expect(compact(9999), '9,999');
      expect(compact(10000), '10K');
      expect(compact(54321), '54.32K');
      expect(compact(99999), '99.99K');
      expect(compact(100000), '100K');
      expect(compact(1234567), '1.23M');
      expect(compact(1239999), '1.23M');
      expect(compact(10000000), '10M');
      expect(compact(123456789), '123.45M');
      expect(compact(1234567890), '1.23B');
      expect(compact(-54321), '-54.32K');
    });

    test('other locales keep their digits, separators and words', () {
      expect(full(1234567, hi), '1,234,567');
      expect(coins(1000000, hi), '1 मिलियन');
      expect(coins(1000000000, hi), '1 बिलियन');
      expect(compact(54321, hi), '54.32 हज़ार');
      expect(full(1234567, ur), '1,234,567');
      expect(coins(1000000, ur), '1 ملین');
      expect(full(-1500, ur), '‎-1,500');
      expect(full(1234567, id), '1.234.567');
      expect(coins(1000000000, id), '1 M');
      expect(compact(54321, id), '54,32 rb');
      expect(full(1234567, ar), '1,234,567');
      expect(coins(1000000000, ar), '1 مليار');
      expect(coins(-1000000, ar), '‎-1 مليون');
      expect(compact(54321, ar), '54.32 ألف');
    });

    test('id/ar defaults match the previous intl compact output', () {
      String old(int v, Locale l) => (NumberFormat.compact(
        locale: l.languageCode,
      )..maximumFractionDigits = 2).format(v);
      const samples = [
        10000,
        54321,
        999999,
        1000000,
        1230000,
        1234567,
        12340000,
        123456789,
        999990000,
        1000000000,
        1230000000,
        12345678901,
        -1000000,
        -54321,
      ];
      int unitOf(int abs) => abs >= 1000000000
          ? 1000000000
          : abs >= 1000000
          ? 1000000
          : 1000;
      for (final l in [id, ar]) {
        for (final v in samples) {
          final unit = unitOf(v.abs());
          final step = unit ~/ 100;
          // Chips: floored to two decimals, then compact.
          expect(
            formatCoinsCompact(v, l),
            old((v ~/ step) * step, l),
            reason: 'compact $v $l',
          );
          if (v.abs() >= 1000000 && v % step == 0) {
            expect(formatCoins(v, l), old(v, l), reason: 'coins $v $l');
          }
        }
      }
    });
  });

  test('dates use the app locale', () {
    final t = DateTime(2026, 10, 21, 15, 30);
    expect(AppNumberFormat.dateTime(t, en), contains('2026'));
    expect(AppNumberFormat.time(t, en).toLowerCase(), contains('3:30'));
    expect(AppNumberFormat.dateTime(t, hi), isNotEmpty);
  });
}
