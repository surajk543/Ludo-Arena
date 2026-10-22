import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/features/ludo/presentation/board/mini_ludo_board.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/mini_snakes_board.dart';
import 'package:ludo_arena/shared/game_visuals/game_visuals.dart';

/// Every renderable id from docs/cosmetics-catalog.md.
const _catalog = {
  CosmeticVisualKind.dice: [
    'dice_classic',
    'dice_neon',
    'dice_golden',
    'dice_autumn',
  ],
  CosmeticVisualKind.token: [
    'token_classic',
    'token_gem',
    'token_royal',
    'token_crown',
  ],
  CosmeticVisualKind.ludoBoard: [
    'ludo_board_classic',
    'ludo_board_midnight',
    'ludo_board_royal',
  ],
  CosmeticVisualKind.snakesBoard: [
    'snakes_board_classic',
    'snakes_board_jungle',
    'snakes_board_candy',
  ],
  CosmeticVisualKind.trail: ['trail_none', 'trail_sparkle', 'trail_comet'],
  CosmeticVisualKind.victory: [
    'victory_confetti',
    'victory_fireworks',
    'victory_crown',
  ],
};

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('CosmeticVisuals', () {
    test('covers exactly the catalog ids, starter first', () {
      expect(CosmeticVisuals.ids, _catalog);
      for (final e in _catalog.entries) {
        expect(CosmeticVisuals.starters[e.key], e.value.first);
        for (final id in e.value) {
          expect(CosmeticVisuals.kindOf(id), e.key);
          expect(CosmeticVisuals.isKnown(id), isTrue);
          expect(CosmeticVisuals.resolve(e.key, id), id);
        }
      }
    });

    test('unknown ids fall back to the starter of their kind', () {
      expect(CosmeticVisuals.dice('dice_lava'), 'dice_classic');
      expect(CosmeticVisuals.token('token_x'), 'token_classic');
      expect(CosmeticVisuals.ludoBoard(null), 'ludo_board_classic');
      expect(
        CosmeticVisuals.snakesBoard('snakes_board_x'),
        'snakes_board_classic',
      );
      expect(CosmeticVisuals.trail('trail_rainbow'), 'trail_none');
      expect(CosmeticVisuals.victory('victory_x'), 'victory_confetti');
      expect(CosmeticVisuals.isKnown('dice_lava'), isFalse);
      expect(CosmeticVisuals.canPreview('dice_lava'), isTrue);
      expect(CosmeticVisuals.kindOf('frame_gold'), isNull);
      expect(CosmeticVisuals.canPreview('emote_wave'), isFalse);
    });
  });

  group('previews render in light and dark', () {
    for (final brightness in Brightness.values) {
      testWidgets('all ids (${brightness.name})', (tester) async {
        final ids = [
          for (final l in _catalog.values) ...l,
          'dice_lava',
          'token_x',
          'frame_gold',
        ];
        await tester.pumpWidget(
          _app(
            SingleChildScrollView(
              child: Wrap(
                children: [
                  for (final id in ids)
                    CosmeticPreview(id, color: SeatColor.green, size: 90),
                ],
              ),
            ),
            brightness: brightness,
          ),
        );
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(DiceSkinPreview), findsNWidgets(5));
        expect(find.byType(TokenSkinPreview), findsNWidgets(5));
        expect(find.byType(MiniLudoBoard), findsNWidgets(3));
        expect(find.byType(MiniSnakesBoard), findsNWidgets(3));
        expect(find.byType(TrailPreview), findsNWidgets(3));
        expect(find.byType(VictoryPreview), findsNWidgets(3));
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('animated dice preview rolls and stops cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const DiceSkinPreview('dice_neon', animate: true)),
      );
      await tester.pump(const Duration(milliseconds: 2700));
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('static previews do not tick (reduced motion)', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TrailPreview('trail_comet', animate: true),
              VictoryPreview('victory_fireworks', size: 80),
              DiceSkinPreview('dice_golden'),
              TokenSkinPreview('token_crown', SeatColor.blue),
              BoardThemePreview('snakes_board_candy', size: 120),
              BoardThemePreview('ludo_board_royal', size: 120),
            ],
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('trail preview loops while animating', (tester) async {
      await tester.pumpWidget(
        _app(const TrailPreview('trail_sparkle', color: SeatColor.yellow)),
      );
      for (var i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.hasRunningAnimations, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
