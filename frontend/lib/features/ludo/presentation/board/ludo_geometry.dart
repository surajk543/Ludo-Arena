import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import '../../../../shared/game_visuals/board_cell.dart';
import '../../../../shared/game_visuals/seat_color.dart';

/// What kind of place a [LudoSpot] is.
enum LudoSpotKind {
  /// Waiting in the color's base (progress -1).
  base,

  /// On the 52-square main track (progress 0..50).
  track,

  /// In the color's home column (progress 51..55).
  homeColumn,

  /// Finished, in the color's center triangle (progress 56).
  home,
}

/// A resolved token position on the Ludo board.
///
/// [center] is in grid units (one unit = one cell, `(0, 0)` = top-left of
/// the 15 × 15 grid). Track and home-column spots also carry their [cell];
/// base spots carry their [baseSlot].
@immutable
class LudoSpot {
  const LudoSpot._({
    required this.kind,
    required this.color,
    required this.center,
    this.cell,
    this.trackIndex,
    this.baseSlot,
  });

  final LudoSpotKind kind;

  /// The color whose progress produced this spot.
  final SeatColor color;
  final Offset center;
  final BoardCell? cell;

  /// Absolute main-track index 0..51 (track spots only).
  final int? trackIndex;

  /// Base slot 0..3 (base spots only): 0 top-left, 1 top-right,
  /// 2 bottom-left, 3 bottom-right of the base's inner panel.
  final int? baseSlot;

  /// Whether a token here can never be captured (base, safe squares, home
  /// column, home).
  bool get isSafe =>
      kind != LudoSpotKind.track || LudoGeometry.isSafeTrackIndex(trackIndex!);

