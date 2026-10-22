import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/snakes_board.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/snakes_board_controller.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/snakes_geometry.dart';
import 'package:ludo_arena/l10n/generated/app_localizations.dart';
import 'package:ludo_arena/shared/game_visuals/game_palette.dart';

Future<void> _pumpBoard(
  WidgetTester tester,
  SnakesBoardController controller, {
  bool reducedMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 420,
            child: SnakesBoard(
              controller: controller,
              reducedMotion: reducedMotion,
              trails: const ['trail_comet', 'trail_sparkle'],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps frames until [future] completes (max ~6 s of animation).
Future<bool> _pumpUntilDone(WidgetTester tester, Future<void> future) async {
  var done = false;
  future.then((_) => done = true);
  for (var i = 0; i < 400 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return done;
}

SnakesBoardController _controller(List<int> positions) => SnakesBoardController(
  seatColors: SeatColor.forPlayerCount(positions.length),
  positions: positions,
);

List<String> _record(SnakesBoardController c) {
  final events = <String>[];
  c.onStep = (seat, square) => events.add('step:$seat:$square');
  c.onLadder = (seat, from, to) => events.add('ladder:$seat:$from:$to');
  c.onSnake = (seat, from, to) => events.add('snake:$seat:$from:$to');
  c.onFinish = (seat) => events.add('finish:$seat');
  return events;
}

void main() {
  group('without a board', () {
    test('animateMove applies instantly and completes', () async {
      final c = _controller([0, 0]);
      final events = _record(c);
      await c.animateMove(
        seat: 0,
        from: 0,
        to: 38,
        landing: 1,
        transition: (kind: 'ladder', from: 1, to: 38),
      );
      expect(c.positions, [38, 0]);
      expect(c.displayedSquare(0), 38);
      expect(c.isAnimating, isFalse);
      expect(c.debugVisualCenter(0), SnakesGeometry.centerOf(38));
      expect(events, isEmpty, reason: 'events only fire for played animations');
      c.dispose();
    });

    test('positions is an unmodifiable copy normalised to the seat count', () {
      final c = SnakesBoardController(
        seatColors: const [SeatColor.red, SeatColor.yellow],
        positions: const [5],
      );
      expect(c.positions, [5, 0]);
      expect(() => c.positions[0] = 3, throwsUnsupportedError);
      c.dispose();
    });

    test('setPositions and setTurnSeat notify listeners', () {
      final c = _controller([0, 0, 0]);
      var notified = 0;
      c.addListener(() => notified++);
      c.setPositions([3, 9, 100]);
      expect(c.positions, [3, 9, 100]);
      c.setTurnSeat(2);
      expect(c.turnSeat, 2);
      expect(notified, greaterThanOrEqualTo(2));
      c.dispose();
    });

    test('tokens sharing a square fan out and shrink', () {
      final c = _controller([23, 23, 23]);
      final centers = {for (var s = 0; s < 3; s++) c.restingCenter(s)};
      expect(centers.length, 3);
      expect(c.restingScale(0), lessThan(1));
      final alone = _controller([23, 5]);
      expect(alone.restingCenter(0), SnakesGeometry.centerOf(23));
      expect(alone.restingScale(0), 1);
      expect(alone.restingCenter(1), SnakesGeometry.centerOf(5));
      final start = _controller([0, 0]);
      expect(start.restingCenter(0), SnakesGeometry.startSlot(0));
      expect(start.restingCenter(1), SnakesGeometry.startSlot(1));
      c.dispose();
      alone.dispose();
      start.dispose();
    });
  });

  group('with a board', () {
    testWidgets('ladder climb from the start: 0 → 1 → 38', (tester) async {
      final c = _controller([0, 0]);
      final events = _record(c);
      await _pumpBoard(tester, c);
      final future = c.animateMove(
        seat: 0,
        from: 0,
        to: 38,
        landing: 1,
        transition: (kind: 'ladder', from: 1, to: 38),
      );
      expect(c.positions[0], 38, reason: 'logical state updates immediately');
      await tester.pump();
      expect(c.isAnimating, isTrue);
      expect(await _pumpUntilDone(tester, future), isTrue);
      expect(events, ['step:0:1', 'ladder:0:1:38']);
      expect(c.isAnimating, isFalse);
      expect(c.motionOf(0).active, isFalse);
      expect(c.debugVisualCenter(0), SnakesGeometry.centerOf(38));
      expect(tester.takeException(), isNull);
      // Let effects finish.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('snake slide 95 → 98 → 78', (tester) async {
      final c = _controller([95, 10]);
      final events = _record(c);
      await _pumpBoard(tester, c);
      final future = c.animateMove(
        seat: 0,
        from: 95,
        to: 78,
        landing: 98,
        transition: (kind: 'snake', from: 98, to: 78),
      );
      // Mid-slide the token follows the snake body.
      var sawOnBody = false;
      final body = SnakesGeometry.snakeBody(98);
      var done = false;
      future.then((_) => done = true);
      for (var i = 0; i < 400 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (events.contains('snake:0:98:78') && c.motionOf(0).active) {
          final p = c.debugVisualCenter(0);
          for (var k = 0; k <= 50; k++) {
            if ((body.pointAt(k / 50) - p).distance < 0.15) sawOnBody = true;
          }
        }
      }
      expect(done, isTrue);
      expect(sawOnBody, isTrue);
      expect(events, ['step:0:96', 'step:0:97', 'step:0:98', 'snake:0:98:78']);
      expect(c.positions, [78, 10]);
      expect(c.debugVisualCenter(0), SnakesGeometry.centerOf(78));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('plain move and move to 100 fire steps and finish', (
      tester,
    ) async {
      final c = _controller([10, 97]);
      final events = _record(c);
      await _pumpBoard(tester, c);
      expect(
        await _pumpUntilDone(tester, c.animateMove(seat: 0, from: 10, to: 13)),
        isTrue,
      );
      expect(events, ['step:0:11', 'step:0:12', 'step:0:13']);
      events.clear();
      expect(
        await _pumpUntilDone(tester, c.animateMove(seat: 1, from: 97, to: 100)),
        isTrue,
      );
      expect(events, ['step:1:98', 'step:1:99', 'step:1:100', 'finish:1']);
      expect(c.positions, [13, 100]);
      expect(c.debugVisualCenter(1), SnakesGeometry.centerOf(100));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ladder 80 → 100 finishes after the climb', (tester) async {
      final c = _controller([77]);
      final events = _record(c);
      await _pumpBoard(tester, c);
      // Landing/transition omitted: inferred from the ladder map.
      final ok = await _pumpUntilDone(
        tester,
        c.animateMove(seat: 0, from: 77, to: 100, landing: 80),
      );
      expect(ok, isTrue);
      expect(events, [
        'step:0:78',
        'step:0:79',
        'step:0:80',
        'ladder:0:80:100',
        'finish:0',
      ]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('cancelAndSnap mid-animation completes and jumps to the end', (
      tester,
    ) async {
      final c = _controller([10, 40]);
      await _pumpBoard(tester, c);
      var done = false;
      c.animateMove(seat: 0, from: 10, to: 13).then((_) => done = true);
      var queuedDone = false;
      c.animateMove(seat: 1, from: 40, to: 42).then((_) => queuedDone = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(c.motionOf(0).active, isTrue);
      expect(c.debugVisualCenter(0), isNot(SnakesGeometry.centerOf(13)));
      c.cancelAndSnap();
      await tester.pump();
      expect(done, isTrue);
      expect(queuedDone, isTrue);
      expect(c.isAnimating, isFalse);
      expect(c.debugVisualCenter(0), SnakesGeometry.centerOf(13));
      expect(c.debugVisualCenter(1), SnakesGeometry.centerOf(42));
      expect(c.displayedSquare(1), 42);
    });

    testWidgets('queued moves run sequentially', (tester) async {
      final c = _controller([10, 20]);
      await _pumpBoard(tester, c);
      final order = <String>[];
      final first = c.animateMove(seat: 0, from: 10, to: 12)
        ..then((_) => order.add('first'));
      final second = c.animateMove(seat: 1, from: 20, to: 23)
        ..then((_) => order.add('second'));
      expect(c.positions, [12, 23]);
      await tester.pump();
      // Second job has not begun: seat 1 still displayed on 20.
      expect(c.displayedSquare(1), 20);
      expect(c.motionOf(1).active, isFalse);
      expect(await _pumpUntilDone(tester, first), isTrue);
      expect(order, ['first']);
      await tester.pump(const Duration(milliseconds: 16));
      expect(c.motionOf(1).active, isTrue);
      expect(await _pumpUntilDone(tester, second), isTrue);
      expect(order, ['first', 'second']);
    });

    testWidgets('setPositions snaps and completes running animations', (
      tester,
    ) async {
      final c = _controller([10, 20]);
      await _pumpBoard(tester, c);
      var done = false;
      c.animateMove(seat: 0, from: 10, to: 14).then((_) => done = true);
      await tester.pump(const Duration(milliseconds: 50));
      c.setPositions([5, 6]);
      await tester.pump();
      expect(done, isTrue);
      expect(c.positions, [5, 6]);
      expect(c.displayedSquare(0), 5);
      expect(c.motionOf(0).active, isFalse);
      expect(c.debugVisualCenter(0), SnakesGeometry.centerOf(5));
    });

    testWidgets('reduced motion still completes and reports what happened', (
      tester,
    ) async {
      final c = _controller([0, 0]);
      final events = _record(c);
      await _pumpBoard(tester, c, reducedMotion: true);
      final future = c.animateMove(
        seat: 1,
        from: 0,
        to: 38,
        landing: 1,
        transition: (kind: 'ladder', from: 1, to: 38),
      );
      var frames = 0;
      var done = false;
      future.then((_) => done = true);
      while (!done && frames < 200) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      expect(done, isTrue);
      expect(frames * 16, lessThan(900), reason: 'reduced motion is short');
      expect(events, ['step:1:1', 'ladder:1:1:38']);
      expect(c.debugVisualCenter(1), SnakesGeometry.centerOf(38));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('disposing the board snaps pending animations', (tester) async {
      final c = _controller([10]);
      await _pumpBoard(tester, c);
      var done = false;
      c.animateMove(seat: 0, from: 10, to: 15).then((_) => done = true);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(done, isTrue);
      expect(c.displayedSquare(0), 15);
      c.dispose();
    });
  });
}
