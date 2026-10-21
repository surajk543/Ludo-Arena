import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'snakes_board_theme.dart';
import 'snakes_geometry.dart';

/// Paints the static Snakes & Ladders board: frame, plinth with start pad,
/// cells, numbers, finish square, ladders and snakes.
///
/// Everything except text is drawn in grid units under one
/// `translate + scale`, so the cached geometry paths ([_SnakeArt],
/// [_LadderArt]) are size independent and built once per process. Text is
/// laid out per cell size and cached. Use inside a [RepaintBoundary] with
/// `isComplex: true, willChange: false`; it only repaints when the theme,
/// palette, detail level or size changes.
class SnakesBoardPainter extends CustomPainter {
  SnakesBoardPainter({required this.style, this.detailed = true});

  final SnakesBoardStyle style;

  /// False for mini boards: no numbers, patterns or tile decorations.
  final bool detailed;

  static final Paint _paint = Paint()..isAntiAlias = true;
  static final Paint _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final layout = SnakesBoardLayout.fit(size);
    canvas.save();
    canvas.translate(layout.gridOrigin.dx, layout.gridOrigin.dy);
    // Static art in tile space, stretched to the taller rows.
    canvas.save();
    canvas.scale(layout.cell, layout.cell * SnakesGeometry.rowHeight);
    _paintFrame(canvas);
    _paintCells(canvas);
    _paintFinishSquare(canvas);
    _paintStartPad(canvas);
    if (detailed) _paintPlinthDecor(canvas);
    canvas.restore();
    // Ladders, snakes and the finish ring in grid units (unstretched).
    canvas.scale(layout.cell);
    for (final ladder in SnakesGeometry.allLadders) {
      _paintLadder(canvas, _LadderArt.of(ladder));
    }
    var i = 0;
    for (final body in SnakesGeometry.allSnakes) {
      final skin = style.snakes[i % style.snakes.length];
      _paintSnake(canvas, _SnakeArt.of(body, skin.kind), skin);
      i++;
    }
    _paintFinishRing(canvas);
    canvas.restore();
    if (detailed) _paintNumbers(canvas, layout);
  }

  // ---------------------------------------------------------------------------
  // Frame & plinth.

  void _paintFrame(Canvas canvas) {
    const f = SnakesGeometry.frameInset;
    const bottom = 10 + SnakesGeometry.plinthHeight + f;
    final outer = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-f, -f, 10 + f, bottom),
      const Radius.circular(0.42),
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(0, -f),
        const Offset(0, bottom),
        [style.frameTop, style.frameBottom],
      );
    canvas.drawRRect(outer, _paint);
    _paint.shader = null;

    _stroke
      ..strokeWidth = 0.06
      ..color = style.frameEdge
      ..shader = null;
    canvas.drawRRect(outer.deflate(0.03), _stroke);
    _stroke
      ..strokeWidth = 0.025
      ..color = Colors.white.withValues(alpha: style.isDark ? 0.08 : 0.22);
    canvas.drawRRect(outer.deflate(0.1), _stroke);

    if (detailed) _paintFrameDecor(canvas);

    // Recessed well behind the grid.
    _paint.color = style.frameEdge.withValues(alpha: 0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-0.08, -0.06, 10.08, 10.1),
        const Radius.circular(0.12),
      ),
      _paint,
    );
  }

  void _paintFrameDecor(Canvas canvas) {
    const f = SnakesGeometry.frameInset;
    const bottom = 10 + SnakesGeometry.plinthHeight + f;
    switch (style.tiles) {
      case TileKind.flat:
        // Stitched trim along the frame.
        _paint.color = style.frameTrim.withValues(alpha: 0.45);
        for (var x = 0.2; x < 10; x += 0.4) {
          canvas.drawCircle(Offset(x, -f / 2), 0.03, _paint);
        }
        for (var y = 0.2; y < 10; y += 0.4) {
          canvas.drawCircle(Offset(-f / 2, y), 0.03, _paint);
          canvas.drawCircle(Offset(10 + f / 2, y), 0.03, _paint);
        }
      case TileKind.stone:
        // Carved notches.
        _paint.color = style.frameEdge.withValues(alpha: 0.55);
        for (var x = 0.25; x < 10; x += 0.75) {
          canvas.drawRect(Rect.fromLTWH(x, -f + 0.08, 0.32, f - 0.16), _paint);
          canvas.drawRect(
            Rect.fromLTWH(x, bottom - f + 0.08, 0.32, f - 0.16),
            _paint,
          );
        }
        for (var y = 0.25; y < 10.5; y += 0.75) {
          canvas.drawRect(Rect.fromLTWH(-f + 0.08, y, f - 0.16, 0.32), _paint);
          canvas.drawRect(Rect.fromLTWH(10 + 0.08, y, f - 0.16, 0.32), _paint);
        }
        _paintVines(canvas);
      case TileKind.candy:
        // Frosting scallops around the grid.
        _paint.color = style.frameTrim.withValues(alpha: 0.95);
        for (var x = 0.25; x < 10; x += 0.5) {
          canvas.drawCircle(Offset(x, -0.04), 0.16, _paint);
        }
        for (var y = 0.25; y < 10; y += 0.5) {
          canvas.drawCircle(Offset(-0.04, y), 0.16, _paint);
          canvas.drawCircle(Offset(10.04, y), 0.16, _paint);
        }
        _sprinkles(canvas, const Rect.fromLTRB(3.8, 10.15, 9.9, 11.05), 22, 7);
    }
  }

  void _paintVines(Canvas canvas) {
    final leaf = style.decorA;
    final vine = Color.lerp(style.decorA, Colors.black, 0.35)!;
    final path = Path()
      ..moveTo(-0.2, 3.8)
      ..cubicTo(-0.35, 2.6, 0.05, 1.8, -0.18, 0.9)
      ..cubicTo(-0.3, 0.2, 0.3, -0.35, 1.2, -0.18)
      ..cubicTo(2.0, -0.05, 2.6, -0.32, 3.4, -0.16);
    _stroke
      ..strokeWidth = 0.05
      ..color = vine;
    canvas.drawPath(path, _stroke);
    final path2 = Path()
      ..moveTo(10.2, 6.5)
      ..cubicTo(10.35, 7.4, 10.0, 8.2, 10.18, 9.1)
      ..cubicTo(10.3, 9.9, 9.8, 10.4, 9.0, 10.3);
    canvas.drawPath(path2, _stroke);
    _paint.color = leaf;
    const leaves = [
      Offset(-0.22, 3.2),
      Offset(-0.12, 2.3),
      Offset(-0.2, 1.4),
      Offset(0.0, 0.2),
      Offset(0.8, -0.24),
      Offset(1.7, -0.1),
      Offset(2.6, -0.24),
      Offset(10.22, 7.2),
      Offset(10.12, 8.4),
      Offset(10.1, 9.6),
    ];
    for (var i = 0; i < leaves.length; i++) {
      final c = leaves[i];
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i.isEven ? 0.7 : -0.5);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 0.32, height: 0.15),
        _paint,
      );
      canvas.restore();
    }
  }

  void _sprinkles(Canvas canvas, Rect area, int count, int seed) {
    final colors = [
      style.decorA,
      style.decorB,
      const Color(0xFFFFD43B),
      const Color(0xFF8BE3A6),
      Colors.white,
    ];
    _stroke.strokeWidth = 0.055;
    for (var i = 0; i < count; i++) {
      final hx = _hash(seed, i * 3);
      final hy = _hash(seed, i * 3 + 1);
      final ha = _hash(seed, i * 3 + 2);
      final c = Offset(
        area.left + hx * area.width,
        area.top + hy * area.height,
      );
      final d = Offset(math.cos(ha * math.pi), math.sin(ha * math.pi)) * 0.065;
      _stroke.color = colors[i % colors.length];
      canvas.drawLine(c - d, c + d, _stroke);
    }
  }

  // ---------------------------------------------------------------------------
  // Cells.

  void _paintCells(Canvas canvas) {
    switch (style.tiles) {
      case TileKind.flat:
        for (var row = 0; row < 10; row++) {
          for (var col = 0; col < 10; col++) {
            _paint.color = style.cellColor(col, row);
            canvas.drawRect(
              Rect.fromLTWH(col.toDouble(), row.toDouble(), 1.002, 1.002),
              _paint,
            );
          }
        }
        // Soft inner gloss on colored cells.
        if (detailed) {
          _paint.color = Colors.white.withValues(
            alpha: style.isDark ? 0.04 : 0.18,
          );
          for (var row = 0; row < 10; row++) {
            for (var col = 0; col < 10; col++) {
              if ((col + row).isEven) continue;
              canvas.drawRect(
                Rect.fromLTWH(col + 0.06, row + 0.06, 0.88, 0.3),
                _paint,
              );
            }
          }
        }
        _stroke
          ..strokeWidth = 0.02
          ..color = style.gridLine;
        for (var i = 1; i < 10; i++) {
          canvas.drawLine(
            Offset(i.toDouble(), 0),
            Offset(i.toDouble(), 10),
            _stroke,
          );
          canvas.drawLine(
            Offset(0, i.toDouble()),
            Offset(10, i.toDouble()),
            _stroke,
          );
        }
      case TileKind.stone:
        _paint.color = style.mortar;
        canvas.drawRect(const Rect.fromLTWH(0, 0, 10, 10), _paint);
        for (var row = 0; row < 10; row++) {
          for (var col = 0; col < 10; col++) {
            final r = RRect.fromRectAndRadius(
              Rect.fromLTWH(col + 0.04, row + 0.04, 0.92, 0.92),
              const Radius.circular(0.08),
            );
            _paint.color = style.cellColor(col, row);
            canvas.drawRRect(r, _paint);
            if (!detailed) continue;
            // Bevel.
            _stroke
              ..strokeWidth = 0.035
              ..color = Colors.white.withValues(
                alpha: style.isDark ? 0.07 : 0.28,
              );
            canvas.drawLine(
              Offset(col + 0.1, row + 0.08),
              Offset(col + 0.9, row + 0.08),
              _stroke,
            );
            canvas.drawLine(
              Offset(col + 0.08, row + 0.1),
              Offset(col + 0.08, row + 0.9),
              _stroke,
            );
            _stroke.color = Colors.black.withValues(
              alpha: style.isDark ? 0.3 : 0.16,
            );
            canvas.drawLine(
              Offset(col + 0.1, row + 0.92),
              Offset(col + 0.9, row + 0.92),
              _stroke,
            );
            final h = _hash(col, row);
            if (h < 0.22) {
              // Moss patch in a lower corner.
              final corner = Offset(col + (h < 0.11 ? 0.2 : 0.8), row + 0.82);
              _paint.color = style.decorA.withValues(alpha: 0.75);
              canvas.drawCircle(corner, 0.13, _paint);
              canvas.drawCircle(
                corner + const Offset(0.12, 0.04),
                0.09,
                _paint,
              );
              canvas.drawCircle(
                corner + const Offset(-0.1, 0.05),
                0.08,
                _paint,
              );
            } else if (h > 0.84) {
              // Crack.
              _stroke
                ..strokeWidth = 0.022
                ..color = style.decorB;
              canvas.drawLine(
                Offset(col + 0.55, row + 0.3),
                Offset(col + 0.68, row + 0.52),
                _stroke,
              );
              canvas.drawLine(
                Offset(col + 0.68, row + 0.52),
                Offset(col + 0.6, row + 0.74),
                _stroke,
              );
              canvas.drawLine(
                Offset(col + 0.68, row + 0.52),
                Offset(col + 0.84, row + 0.6),
                _stroke,
              );
            }
          }
        }
      case TileKind.candy:
        _paint.color = style.mortar;
        canvas.drawRect(const Rect.fromLTWH(0, 0, 10, 10), _paint);
        for (var row = 0; row < 10; row++) {
          for (var col = 0; col < 10; col++) {
            final r = RRect.fromRectAndRadius(
              Rect.fromLTWH(col + 0.05, row + 0.05, 0.9, 0.9),
              const Radius.circular(0.2),
            );
            _paint.color = style.cellColor(col, row);
            canvas.drawRRect(r, _paint);
            if (!detailed) continue;
            _paint.color = Colors.white.withValues(
              alpha: style.isDark ? 0.07 : 0.4,
            );
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(col + 0.16, row + 0.12, 0.68, 0.16),
                const Radius.circular(0.08),
              ),
              _paint,
            );
            if (_hash(col * 3, row * 5) < 0.3) {
              _sprinkles(
                canvas,
                Rect.fromLTWH(col + 0.5, row + 0.55, 0.36, 0.3),
                2,
                col * 10 + row,
              );
            }
          }
        }
    }
  }

  void _paintFinishSquare(Canvas canvas) {
    final cell = SnakesGeometry.cellFor(100);
    final rect = Rect.fromLTWH(cell.col.toDouble(), cell.row.toDouble(), 1, 1);
    final inset = switch (style.tiles) {
      TileKind.flat => 0.0,
      TileKind.stone => 0.04,
      TileKind.candy => 0.05,
    };
    final radius = switch (style.tiles) {
      TileKind.flat => 0.0,
      TileKind.stone => 0.08,
      TileKind.candy => 0.2,
    };
    final tile = RRect.fromRectAndRadius(
      rect.deflate(inset),
      Radius.circular(radius),
    );
    _paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.radial(
        rect.center - const Offset(0.1, 0.12),
        0.8,
        [style.finishLight, style.finishDeep],
      );
    canvas.drawRRect(tile, _paint);
    _paint.shader = null;
    // Rays.
    canvas.save();
    canvas.clipRRect(tile);
    _paint.color = Colors.white.withValues(alpha: 0.22);
    final c = rect.center;
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5;
      final p = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(
          c.dx + math.cos(a - 0.12) * 1.2,
          c.dy + math.sin(a - 0.12) * 1.2,
        )
        ..lineTo(
          c.dx + math.cos(a + 0.12) * 1.2,
          c.dy + math.sin(a + 0.12) * 1.2,
        )
        ..close();
      canvas.drawPath(p, _paint);
    }
    canvas.restore();
    // Star (undo the row stretch so it keeps its shape).
    canvas.save();
    canvas.translate(c.dx, c.dy + 0.04);
    canvas.scale(1, 1 / SnakesGeometry.rowHeight);
    final star = _starPath(Offset.zero, 0.4, 0.17);
    _paint.color = Colors.white.withValues(alpha: 0.92);
    canvas.drawPath(star, _paint);
    _stroke
      ..strokeWidth = 0.035
      ..color = style.finishDeep;
    canvas.drawPath(star, _stroke);
    canvas.restore();
    _stroke
      ..strokeWidth = 0.04
      ..color = Color.lerp(style.finishDeep, Colors.black, 0.25)!;
    canvas.drawRRect(tile.deflate(0.02), _stroke);
  }

  /// Gold ring around square 100, drawn above ladders so the finish always
  /// reads clearly.
  void _paintFinishRing(Canvas canvas) {
    final cell = SnakesGeometry.cellFor(100);
    const h = SnakesGeometry.rowHeight;
    final rect = Rect.fromLTWH(
      cell.col.toDouble(),
      cell.row * h,
      1,
      h,
    ).deflate(0.035);
    final ring = RRect.fromRectAndRadius(
      rect,
      Radius.circular(style.tiles == TileKind.candy ? 0.2 : 0.1),
    );
    _stroke
      ..strokeWidth = 0.1
      ..color = Colors.white.withValues(alpha: style.isDark ? 0.25 : 0.6);
    canvas.drawRRect(ring.inflate(0.01), _stroke);
    _stroke
      ..strokeWidth = 0.06
      ..color = style.finishDeep;
    canvas.drawRRect(ring, _stroke);
    _stroke
      ..strokeWidth = 0.02
      ..color = style.finishLight;
    canvas.drawRRect(ring.deflate(0.015), _stroke);
  }

  static Path _starPath(Offset c, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  void _paintStartPad(Canvas canvas) {
    const pad = SnakesGeometry.startPadRect;
    final rr = RRect.fromRectAndRadius(pad, const Radius.circular(0.34));
    _paint.color = Colors.black.withValues(alpha: 0.18);
    canvas.drawRRect(rr.shift(const Offset(0.03, 0.05)), _paint);
    _paint.color = style.padFill;
    canvas.drawRRect(rr, _paint);
    _stroke
      ..strokeWidth = 0.045
      ..color = style.padEdge;
    canvas.drawRRect(rr, _stroke);
    // Seat wells.
    _paint.color = style.padEdge.withValues(alpha: 0.22);
    for (var seat = 0; seat < 4; seat++) {
      final s = SnakesGeometry.startSlotTile(seat);
      canvas.drawOval(
        Rect.fromCenter(
          center: s + const Offset(0, 0.2),
          width: 0.62,
          height: 0.22,
        ),
        _paint,
      );
    }
    // Arrow pointing up into square 1.
    final first = SnakesGeometry.cellFor(1).center;
    final arrow = Path()
      ..moveTo(first.dx, 10.03)
      ..lineTo(first.dx + 0.26, pad.top + 0.06)
      ..lineTo(first.dx + 0.11, pad.top + 0.06)
      ..lineTo(first.dx + 0.11, pad.top + 0.12)
      ..lineTo(first.dx - 0.11, pad.top + 0.12)
      ..lineTo(first.dx - 0.11, pad.top + 0.06)
      ..lineTo(first.dx - 0.26, pad.top + 0.06)
      ..close();
    _paint.color = style.arrow;
    canvas.drawPath(arrow, _paint);
    _stroke
      ..strokeWidth = 0.025
      ..color = Color.lerp(style.arrow, Colors.black, 0.35)!;
    canvas.drawPath(arrow, _stroke);
  }

  /// Decoration on the free part of the plinth, right of the start pad.
  void _paintPlinthDecor(Canvas canvas) {
    const area = Rect.fromLTRB(4.1, 10.25, 9.9, 10.95);
    switch (style.tiles) {
      case TileKind.flat:
        final grass = Color.lerp(style.frameTop, Colors.white, 0.25)!;
        _stroke
          ..strokeWidth = 0.035
          ..color = grass;
        for (var i = 0; i < 9; i++) {
          final x = area.left + 0.3 + i * 0.66;
          final y = area.bottom - 0.08;
          canvas.drawLine(Offset(x, y), Offset(x - 0.06, y - 0.2), _stroke);
          canvas.drawLine(
            Offset(x + 0.06, y),
            Offset(x + 0.1, y - 0.24),
            _stroke,
          );
          canvas.drawLine(
            Offset(x + 0.12, y),
            Offset(x + 0.22, y - 0.16),
            _stroke,
          );
        }
        const petals = [
          Color(0xFFFFFFFF),
          Color(0xFFFFD6E4),
          Color(0xFFFFF0A3),
        ];
        for (var i = 0; i < 5; i++) {
          final c = Offset(
            area.left + 0.65 + i * 1.18,
            area.top + 0.3 + (i.isEven ? 0.0 : 0.12),
          );
          _paint.color = petals[i % petals.length];
          for (var k = 0; k < 5; k++) {
            final a = k * 2 * math.pi / 5;
            canvas.drawCircle(
              c + Offset(math.cos(a), math.sin(a)) * 0.085,
              0.065,
              _paint,
            );
          }
          _paint.color = const Color(0xFFF5B800);
          canvas.drawCircle(c, 0.05, _paint);
        }
      case TileKind.stone:
        _paint.color = style.decorA.withValues(alpha: 0.85);
        for (var i = 0; i < 7; i++) {
          final c = Offset(area.left + 0.4 + i * 0.85, area.bottom - 0.12);
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(i.isEven ? -0.5 : 0.5);
          canvas.drawOval(
            Rect.fromCenter(
              center: const Offset(0, -0.12),
              width: 0.14,
              height: 0.34,
            ),
            _paint,
          );
          canvas.restore();
        }
        _paint.color = Color.lerp(style.cellBase, Colors.black, 0.25)!;
        for (var i = 0; i < 4; i++) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(area.left + 0.9 + i * 1.4, area.top + 0.35),
              width: 0.36,
              height: 0.2,
            ),
            _paint,
          );
        }
      case TileKind.candy:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Ladders.

  void _paintLadder(Canvas canvas, _LadderArt art) {
    final l = style.ladder;
    final rails = art.rails;
    // Shadow.
    _stroke
      ..shader = null
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: style.isDark ? 0.35 : 0.22);
    canvas.save();
    canvas.translate(0.05, 0.08);
    _stroke.strokeWidth = 0.1;
    for (final (a, b) in art.rungs) {
      canvas.drawLine(a, b, _stroke);
    }
    _stroke.strokeWidth = 0.16;
    canvas.drawLine(rails.leftStart, rails.leftEnd, _stroke);
    canvas.drawLine(rails.rightStart, rails.rightEnd, _stroke);
    canvas.restore();

    // Rungs (under the rails).
    for (final (a, b) in art.rungs) {
      _stroke
        ..strokeWidth = 0.11
        ..color = l.rungDark;
      canvas.drawLine(a, b, _stroke);
      _stroke
        ..strokeWidth = 0.07
        ..color = l.rungMid;
      canvas.drawLine(a, b, _stroke);
      if (detailed) {
        _stroke
          ..strokeWidth = 0.02
          ..color = l.rungLight;
        canvas.drawLine(
          a + const Offset(-0.01, -0.018),
          b + const Offset(-0.01, -0.018),
          _stroke,
        );
      }
    }

    // Rails.
    for (final (s, e, poly) in [
      (rails.leftStart, rails.leftEnd, art.leftPoly),
      (rails.rightStart, rails.rightEnd, art.rightPoly),
    ]) {
      _stroke
        ..strokeWidth = 0.15
        ..color = l.railDark;
      canvas.drawLine(s, e, _stroke);
      _stroke
        ..strokeWidth = 0.11
        ..color = l.railMid;
      canvas.drawLine(s, e, _stroke);
      if (l.kind == LadderKind.candyCane) {
        canvas.save();
        canvas.clipPath(poly);
        _stroke
          ..strokeWidth = 0.075
          ..strokeCap = StrokeCap.butt
          ..color = l.accent;
        final d = e - s;
        final len = d.distance;
        final u = d / len;
        final n = Offset(-u.dy, u.dx);
        for (var x = 0.0; x < len + 0.2; x += 0.24) {
          final c = s + u * x;
          canvas.drawLine(
            c - n * 0.1 - u * 0.08,
            c + n * 0.1 + u * 0.08,
            _stroke,
          );
        }
        _stroke.strokeCap = StrokeCap.round;
        canvas.restore();
      }
      if (detailed) {
        _stroke
          ..strokeWidth = 0.03
          ..color = l.railLight.withValues(
            alpha: l.kind == LadderKind.candyCane ? 0.7 : 0.9,
          );
        canvas.drawLine(
          s + const Offset(-0.022, -0.022),
          e + const Offset(-0.022, -0.022),
          _stroke,
        );
      }
      if (detailed && l.kind == LadderKind.bamboo) {
        final d = e - s;
        final len = d.distance;
        final u = d / len;
        final n = Offset(-u.dy, u.dx);
        for (var x = 0.45; x < len - 0.2; x += 0.6) {
          final c = s + u * x;
          _stroke
            ..strokeWidth = 0.03
            ..color = l.railDark;
          canvas.drawLine(c - n * 0.065, c + n * 0.065, _stroke);
          _stroke.color = l.railLight;
          canvas.drawLine(
            c - n * 0.05 + u * 0.035,
            c + n * 0.05 + u * 0.035,
            _stroke,
          );
        }
      }
      if (detailed && l.kind == LadderKind.wood) {
        _stroke
          ..strokeWidth = 0.012
          ..color = l.accent.withValues(alpha: 0.4);
        canvas.drawLine(
          s + const Offset(0.02, 0.02),
          e + const Offset(0.02, 0.02),
          _stroke,
        );
      }
    }

    // Joints: nails, lashings.
    if (detailed) {
      for (final (a, b) in art.rungs) {
        for (final p in [a, b]) {
          if (l.kind == LadderKind.bamboo) {
            _stroke
              ..strokeWidth = 0.025
              ..color = l.accent;
            canvas.drawLine(
              p + const Offset(-0.06, -0.05),
              p + const Offset(0.06, 0.05),
              _stroke,
            );
            canvas.drawLine(
              p + const Offset(-0.06, 0.05),
              p + const Offset(0.06, -0.05),
              _stroke,
            );
          } else if (l.kind == LadderKind.wood) {
            _paint.color = l.railDark;
            canvas.drawCircle(p, 0.025, _paint);
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Snakes.

  void _paintSnake(Canvas canvas, _SnakeArt art, SnakeSkin skin) {
    // Shadow.
    _paint
      ..shader = null
      ..color = Colors.black.withValues(alpha: style.isDark ? 0.38 : 0.22);
    canvas.save();
    canvas.translate(0.05, 0.08);
    canvas.drawPath(art.body, _paint);
    canvas.restore();

    _paint.color = skin.body;
    canvas.drawPath(art.body, _paint);
    _paint.color = skin.shade.withValues(alpha: 0.75);
    canvas.drawPath(art.shade, _paint);
    _paint.color = skin.highlight.withValues(alpha: 0.6);
    canvas.drawPath(art.highlight, _paint);

    if (detailed) {
      canvas.save();
      canvas.clipPath(art.body);
      _paint.color = skin.kind == SnakePattern.candyStripes
          ? skin.pattern.withValues(alpha: 0.88)
          : skin.pattern;
      canvas.drawPath(art.pattern, _paint);
      // Re-apply a light gloss over the pattern for roundness.
      _paint.color = Colors.white.withValues(alpha: 0.16);
      canvas.drawPath(art.highlight, _paint);
      canvas.restore();
    }

    _stroke
      ..strokeWidth = 0.032
      ..color = skin.outline;
    canvas.drawPath(art.body, _stroke);

    _paintHead(canvas, art, skin);
  }

  void _paintHead(Canvas canvas, _SnakeArt art, SnakeSkin skin) {
    canvas.save();
    canvas.translate(art.headPoint.dx, art.headPoint.dy);
    canvas.rotate(art.headAngle);
    canvas.scale(art.headScale);

    // Forked tongue.
    _stroke
      ..strokeWidth = 0.03
      ..color = const Color(0xFFD7263D);
    canvas.drawPath(_tongue, _stroke);

    _paint.color = skin.body;
    canvas.drawPath(_headPath, _paint);
    // Shading toward the shaded side, highlight toward the light.
    final light = art.localLight;
    _paint.color = skin.shade.withValues(alpha: 0.55);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0.1, -light.dy * 0.1),
        width: 0.42,
        height: 0.16,
      ),
      _paint,
    );
    _paint.color = skin.highlight.withValues(alpha: 0.8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0.14, light.dy * 0.08),
        width: 0.3,
        height: 0.1,
      ),
      _paint,
    );
    if (detailed && skin.kind != SnakePattern.candyStripes) {
      _stroke
        ..strokeWidth = 0.035
        ..color = skin.pattern;
      canvas.drawPath(_headMark, _stroke);
    }
    _stroke
      ..strokeWidth = 0.032
      ..color = skin.outline;
    canvas.drawPath(_headPath, _stroke);

    // Eyes.
    for (final side in const [-1.0, 1.0]) {
      final eye = Offset(0.14, 0.11 * side);
      _paint.color = Colors.white;
      canvas.drawCircle(eye, 0.064, _paint);
      _stroke
        ..strokeWidth = 0.016
        ..color = skin.outline;
      canvas.drawCircle(eye, 0.064, _stroke);
      _paint.color = const Color(0xFF14110F);
      canvas.drawOval(
        Rect.fromCenter(
          center: eye + const Offset(0.014, 0),
          width: 0.05,
          height: 0.07,
        ),
        _paint,
      );
      _paint.color = Colors.white;
      canvas.drawCircle(eye + const Offset(0.026, -0.02), 0.014, _paint);
      // Nostrils.
      _paint.color = skin.outline;
      canvas.drawCircle(Offset(0.33, 0.045 * side), 0.014, _paint);
    }
    canvas.restore();
  }

  static final Path _headPath = Path()
    ..moveTo(-0.14, -0.16)
    ..cubicTo(0.08, -0.25, 0.36, -0.18, 0.4, 0)
    ..cubicTo(0.36, 0.18, 0.08, 0.25, -0.14, 0.16)
    ..close();

  static final Path _headMark = Path()
    ..moveTo(-0.04, -0.09)
    ..lineTo(0.1, 0)
    ..lineTo(-0.04, 0.09);

  static final Path _tongue = Path()
    ..moveTo(0.36, 0)
    ..lineTo(0.54, 0)
    ..lineTo(0.62, -0.06)
    ..moveTo(0.54, 0)
    ..lineTo(0.62, 0.06);

  // ---------------------------------------------------------------------------
  // Numbers.

  void _paintNumbers(Canvas canvas, SnakesBoardLayout layout) {
    final sprites = _NumberSprites.of(layout.cell, style);
    final pad = Offset(layout.cell * 0.07, layout.cell * 0.04);
    for (var square = 1; square <= 99; square++) {
      final rect = layout.cellRect(SnakesGeometry.cellFor(square));
      final o = rect.topLeft + pad;
      sprites.halo[square].paint(canvas, o);
      sprites.fill[square].paint(canvas, o);
    }
    final rect = layout.cellRect(SnakesGeometry.cellFor(100));
    final halo = sprites.halo[0];
    final fill = sprites.fill[0];
    final o =
        rect.center -
        Offset(fill.width / 2, fill.height / 2) +
        Offset(0, layout.cell * 0.04);
    halo.paint(canvas, o);
    fill.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant SnakesBoardPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.detailed != detailed;

  static double _hash(int a, int b) {
    var h = a * 374761393 + b * 668265263 + 1013904223;
    h = (h ^ (h >> 13)) * 1274126177;
    h = h ^ (h >> 16);
    return (h & 0xFFFF) / 0xFFFF;
  }
}

