import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../shared/game_visuals/board_cell.dart';
import '../../../../shared/game_visuals/game_palette.dart';
import 'ludo_board_theme.dart';
import 'ludo_geometry.dart';

/// Paints the static Ludo board (frame, track, bases, home columns, safe
/// stars, start arrows, center triangles, texture).
///
/// Everything is authored in grid units and drawn through one canvas
/// transform, so the board is crisp at any size. Use inside a
/// [RepaintBoundary] with `isComplex: true, willChange: false`; it repaints
/// only when its configuration or size changes.
class LudoBoardPainter extends CustomPainter {
  LudoBoardPainter({
    required this.style,
    this.tokensPerPlayer = 4,
    this.activeColors,
    this.detailed = true,
  });

  final LudoBoardStyle style;

  /// Number of wells drawn per base (4 classic, 2 Quick Ludo).
  final int tokensPerPlayer;

  /// Colors seated in the game; other bases are drawn muted. Null = all.
  final Set<SeatColor>? activeColors;

  /// False for mini illustrations: skips textures and fine ornaments.
  final bool detailed;

  static const double _f = LudoBoardLayout.frameInset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final layout = LudoBoardLayout.fit(size);
    canvas.save();
    canvas.translate(layout.gridOrigin.dx, layout.gridOrigin.dy);
    canvas.scale(layout.cell);