  /// Groups tokens that share the same physical place (used for stacking).
  int get stackKey {
    switch (kind) {
      case LudoSpotKind.track:
        return 100 + trackIndex!;
      case LudoSpotKind.homeColumn:
        return 200 + cell!.col * 15 + cell!.row;
      case LudoSpotKind.home:
        return 600 + color.index;
      case LudoSpotKind.base:
        return 700 + color.index * 4 + baseSlot!;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LudoSpot &&
      other.kind == kind &&
      other.color == color &&
      other.center == center &&
      other.cell == cell &&
      other.trackIndex == trackIndex &&
      other.baseSlot == baseSlot;

  @override
  int get hashCode =>
      Object.hash(kind, color, center, cell, trackIndex, baseSlot);

  @override
  String toString() {
    switch (kind) {
      case LudoSpotKind.base:
        return 'LudoSpot.base(${color.name}, slot $baseSlot)';
      case LudoSpotKind.track:
        return 'LudoSpot.track($trackIndex $cell)';
      case LudoSpotKind.homeColumn:
        return 'LudoSpot.homeColumn(${color.name} $cell)';
      case LudoSpotKind.home:
        return 'LudoSpot.home(${color.name})';
    }
  }
}

/// Ludo board geometry exactly as documented in
/// `backend/docs/game-rules.md` (15 × 15 grid, `(col, row)`, origin
/// top-left). Never mirrored for RTL.
abstract final class LudoGeometry {
  static const int gridSize = 15;
  static const int trackLength = 52;

  static const int baseProgress = -1;
  static const int lastTrackProgress = 50;
  static const int firstHomeColumnProgress = 51;
  static const int homeProgress = 56;

  /// Main track, absolute index 0..51, clockwise.
  static const List<BoardCell> track = [
    // 0–4
    BoardCell(1, 6), BoardCell(2, 6), BoardCell(3, 6), BoardCell(4, 6),
    BoardCell(5, 6),
    // 5–10
    BoardCell(6, 5), BoardCell(6, 4), BoardCell(6, 3), BoardCell(6, 2),
    BoardCell(6, 1), BoardCell(6, 0),
    // 11
    BoardCell(7, 0),
    // 12–17
    BoardCell(8, 0), BoardCell(8, 1), BoardCell(8, 2), BoardCell(8, 3),
    BoardCell(8, 4), BoardCell(8, 5),
    // 18–23
    BoardCell(9, 6), BoardCell(10, 6), BoardCell(11, 6), BoardCell(12, 6),
    BoardCell(13, 6), BoardCell(14, 6),
    // 24
    BoardCell(14, 7),
    // 25–30
    BoardCell(14, 8), BoardCell(13, 8), BoardCell(12, 8), BoardCell(11, 8),
    BoardCell(10, 8), BoardCell(9, 8),
    // 31–36
    BoardCell(8, 9), BoardCell(8, 10), BoardCell(8, 11), BoardCell(8, 12),
    BoardCell(8, 13), BoardCell(8, 14),
    // 37
    BoardCell(7, 14),
    // 38–43
    BoardCell(6, 14), BoardCell(6, 13), BoardCell(6, 12), BoardCell(6, 11),
    BoardCell(6, 10), BoardCell(6, 9),
    // 44–49
    BoardCell(5, 8), BoardCell(4, 8), BoardCell(3, 8), BoardCell(2, 8),
    BoardCell(1, 8), BoardCell(0, 8),
    // 50
    BoardCell(0, 7),
    // 51
    BoardCell(0, 6),
  ];

  /// Home columns (progress 51 → 55) per color index.
  static const List<List<BoardCell>> homeColumns = [
    [
      BoardCell(1, 7),
      BoardCell(2, 7),
      BoardCell(3, 7),
      BoardCell(4, 7),
      BoardCell(5, 7),
    ],
    [
      BoardCell(7, 1),
      BoardCell(7, 2),
      BoardCell(7, 3),
      BoardCell(7, 4),
      BoardCell(7, 5),
    ],
    [
      BoardCell(13, 7),
      BoardCell(12, 7),
      BoardCell(11, 7),
      BoardCell(10, 7),
      BoardCell(9, 7),
    ],
    [
      BoardCell(7, 13),
      BoardCell(7, 12),
      BoardCell(7, 11),
      BoardCell(7, 10),
      BoardCell(7, 9),
    ],
  ];

  /// Safe squares (absolute): the four starts and the four stars.
  static const List<int> safeTrackIndices = [0, 8, 13, 21, 26, 34, 39, 47];

  /// Star squares (absolute).
  static const List<int> starTrackIndices = [8, 21, 34, 47];

  /// Top-left cell of each color's 6 × 6 base.
  static const List<BoardCell> baseOrigins = [
    BoardCell(0, 0),
    BoardCell(9, 0),
    BoardCell(9, 9),
    BoardCell(0, 9),
  ];

  /// Center of the 3 × 3 home area.
  static const Offset boardCenter = Offset(7.5, 7.5);

  static final Map<BoardCell, int> _trackIndexByCell = {
    for (var i = 0; i < track.length; i++) track[i]: i,
  };

  /// Absolute start square of [color] (`13 × colorIndex`).
  static int startIndex(SeatColor color) => 13 * color.index;

  /// Absolute track index for [progress] 0..50 of [color].
  static int absoluteIndex(SeatColor color, int progress) {
    if (progress < 0 || progress > lastTrackProgress) {
      throw RangeError.range(progress, 0, lastTrackProgress, 'progress');
    }
    return (13 * color.index + progress) % trackLength;
  }

  /// Cell of absolute track index [index] 0..51.
  static BoardCell trackCell(int index) {
    RangeError.checkValueInInterval(index, 0, trackLength - 1, 'index');
    return track[index];
  }

  /// Absolute track index of [cell], or null when it is not on the track.
  static int? trackIndexOf(BoardCell cell) => _trackIndexByCell[cell];

  static bool isSafeTrackIndex(int index) => safeTrackIndices.contains(index);

  static bool isStarTrackIndex(int index) => starTrackIndices.contains(index);

  /// The color whose start square is absolute [index], if any.
  static SeatColor? startColorAt(int index) =>
      index % 13 == 0 ? SeatColor.values[index ~/ 13] : null;

  /// Home column cells (progress 51..55 in order) of [color].
  static List<BoardCell> homeColumn(SeatColor color) =>
      homeColumns[color.index];

  /// The 6 × 6 base area of [color] in grid units.
  static Rect baseRect(SeatColor color) {
    final o = baseOrigins[color.index];
    return Rect.fromLTWH(o.col.toDouble(), o.row.toDouble(), 6, 6);
  }

  /// The three vertices of [color]'s home triangle (grid units). Red points
  /// in from the left, green from the top, yellow from the right, blue from
  /// the bottom.
  static List<Offset> homeTriangle(SeatColor color) {
    switch (color) {
      case SeatColor.red:
        return const [Offset(6, 6), Offset(6, 9), boardCenter];
      case SeatColor.green:
        return const [Offset(6, 6), Offset(9, 6), boardCenter];
      case SeatColor.yellow:
        return const [Offset(9, 6), Offset(9, 9), boardCenter];
      case SeatColor.blue:
        return const [Offset(6, 9), Offset(9, 9), boardCenter];
    }
  }

  /// Visual resting point of finished tokens of [color] (inside its
  /// triangle, toward its outer edge).
  static Offset homeCenter(SeatColor color) {
    switch (color) {
      case SeatColor.red:
        return const Offset(6.58, 7.5);
      case SeatColor.green:
        return const Offset(7.5, 6.58);
      case SeatColor.yellow:
        return const Offset(8.42, 7.5);
      case SeatColor.blue:
        return const Offset(7.5, 8.42);
    }
  }

  /// Direction (unit grid vector) along which finished tokens line up.
  static Offset homeSpread(SeatColor color) =>
      color == SeatColor.red || color == SeatColor.yellow
      ? const Offset(0, 1)
      : const Offset(1, 0);

  /// Base slot (0 TL, 1 TR, 2 BL, 3 BR) used by [tokenIndex].
  ///
  /// With 4 tokens per player token i uses slot i. With 2 tokens (Quick
  /// Ludo) the tokens use the diagonal pair pointing at the board center:
  /// red/yellow TL + BR, green/blue TR + BL. Other counts fill slots in
  /// order.
  static int baseSlotFor(SeatColor color, int tokenIndex, int tokensPerPlayer) {
    if (tokensPerPlayer == 2) {
      final diagonal = color == SeatColor.red || color == SeatColor.yellow
          ? const [0, 3]
          : const [1, 2];
      return diagonal[tokenIndex.clamp(0, 1)];
    }
    return tokenIndex.clamp(0, 3);
  }

  /// Center of base [slot] of [color] (grid units).
  static Offset baseSlotCenter(SeatColor color, int slot) {
    final o = baseOrigins[color.index];
    final dx = slot.isEven ? 2.0 : 4.0;
    final dy = slot < 2 ? 2.0 : 4.0;
    return Offset(o.col + dx, o.row + dy);
  }

  /// Where a [color] token with [progress] stands.
  ///
  /// `-1` → base slot (depends on [tokenIndex] / [tokensPerPlayer]),
  /// `0..50` → main track, `51..55` → home column, `56` → home.
  static LudoSpot cellFor(
    SeatColor color,
    int progress, {
    required int tokenIndex,
    required int tokensPerPlayer,
  }) {
    if (progress == baseProgress) {
      final slot = baseSlotFor(color, tokenIndex, tokensPerPlayer);
      return LudoSpot._(
        kind: LudoSpotKind.base,
        color: color,
        center: baseSlotCenter(color, slot),
        baseSlot: slot,
      );
    }
    return _spot(color, progress);
  }

  static LudoSpot _spot(SeatColor color, int progress) {
    if (progress >= 0 && progress <= lastTrackProgress) {
      final index = absoluteIndex(color, progress);
      final cell = track[index];
      return LudoSpot._(
        kind: LudoSpotKind.track,
        color: color,
        center: cell.center,
        cell: cell,
        trackIndex: index,
      );
    }
    if (progress >= firstHomeColumnProgress && progress < homeProgress) {
      final cell = homeColumns[color.index][progress - firstHomeColumnProgress];
      return LudoSpot._(
        kind: LudoSpotKind.homeColumn,
        color: color,
        center: cell.center,
        cell: cell,
      );
    }
    if (progress == homeProgress) {
      return LudoSpot._(
        kind: LudoSpotKind.home,
        color: color,
        center: homeCenter(color),
      );
    }
    throw RangeError.range(progress, baseProgress, homeProgress, 'progress');
  }

  /// The spots a token visits moving from [fromProgress] to [toProgress],
  /// excluding the start and including the destination. Leaving base
  /// (`-1 → 0`) is a single hop onto the start square.
  ///
  /// Returns an empty list when the move is not forward.
  static List<LudoSpot> pathCells(
    SeatColor color,
    int fromProgress,
    int toProgress,
  ) {
    if (toProgress <= fromProgress) return const [];
    RangeError.checkValueInInterval(
      fromProgress,
      baseProgress,
      homeProgress,
      'fromProgress',
    );
    RangeError.checkValueInInterval(toProgress, 0, homeProgress, 'toProgress');
    return [
      for (var p = fromProgress + 1; p <= toProgress; p++) _spot(color, p),
    ];
  }

  /// Steps still needed to finish from [progress] (base counts as 57).
  static int stepsToHome(int progress) =>
      progress < 0 ? homeProgress + 1 : homeProgress - progress;
}

/// Pixel layout of a square Ludo board (grid + decorative frame) fitted in
/// a given size.
@immutable
class LudoBoardLayout {
  const LudoBoardLayout._(this.cell, this.gridOrigin, this.boardRect);

  /// Decorative frame around the grid, in grid units.
  static const double frameInset = 0.3;

  /// Total board side in grid units (grid + frame).
  static const double totalUnits = LudoGeometry.gridSize + 2 * frameInset;

  /// Fits a square board centered in [size].
  factory LudoBoardLayout.fit(Size size) {
    final side = size.shortestSide;
    final cell = side / totalUnits;
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;
    return LudoBoardLayout._(
      cell,
      Offset(left + frameInset * cell, top + frameInset * cell),
      Rect.fromLTWH(left, top, side, side),
    );
  }

  /// Pixel size of one grid unit.
  final double cell;

  /// Pixel position of grid point (0, 0).
  final Offset gridOrigin;

  /// Whole board including the frame.
  final Rect boardRect;

  Offset toPx(Offset grid) =>
      Offset(gridOrigin.dx + grid.dx * cell, gridOrigin.dy + grid.dy * cell);

  Offset toGrid(Offset px) =>
      Offset((px.dx - gridOrigin.dx) / cell, (px.dy - gridOrigin.dy) / cell);

  Rect cellRect(BoardCell c) => Rect.fromLTWH(
    gridOrigin.dx + c.col * cell,
    gridOrigin.dy + c.row * cell,
    cell,
    cell,
  );
}