/// Cached grid-unit geometry of one ladder.
class _LadderArt {
  _LadderArt._(this.rails, this.rungs, this.leftPoly, this.rightPoly);

  static final Map<int, _LadderArt> _cache = <int, _LadderArt>{};

  static _LadderArt of(LadderRails rails) =>
      _cache.putIfAbsent(rails.bottom, () {
        final rungs = [for (final t in rails.rungTs) rails.rungAt(t)];
        return _LadderArt._(
          rails,
          rungs,
          _railPoly(rails.leftStart, rails.leftEnd),
          _railPoly(rails.rightStart, rails.rightEnd),
        );
      });

  static Path _railPoly(Offset s, Offset e) {
    final d = e - s;
    final u = d / d.distance;
    final n = Offset(-u.dy, u.dx) * 0.055;
    return Path()
      ..addPolygon([s + n, e + n, e - n, s - n], true)
      ..addOval(Rect.fromCircle(center: s, radius: 0.055))
      ..addOval(Rect.fromCircle(center: e, radius: 0.055));
  }

  final LadderRails rails;
  final List<(Offset, Offset)> rungs;
  final Path leftPoly;
  final Path rightPoly;
}

/// Cached grid-unit geometry of one snake (body outline, shading bands,
/// pattern and head placement).
class _SnakeArt {
  _SnakeArt._({
    required this.body,
    required this.highlight,
    required this.shade,
    required this.pattern,
    required this.headPoint,
    required this.headAngle,
    required this.headScale,
    required this.localLight,
  });

