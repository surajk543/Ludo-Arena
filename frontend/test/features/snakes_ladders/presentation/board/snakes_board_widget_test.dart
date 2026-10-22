import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/mini_snakes_board.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/snakes_board.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/snakes_board_controller.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/snakes_board_painter.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/snakes_board_theme.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/snakes_geometry.dart';
import 'package:ludo_arena/l10n/generated/app_localizations.dart';
import 'package:ludo_arena/shared/game_visuals/game_palette.dart';

Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
  TextDirection? direction,
  Locale? locale,
}) {
  Widget body = child;
  if (direction != null) {
    body = Directionality(textDirection: direction, child: body);
  }
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: body)),
  );
}

void main() {
  for (final theme in SnakesBoardThemes.all) {
    for (final brightness in Brightness.values) {
      for (final width in [280.0, 420.0]) {
        testWidgets(
          '$theme renders (${brightness.name}, ${width.toInt()} px)',
          (tester) async {
            final c = SnakesBoardController(
              seatColors: SeatColor.values,
              positions: const [0, 23, 23, 57],
            )..setTurnSeat(1);
            await tester.pumpWidget(
              _app(
                brightness: brightness,
                child: SizedBox(
                  width: width,
                  height: width * 1.3,
                  child: SnakesBoard(
                    controller: c,
                    boardTheme: theme,
                    tokenSkins: const [
                      'token_classic',
                      'token_gem',
                      'token_royal',
                      'token_crown',
                    ],
                    trails: const [
                      'trail_sparkle',
                      'trail_comet',
                      'trail_none',
                      'trail_sparkle',
                    ],
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            final board = tester.getSize(find.byType(SnakesBoard));
            expect(board.width, width);
            // The board keeps its aspect ratio inside the box.
            final paint = tester.getSize(
              find.descendant(
                of: find.byType(SnakesBoard),
                matching: find.byType(AspectRatio),
              ),
            );
            expect(
              paint.width / paint.height,
              closeTo(SnakesGeometry.aspectRatio, 0.01),
            );

            // Exercise the animated layer: trails, slide, effects.
            var done = false;
            c
                .animateMove(
                  seat: 0,
                  from: 95,
                  to: 78,
                  landing: 98,
                  transition: (kind: 'snake', from: 98, to: 78),
                )
                .then((_) => done = true);
            for (var i = 0; i < 300 && !done; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(done, isTrue);
            await tester.pump(const Duration(seconds: 2));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('semantics: one labelled node per token, board label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final c = SnakesBoardController(
      seatColors: const [SeatColor.red, SeatColor.green, SeatColor.yellow],
      positions: const [23, 0, 100],
    )..setTurnSeat(1);
    await tester.pumpWidget(
      _app(
        child: SizedBox(
          width: 320,
          height: 400,
          child: SnakesBoard(controller: c),
        ),
      ),
    );
    expect(find.semantics.byLabel('Snakes and Ladders board'), findsOne);
    expect(find.semantics.byLabel('Red token on square 23'), findsOne);
    expect(
      find.semantics.byLabel('Green token at the start, current turn'),
      findsOne,
    );
    expect(find.semantics.byLabel('Yellow token on square 100'), findsOne);
    // Turn change rebuilds the labels.
    c.setTurnSeat(0);
    await tester.pump();
    expect(
      find.semantics.byLabel('Red token on square 23, current turn'),
      findsOne,
    );
    expect(find.semantics.byLabel('Green token at the start'), findsOne);
    handle.dispose();
  });

  testWidgets('semantics labels are localized', (tester) async {
    final handle = tester.ensureSemantics();
    final c = SnakesBoardController(
      seatColors: const [SeatColor.red, SeatColor.yellow],
      positions: const [34, 0],
    );
    await tester.pumpWidget(
      _app(
        locale: const Locale('id'),
        child: SizedBox(
          width: 320,
          height: 400,
          child: SnakesBoard(controller: c),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('Bidak Merah di kotak 34'), findsOne);
    expect(find.semantics.byLabel('Papan Ular Tangga'), findsOne);
    handle.dispose();
  });

  testWidgets('RTL does not mirror the board', (tester) async {
    final handle = tester.ensureSemantics();
    Future<(Rect, Offset)> measure(TextDirection dir) async {
      final c = SnakesBoardController(
        seatColors: const [SeatColor.red, SeatColor.yellow],
        positions: const [23, 0],
      );
      await tester.pumpWidget(
        _app(
          direction: dir,
          child: SizedBox(
            width: 300,
            height: 380,
            child: SnakesBoard(controller: c),
          ),
        ),
      );
      final node = find.semantics
          .byLabel('Red token on square 23')
          .evaluate()
          .single;
      final origin = tester.getTopLeft(find.byType(SnakesBoard));
      return (node.rect, origin);
    }

    final (ltrRect, ltrOrigin) = await measure(TextDirection.ltr);
    final (rtlRect, rtlOrigin) = await measure(TextDirection.rtl);
    expect(rtlOrigin, ltrOrigin);
    expect(rtlRect, ltrRect);
    // Square 23 is in the left half of the grid (col 2) in both directions.
    final layout = SnakesBoardLayout.fit(
      tester.getSize(find.byType(AspectRatio).first),
    );
    final expected = layout.toPx(SnakesGeometry.centerOf(23));
    expect(rtlRect.center.dx, closeTo(expected.dx, 0.5));
    expect(rtlRect.center.dx, lessThan(layout.boardRect.center.dx));
    handle.dispose();
  });

  testWidgets('board is wrapped in an LTR Directionality', (tester) async {
    final c = SnakesBoardController(
      seatColors: SeatColor.values,
      positions: const [0, 0, 0, 0],
    );
    await tester.pumpWidget(
      _app(
        direction: TextDirection.rtl,
        child: SizedBox(
          width: 300,
          height: 380,
          child: SnakesBoard(controller: c),
        ),
      ),
    );
    final inner = tester.widget<Directionality>(
      find
          .descendant(
            of: find.byType(SnakesBoard),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(inner.textDirection, TextDirection.ltr);
  });

  testWidgets('unknown theme id falls back to classic', (tester) async {
    expect(
      SnakesBoardThemes.resolve('snakes_board_unknown'),
      SnakesBoardThemes.classic,
    );
    expect(SnakesBoardThemes.resolve(null), SnakesBoardThemes.classic);
    expect(
      SnakesBoardThemes.style('nope', GamePalette.light).id,
      SnakesBoardThemes.classic,
    );
    final c = SnakesBoardController(
      seatColors: SeatColor.values,
      positions: const [1, 2, 3, 4],
    );
    await tester.pumpWidget(
      _app(
        child: SizedBox(
          width: 300,
          height: 380,
          child: SnakesBoard(
            controller: c,
            boardTheme: 'nope',
            tokenSkins: const ['token_unknown'],
            trails: const ['trail_unknown'],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(SnakesBoard),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((p) => p.painter)
        .whereType<SnakesBoardPainter>()
        .single;
    expect(painter.style.id, SnakesBoardThemes.classic);
  });

  testWidgets(
    'static board layer is isolated and not repainted by token frames',
    (tester) async {
      final c = SnakesBoardController(
        seatColors: SeatColor.values,
        positions: const [0, 0, 0, 0],
      );
      await tester.pumpWidget(
        _app(
          child: SizedBox(
            width: 300,
            height: 380,
            child: SnakesBoard(controller: c),
          ),
        ),
      );
      final staticPaint = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(SnakesBoard),
              matching: find.byType(CustomPaint),
            ),
          )
          .firstWhere((p) => p.painter is SnakesBoardPainter);
      expect(staticPaint.isComplex, isTrue);
      expect(staticPaint.willChange, isFalse);
      final boundaries = find.descendant(
        of: find.byType(SnakesBoard),
        matching: find.byType(RepaintBoundary),
      );
      expect(boundaries, findsAtLeastNWidgets(2));
      final painter = staticPaint.painter! as SnakesBoardPainter;
      expect(
        painter.shouldRepaint(SnakesBoardPainter(style: painter.style)),
        isFalse,
      );
      expect(
        painter.shouldRepaint(
          SnakesBoardPainter(style: painter.style, detailed: false),
        ),
        isTrue,
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        boundaries.first,
      );
      expect(boundary, isNotNull);
    },
  );

  for (final theme in SnakesBoardThemes.all) {
    for (final brightness in Brightness.values) {
      testWidgets('MiniSnakesBoard $theme (${brightness.name})', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            child: SizedBox(
              width: 140,
              child: MiniSnakesBoard(boardTheme: theme),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final size = tester.getSize(find.byType(MiniSnakesBoard));
        expect(
          size.width / size.height,
          closeTo(SnakesGeometry.aspectRatio, 0.01),
        );
      });
    }
  }

  testWidgets('MiniSnakesBoard without tokens and with an unknown theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        child: const SizedBox(
          width: 100,
          child: MiniSnakesBoard(boardTheme: 'whatever', showTokens: false),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('fewer seats than colors draws only present seats', (
    tester,
  ) async {
    final c = SnakesBoardController(
      seatColors: const [SeatColor.red, SeatColor.yellow],
      positions: const [3, 3, 9, 9],
    );
    expect(c.seatCount, 2);
    expect(c.positions, [3, 3]);
    await tester.pumpWidget(
      _app(
        child: SizedBox(
          width: 300,
          height: 380,
          child: SnakesBoard(controller: c),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
