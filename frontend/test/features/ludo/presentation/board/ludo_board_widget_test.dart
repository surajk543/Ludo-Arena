import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/features/ludo/presentation/board/ludo_board.dart';
import 'package:ludo_royale/features/ludo/presentation/board/ludo_board_controller.dart';
import 'package:ludo_royale/features/ludo/presentation/board/ludo_board_theme.dart';
import 'package:ludo_royale/features/ludo/presentation/board/ludo_geometry.dart';
import 'package:ludo_royale/features/ludo/presentation/board/mini_ludo_board.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:ludo_royale/shared/game_visuals/game_palette.dart';
import 'package:ludo_royale/shared/game_visuals/tokens/token_renderer.dart';
import 'package:ludo_royale/shared/game_visuals/trails/trail_renderer.dart';

const _boardKey = Key('board');

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  TextDirection direction = TextDirection.ltr,
  double size = 400,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.square(key: _boardKey, dimension: size, child: child),
        ),
      ),
    ),
  );
}

LudoBoardController _busy({
  int tokens = 4,
  List<SeatColor> colors = SeatColor.values,
}) {
  final all = [
    [-1, 5, 8, 56],
    [13, 13, 52, -1],
    [0, 26, 40, 56],
    [10, 10, 10, -1],
  ];
  return LudoBoardController(
      seatColors: colors,
      tokensPerPlayer: tokens,
      positions: [
        for (var s = 0; s < colors.length; s++) all[s].sublist(0, tokens),
      ],
    )
    ..setTurnSeat(0)
    ..setInteraction(seat: 0, legalTokens: {0, 1});
}

/// Global pixel position of grid point [grid] for a board of [size] at the
/// top-left of the screen.
Offset _gridToGlobal(WidgetTester tester, Offset grid) {
  final box = tester.getRect(find.byKey(_boardKey));
  final layout = LudoBoardLayout.fit(box.size);
  return box.topLeft + layout.toPx(grid);
}