  static final Map<int, _SnakeArt> _cache = <int, _SnakeArt>{};

  static _SnakeArt of(SnakeBody body, SnakePattern kind) =>
      _cache.putIfAbsent(body.head * 8 + kind.index, () => _build(body, kind));

  /// Half-width profile: slight neck, then a taper to the tail.
  static double halfWidth(SnakeBody body, double t) {
    final base = body.width / 2;
    if (t < 0.06) return base * (0.84 + 0.16 * t / 0.06);
    final u = (t - 0.06) / 0.94;
    return base * (1 - 0.9 * math.pow(u, 1.5));
  }

  static _SnakeArt _build(SnakeBody body, SnakePattern kind) {
    final n = math.max(32, (body.length * 14).round());
    final pts = <Offset>[];
    final nor = <Offset>[];
    final hw = <double>[];
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final tan = body.tangentAt(t);
      pts.add(body.pointAt(t));
      nor.add(Offset(-tan.dy, tan.dx));
      hw.add(halfWidth(body, t));
    }
    // Pick the side of the body facing the light (top-left).
    const light = Offset(-0.6, -0.8);
    var dot = 0.0;
    for (final v in nor) {
      dot += v.dx * light.dx + v.dy * light.dy;
    }
    final side = dot >= 0 ? 1.0 : -1.0;

