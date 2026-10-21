import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../../shared/game_visuals/board_cell.dart';

/// Snakes & Ladders board geometry, exactly as documented in
/// `backend/docs/game-rules.md` (10 × 10 grid, square 1 bottom-left,
/// boustrophedon numbering, square 100 top-left).
///
/// Two coordinate spaces, both with `(0, 0)` at the top-left corner of the
/// 10 × 10 grid:
///
/// - *Tile space*: one unit per cell in both directions. The static board
///   art (frame, tiles, start pad, plinth) is drawn here, stretched
///   vertically by [rowHeight].
/// - *Grid units* (everything else: [centerOf], snakes, ladders, tokens,
///   [SnakesBoardLayout]): one unit is one cell's width and rows are
///   [rowHeight] units tall, so round things stay round on the taller board.
///
/// The whole board adds a frame of [frameInset] around the grid and a plinth
/// strip of [plinthHeight] below it (tile space), where tokens wait at
/// position 0 on a start pad beside square 1.
abstract final class SnakesGeometry {
  /// Snakes, head → tail.
  static const Map<int, int> snakes = {
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
  };

  /// Ladders, bottom → top.
  static const Map<int, int> ladders = {
    1: 38,
    4: 14,
    9: 31,
    21: 42,
    28: 84,
    36: 44,
    51: 67,
    71: 91,
    80: 100,
  };

  /// Frame width around the grid (grid units).
  static const double frameInset = 0.32;

  /// Height of the plinth strip under the grid that holds the start pad.
  static const double plinthHeight = 1.12;

  /// Height of a row relative to its width: the board is a little taller
  /// than wide at the same width (owner, 21 Oct 2026).
  static const double rowHeight = 1.1;

  /// Whole board width in grid units (grid + frame).
  static const double boardWidth = 10 + 2 * frameInset;

  /// Whole board height in grid units (grid + plinth + frame).
  static const double boardHeight =
      (10 + 2 * frameInset + plinthHeight) * rowHeight;

  /// Tile space → grid units.
  static Offset fromTile(Offset tile) => Offset(tile.dx, tile.dy * rowHeight);

  /// Width / height of the whole board, for `AspectRatio`.
  static double get aspectRatio => boardWidth / boardHeight;

  /// Spacing between seat slots on the start pad.
  static const double startSlotSpacing = 0.9;

  /// Token scale while waiting on the start pad.
  static const double startTokenScale = 0.8;

  /// The start pad (tile space), directly under squares 1–4.
  static const Rect startPadRect = Rect.fromLTRB(0.06, 10.2, 3.62, 11.0);

  /// The cell of [square] (1..100). Throws [RangeError] otherwise.
  static BoardCell cellFor(int square) {
    RangeError.checkValueInInterval(square, 1, 100, 'square');
    final rowFromBottom = (square - 1) ~/ 10;
    final colInRow = (square - 1) % 10;
    final col = rowFromBottom.isEven ? colInRow : 9 - colInRow;
    return BoardCell(col, 9 - rowFromBottom);
  }

  /// Inverse of [cellFor].
  static int squareAt(BoardCell cell) {
    RangeError.checkValueInInterval(cell.col, 0, 9, 'col');
    RangeError.checkValueInInterval(cell.row, 0, 9, 'row');
    final rowFromBottom = 9 - cell.row;
    final colInRow = rowFromBottom.isEven ? cell.col : 9 - cell.col;
    return rowFromBottom * 10 + colInRow + 1;
  }

  /// Cell center of [square] in grid units (1..100).
  static Offset centerOf(int square) => fromTile(cellFor(square).center);

  /// Where [seat]'s token waits at position 0 (beside square 1), in tile
  /// space.
  static Offset startSlotTile(int seat) => Offset(
    0.5 + seat.clamp(0, 3) * startSlotSpacing,
    startPadRect.center.dy - 0.02,
  );

  /// Where [seat]'s token waits at position 0 (beside square 1).
  static Offset startSlot(int seat) => fromTile(startSlotTile(seat));

  /// Resting point of a token at [square] (0 = start pad slot of [seat]).
  static Offset positionCenter(int square, {required int seat}) =>
      square <= 0 ? startSlot(seat) : centerOf(square.clamp(1, 100));

  /// Squares visited when stepping from [from] (exclusive) to [landing]
  /// (inclusive). From 0 the first step is square 1. Empty if
  /// `landing <= from`.
  static List<int> stepPath(int from, int landing) {
    final start = math.max(from, 0) + 1;
    final end = math.min(landing, 100);
    if (end < start) return const <int>[];
    return [for (var s = start; s <= end; s++) s];
  }

  static final Map<int, SnakeBody> _bodies = <int, SnakeBody>{};
  static final Map<int, LadderRails> _ladders = <int, LadderRails>{};

  /// Deterministic body of the snake whose head is on [head].
  static SnakeBody snakeBody(int head) {
    final tail = snakes[head];
    if (tail == null) {
      throw ArgumentError.value(head, 'head', 'No snake head on this square');
    }
    return _bodies.putIfAbsent(head, () => SnakeBody._build(head, tail));
  }

