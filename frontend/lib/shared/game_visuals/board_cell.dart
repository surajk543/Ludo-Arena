import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// A grid cell `(col, row)` with `(0, 0)` at the top-left of the board grid.
///
/// Board geometry is always expressed in *grid units*: one unit is one cell,
/// so the center of a cell is `(col + 0.5, row + 0.5)`. Painters convert grid
/// units to pixels with a single scale + offset, which keeps every board
/// resolution independent.
@immutable
class BoardCell {
  const BoardCell(this.col, this.row);

  final int col;
  final int row;

  /// Center of the cell in grid units.
  Offset get center => Offset(col + 0.5, row + 0.5);

  @override
  bool operator ==(Object other) =>
      other is BoardCell && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => '($col,$row)';
}