void main() {
  group('renders every theme', () {
    for (final theme in [...LudoBoardThemes.all, 'ludo_board_unknown']) {
      for (final brightness in Brightness.values) {
        for (final size in [280.0, 420.0]) {
          testWidgets('$theme ${brightness.name} ${size.toInt()}px', (
            tester,
          ) async {
            final c = _busy();
            await tester.pumpWidget(
              _app(
                LudoBoard(
                  controller: c,
                  boardTheme: theme,
                  tokenSkins: TokenSkins.all,
                  trails: TrailStyles.all,
                ),
                brightness: brightness,
                size: size,
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            expect(find.byType(LudoBoard), findsOneWidget);
            // Animate a move with a trail to exercise the token layer.
            final f = c.animateMove(seat: 0, token: 1, from: 5, to: 9);
            for (var i = 0; i < 90; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            await f;
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            c.dispose();
          });
        }
      }
    }

    testWidgets('Quick Ludo with two players', (tester) async {
      final c = _busy(
        tokens: 2,
        colors: const [SeatColor.red, SeatColor.yellow],
      );
      await tester.pumpWidget(_app(LudoBoard(controller: c), size: 300));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(c.positions, hasLength(2));
      expect(c.positions.first, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('mini board renders for all themes', (tester) async {
      for (final theme in LudoBoardThemes.all) {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            _app(
              MiniLudoBoard(boardTheme: theme),
              brightness: brightness,
              size: 120,
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
    });

    test('unknown theme ids fall back to the classic look', () {
      expect(LudoBoardThemes.resolve('nope'), LudoBoardThemes.classic);
      expect(
        LudoBoardThemes.style('nope', GamePalette.light),
        LudoBoardThemes.style(LudoBoardThemes.classic, GamePalette.light),
      );
    });
  });

  group('interaction', () {
    testWidgets('tapping a legal token calls onTokenTap with its index', (
      tester,
    ) async {
      final c = LudoBoardController(
        seatColors: SeatColor.values,
        tokensPerPlayer: 4,
        positions: [
          [5, 5, 20, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      )..setInteraction(seat: 0, legalTokens: {0, 2});
      final taps = <int>[];
      await tester.pumpWidget(
        _app(LudoBoard(controller: c, onTokenTap: taps.add)),
      );
      await tester.pump();

      await tester.tapAt(_gridToGlobal(tester, c.restingCenter(0, 2)));
      await tester.tapAt(_gridToGlobal(tester, c.restingCenter(0, 1)));
      await tester.tapAt(_gridToGlobal(tester, c.restingCenter(0, 3)));
      await tester.tapAt(_gridToGlobal(tester, const Offset(7.5, 1.5)));
      expect(taps, [
        2,
        0,
      ], reason: 'twin of token 0 maps to 0; base/empty taps ignored');

      c.setInteraction();
      await tester.pump();
      await tester.tapAt(_gridToGlobal(tester, c.restingCenter(0, 2)));
      expect(taps, [2, 0]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('a turned board maps taps to the turned tokens', (
      tester,
    ) async {
      // Red seen from the bottom-left (three clockwise quarter turns).
      final c = LudoBoardController(
        seatColors: SeatColor.values,
        tokensPerPlayer: 4,
        positions: [
          [-1, 0, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
        quarterTurns: SeatColor.red.turnsToBottomLeft,
      )..setInteraction(seat: 0, legalTokens: {0, 1});
      final taps = <int>[];
      await tester.pumpWidget(
        _app(LudoBoard(controller: c, onTokenTap: taps.add)),
      );
      await tester.pump();

      final base = c.restingCenter(0, 0);
      expect(LudoGeometry.baseRect(SeatColor.blue).contains(base), isTrue);
      // Red's start square is blue's start square in the turned view.
      expect(
        c.restingCenter(0, 1),
        LudoGeometry.cellFor(
          SeatColor.blue,
          0,
          tokenIndex: 1,
          tokensPerPlayer: 4,
        ).center,
      );
      await tester.tapAt(_gridToGlobal(tester, base));
      await tester.tapAt(_gridToGlobal(tester, c.restingCenter(0, 1)));
      // The unturned red base (top-left) is empty now.
      await tester.tapAt(_gridToGlobal(tester, const Offset(2, 2)));
      expect(taps, [0, 1]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('accessibility labels and the semantic tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final c =
          LudoBoardController(
              seatColors: SeatColor.values,
              tokensPerPlayer: 4,
              positions: [
                [5, -1, 56, -1],
                [-1, -1, -1, -1],
                [-1, -1, -1, -1],
                [-1, -1, -1, -1],
              ],
            )
            ..setTurnSeat(0)
            ..setInteraction(seat: 0, legalTokens: {0});
      final taps = <int>[];
      await tester.pumpWidget(
        _app(LudoBoard(controller: c, onTokenTap: taps.add)),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Ludo board'), findsOneWidget);
      expect(
        find.semantics.byLabel(
          'Red token 1, 51 squares from home, can move, current turn',
        ),
        findsOne,
      );
      expect(
        find.semantics.byLabel('Red token 2, in base, current turn'),
        findsOne,
      );
      expect(
        find.semantics.byLabel('Red token 3, finished, current turn'),
        findsOne,
      );
      expect(find.semantics.byLabel('Green token 1, in base'), findsOne);
      final node = find.semantics
          .byLabel(RegExp('^Red token 1,'))
          .evaluate()
          .single;
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.getSemanticsData().hint, 'move this token');
      final notLegal = find.semantics
          .byLabel(RegExp('^Red token 2,'))
          .evaluate()
          .single;
      expect(
        notLegal.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      tester.semantics.tap(find.semantics.byLabel(RegExp('^Red token 1,')));
      expect(taps, [0]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      handle.dispose();
    });

    testWidgets('localized labels (Hindi)', (tester) async {
      final handle = tester.ensureSemantics();
      final c = LudoBoardController(
        seatColors: const [SeatColor.red, SeatColor.yellow],
        tokensPerPlayer: 2,
        positions: [
          [53, -1],
          [-1, -1],
        ],
      );
      await tester.pumpWidget(
        _app(LudoBoard(controller: c), locale: const Locale('hi')),
      );
      await tester.pump();
      expect(
        find.semantics.byLabel(RegExp('लाल गोटी 1, मंज़िल से 3 खाने दूर')),
        findsOne,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      handle.dispose();
    });
  });

  group('RTL', () {
    testWidgets('the board is never mirrored', (tester) async {
      final handle = tester.ensureSemantics();
      Future<Rect> tokenRect(TextDirection direction) async {
        final c = LudoBoardController(
          seatColors: SeatColor.values,
          tokensPerPlayer: 4,
          positions: [
            [5, -1, -1, -1],
            [-1, -1, -1, -1],
            [-1, -1, -1, -1],
            [-1, -1, -1, -1],
          ],
        );
        await tester.pumpWidget(
          _app(
            LudoBoard(controller: c),
            direction: direction,
            locale: const Locale('ar'),
          ),
        );
        await tester.pump();
        final node = find.semantics
            .byLabel(RegExp('^الحجر الأحمر رقم 1'))
            .evaluate()
            .single;
        final rect = node.rect;
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        return rect;
      }

      final ltr = await tokenRect(TextDirection.ltr);
      final rtl = await tokenRect(TextDirection.rtl);
      expect(rtl, ltr);
      // Red progress 5 is at (6,5): the left half of the board, in both.
      final layout = LudoBoardLayout.fit(const Size(400, 400));
      expect(ltr.center.dx, closeTo(layout.toPx(const Offset(6.5, 5.5)).dx, 1));
      handle.dispose();
    });

    testWidgets('taps hit the same token in RTL', (tester) async {
      final c = LudoBoardController(
        seatColors: SeatColor.values,
        tokensPerPlayer: 4,
        positions: [
          [5, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      )..setInteraction(seat: 0, legalTokens: {0});
      final taps = <int>[];
      await tester.pumpWidget(
        _app(
          LudoBoard(controller: c, onTokenTap: taps.add),
          direction: TextDirection.rtl,
        ),
      );
      await tester.pump();
      await tester.tapAt(_gridToGlobal(tester, const Offset(6.5, 5.5)));
      expect(taps, [0]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
