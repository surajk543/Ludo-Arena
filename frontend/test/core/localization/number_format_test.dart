import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/core/localization/number_format.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());

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

  test('dates use the app locale', () {
    final t = DateTime(2026, 10, 21, 15, 30);
    expect(AppNumberFormat.dateTime(t, en), contains('2026'));
    expect(AppNumberFormat.time(t, en).toLowerCase(), contains('3:30'));
    expect(AppNumberFormat.dateTime(t, hi), isNotEmpty);
  });
}
