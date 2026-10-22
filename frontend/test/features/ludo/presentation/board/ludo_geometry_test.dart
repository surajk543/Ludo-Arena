import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/features/ludo/presentation/board/ludo_geometry.dart';
import 'package:ludo_arena/shared/game_visuals/board_cell.dart';
import 'package:ludo_arena/shared/game_visuals/seat_color.dart';

/// Main-track table copied verbatim from backend/docs/game-rules.md.
const _docTrack = '''
(1,6) (2,6) (3,6) (4,6) (5,6)
(6,5) (6,4) (6,3) (6,2) (6,1) (6,0)
(7,0)
(8,0) (8,1) (8,2) (8,3) (8,4) (8,5)
(9,6) (10,6) (11,6) (12,6) (13,6) (14,6)
(14,7)
(14,8) (13,8) (12,8) (11,8) (10,8) (9,8)
(8,9) (8,10) (8,11) (8,12) (8,13) (8,14)
(7,14)
(6,14) (6,13) (6,12) (6,11) (6,10) (6,9)
(5,8) (4,8) (3,8) (2,8) (1,8) (0,8)
(0,7)
(0,6)
''';

/// Home-column table (progress 51 → 55) from the doc.
const _docHomeColumns = {
  SeatColor.red: '(1,7) (2,7) (3,7) (4,7) (5,7)',
  SeatColor.green: '(7,1) (7,2) (7,3) (7,4) (7,5)',
  SeatColor.yellow: '(13,7) (12,7) (11,7) (10,7) (9,7)',
  SeatColor.blue: '(7,13) (7,12) (7,11) (7,10) (7,9)',
};

List<BoardCell> _parse(String text) => [
  for (final m in RegExp(r'\((\d+),(\d+)\)').allMatches(text))
    BoardCell(int.parse(m.group(1)!), int.parse(m.group(2)!)),
];

BoardCell _cell(SeatColor color, int progress) => LudoGeometry.cellFor(
  color,
  progress,
  tokenIndex: 0,
  tokensPerPlayer: 4,
).cell!;