    Path band(double a, double b, {double from = 0, double to = 1}) {
      final i0 = (from * n).round();
      final i1 = (to * n).round();
      final path = Path();
      for (var i = i0; i <= i1; i++) {
        final p = pts[i] + nor[i] * (hw[i] * b * side);
        if (i == i0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      for (var i = i1; i >= i0; i--) {
        final p = pts[i] + nor[i] * (hw[i] * a * side);
        path.lineTo(p.dx, p.dy);
      }
      return path..close();
    }

    final outline = band(-1, 1);
    // Pointed tail tip.
    final tailTan = body.tangentAt(1);
    final tip = pts.last + tailTan * 0.08;
    final bodyPath = Path()
      ..addPath(outline, Offset.zero)
      ..addPolygon([
        pts.last + nor.last * hw.last,
        tip,
        pts.last - nor.last * hw.last,
      ], true);

    final highlight = band(0.12, 0.62, from: 0.02, to: 0.94);
    final shade = band(-0.45, -1.0, from: 0.0, to: 1.0);

    final pattern = Path();
    Offset pointAt(double t) => body.pointAt(t);
    Offset normalAt(double t) {
      final tan = body.tangentAt(t);
      return Offset(-tan.dy, tan.dx);
    }

    final len = body.length;
    switch (kind) {
      case SnakePattern.bands:
        for (var s = 0.32; s < len - 0.15; s += 0.34) {
          final ta = (s - 0.055) / len;
          final tb = (s + 0.055) / len;
          final na = normalAt(ta) * (halfWidth(body, ta) * 1.15);
          final nb = normalAt(tb) * (halfWidth(body, tb) * 1.15);
          pattern.addPolygon([
            pointAt(ta) + na,
            pointAt(tb) + nb,
            pointAt(tb) - nb,
            pointAt(ta) - na,
          ], true);
        }
      case SnakePattern.diamonds:
        for (var s = 0.34; s < len - 0.2; s += 0.36) {
          final t = s / len;
          final p = pointAt(t);
          final tan = body.tangentAt(t);
          final nn = normalAt(t) * (halfWidth(body, t) * 0.66);
          pattern.addPolygon([
            p + tan * 0.12,
            p + nn,
            p - tan * 0.12,
            p - nn,
          ], true);
        }
      case SnakePattern.spots:
        var alt = 1.0;
        for (var s = 0.3; s < len - 0.15; s += 0.23) {
          final t = s / len;
          final w = halfWidth(body, t);
          final p = pointAt(t) + normalAt(t) * (w * 0.42 * alt);
          pattern.addOval(Rect.fromCircle(center: p, radius: w * 0.3));
          alt = -alt;
        }
      case SnakePattern.candyStripes:
        for (var s = 0.22; s < len; s += 0.26) {
          final ta = s / len;
          final tb = math.min(1.0, (s + 0.09) / len);
          final tc = math.min(1.0, (s + 0.21) / len);
          final td = math.min(1.0, (s + 0.12) / len);
          final wa = halfWidth(body, ta) * 1.2;
          final wb = halfWidth(body, tb) * 1.2;
          pattern.addPolygon([
            pointAt(ta) + normalAt(ta) * wa,
            pointAt(tb) + normalAt(tb) * wb,
            pointAt(tc) - normalAt(tc) * wb,
            pointAt(td) - normalAt(td) * wa,
          ], true);
        }
    }

    final fwd = -body.tangentAt(0);
    final angle = math.atan2(fwd.dy, fwd.dx);
    // Light direction in head-local coordinates.
    final ca = math.cos(-angle);
    final sa = math.sin(-angle);
    final local = Offset(
      light.dx * ca - light.dy * sa,
      light.dx * sa + light.dy * ca,
    );
    return _SnakeArt._(
      body: bodyPath,
      highlight: highlight,
      shade: shade,
      pattern: pattern,
      headPoint: pts.first,
      headAngle: angle,
      headScale: body.width / 0.34,
      localLight: local,
    );
  }

  final Path body;
  final Path highlight;
  final Path shade;
  final Path pattern;
  final Offset headPoint;
  final double headAngle;
  final double headScale;

  /// Light direction in head-local coordinates (x forward).
  final Offset localLight;
}

/// Laid-out number labels for one cell size and style (index 0 = "100").
class _NumberSprites {
  _NumberSprites._(this.fill, this.halo);

