import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/board_motion.dart';
import '../motion/effects_renderer.dart';

/// Trail cosmetic ids from `docs/cosmetics-catalog.md`.
abstract final class TrailStyles {
  static const none = 'trail_none';
  static const sparkle = 'trail_sparkle';
  static const comet = 'trail_comet';

  static const all = [none, sparkle, comet];

  /// Known id or the starter (no trail).
  static String resolve(String? id) => all.contains(id) ? id! : none;
}

/// Draws a moving token's trail from its [TrailHistory].
abstract final class TrailRenderer {
  /// How long a trail sample stays visible (seconds).
  static const double lifetime = 0.42;

  static final Paint _paint = Paint()
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round;

  /// Paints [history] using [trailId]. Positions are grid units mapped by
  /// [cell] and [origin]; [now] is engine time; [color] the seat color.
  static void paint(
    Canvas canvas,
    TrailHistory history, {
    required String trailId,
    required double now,
    required double cell,
    required Offset origin,
    double rowScale = 1,
    required Color color,
    double opacity = 1,
  }) {
    final id = TrailStyles.resolve(trailId);
    if (id == TrailStyles.none || history.length < 2) return;
    if (id == TrailStyles.comet) {
      _comet(canvas, history, now, cell, origin, rowScale, color, opacity);
    } else {
      _sparkle(canvas, history, now, cell, origin, rowScale, color, opacity);
    }
  }

  static void _comet(
    Canvas canvas,
    TrailHistory h,
    double now,
    double cell,
    Offset origin,
    double rowScale,
    Color color,
    double opacity,
  ) {
    final n = h.length;
    _paint.style = PaintingStyle.stroke;
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 1; i < n; i++) {
        final age = now - h.timeAt(i);
        if (age > lifetime) continue;
        final life = 1 - age / lifetime;
        final p0 = Offset(
          origin.dx + h.xAt(i - 1) * cell,
          origin.dy + h.yAt(i - 1) * cell * rowScale,
        );
        final p1 = Offset(
          origin.dx + h.xAt(i) * cell,
          origin.dy + h.yAt(i) * cell * rowScale,
        );
        if (pass == 0) {
          _paint
            ..strokeWidth = cell * 0.5 * life
            ..color = color.withValues(alpha: 0.35 * life * opacity);
        } else {
          _paint
            ..strokeWidth = cell * 0.18 * life
            ..color = Colors.white.withValues(alpha: 0.85 * life * opacity);
        }
        canvas.drawLine(p0, p1, _paint);
      }
    }
    _paint.style = PaintingStyle.fill;
  }

  static void _sparkle(
    Canvas canvas,
    TrailHistory h,
    double now,
    double cell,
    Offset origin,
    double rowScale,
    Color color,
    double opacity,
  ) {
    final n = h.length;
    _paint.style = PaintingStyle.fill;
    for (var i = 0; i < n; i++) {
      final age = now - h.timeAt(i);
      if (age > lifetime * 1.4) continue;
      final life = (1 - age / (lifetime * 1.4)).clamp(0.0, 1.0);
      final seed = (h.timeAt(i) * 1000).round();
      final jx = (MotionCurves.hash(seed, 1) - 0.5) * 0.45;
      final jy = (MotionCurves.hash(seed, 2) - 0.5) * 0.45 + 0.25 * (1 - life);
      final pos = Offset(
        origin.dx + (h.xAt(i) + jx) * cell,
        origin.dy + (h.yAt(i) + jy) * cell * rowScale,
      );
      final twinkle = 0.6 + 0.4 * math.sin(age * 40 + seed);
      final r =
          cell * (0.1 + 0.08 * MotionCurves.hash(seed, 3)) * life * twinkle;
      _paint.color = color.withValues(alpha: 0.5 * life * opacity);
      canvas.drawCircle(pos, r * 0.9, _paint);
      _paint.color = Colors.white.withValues(alpha: 0.95 * life * opacity);
      BoardEffectsRenderer.sparkle(canvas, _paint, pos, r * 1.3);
    }
  }
}
