import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/features/ludo/presentation/board/ludo_board.dart';
import 'package:ludo_royale/features/ludo/presentation/board/ludo_board_controller.dart';
import 'package:ludo_royale/features/ludo/presentation/board/ludo_geometry.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:ludo_royale/shared/game_visuals/game_palette.dart';

LudoBoardController _controller({
  int tokensPerPlayer = 4,
  List<List<int>>? positions,
  List<SeatColor> colors = SeatColor.values,
}) {
  return LudoBoardController(
    seatColors: colors,
    tokensPerPlayer: tokensPerPlayer,
    positions:
        positions ??
        [
          for (var s = 0; s < colors.length; s++)
            List<int>.filled(tokensPerPlayer, -1),
        ],
  );
}

Future<void> _pumpBoard(
  WidgetTester tester,
  LudoBoardController controller, {
  bool reducedMotion = false,
  ValueChanged<int>? onTokenTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox.square(
            dimension: 400,
            child: LudoBoard(
              controller: controller,
              reducedMotion: reducedMotion,
              onTokenTap: onTokenTap,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps frames until [future] completes (or [max] elapses).
Future<bool> _settle(
  WidgetTester tester,
  Future<void> future, {
  Duration max = const Duration(seconds: 5),
}) async {
  var done = false;
  future.then((_) => done = true);
  var elapsed = Duration.zero;
  const step = Duration(milliseconds: 16);
  while (!done && elapsed < max) {
    await tester.pump(step);
    elapsed += step;
  }
  await tester.pump();
  return done;
}

void main() {
  group('without a board', () {
    test('animateMove applies instantly and completes', () async {
      final c = _controller(
        positions: [
          [3, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      var steps = 0;
      c.onStep = (_, _, _) => steps++;
      await c.animateMove(seat: 0, token: 0, from: 3, to: 8);
      expect(c.positions[0][0], 8);
      expect(c.displayedProgress(0, 0), 8);
      expect(c.isAnimating, isFalse);
      expect(steps, 0, reason: 'no events without an attached board');
      c.dispose();
    });

    test('captures send the victims to base', () async {
      final c = _controller(
        positions: [
          [9, -1, -1, -1],
          [49, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      await c.animateMove(
        seat: 0,
        token: 0,
        from: 9,
        to: 10,
        captures: const [(seat: 1, token: 0)],
      );
      expect(c.positions[0][0], 10);
      expect(c.positions[1][0], -1);
      expect(
        c.restingCenter(1, 0),
        LudoGeometry.cellFor(
          SeatColor.green,
          -1,
          tokenIndex: 0,
          tokensPerPlayer: 4,
        ).center,
      );
      c.dispose();
    });

    test('positions are normalised and copied', () {
      final c = _controller(
        colors: const [SeatColor.red, SeatColor.yellow],
        positions: [
          [70, -5],
        ],
      );
      expect(c.positions, [
        [56, -1, -1, -1],
        [-1, -1, -1, -1],
      ]);
      expect(() => c.positions[0][0] = 3, throwsUnsupportedError);
      c.setPositions([
        [1, 2, 3, 4],
        [5, 6, 7, 8],
      ]);
      expect(c.positions[1], [5, 6, 7, 8]);
      c.dispose();
    });

    test(
      'hitTest maps taps to legal tokens, including same-progress twins',
      () {
        final c = _controller(
          positions: [
            [5, 5, 20, -1],
            [-1, -1, -1, -1],
            [-1, -1, -1, -1],
            [-1, -1, -1, -1],
          ],
        );
        final cell = LudoGeometry.cellFor(
          SeatColor.red,
          5,
          tokenIndex: 0,
          tokensPerPlayer: 4,
        ).center;
        expect(c.hitTest(cell), isNull, reason: 'no interaction yet');
        c.setInteraction(seat: 0, legalTokens: {0, 2});
        expect(c.hitTest(c.restingCenter(0, 0)), 0);
        expect(
          c.hitTest(c.restingCenter(0, 1)),
          0,
          reason: 'twin of legal token 0',
        );
        expect(c.hitTest(c.restingCenter(0, 2)), 2);
        expect(
          c.hitTest(c.restingCenter(0, 3)),
          isNull,
          reason: 'base token is not legal',
        );
        expect(c.hitTest(const Offset(14, 14)), isNull);
        c.setInteraction();
        expect(c.hitTest(c.restingCenter(0, 2)), isNull);
        c.dispose();
      },
    );

    test('stacks fan out, shrink and carry a count badge', () {
      final c = _controller(
        positions: [
          [5, 5, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      final a = c.restingCenter(0, 0);
      final b = c.restingCenter(0, 1);
      expect(a, isNot(b));
      expect(c.restingScale(0, 0), lessThan(1));
      expect(c.restingBadge(0, 0) + c.restingBadge(0, 1), 2);
      expect(c.restingBadge(0, 2), 0);
      // Three tokens of two colors on a square → total badge 3.
      c.setPositions([
        [5, 5, -1, -1],
        [44, -1, -1, -1], // green 44 → abs (13 + 44) % 52 = 5 = red 5
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
      ]);
      final badges = [
        c.restingBadge(0, 0),
        c.restingBadge(0, 1),
        c.restingBadge(1, 0),
      ];
      expect(badges.where((b) => b > 0).single, 3);
      c.dispose();
    });

    test('finished tokens line up in their home triangle', () {
      final c = _controller(
        positions: [
          [56, 56, 56, 56],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      final centers = {for (var t = 0; t < 4; t++) c.restingCenter(0, t)};
      expect(centers, hasLength(4));
      for (final p in centers) {
        expect(const Rect.fromLTRB(6, 6, 9, 9).contains(p), isTrue);
      }
      c.dispose();
    });

    test('forfeited seats are hidden', () {
      final c = _controller();
      c.setForfeitedSeats({2});
      expect(c.isSeatVisible(2), isFalse);
      expect(c.isSeatVisible(1), isTrue);
      c.dispose();
    });
  });

  group('with a board', () {
    testWidgets('animateMove hops cell by cell and completes', (tester) async {
      final c = _controller(
        positions: [
          [3, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      await _pumpBoard(tester, c);
      final steps = <int>[];
      c.onStep = (seat, token, progress) => steps.add(progress);
      final future = c.animateMove(seat: 0, token: 0, from: 3, to: 8);
      expect(c.positions[0][0], 8, reason: 'logical state updates immediately');
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.isAnimating, isTrue);
      expect(c.motionOf(0, 0).active, isTrue);
      final done = await _settle(tester, future);
      expect(done, isTrue);
      expect(steps, [4, 5, 6, 7, 8]);
      expect(c.isAnimating, isFalse);
      expect(c.motionOf(0, 0).active, isFalse);
      expect(c.visualCenter(0, 0), c.restingCenter(0, 0));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('leaving base is one hop onto the start square', (
      tester,
    ) async {
      final c = _controller();
      await _pumpBoard(tester, c);
      final steps = <int>[];
      c.onStep = (_, _, p) => steps.add(p);
      expect(
        await _settle(
          tester,
          c.animateMove(seat: 2, token: 1, from: -1, to: 0),
        ),
        isTrue,
      );
      expect(steps, [0]);
      expect(c.restingCenter(2, 1), const Offset(13.5, 8.5));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('capture knocks victims back to base and fires onCapture', (
      tester,
    ) async {
      final c = _controller(
        positions: [
          [9, -1, -1, -1],
          [49, 49, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      await _pumpBoard(tester, c);
      final events = <String>[];
      c.onStep = (_, _, p) => events.add('step$p');
      c.onCapture = (seat, token, captured) =>
          events.add('capture${captured.length}');
      final future = c.animateMove(
        seat: 0,
        token: 0,
        from: 9,
        to: 10,
        captures: const [(seat: 1, token: 0), (seat: 1, token: 1)],
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 260));
      expect(c.motionOf(1, 0).active, isTrue, reason: 'victim animates');
      expect(await _settle(tester, future), isTrue);
      expect(events, ['step10', 'capture2']);
      expect(c.displayedProgress(1, 0), -1);
      expect(c.displayedProgress(1, 1), -1);
      expect(
        c.visualCenter(1, 1),
        LudoGeometry.cellFor(
          SeatColor.green,
          -1,
          tokenIndex: 1,
          tokensPerPlayer: 4,
        ).center,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('reaching home fires onHome', (tester) async {
      final c = _controller(
        positions: [
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, 50, -1],
          [-1, -1, -1, -1],
        ],
      );
      await _pumpBoard(tester, c);
      final homes = <int>[];
      c.onHome = (seat, token) => homes.add(seat * 10 + token);
      expect(
        await _settle(
          tester,
          c.animateMove(seat: 2, token: 2, from: 50, to: 56, reachedHome: true),
        ),
        isTrue,
      );
      expect(homes, [22]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('cancelAndSnap completes pending moves at their final state', (
      tester,
    ) async {
      final c = _controller(
        positions: [
          [3, 10, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      await _pumpBoard(tester, c);
      var firstDone = false;
      var secondDone = false;
      c
          .animateMove(seat: 0, token: 0, from: 3, to: 9)
          .then((_) => firstDone = true);
      c
          .animateMove(seat: 0, token: 1, from: 10, to: 14)
          .then((_) => secondDone = true);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        c.displayedProgress(0, 1),
        10,
        reason: 'second move is still queued',
      );
      c.cancelAndSnap();
      await tester.pump();
      expect(firstDone && secondDone, isTrue);
      expect(c.displayedProgress(0, 0), 9);
      expect(c.displayedProgress(0, 1), 14);
      expect(c.motionOf(0, 0).active, isFalse);
      expect(c.visualCenter(0, 0), c.restingCenter(0, 0));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('queued moves run sequentially', (tester) async {
      final c = _controller(
        positions: [
          [3, 10, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      await _pumpBoard(tester, c);
      final order = <int>[];
      final a = c
          .animateMove(seat: 0, token: 0, from: 3, to: 5)
          .then((_) => order.add(1));
      final b = c
          .animateMove(seat: 0, token: 1, from: 10, to: 12)
          .then((_) => order.add(2));
      expect(c.positions[0], [5, 12, -1, -1]);
      await _settle(tester, Future.wait([a, b]));
      expect(order, [1, 2]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('setPositions during an animation snaps and completes it', (
      tester,
    ) async {
      final c = _controller(
        positions: [
          [3, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      await _pumpBoard(tester, c);
      var done = false;
      c.animateMove(seat: 0, token: 0, from: 3, to: 9).then((_) => done = true);
      await tester.pump(const Duration(milliseconds: 100));
      c.setPositions([
        [20, -1, -1, -1],
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
        [-1, -1, -1, -1],
      ]);
      await tester.pump();
      expect(done, isTrue);
      expect(c.displayedProgress(0, 0), 20);
      expect(c.isAnimating, isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('reduced motion still completes quickly with events', (
      tester,
    ) async {
      final c = _controller(
        positions: [
          [9, -1, -1, -1],
          [49, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      await _pumpBoard(tester, c, reducedMotion: true);
      final events = <String>[];
      c.onStep = (_, _, p) => events.add('step$p');
      c.onCapture = (_, _, _) => events.add('capture');
      final future = c.animateMove(
        seat: 0,
        token: 0,
        from: 9,
        to: 10,
        captures: const [(seat: 1, token: 0)],
      );
      expect(
        await _settle(tester, future, max: const Duration(milliseconds: 600)),
        isTrue,
      );
      expect(events, ['step10', 'capture']);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('disposing the board mid-animation snaps and completes', (
      tester,
    ) async {
      final c = _controller(
        positions: [
          [3, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      await _pumpBoard(tester, c);
      var done = false;
      c.animateMove(seat: 0, token: 0, from: 3, to: 9).then((_) => done = true);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(done, isTrue);
      expect(c.displayedProgress(0, 0), 9);
      c.dispose();
    });
  });
}