  static final Map<int, _NumberSprites> _cache = <int, _NumberSprites>{};

  static _NumberSprites of(double cell, SnakesBoardStyle style) {
    final key = Object.hash(
      (cell * 4).round(),
      style.numberInk,
      style.numberHalo,
      style.finishInk,
    );
    return _cache.putIfAbsent(key, () {
      if (_cache.length > 6) _cache.clear();
      final small = cell * 0.27;
      final big = cell * 0.31;
      TextPainter make(String text, double size, Color color, {double? halo}) {
        final style = TextStyle(
          fontFamily: 'Fredoka',
          fontWeight: FontWeight.w600,
          fontSize: size,
          height: 1,
          color: halo == null ? color : null,
          foreground: halo == null
              ? null
              : (Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = halo
                  ..strokeJoin = StrokeJoin.round
                  ..color = color),
        );
        return TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
      }

      final fill = <TextPainter>[];
      final halo = <TextPainter>[];
      for (var i = 0; i <= 99; i++) {
        if (i == 0) {
          fill.add(make('100', big, style.finishInk));
          halo.add(
            make(
              '100',
              big,
              Colors.white.withValues(alpha: 0.85),
              halo: big * 0.22,
            ),
          );
        } else {
          fill.add(make('$i', small, style.numberInk));
          halo.add(make('$i', small, style.numberHalo, halo: small * 0.24));
        }
      }
      return _NumberSprites._(fill, halo);
    });
  }

  final List<TextPainter> fill;
  final List<TextPainter> halo;
}