    final paint = Paint()..isAntiAlias = true;
    _paintFrame(canvas, paint);
    _paintCells(canvas, paint);
    if (detailed && style.texture == LudoBoardTexture.marble) {
      _paintMarble(canvas, paint);
    }
    for (final c in SeatColor.values) {
      _paintBase(canvas, paint, c);
    }
    _paintCenter(canvas, paint);
    canvas.restore();
  }

  // ---------------------------------------------------------------------------

  void _paintFrame(Canvas canvas, Paint paint) {
    const outer = Rect.fromLTRB(-_f, -_f, 15 + _f, 15 + _f);
    final outerRRect = RRect.fromRectAndRadius(
      outer,
      const Radius.circular(0.55),
    );
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(outer.topCenter, outer.bottomCenter, [
        style.frameTop,
        style.frameBottom,
      ]);
    canvas.drawRRect(outerRRect, paint);
    paint.shader = null;

    if (style.texture == LudoBoardTexture.marble && detailed) {
      canvas.save();
      canvas.clipRRect(outerRRect);
      _marbleVeins(canvas, paint, alphaScale: 0.8);
      canvas.restore();
    }

    final trim = style.frameTrim;
    if (trim != null) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05
        ..color = trim.withValues(alpha: 0.9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          outer.deflate(_f * 0.32),
          const Radius.circular(0.45),
        ),
        paint,
      );
      if (style.texture == LudoBoardTexture.damask && detailed) {
        paint
          ..strokeWidth = 0.025
          ..color = trim.withValues(alpha: 0.6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            outer.deflate(_f * 0.68),
            const Radius.circular(0.35),
          ),
          paint,
        );
        // Corner ornaments.
        paint
          ..style = PaintingStyle.fill
          ..color = trim;
        for (final c in const [
          Offset(-_f / 2, -_f / 2),
          Offset(15 + _f / 2, -_f / 2),
          Offset(-_f / 2, 15 + _f / 2),
          Offset(15 + _f / 2, 15 + _f / 2),
        ]) {
          _diamond(canvas, paint, c, 0.13);
        }
        for (var i = 1; i < 15; i += 2) {
          for (final c in [
            Offset(i + 0.5, -_f / 2),
            Offset(i + 0.5, 15 + _f / 2),
            Offset(-_f / 2, i + 0.5),
            Offset(15 + _f / 2, i + 0.5),
          ]) {
            canvas.drawCircle(c, 0.035, paint);
          }
        }
      }
      paint.style = PaintingStyle.fill;
    }

    // Board surface under the cells with a soft inset edge.
    const grid = Rect.fromLTRB(0, 0, 15, 15);
    paint.color = style.shadow;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        grid.shift(const Offset(0, 0.05)),
        const Radius.circular(0.3),
      ),
      paint,
    );
    paint.color = style.surface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(grid, const Radius.circular(0.3)),
      paint,
    );
  }

  void _paintCells(Canvas canvas, Paint paint) {
    final gap = style.cellGap;
    final radius = Radius.circular(style.cellRadius);

    RRect cellRRect(BoardCell c) => RRect.fromRectAndRadius(
      Rect.fromLTWH(c.col + gap / 2, c.row + gap / 2, 1 - gap, 1 - gap),
      radius,
    );

    void lip(BoardCell c, Color color) {
      paint
        ..shader = null
        ..color = color;
      canvas.drawRRect(cellRRect(c).shift(const Offset(0, 0.045)), paint);
    }

    void colored(BoardCell c, SeatShades s) {
      lip(c, s.deep);
      final r = cellRRect(c);
      paint
        ..color = const Color(0xFFFFFFFF)
        ..shader = ui.Gradient.linear(
          r.outerRect.topLeft,
          r.outerRect.bottomRight,
          [s.soft, s.base, s.shade],
          const [0.0, 0.55, 1.0],
        );
      canvas.drawRRect(r, paint);
      paint.shader = null;
      // Gloss on the top half.
      paint.color = Colors.white.withValues(alpha: style.dark ? 0.07 : 0.14);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.45),
          topLeft: radius,
          topRight: radius,
        ),
        paint,
      );
    }

    // Main track.
    for (var i = 0; i < LudoGeometry.trackLength; i++) {
      final c = LudoGeometry.track[i];
      final startColor = LudoGeometry.startColorAt(i);
      if (startColor != null) {
        colored(c, style.seat(startColor));
        _arrow(
          canvas,
          paint,
          c.center,
          _travelDirection(i),
          style.seat(startColor).onColor,
          1,
        );
        continue;
      }
      lip(c, style.trackCellEdge);
      paint.color = style.trackCell;
      canvas.drawRRect(cellRRect(c), paint);
      if (LudoGeometry.isStarTrackIndex(i)) {
        paint.color = style.star;
        _star(canvas, paint, c.center, 0.34, 0.15, fill: true);
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.045
          ..strokeJoin = StrokeJoin.round
          ..color = style.starEdge;
        _star(canvas, paint, c.center, 0.34, 0.15, fill: false);
        paint.style = PaintingStyle.fill;
      }
    }

    // Home columns and their entry arrows (on absolute square 50 of each
    // color, the last track square before the column).
    for (final color in SeatColor.values) {
      final shades = style.seat(color);
      for (final c in LudoGeometry.homeColumn(color)) {
        colored(c, shades);
      }
      final entry = LudoGeometry.track[LudoGeometry.absoluteIndex(color, 50)];
      final into = LudoGeometry.homeColumn(color).first.center - entry.center;
      _arrow(canvas, paint, entry.center, into, shades.base, 0.85);
    }
  }

  /// Unit direction of travel leaving absolute square [index].
  static Offset _travelDirection(int index) {
    final a = LudoGeometry.track[index].center;
    final b = LudoGeometry.track[(index + 1) % LudoGeometry.trackLength].center;
    final d = b - a;
    return d / d.distance;
  }

  void _paintBase(Canvas canvas, Paint paint, SeatColor color) {
    final active = activeColors == null || activeColors!.contains(color);
    var s = style.seat(color);
    if (!active) {
      final grey = style.dark
          ? const Color(0xFF3A3F4B)
          : const Color(0xFFB8BDC7);
      s = SeatShades(
        base: Color.lerp(s.base, grey, 0.62)!,
        tint: Color.lerp(s.tint, grey, 0.5)!,
        soft: Color.lerp(s.soft, grey, 0.62)!,
        shade: Color.lerp(s.shade, grey, 0.62)!,
        deep: Color.lerp(s.deep, grey, 0.62)!,
        outline: s.outline,
        glow: s.glow,
        onColor: s.onColor,
      );
    }
    final rect = LudoGeometry.baseRect(color).deflate(0.06);
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(0.42));

    paint.color = style.shadow;
    canvas.drawRRect(outer.shift(const Offset(0, 0.06)), paint);
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [s.soft, s.base, s.shade],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRRect(outer, paint);
    paint.shader = null;
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05
      ..color = Colors.white.withValues(alpha: style.dark ? 0.1 : 0.25);
    canvas.drawRRect(outer.deflate(0.1), paint);
    paint.style = PaintingStyle.fill;

    if (style.baseTrim != null && detailed) {
      _baseTrim(canvas, paint, rect, style.baseTrim!);
    }
    if (style.texture == LudoBoardTexture.marble && detailed) {
      canvas.save();
      canvas.clipRRect(outer);
      _marbleVeins(canvas, paint, alphaScale: 1.3, seed: color.index);
      canvas.restore();
    }

    // Inner panel.
    final o = LudoGeometry.baseOrigins[color.index];
    final panelRect = Rect.fromLTWH(o.col + 0.85, o.row + 0.85, 4.3, 4.3);
    final panel = RRect.fromRectAndRadius(
      panelRect,
      const Radius.circular(0.55),
    );
    paint.color = s.deep.withValues(alpha: 0.55);
    canvas.drawRRect(panel.shift(const Offset(0, 0.07)), paint);
    paint.color = style.basePanel;
    canvas.drawRRect(panel, paint);
    if (style.texture == LudoBoardTexture.damask && detailed) {
      canvas.save();
      canvas.clipRRect(panel);
      _damaskLattice(canvas, paint, panelRect);
      canvas.restore();
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.texture == LudoBoardTexture.damask ? 0.07 : 0.04
      ..color = style.basePanelEdge;
    canvas.drawRRect(panel, paint);
    paint.style = PaintingStyle.fill;

    // Center glyph between the wells.
    if (tokensPerPlayer != 2) {
      paint.color = s.base.withValues(alpha: 0.35);
      _diamond(canvas, paint, Offset(o.col + 3.0, o.row + 3.0), 0.22);
    }

    // Wells.
    final rim = style.wellRim ?? s.base;
    for (var t = 0; t < tokensPerPlayer.clamp(1, 4); t++) {
      final slot = LudoGeometry.baseSlotFor(color, t, tokensPerPlayer);
      final c = LudoGeometry.baseSlotCenter(color, slot);
      const r = 0.68;
      paint
        ..color = const Color(0xFFFFFFFF)
        ..shader = ui.Gradient.radial(
          c.translate(0, 0.12),
          r,
          [s.tint, Color.lerp(s.tint, s.shade, style.dark ? 0.35 : 0.22)!],
          const [0.55, 1.0],
        );
      canvas.drawCircle(c, r, paint);
      paint.shader = null;
      // Inner shadow on the upper rim.
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.08
        ..color = Colors.black.withValues(alpha: style.dark ? 0.35 : 0.12);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 0.08),
        math.pi * 1.05,
        math.pi * 0.9,
        false,
        paint,
      );
      paint
        ..strokeWidth = 0.11
        ..color = rim;
      canvas.drawCircle(c, r, paint);
      paint
        ..strokeWidth = 0.03
        ..color = Colors.white.withValues(alpha: 0.45);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + 0.02),
        math.pi * 1.1,
        math.pi * 0.5,
        false,
        paint,
      );
      paint.style = PaintingStyle.fill;
    }
  }

  void _paintCenter(Canvas canvas, Paint paint) {
    const center = LudoGeometry.boardCenter;
    for (final color in SeatColor.values) {
      final s = style.seat(color);
      final tri = LudoGeometry.homeTriangle(color);
      final path = Path()..addPolygon(tri, true);
      final edgeMid = (tri[0] + tri[1]) / 2;
      paint
        ..color = const Color(0xFFFFFFFF)
        ..shader = ui.Gradient.linear(
          edgeMid,
          center,
          [s.soft, s.base, s.shade],
          const [0.0, 0.45, 1.0],
        );
      canvas.drawPath(path, paint);
      paint.shader = null;
    }
    // Separators.
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05
      ..strokeCap = StrokeCap.round
      ..color = style.dark
          ? Colors.black.withValues(alpha: 0.45)
          : Colors.white.withValues(alpha: 0.85);
    canvas.drawLine(const Offset(6, 6), const Offset(9, 9), paint);
    canvas.drawLine(const Offset(9, 6), const Offset(6, 9), paint);
    paint
      ..strokeWidth = 0.04
      ..color = style.trackCellEdge;
    canvas.drawRect(const Rect.fromLTRB(6, 6, 9, 9), paint);
    paint.style = PaintingStyle.fill;

    // Medallion.
    const r = 0.5;
    paint.color = style.shadow;
    canvas.drawCircle(center.translate(0, 0.05), r, paint);
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.radial(center.translate(-0.12, -0.15), r * 1.4, [
        Color.lerp(style.centerEmblem, Colors.white, style.dark ? 0.08 : 0.0)!,
        style.centerEmblem,
      ]);
    canvas.drawCircle(center, r, paint);
    paint.shader = null;
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07
      ..color = style.centerEmblemEdge;
    canvas.drawCircle(center, r, paint);
    paint.style = PaintingStyle.fill;
    paint.color = style.accent;
    if (style.texture == LudoBoardTexture.damask) {
      _crown(canvas, paint, center, 0.3);
    } else {
      _star(canvas, paint, center, 0.27, 0.115, fill: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Textures.

  static final Map<int, List<Path>> _veinCache = <int, List<Path>>{};

  /// Deterministic marble veins in grid units (built once).
  static List<Path> _veins([int seed = 0]) {
    return _veinCache.putIfAbsent(seed, () {
      final rnd = math.Random(20251021 + seed * 7919);
      final veins = <Path>[];
      for (var i = 0; i < 11; i++) {
        final path = Path();
        var p = Offset(
          rnd.nextDouble() * 16 - 0.5,
          rnd.nextDouble() * 16 - 0.5,
        );
        final heading = rnd.nextDouble() * math.pi * 2;
        path.moveTo(p.dx, p.dy);
        final segments = 3 + rnd.nextInt(3);
        var h = heading;
        for (var k = 0; k < segments; k++) {
          h += (rnd.nextDouble() - 0.5) * 1.1;
          final len = 1.8 + rnd.nextDouble() * 2.6;
          final next = p + Offset(math.cos(h) * len, math.sin(h) * len);
          final c1 =
              p +
              Offset(
                math.cos(h + 0.6) * len * 0.4,
                math.sin(h + 0.6) * len * 0.4,
              );
          final c2 =
              next -
              Offset(
                math.cos(h - 0.5) * len * 0.4,
                math.sin(h - 0.5) * len * 0.4,
              );
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, next.dx, next.dy);
          p = next;
        }
        veins.add(path);
      }
      return veins;
    });
  }

  void _marbleVeins(
    Canvas canvas,
    Paint paint, {
    double alphaScale = 1,
    int seed = 0,
  }) {
    final veins = _veins(seed);
    paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < veins.length; i++) {
      final w = 0.02 + (i % 4) * 0.018;
      paint
        ..strokeWidth = w * 3.5
        ..color = style.textureColor.withValues(alpha: 0.04 * alphaScale);
      canvas.drawPath(veins[i], paint);
      paint
        ..strokeWidth = w
        ..color = style.textureColor.withValues(
          alpha: (0.11 + (i % 3) * 0.05) * alphaScale,
        );
      canvas.drawPath(veins[i], paint);
    }
    paint.style = PaintingStyle.fill;
  }

  void _paintMarble(Canvas canvas, Paint paint) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(0, 0, 15, 15),
        const Radius.circular(0.3),
      ),
    );
    _marbleVeins(canvas, paint);
    // Polished sheen.
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(15, 15),
        [
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.04),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(const Rect.fromLTRB(0, 0, 15, 15), paint);
    paint.shader = null;
    canvas.restore();
  }

  void _damaskLattice(Canvas canvas, Paint paint, Rect rect) {
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.025
      ..color = style.textureColor.withValues(alpha: style.dark ? 0.22 : 0.2);
    const step = 0.72;
    for (var x = rect.left - rect.height; x < rect.right; x += step) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + rect.height, rect.top),
        paint,
      );
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x + rect.height, rect.bottom),
        paint,
      );
    }
    paint
      ..style = PaintingStyle.fill
      ..color = style.textureColor.withValues(alpha: style.dark ? 0.3 : 0.26);
    for (var y = rect.top + step / 2; y < rect.bottom; y += step) {
      for (var x = rect.left + step / 2; x < rect.right; x += step) {
        canvas.drawCircle(Offset(x, y), 0.045, paint);
      }
    }
  }

  void _baseTrim(Canvas canvas, Paint paint, Rect rect, Color trim) {
    final damask = style.texture == LudoBoardTexture.damask;
    paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = damask ? 0.06 : 0.035
      ..color = trim.withValues(alpha: damask ? 0.9 : 0.55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.28), const Radius.circular(0.3)),
      paint,
    );
    paint.style = PaintingStyle.fill;
    if (!damask) return;
    paint.color = trim;
    for (final c in [
      rect.topLeft.translate(0.28, 0.28),
      rect.topRight.translate(-0.28, 0.28),
      rect.bottomLeft.translate(0.28, -0.28),
      rect.bottomRight.translate(-0.28, -0.28),
    ]) {
      _diamond(canvas, paint, c, 0.11);
    }
  }

  // ---------------------------------------------------------------------------
  // Glyphs (grid units).

  static void _star(
    Canvas canvas,
    Paint paint,
    Offset c,
    double outer,
    double inner, {
    required bool fill,
  }) {
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
    path.close();
    canvas.drawPath(path, paint);
  }

  static void _diamond(Canvas canvas, Paint paint, Offset c, double r) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r, c.dy)
        ..close(),
      paint,
    );
  }

  static void _crown(Canvas canvas, Paint paint, Offset c, double s) {
    final path = Path()
      ..moveTo(c.dx - s, c.dy + s * 0.55)
      ..lineTo(c.dx - s, c.dy - s * 0.45)
      ..lineTo(c.dx - s * 0.5, c.dy + s * 0.05)
      ..lineTo(c.dx, c.dy - s * 0.75)
      ..lineTo(c.dx + s * 0.5, c.dy + s * 0.05)
      ..lineTo(c.dx + s, c.dy - s * 0.45)
      ..lineTo(c.dx + s, c.dy + s * 0.55)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// Solid arrow centred at [c] pointing along unit [dir].
  static void _arrow(
    Canvas canvas,
    Paint paint,
    Offset c,
    Offset dir,
    Color color,
    double scale,
  ) {
    final d = dir / dir.distance;
    final n = Offset(-d.dy, d.dx);
    Offset p(double along, double across) =>
        c + d * (along * scale) + n * (across * scale);
    final path = Path()
      ..moveTo(p(-0.3, -0.075).dx, p(-0.3, -0.075).dy)
      ..lineTo(p(0.04, -0.075).dx, p(0.04, -0.075).dy)
      ..lineTo(p(0.04, -0.2).dx, p(0.04, -0.2).dy)
      ..lineTo(p(0.32, 0).dx, p(0.32, 0).dy)
      ..lineTo(p(0.04, 0.2).dx, p(0.04, 0.2).dy)
      ..lineTo(p(0.04, 0.075).dx, p(0.04, 0.075).dy)
      ..lineTo(p(-0.3, 0.075).dx, p(-0.3, 0.075).dy)
      ..close();
    paint
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.18);
    canvas.drawPath(path.shift(const Offset(0, 0.035)), paint);
    paint.color = color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant LudoBoardPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.tokensPerPlayer != tokensPerPlayer ||
      oldDelegate.detailed != detailed ||
      !setEquals(oldDelegate.activeColors, activeColors);
}