void main() {
  quarterTurnSymmetryTests();
  group('main track', () {
    test('has 52 unique squares matching the doc table in order', () {
      final doc = _parse(_docTrack);
      expect(doc, hasLength(52));
      expect(LudoGeometry.track, hasLength(52));
      expect(LudoGeometry.track.toSet(), hasLength(52));
      for (var i = 0; i < 52; i++) {
        expect(LudoGeometry.trackCell(i), doc[i], reason: 'abs index $i');
        expect(LudoGeometry.trackIndexOf(doc[i]), i);
      }
    });

    test('consecutive squares are orthogonally adjacent (closed loop)', () {
      for (var i = 0; i < 52; i++) {
        final a = LudoGeometry.track[i];
        final b = LudoGeometry.track[(i + 1) % 52];
        final manhattan = (a.col - b.col).abs() + (a.row - b.row).abs();
        // The turns at the arm corners are diagonal steps (e.g. (5,6) → (6,5)).
        expect(manhattan, inInclusiveRange(1, 2), reason: '$a → $b');
      }
    });

    test('start squares are 13 × colorIndex', () {
      const starts = {
        SeatColor.red: BoardCell(1, 6),
        SeatColor.green: BoardCell(8, 1),
        SeatColor.yellow: BoardCell(13, 8),
        SeatColor.blue: BoardCell(6, 13),
      };
      for (final e in starts.entries) {
        expect(LudoGeometry.startIndex(e.key), 13 * e.key.index);
        expect(_cell(e.key, 0), e.value);
        expect(LudoGeometry.startColorAt(13 * e.key.index), e.key);
      }
      expect(LudoGeometry.startColorAt(8), isNull);
    });

    test('safe squares are the starts and the stars', () {
      expect(LudoGeometry.safeTrackIndices.toSet(), {
        0,
        8,
        13,
        21,
        26,
        34,
        39,
        47,
      });
      expect(
        [for (final i in LudoGeometry.starTrackIndices) LudoGeometry.track[i]],
        const [
          BoardCell(6, 2),
          BoardCell(12, 6),
          BoardCell(8, 12),
          BoardCell(2, 8),
        ],
      );
      for (var i = 0; i < 52; i++) {
        expect(
          LudoGeometry.isSafeTrackIndex(i),
          const {0, 8, 13, 21, 26, 34, 39, 47}.contains(i),
          reason: 'abs $i',
        );
      }
    });

    test('progress maps to (13 × colorIndex + progress) mod 52', () {
      for (final color in SeatColor.values) {
        final seen = <BoardCell>{};
        for (var p = 0; p <= 50; p++) {
          final spot = LudoGeometry.cellFor(
            color,
            p,
            tokenIndex: 0,
            tokensPerPlayer: 4,
          );
          expect(spot.kind, LudoSpotKind.track);
          expect(spot.trackIndex, (13 * color.index + p) % 52);
          expect(spot.cell, LudoGeometry.track[(13 * color.index + p) % 52]);
          expect(spot.center, spot.cell!.center);
          seen.add(spot.cell!);
        }
        expect(
          seen,
          hasLength(51),
          reason: '$color visits 51 distinct squares',
        );
      }
    });

    test('progress 50 is the square before each home column', () {
      expect(_cell(SeatColor.red, 50), const BoardCell(0, 7));
      expect(_cell(SeatColor.green, 50), const BoardCell(7, 0));
      expect(_cell(SeatColor.yellow, 50), const BoardCell(14, 7));
      expect(_cell(SeatColor.blue, 50), const BoardCell(7, 14));
    });

    test('a few wrap-around spot checks', () {
      // green 45 → abs (13 + 45) % 52 = 6 → (6,4)
      expect(_cell(SeatColor.green, 45), const BoardCell(6, 4));
      // yellow 26 → abs 0 → red start (1,6)
      expect(_cell(SeatColor.yellow, 26), const BoardCell(1, 6));
      // blue 13 → abs 0
      expect(_cell(SeatColor.blue, 13), const BoardCell(1, 6));
    });
  });

  group('home columns and home', () {
    test('progress 51..55 follow the doc table per color', () {
      for (final e in _docHomeColumns.entries) {
        final doc = _parse(e.value);
        expect(LudoGeometry.homeColumn(e.key), doc);
        for (var p = 51; p <= 55; p++) {
          final spot = LudoGeometry.cellFor(
            e.key,
            p,
            tokenIndex: 2,
            tokensPerPlayer: 4,
          );
          expect(spot.kind, LudoSpotKind.homeColumn);
          expect(spot.cell, doc[p - 51], reason: '${e.key} progress $p');
          expect(spot.isSafe, isTrue);
        }
      }
    });

    test('home columns never overlap the track', () {
      final track = LudoGeometry.track.toSet();
      for (final color in SeatColor.values) {
        for (final c in LudoGeometry.homeColumn(color)) {
          expect(track.contains(c), isFalse);
        }
      }
    });

    test('progress 56 is the color home inside its center triangle', () {
      for (final color in SeatColor.values) {
        final spot = LudoGeometry.cellFor(
          color,
          56,
          tokenIndex: 0,
          tokensPerPlayer: 4,
        );
        expect(spot.kind, LudoSpotKind.home);
        expect(spot.cell, isNull);
        final tri = LudoGeometry.homeTriangle(color);
        expect(_inTriangle(spot.center, tri), isTrue, reason: '$color');
        expect(const Rect.fromLTRB(6, 6, 9, 9).contains(spot.center), isTrue);
      }
    });

    test('triangles point in from the documented sides', () {
      expect(LudoGeometry.homeTriangle(SeatColor.red).first.dx, 6);
      expect(LudoGeometry.homeTriangle(SeatColor.green).first.dy, 6);
      expect(LudoGeometry.homeTriangle(SeatColor.yellow).first.dx, 9);
      expect(LudoGeometry.homeTriangle(SeatColor.blue).first.dy, 9);
    });
  });

  group('bases', () {
    test('4-token bases use four distinct slots inside the base', () {
      for (final color in SeatColor.values) {
        final rect = LudoGeometry.baseRect(color);
        final centers = <Offset>{};
        for (var t = 0; t < 4; t++) {
          final spot = LudoGeometry.cellFor(
            color,
            -1,
            tokenIndex: t,
            tokensPerPlayer: 4,
          );
          expect(spot.kind, LudoSpotKind.base);
          expect(spot.baseSlot, t);
          expect(rect.contains(spot.center), isTrue);
          expect(spot.isSafe, isTrue);
          centers.add(spot.center);
        }
        expect(centers, hasLength(4));
      }
      expect(
        LudoGeometry.baseRect(SeatColor.red),
        const Rect.fromLTWH(0, 0, 6, 6),
      );
      expect(
        LudoGeometry.baseRect(SeatColor.green),
        const Rect.fromLTWH(9, 0, 6, 6),
      );
      expect(
        LudoGeometry.baseRect(SeatColor.yellow),
        const Rect.fromLTWH(9, 9, 6, 6),
      );
      expect(
        LudoGeometry.baseRect(SeatColor.blue),
        const Rect.fromLTWH(0, 9, 6, 6),
      );
    });

    test('Quick Ludo (2 tokens) uses the diagonal pointing at the center', () {
      Offset c(SeatColor color, int t) => LudoGeometry.cellFor(
        color,
        -1,
        tokenIndex: t,
        tokensPerPlayer: 2,
      ).center;
      expect(
        [c(SeatColor.red, 0), c(SeatColor.red, 1)],
        const [Offset(2, 2), Offset(4, 4)],
      );
      expect(
        [c(SeatColor.green, 0), c(SeatColor.green, 1)],
        const [Offset(13, 2), Offset(11, 4)],
      );
      expect(
        [c(SeatColor.yellow, 0), c(SeatColor.yellow, 1)],
        const [Offset(11, 11), Offset(13, 13)],
      );
      expect(
        [c(SeatColor.blue, 0), c(SeatColor.blue, 1)],
        const [Offset(4, 11), Offset(2, 13)],
      );
    });
  });

  group('pathCells', () {
    test('leaving base is a single hop onto the start square', () {
      for (final color in SeatColor.values) {
        final path = LudoGeometry.pathCells(color, -1, 0);
        expect(path, hasLength(1));
        expect(path.single.trackIndex, LudoGeometry.startIndex(color));
      }
    });

    test('steps cell by cell across the home-column entry', () {
      final path = LudoGeometry.pathCells(SeatColor.red, 48, 53);
      expect(
        [for (final s in path) s.cell],
        const [
          BoardCell(0, 8),
          BoardCell(0, 7),
          BoardCell(1, 7),
          BoardCell(2, 7),
          BoardCell(3, 7),
        ],
      );
      expect(path.map((s) => s.kind).toList(), [
        LudoSpotKind.track,
        LudoSpotKind.track,
        LudoSpotKind.homeColumn,
        LudoSpotKind.homeColumn,
        LudoSpotKind.homeColumn,
      ]);
    });

    test('ends at home and wraps the track for green', () {
      final home = LudoGeometry.pathCells(SeatColor.blue, 50, 56);
      expect(home, hasLength(6));
      expect(home.last.kind, LudoSpotKind.home);
      final wrap = LudoGeometry.pathCells(SeatColor.green, 36, 40);
      expect([for (final s in wrap) s.trackIndex], [50, 51, 0, 1]);
    });

    test('non-forward moves produce no path; bad progress throws', () {
      expect(LudoGeometry.pathCells(SeatColor.red, 10, 10), isEmpty);
      expect(LudoGeometry.pathCells(SeatColor.red, 10, -1), isEmpty);
      expect(
        () => LudoGeometry.cellFor(
          SeatColor.red,
          57,
          tokenIndex: 0,
          tokensPerPlayer: 4,
        ),
        throwsRangeError,
      );
      expect(
        () => LudoGeometry.cellFor(
          SeatColor.red,
          -2,
          tokenIndex: 0,
          tokensPerPlayer: 4,
        ),
        throwsRangeError,
      );
    });

    test('stepsToHome', () {
      expect(LudoGeometry.stepsToHome(0), 56);
      expect(LudoGeometry.stepsToHome(53), 3);
      expect(LudoGeometry.stepsToHome(56), 0);
      expect(LudoGeometry.stepsToHome(-1), 57);
    });
  });

  test('layout fits a centered, slightly taller board with a frame', () {
    const h = LudoBoardLayout.rowHeight;
    expect(h, greaterThan(1));
    expect(LudoBoardLayout.aspectRatio, closeTo(1 / h, 1e-12));
    // Height-limited: the board is 300 tall and 300 / h wide.
    final layout = LudoBoardLayout.fit(const Size(420, 300));
    expect(layout.boardRect.height, closeTo(300, 1e-9));
    expect(layout.boardRect.width, closeTo(300 / h, 1e-9));
    expect(layout.boardRect.center.dx, closeTo(210, 1e-9));
    expect(layout.cell, closeTo(300 / (LudoBoardLayout.totalUnits * h), 1e-9));
    expect(layout.cellY, closeTo(layout.cell * h, 1e-9));
    final p = layout.toPx(const Offset(7.5, 7.5));
    expect(p.dx, closeTo(210, 1e-9));
    expect(p.dy, closeTo(150, 1e-9));
    final g = layout.toGrid(p);
    expect(g.dx, closeTo(7.5, 1e-9));
    expect(g.dy, closeTo(7.5, 1e-9));
    // Width-limited: the same width as before, taller.
    final wide = LudoBoardLayout.fit(const Size(300, 600));
    expect(wide.boardRect.width, closeTo(300, 1e-9));
    expect(wide.boardRect.height, closeTo(300 * h, 1e-9));
    expect(wide.cell, closeTo(300 / LudoBoardLayout.totalUnits, 1e-9));
    final r = wide.cellRect(const BoardCell(3, 4));
    expect(r.width, closeTo(wide.cell, 1e-9));
    expect(r.height, closeTo(wide.cell * h, 1e-9));
    expect(r.center, wide.toPx(const BoardCell(3, 4).center));
  });
}

