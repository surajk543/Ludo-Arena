import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/realtime/backoff.dart';

void main() {
  test('ceiling doubles from 0.5 s and is capped at 30 s', () {
    final b = ReconnectBackoff();
    expect(b.ceilingFor(0), const Duration(milliseconds: 500));
    expect(b.ceilingFor(1), const Duration(seconds: 1));
    expect(b.ceilingFor(2), const Duration(seconds: 2));
    expect(b.ceilingFor(5), const Duration(seconds: 16));
    expect(b.ceilingFor(6), const Duration(seconds: 30));
    expect(b.ceilingFor(60), const Duration(seconds: 30));
  });

  test('full jitter: every delay within [0, ceiling(attempt)]', () {
    for (var seed = 0; seed < 50; seed++) {
      final b = ReconnectBackoff(random: Random(seed));
      for (var attempt = 0; attempt < 20; attempt++) {
        final ceiling = b.ceilingFor(b.attempt);
        final d = b.next();
        expect(d, greaterThanOrEqualTo(Duration.zero));
        expect(d, lessThanOrEqualTo(ceiling));
      }
      expect(b.attempt, 20);
    }
  });

  test('jitter actually spreads delays', () {
    final b = ReconnectBackoff(random: Random(3));
    final delays = <int>{};
    for (var i = 0; i < 20; i++) {
      b.reset();
      for (var k = 0; k < 6; k++) {
        b.next();
      }
      delays.add(b.next().inMilliseconds);
    }
    expect(delays.length, greaterThan(10));
  });

  test('reset returns to the first ceiling', () {
    final b = ReconnectBackoff(random: Random(1));
    for (var i = 0; i < 8; i++) {
      b.next();
    }
    b.reset();
    expect(b.attempt, 0);
    expect(b.next(), lessThanOrEqualTo(const Duration(milliseconds: 500)));
    expect(b.stableAfter, const Duration(seconds: 30));
  });
}
