import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game_palette.dart';
import 'board_motion.dart';

/// Paints [BoardEffect]s. All particles are derived analytically from the
/// effect's age and a seed, so nothing is simulated or allocated per frame
/// apart from a gradient for glows.
abstract final class BoardEffectsRenderer {
  static final Paint _paint = Paint()..isAntiAlias = true;
  static final Path _path = Path();

  /// Paints all [effects] at engine time [now]. [cell] is the pixel size of
  /// one grid unit and [origin] the pixel position of grid (0, 0).
  static void paintAll(
    Canvas canvas,
    List<BoardEffect> effects,
    double now, {
    required double cell,
    required Offset origin,
    required GamePalette palette,
  }) {
    for (var i = 0; i < effects.length; i++) {
      final e = effects[i];
      final age = now - e.start;
      if (age < 0) continue;
      final p = e.progress(now);
      final c = origin + e.center * cell;
      final color = e.seatColor == null ? e.color : palette.seat(e.seatColor!);
      switch (e.kind) {
        case BoardEffectKind.captureBurst:
          _captureBurst(canvas, c, cell * e.scale, p, e, color);
        case BoardEffectKind.homeSparkle:
          _homeSparkle(canvas, c, cell * e.scale, p, e, color, palette);
        case BoardEffectKind.finishBurst:
          _finishBurst(canvas, c, cell * e.scale, p, e, color, palette);
        case BoardEffectKind.landingRing:
          _landingRing(canvas, c, cell * e.scale, p, color);
        case BoardEffectKind.transitionFlash:
          _transitionFlash(canvas, c, cell * e.scale, p, color);
      }
    }
    _paint
      ..shader = null
      ..style = PaintingStyle.fill;
  }

  static void _glow(Canvas canvas, Offset c, double r, Color color, double a) {
    if (a <= 0.01 || r <= 0) return;
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.radial(c, r, [
        color.withValues(alpha: a.clamp(0.0, 1.0)),
        color.withValues(alpha: 0),
      ]);
    canvas.drawCircle(c, r, _paint);
    _paint.shader = null;
  }

  static void _captureBurst(
    Canvas canvas,
    Offset c,
    double cell,
    double p,
    BoardEffect e,
    Color color,
  ) {
    final fade = 1 - p;
    // Shock ring.
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.08 * fade
      ..color = Colors.white.withValues(alpha: 0.8 * fade);
    canvas.drawCircle(
      c,
      cell * (0.25 + 0.75 * MotionCurves.easeOut(p)),
      _paint,
    );
    _paint
      ..strokeWidth = cell * 0.05 * fade
      ..color = color.withValues(alpha: 0.9 * fade);
    canvas.drawCircle(c, cell * (0.2 + 0.6 * MotionCurves.easeOut(p)), _paint);
    _paint.style = PaintingStyle.fill;
    // Shards.
    const n = 10;
    final travel = MotionCurves.easeOut(p);
    for (var i = 0; i < n; i++) {
      final jitter = MotionCurves.hash(e.seed, i);
      final angle = i * 2 * math.pi / n + jitter * 0.5;
      final dist = cell * (0.25 + (0.55 + 0.35 * jitter) * travel);
      final pos =
          c +
          Offset(
            math.cos(angle) * dist,
            math.sin(angle) * dist + cell * 0.25 * p * p,
          );
      final size = cell * (0.07 + 0.04 * jitter) * (1 - p * 0.8);
      _paint.color = (i.isEven ? color : Colors.white).withValues(
        alpha: (1 - p * p).clamp(0.0, 1.0),
      );
      canvas.drawCircle(pos, size, _paint);
    }
  }