  /// Rails and rungs of the ladder whose foot is on [bottom].
  static LadderRails ladderRails(int bottom) {
    final top = ladders[bottom];
    if (top == null) {
      throw ArgumentError.value(
        bottom,
        'bottom',
        'No ladder foot on this square',
      );
    }
    return _ladders.putIfAbsent(bottom, () => LadderRails._build(bottom, top));
  }

  /// All snake bodies in ascending head order.
  static List<SnakeBody> get allSnakes => [
    for (final head in snakes.keys) snakeBody(head),
  ];

  /// All ladders in ascending foot order.
  static List<LadderRails> get allLadders => [
    for (final bottom in ladders.keys) ladderRails(bottom),
  ];
}

/// Pixel mapping of the whole board inside a widget of a given size.
@immutable
class SnakesBoardLayout {
  const SnakesBoardLayout._(this.cell, this.gridOrigin, this.boardRect);

  /// Fits the board (frame + plinth) centered into [size].
  factory SnakesBoardLayout.fit(Size size) {
    final scale = math.min(
      size.width / SnakesGeometry.boardWidth,
      size.height / SnakesGeometry.boardHeight,
    );
    final w = SnakesGeometry.boardWidth * scale;
    final h = SnakesGeometry.boardHeight * scale;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    final boardRect = Rect.fromLTWH(left, top, w, h);
    final origin = Offset(
      left + SnakesGeometry.frameInset * scale,
      top + SnakesGeometry.frameInset * SnakesGeometry.rowHeight * scale,
    );
    return SnakesBoardLayout._(scale, origin, boardRect);
  }

  /// Pixel size of one grid unit (one cell).
  final double cell;

  /// Pixel position of grid (0, 0).
  final Offset gridOrigin;

  /// The whole board including frame and plinth.
  final Rect boardRect;

  Offset toPx(Offset grid) =>
      Offset(gridOrigin.dx + grid.dx * cell, gridOrigin.dy + grid.dy * cell);

  Offset toGrid(Offset px) =>
      Offset((px.dx - gridOrigin.dx) / cell, (px.dy - gridOrigin.dy) / cell);

  Rect cellRect(BoardCell c) => Rect.fromLTWH(
    gridOrigin.dx + c.col * cell,
    gridOrigin.dy + c.row * cell * SnakesGeometry.rowHeight,
    cell,
    cell * SnakesGeometry.rowHeight,
  );

  @override
  bool operator ==(Object other) =>
      other is SnakesBoardLayout &&
      other.cell == cell &&
      other.gridOrigin == gridOrigin &&
      other.boardRect == boardRect;

  @override
  int get hashCode => Object.hash(cell, gridOrigin, boardRect);
}

/// One cubic Bézier segment (grid units).
@immutable
class CubicSegment {
  const CubicSegment(this.p0, this.c1, this.c2, this.p3);
  final Offset p0;
  final Offset c1;
  final Offset c2;
  final Offset p3;

  Offset at(double t) {
    final u = 1 - t;
    final a = u * u * u;
    final b = 3 * u * u * t;
    final c = 3 * u * t * t;
    final d = t * t * t;
    return Offset(
      a * p0.dx + b * c1.dx + c * c2.dx + d * p3.dx,
      a * p0.dy + b * c1.dy + c * c2.dy + d * p3.dy,
    );
  }
}

/// A snake's body: a C1-continuous chain of cubic segments from the head
/// square center to the tail square center, with an arc-length lookup table
/// so animations can follow the drawn body at constant speed.
class SnakeBody {
  SnakeBody._(this.head, this.tail, this.segments, this.width) {
    _buildLut();
  }

  factory SnakeBody._build(int head, int tail) {
    final h = SnakesGeometry.centerOf(head);
    final t = SnakesGeometry.centerOf(tail);
    final d = t - h;
    final length = d.distance;
    final u = d / length;
    final n = Offset(-u.dy, u.dx);
    final halfWaves = math.max(2, (length / 1.45).round());
    final amplitude = (length * 0.085).clamp(0.24, 0.52);
    // Deterministic side per snake.
    final sign = ((head * 7 + tail * 3) % 2 == 0) ? 1.0 : -1.0;
    final segments = <CubicSegment>[];
    final step = d / halfWaves.toDouble();
    for (var j = 0; j < halfWaves; j++) {
      final p0 = h + step * j.toDouble();
      final p3 = j == halfWaves - 1 ? t : p0 + step;
      final side = sign * (j.isEven ? 1 : -1);
      // Both controls offset by 4/3·A so the half-wave peaks at A.
      final bulge = n * (amplitude * 4 / 3 * side);
      segments.add(
        CubicSegment(
          p0,
          p0 + step * (1 / 3) + bulge,
          p0 + step * (2 / 3) + bulge,
          p3,
        ),
      );
    }
    final width = (0.3 + length * 0.008).clamp(0.3, 0.38);
    return SnakeBody._(head, tail, List.unmodifiable(segments), width);
  }

  /// Head square.
  final int head;

  /// Tail square.
  final int tail;

