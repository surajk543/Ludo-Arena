import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/features/snakes_ladders/presentation/board/snakes_geometry.dart';
import 'package:ludo_royale/shared/game_visuals/board_cell.dart';

void main() {
  group('SnakesGeometry.cellFor (boustrophedon, doc formula)', () {
    test('anchor squares', () {
      expect(SnakesGeometry.cellFor(1), const BoardCell(0, 9));
      expect(SnakesGeometry.cellFor(10), const BoardCell(9, 9));
      expect(SnakesGeometry.cellFor(11), const BoardCell(9, 8));
      expect(SnakesGeometry.cellFor(20), const BoardCell(0, 8));
      expect(SnakesGeometry.cellFor(21), const BoardCell(0, 7));
      expect(SnakesGeometry.cellFor(91), const BoardCell(9, 0));
      expect(SnakesGeometry.cellFor(100), const BoardCell(0, 0));
    });

    test('11 is directly above 10 and 21 directly above 20', () {
      final ten = SnakesGeometry.cellFor(10);
      final eleven = SnakesGeometry.cellFor(11);
      expect(eleven.col, ten.col);
      expect(eleven.row, ten.row - 1);
      final twenty = SnakesGeometry.cellFor(20);
      final twentyOne = SnakesGeometry.cellFor(21);
      expect(twentyOne.col, twenty.col);
      expect(twentyOne.row, twenty.row - 1);
    });

    test('matches the documented formula for all 100 squares, all unique', () {
      final seen = <BoardCell>{};
      for (var s = 1; s <= 100; s++) {
        final rowFromBottom = (s - 1) ~/ 10;
        final colInRow = (s - 1) % 10;
        final col = rowFromBottom.isEven ? colInRow : 9 - colInRow;
        final expected = BoardCell(col, 9 - rowFromBottom);
        final cell = SnakesGeometry.cellFor(s);
        expect(cell, expected, reason: 'square $s');
        expect(SnakesGeometry.squareAt(cell), s);
        expect(seen.add(cell), isTrue, reason: 'square $s duplicated');
      }
      expect(seen.length, 100);
    });

    test('consecutive squares are orthogonal neighbours', () {
      for (var s = 1; s < 100; s++) {
        final a = SnakesGeometry.cellFor(s);
        final b = SnakesGeometry.cellFor(s + 1);
        expect(
          (a.col - b.col).abs() + (a.row - b.row).abs(),
          1,
          reason: '$s→${s + 1}',
        );
      }
    });

    test('out of range throws RangeError', () {
      expect(() => SnakesGeometry.cellFor(0), throwsRangeError);
      expect(() => SnakesGeometry.cellFor(101), throwsRangeError);
      expect(() => SnakesGeometry.cellFor(-1), throwsRangeError);
    });

    test('centerOf is the cell center in grid units (taller rows)', () {
      const h = SnakesGeometry.rowHeight;
      expect(h, greaterThan(1));
      expect(SnakesGeometry.centerOf(1), const Offset(0.5, 9.5 * h));
      expect(SnakesGeometry.centerOf(100), const Offset(0.5, 0.5 * h));
      expect(
        SnakesGeometry.centerOf(1),
        SnakesGeometry.fromTile(SnakesGeometry.cellFor(1).center),
      );
    });
  });

  group('snakes and ladders lists', () {
    test('snakes equal the doc list (head → tail)', () {
      expect(SnakesGeometry.snakes, {
        16: 6,
        47: 26,
        49: 11,
        56: 53,
        62: 19,
        64: 60,
        87: 24,
        93: 73,
        95: 75,
        98: 78,
      });
    });

    test('ladders equal the doc list (bottom → top)', () {
      expect(SnakesGeometry.ladders, {
        1: 38,
        4: 14,
        9: 31,
        21: 42,
        28: 84,
        36: 44,
        51: 67,
        71: 91,
        80: 100,
      });
    });

    test('no square is both a snake head and a ladder foot', () {
      expect(
        SnakesGeometry.snakes.keys.toSet().intersection(
          SnakesGeometry.ladders.keys.toSet(),
        ),
        isEmpty,
      );
    });
  });

  group('start position', () {
    test('slots sit on the plinth beside square 1, side by side', () {
      final one = SnakesGeometry.centerOf(1);
      final slot0 = SnakesGeometry.startSlot(0);
      const h = SnakesGeometry.rowHeight;
      expect(slot0.dx, closeTo(one.dx, 1e-9));
      expect(slot0.dy, greaterThan(10 * h));
      expect(slot0.dy, lessThan((10 + SnakesGeometry.plinthHeight) * h));
      for (var seat = 1; seat < 4; seat++) {
        final s = SnakesGeometry.startSlot(seat);
        expect(s.dy, slot0.dy);
        expect(s.dx, greaterThan(SnakesGeometry.startSlot(seat - 1).dx));
        // The pad is drawn in tile space.
        expect(
          SnakesGeometry.startPadRect.contains(
            SnakesGeometry.startSlotTile(seat),
          ),
          isTrue,
        );
        expect(s, SnakesGeometry.fromTile(SnakesGeometry.startSlotTile(seat)));
      }
      expect(
        SnakesGeometry.positionCenter(0, seat: 2),
        SnakesGeometry.startSlot(2),
      );
      expect(
        SnakesGeometry.positionCenter(57, seat: 2),
        SnakesGeometry.centerOf(57),
      );
    });

    test('aspect ratio includes frame, plinth and the taller rows', () {
      expect(
        SnakesGeometry.aspectRatio,
        closeTo(
          (10 + 2 * SnakesGeometry.frameInset) /
              ((10 +
                      2 * SnakesGeometry.frameInset +
                      SnakesGeometry.plinthHeight) *
                  SnakesGeometry.rowHeight),
          1e-12,
        ),
      );
      expect(SnakesGeometry.aspectRatio, lessThan(1));
    });

    test('cells are taller than wide; cellRect matches centerOf', () {
      final layout = SnakesBoardLayout.fit(const Size(300, 600));
      final rect = layout.cellRect(SnakesGeometry.cellFor(57));
      expect(rect.width, closeTo(layout.cell, 1e-9));
      expect(
        rect.height,
        closeTo(layout.cell * SnakesGeometry.rowHeight, 1e-9),
      );
      final c = layout.toPx(SnakesGeometry.centerOf(57));
      expect(c.dx, closeTo(rect.center.dx, 1e-9));
      expect(c.dy, closeTo(rect.center.dy, 1e-9));
    });

    test('layout fits and centers the board', () {
      final layout = SnakesBoardLayout.fit(const Size(300, 600));
      expect(layout.boardRect.width, closeTo(300, 1e-9));
      expect(
        layout.boardRect.height,
        closeTo(300 / SnakesGeometry.aspectRatio, 1e-9),
      );
      expect(layout.boardRect.center.dy, closeTo(300, 1e-9));
      expect(layout.cell, closeTo(300 / SnakesGeometry.boardWidth, 1e-9));
      final p = layout.toPx(const Offset(3.5, 7.5));
      expect(layout.toGrid(p).dx, closeTo(3.5, 1e-9));
      expect(layout.toGrid(p).dy, closeTo(7.5, 1e-9));
    });
  });

  group('stepPath', () {
    test('from the start, first step is square 1', () {
      expect(SnakesGeometry.stepPath(0, 4), [1, 2, 3, 4]);
      expect(SnakesGeometry.stepPath(0, 1), [1]);
    });

    test('ordinary steps and the finish', () {
      expect(SnakesGeometry.stepPath(97, 100), [98, 99, 100]);
      expect(SnakesGeometry.stepPath(10, 13), [11, 12, 13]);
    });

    test('empty when not moving forward', () {
      expect(SnakesGeometry.stepPath(10, 10), isEmpty);
      expect(SnakesGeometry.stepPath(10, 5), isEmpty);
    });
  });

  group('snake bodies', () {
    test('every body runs from head center to tail center', () {
      for (final entry in SnakesGeometry.snakes.entries) {
        final body = SnakesGeometry.snakeBody(entry.key);
        expect(body.head, entry.key);
        expect(body.tail, entry.value);
        final h = SnakesGeometry.centerOf(entry.key);
        final t = SnakesGeometry.centerOf(entry.value);
        expect(
          (body.pointAt(0) - h).distance,
          lessThan(1e-6),
          reason: 'head ${entry.key}',
        );
        expect(
          (body.pointAt(1) - t).distance,
          lessThan(1e-6),
          reason: 'tail ${entry.key}',
        );
        expect(body.length, greaterThan((t - h).distance));
        expect(body.segments.first.p0, h);
        expect(body.segments.last.p3, t);
      }
    });

    test('bodies are deterministic', () {
      for (final head in SnakesGeometry.snakes.keys) {
        final a = SnakesGeometry.snakeBody(head);
        final b = SnakesGeometry.snakeBody(head);
        for (var i = 0; i <= 10; i++) {
          expect(a.pointAt(i / 10), b.pointAt(i / 10));
        }
        for (var i = 0; i < a.segments.length; i++) {
          expect(a.segments[i].c1, b.segments[i].c1);
          expect(a.segments[i].c2, b.segments[i].c2);
        }
      }
    });

    test('pointAt is arc-length parameterised and tangents are unit', () {
      final body = SnakesGeometry.snakeBody(87);
      const n = 40;
      final steps = <double>[];
      for (var i = 1; i <= n; i++) {
        steps.add((body.pointAt(i / n) - body.pointAt((i - 1) / n)).distance);
        expect(body.tangentAt(i / n).distance, closeTo(1, 1e-6));
      }
      final mean = body.length / n;
      for (final s in steps) {
        expect(s, closeTo(mean, mean * 0.05));
      }
    });

    test('the body is sinuous (deviates from the straight line)', () {
      final body = SnakesGeometry.snakeBody(62);
      final h = SnakesGeometry.centerOf(62);
      final t = SnakesGeometry.centerOf(19);
      var maxDev = 0.0;
      for (var i = 0; i <= 20; i++) {
        final p = body.pointAt(i / 20);
        // Horizontal deviation from the vertical line 62 → 19.
        maxDev = maxDev > (p.dx - h.dx).abs() ? maxDev : (p.dx - h.dx).abs();
      }
      expect(h.dx, t.dx);
      expect(maxDev, greaterThan(0.2));
    });

    test('unknown head throws', () {
      expect(() => SnakesGeometry.snakeBody(17), throwsArgumentError);
    });

    test('buildPath produces a path covering head and tail in pixels', () {
      final body = SnakesGeometry.snakeBody(16);
      final path = body.buildPath(10, const Offset(5, 5));
      final bounds = path.getBounds();
      final head = const Offset(5, 5) + SnakesGeometry.centerOf(16) * 10;
      final tail = const Offset(5, 5) + SnakesGeometry.centerOf(6) * 10;
      expect(bounds.inflate(0.01).contains(head), isTrue);
      expect(bounds.inflate(0.01).contains(tail), isTrue);
    });
  });

  group('ladder rails', () {
    test('rails straddle the foot and top centers', () {
      for (final entry in SnakesGeometry.ladders.entries) {
        final r = SnakesGeometry.ladderRails(entry.key);
        final foot = SnakesGeometry.centerOf(entry.key);
        final top = SnakesGeometry.centerOf(entry.value);
        expect(r.foot, foot);
        expect(r.head, top);
        final startMid = (r.leftStart + r.rightStart) / 2;
        final endMid = (r.leftEnd + r.rightEnd) / 2;
        final u = r.direction;
        expect(
          (startMid - (foot - u * LadderRails.overhang)).distance,
          lessThan(1e-9),
        );
        expect(
          (endMid - (top + u * LadderRails.overhang)).distance,
          lessThan(1e-9),
        );
        expect(
          (r.leftStart - r.rightStart).distance,
          closeTo(2 * LadderRails.halfGauge, 1e-9),
        );
        expect(r.pointAt(0), foot);
        expect(r.pointAt(1), top);
        expect(r.rungTs, isNotEmpty);
        for (var i = 0; i < r.rungTs.length; i++) {
          expect(r.rungTs[i], inExclusiveRange(0, 1));
          if (i > 0) expect(r.rungTs[i], greaterThan(r.rungTs[i - 1]));
        }
        final rungGap =
            (r.rungTs.length > 1 ? r.rungTs[1] - r.rungTs[0] : r.rungTs[0]) *
            (top - foot).distance;
        expect(rungGap, inInclusiveRange(0.3, 0.7));
      }
    });

    test('vertical ladder 80 → 100 has vertical rails', () {
      final r = SnakesGeometry.ladderRails(80);
      expect(r.leftStart.dx, closeTo(r.leftEnd.dx, 1e-9));
      expect(r.rightStart.dx, closeTo(r.rightEnd.dx, 1e-9));
    });
  });
}