  static void _homeSparkle(
    Canvas canvas,
    Offset c,
    double cell,
    double p,
    BoardEffect e,
    Color color,
    GamePalette palette,
  ) {
    final glowA = p < 0.3 ? p / 0.3 : 1 - (p - 0.3) / 0.7;
    _glow(canvas, c, cell * (1.2 + 0.6 * p), color, 0.65 * glowA);
    _glow(canvas, c, cell * 0.7, Colors.white, 0.45 * glowA);
    const n = 9;
    _paint.style = PaintingStyle.fill;
    for (var i = 0; i < n; i++) {
      final h = MotionCurves.hash(e.seed + 7, i);
      final delay = h * 0.35;
      final local = ((p - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final angle = i * 2 * math.pi / n + h;
      final dist = cell * (0.35 + 0.65 * MotionCurves.easeOut(local));
      final pos =
          c +
          Offset(
            math.cos(angle) * dist,
            math.sin(angle) * dist - cell * 0.4 * local,
          );
      final twinkle = math.sin(local * math.pi);
      _paint.color = (i % 3 == 0 ? palette.gold : Colors.white).withValues(
        alpha: twinkle.clamp(0.0, 1.0),
      );
      sparkle(canvas, _paint, pos, cell * (0.12 + 0.1 * h) * twinkle);
    }
  }

  static void _finishBurst(
    Canvas canvas,
    Offset c,
    double cell,
    double p,
    BoardEffect e,
    Color color,
    GamePalette palette,
  ) {
    final fade = p < 0.15 ? p / 0.15 : 1 - (p - 0.15) / 0.85;
    _glow(canvas, c, cell * (1.6 + p), palette.gold, 0.7 * fade);
    // Rotating rays.
    const rays = 12;
    final rot = p * math.pi * 0.5;
    _paint
      ..style = PaintingStyle.fill
      ..color = palette.gold.withValues(alpha: 0.45 * fade);
    final inner = cell * 0.45;
    final outer = cell * (1.1 + 1.0 * MotionCurves.easeOut(p));
    for (var i = 0; i < rays; i++) {
      final a = rot + i * 2 * math.pi / rays;
      const half = math.pi / rays * 0.35;
      _path
        ..reset()
        ..moveTo(
          c.dx + math.cos(a - half) * inner,
          c.dy + math.sin(a - half) * inner,
        )
        ..lineTo(c.dx + math.cos(a) * outer, c.dy + math.sin(a) * outer)
        ..lineTo(
          c.dx + math.cos(a + half) * inner,
          c.dy + math.sin(a + half) * inner,
        )
        ..close();
      canvas.drawPath(_path, _paint);
    }
    // Ring.
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.09 * (1 - p)
      ..color = Colors.white.withValues(alpha: 0.85 * (1 - p));
    canvas.drawCircle(c, cell * (0.4 + 1.4 * MotionCurves.easeOut(p)), _paint);
    _paint.style = PaintingStyle.fill;
    // Particles.
    const n = 16;
    for (var i = 0; i < n; i++) {
      final h = MotionCurves.hash(e.seed + 3, i);
      final a = i * 2 * math.pi / n + h * 0.4;
      final d = cell * (0.4 + (1.2 + 0.8 * h) * MotionCurves.easeOut(p));
      final pos =
          c + Offset(math.cos(a) * d, math.sin(a) * d + cell * 0.6 * p * p);
      final s = cell * (0.1 + 0.08 * h) * (1 - p);
      _paint.color =
          (i % 3 == 0 ? color : (i % 3 == 1 ? palette.gold : Colors.white))
              .withValues(alpha: (1 - p).clamp(0.0, 1.0));
      if (i.isEven) {
        sparkle(canvas, _paint, pos, s * 1.6);
      } else {
        canvas.drawCircle(pos, s * 0.6, _paint);
      }
    }
  }

  static void _landingRing(
    Canvas canvas,
    Offset c,
    double cell,
    double p,
    Color color,
  ) {
    final fade = 1 - p;
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.05 * fade
      ..color = color.withValues(alpha: 0.5 * fade);
    final w = cell * (0.7 + 0.6 * MotionCurves.easeOut(p));
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(0, cell * 0.22),
        width: w,
        height: w * 0.45,
      ),
      _paint,
    );
    _paint.style = PaintingStyle.fill;
  }

  static void _transitionFlash(
    Canvas canvas,
    Offset c,
    double cell,
    double p,
    Color color,
  ) {
    final a = math.sin(p * math.pi);
    _glow(canvas, c, cell * 0.9, color, 0.55 * a);
  }

  /// Four-point sparkle star centred at [c] with radius [r].
  static void sparkle(Canvas canvas, Paint paint, Offset c, double r) {
    if (r <= 0.2) return;
    final w = r * 0.24;
    _path
      ..reset()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(_path, paint);
  }
}