  /// Body segments, head first (grid units).
  final List<CubicSegment> segments;

  /// Body width at the neck (grid units).
  final double width;

  static const int _samplesPerSegment = 40;
  late final Float64List _xs;
  late final Float64List _ys;
  late final Float64List _len;

  /// Total arc length (grid units).
  double get length => _len[_len.length - 1];

  void _buildLut() {
    final count = segments.length * _samplesPerSegment + 1;
    _xs = Float64List(count);
    _ys = Float64List(count);
    _len = Float64List(count);
    var i = 0;
    for (var s = 0; s < segments.length; s++) {
      final seg = segments[s];
      final startJ = s == 0 ? 0 : 1;
      for (var j = startJ; j <= _samplesPerSegment; j++) {
        final p = seg.at(j / _samplesPerSegment);
        _xs[i] = p.dx;
        _ys[i] = p.dy;
        if (i > 0) {
          final dx = _xs[i] - _xs[i - 1];
          final dy = _ys[i] - _ys[i - 1];
          _len[i] = _len[i - 1] + math.sqrt(dx * dx + dy * dy);
        }
        i++;
      }
    }
  }

  int _indexFor(double target) {
    var lo = 0;
    var hi = _len.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_len[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Point at arc-length fraction [t] (0 = head center, 1 = tail center).
  Offset pointAt(double t) {
    final target = t.clamp(0.0, 1.0) * length;
    final i = _indexFor(target);
    if (i == 0) return Offset(_xs[0], _ys[0]);
    final l0 = _len[i - 1];
    final l1 = _len[i];
    final f = l1 > l0 ? (target - l0) / (l1 - l0) : 0.0;
    return Offset(
      _xs[i - 1] + (_xs[i] - _xs[i - 1]) * f,
      _ys[i - 1] + (_ys[i] - _ys[i - 1]) * f,
    );
  }

  /// Unit tangent at [t], pointing from the head toward the tail.
  Offset tangentAt(double t) {
    final target = t.clamp(0.0, 1.0) * length;
    var i = _indexFor(target);
    if (i == 0) i = 1;
    final dx = _xs[i] - _xs[i - 1];
    final dy = _ys[i] - _ys[i - 1];
    final m = math.sqrt(dx * dx + dy * dy);
    if (m == 0) return const Offset(0, 1);
    return Offset(dx / m, dy / m);
  }

  /// The body center line as a path in pixels.
  Path buildPath(double cell, Offset origin) {
    Offset px(Offset g) => origin + g * cell;
    final path = Path();
    final first = px(segments.first.p0);
    path.moveTo(first.dx, first.dy);
    for (final s in segments) {
      final a = px(s.c1);
      final b = px(s.c2);
      final c = px(s.p3);
      path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
    }
    return path;
  }
}

/// A ladder's two rails and its rungs (grid units).
class LadderRails {
  LadderRails._({
    required this.bottom,
    required this.top,
    required this.foot,
    required this.head,
    required this.leftStart,
    required this.leftEnd,
    required this.rightStart,
    required this.rightEnd,
    required this.rungTs,
  });

  factory LadderRails._build(int bottom, int top) {
    final foot = SnakesGeometry.centerOf(bottom);
    final head = SnakesGeometry.centerOf(top);
    final d = head - foot;
    final length = d.distance;
    final u = d / length;
    final n = Offset(-u.dy, u.dx) * halfGauge;
    // Rails overhang the square centers slightly.
    final s = foot - u * overhang;
    final e = head + u * overhang;
    final rungs = math.max(2, (length / rungSpacing).floor());
    final ts = <double>[for (var i = 1; i <= rungs; i++) i / (rungs + 1)];
    return LadderRails._(
      bottom: bottom,
      top: top,
      foot: foot,
      head: head,
      leftStart: s + n,
      leftEnd: e + n,
      rightStart: s - n,
      rightEnd: e - n,
      rungTs: List.unmodifiable(ts),
    );
  }

  /// Half the distance between the rails.
  static const double halfGauge = 0.27;

  /// How far rails extend beyond the square centers.
  static const double overhang = 0.22;

  /// Target spacing between rungs.
  static const double rungSpacing = 0.5;

  final int bottom;
  final int top;

  /// Center of the foot square and of the top square.
  final Offset foot;
  final Offset head;

  final Offset leftStart;
  final Offset leftEnd;
  final Offset rightStart;
  final Offset rightEnd;

  /// Rung positions as fractions from [foot] (0) to [head] (1).
  final List<double> rungTs;

  /// Unit direction foot → head.
  Offset get direction {
    final d = head - foot;
    return d / d.distance;
  }

  /// Point on the ladder's center line, [t] 0 = foot, 1 = head.
  Offset pointAt(double t) => Offset.lerp(foot, head, t.clamp(0.0, 1.0))!;

  /// Rung endpoints (left, right) for rung fraction [t].
  (Offset, Offset) rungAt(double t) {
    final c = pointAt(t);
    final d = direction;
    final n = Offset(-d.dy, d.dx) * halfGauge;
    return (c + n, c - n);
  }
}
