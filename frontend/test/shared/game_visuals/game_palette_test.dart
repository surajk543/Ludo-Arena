import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/shared/game_visuals/game_palette.dart';

void main() {
  group('SeatColor', () {
    test('order and parsing follow the protocol', () {
      expect(SeatColor.values.map((c) => c.name), [
        'red',
        'green',
        'yellow',
        'blue',
      ]);
      expect(SeatColor.values.map((c) => c.colorIndex), [0, 1, 2, 3]);
      expect(SeatColor.fromName('yellow'), SeatColor.yellow);
      expect(SeatColor.fromName(' Blue '), SeatColor.blue);
      expect(() => SeatColor.fromName('purple'), throwsArgumentError);
      expect(SeatColor.tryFromName('purple'), isNull);
      expect(SeatColor.tryFromName(null), isNull);
    });

    test('seat → color mapping per player count', () {
      expect(SeatColor.forPlayerCount(2), [SeatColor.red, SeatColor.yellow]);
      expect(SeatColor.forPlayerCount(3), [
        SeatColor.red,
        SeatColor.green,
        SeatColor.yellow,
      ]);
      expect(SeatColor.forPlayerCount(4), SeatColor.values);
    });
  });

  group('GamePalette', () {
    test('built-in seat colors match the spec', () {
      expect(GamePalette.light.seat(SeatColor.red), const Color(0xFFE5484D));
      expect(GamePalette.light.seat(SeatColor.green), const Color(0xFF30A46C));
      expect(GamePalette.light.seat(SeatColor.yellow), const Color(0xFFF5B800));
      expect(GamePalette.light.seat(SeatColor.blue), const Color(0xFF3E63DD));
      expect(GamePalette.dark.seat(SeatColor.red), const Color(0xFFFF6369));
      expect(GamePalette.dark.seat(SeatColor.green), const Color(0xFF3DD68C));
      expect(GamePalette.dark.seat(SeatColor.yellow), const Color(0xFFFFD43B));
      expect(GamePalette.dark.seat(SeatColor.blue), const Color(0xFF6E8BFF));
    });

    test('derived shades are ordered light → dark and readable', () {
      for (final palette in [GamePalette.light, GamePalette.dark]) {
        for (final c in SeatColor.values) {
          final s = palette.shades(c);
          expect(
            s.soft.computeLuminance(),
            greaterThan(s.base.computeLuminance()),
          );
          expect(
            s.shade.computeLuminance(),
            lessThan(s.base.computeLuminance()),
          );
          expect(
            s.deep.computeLuminance(),
            lessThan(s.shade.computeLuminance()),
          );
          expect(s.glow.a, lessThan(1));
        }
      }
      // Yellow takes dark content, the others white.
      expect(
        GamePalette.light.shades(SeatColor.yellow).onColor,
        isNot(Colors.white),
      );
      expect(GamePalette.light.shades(SeatColor.blue).onColor, Colors.white);
    });

    testWidgets('of() falls back by brightness and prefers the extension', (
      tester,
    ) async {
      late GamePalette light;
      late GamePalette dark;
      late GamePalette custom;
      final registered = GamePalette.light.copyWith(
        red: const Color(0xFFAA0000),
      );
      Widget probe(ThemeData theme, void Function(GamePalette) out) =>
          MaterialApp(
            theme: theme,
            themeAnimationDuration: Duration.zero,
            home: Builder(
              builder: (context) {
                out(GamePalette.of(context));
                return const SizedBox();
              },
            ),
          );
      await tester.pumpWidget(
        probe(ThemeData(brightness: Brightness.light), (p) => light = p),
      );
      await tester.pumpWidget(
        probe(ThemeData(brightness: Brightness.dark), (p) => dark = p),
      );
      await tester.pumpWidget(
        probe(ThemeData(extensions: [registered]), (p) => custom = p),
      );
      expect(light, same(GamePalette.light));
      expect(dark, same(GamePalette.dark));
      expect(custom.seat(SeatColor.red), const Color(0xFFAA0000));
    });

    test('lerp and copyWith', () {
      final mid = GamePalette.light.lerp(GamePalette.dark, 0.5);
      expect(
        mid.seat(SeatColor.red),
        Color.lerp(GamePalette.light.red, GamePalette.dark.red, 0.5),
      );
      expect(GamePalette.light.lerp(null, 0.5), same(GamePalette.light));
      final copy = GamePalette.dark.copyWith();
      expect(copy, GamePalette.dark);
      expect(copy.hashCode, GamePalette.dark.hashCode);
      expect(GamePalette.light == GamePalette.dark, isFalse);
    });
  });
}