bool _inTriangle(Offset p, List<Offset> t) {
  double sign(Offset a, Offset b, Offset c) =>
      (a.dx - c.dx) * (b.dy - c.dy) - (b.dx - c.dx) * (a.dy - c.dy);
  final d1 = sign(p, t[0], t[1]);
  final d2 = sign(p, t[1], t[2]);
  final d3 = sign(p, t[2], t[0]);
  final neg = d1 < 0 || d2 < 0 || d3 < 0;
  final pos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(neg && pos);
}

/// One clockwise quarter turn of a grid point around the board center.
Offset _turn(Offset p) => Offset(LudoGeometry.gridSize - p.dy, p.dx);

void _expectNear(Offset actual, Offset expected, String reason) {
  expect(actual.dx, closeTo(expected.dx, 1e-9), reason: reason);
  expect(actual.dy, closeTo(expected.dy, 1e-9), reason: reason);
}

void quarterTurnSymmetryTests() {
  group('quarter-turn symmetry (board view rotation)', () {
    // The view puts the local player bottom-left by drawing each color with
    // the geometry of `color.rotated(k)`; that is a true rotation only if
    // the board is symmetric under quarter turns.
    for (final color in SeatColor.values) {
      final next = color.rotated(1);
      test('${color.name} turned once lands on ${next.name}', () {
        for (var p = 0; p <= LudoGeometry.homeProgress; p++) {
          _expectNear(
            LudoGeometry.cellFor(
              next,
              p,
              tokenIndex: 0,
              tokensPerPlayer: 4,
            ).center,
            _turn(
              LudoGeometry.cellFor(
                color,
                p,
                tokenIndex: 0,
                tokensPerPlayer: 4,
              ).center,
            ),
            'progress $p',
          );
        }
        final base = LudoGeometry.baseRect(color);
        final turned = Rect.fromPoints(
          _turn(base.topLeft),
          _turn(base.bottomRight),
        );
        expect(LudoGeometry.baseRect(next), turned);
        for (final tpp in [2, 4]) {
          Set<Offset> slots(SeatColor c) => {
            for (var t = 0; t < tpp; t++)
              LudoGeometry.cellFor(
                c,
                LudoGeometry.baseProgress,
                tokenIndex: t,
                tokensPerPlayer: tpp,
              ).center,
          };
          expect(
            slots(next),
            slots(color).map(_turn).toSet(),
            reason: '$tpp tokens',
          );
        }
        expect(
          LudoGeometry.homeTriangle(next).toSet(),
          LudoGeometry.homeTriangle(color).map(_turn).toSet(),
        );
      });
    }
  });
}
