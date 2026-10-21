import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Background treatments.
enum LayeredBackgroundStyle {
  /// Page gradient + soft glows + faint royal lattice.
  standard,

  /// Richer glows and a crown watermark for splash / gate / welcome screens.
  hero,

  /// Plain gradient only (dense content such as settings lists).
  calm,
}

/// The app's layered page background: vertical gradient, soft radial glows
/// and a subtle royal lattice pattern. Paints once (RepaintBoundary) and
/// adapts to light/dark through `context.colors`.
class LayeredBackground extends StatelessWidget {
  const LayeredBackground({
    super.key,
    required this.child,
    this.style = LayeredBackgroundStyle.standard,
  });

  final Widget child;
  final LayeredBackgroundStyle style;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: c.backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (style != LayeredBackgroundStyle.calm)
            Positioned.fill(
              child: RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RoyalBackdropPainter(
                      glowA: c.backgroundGlow,
                      glowB: c.isDark
                          ? BrandPalette.gold500.withValues(alpha: 0.10)
                          : BrandPalette.royal300.withValues(alpha: 0.22),
                      pattern: c.pattern,
                      hero: style == LayeredBackgroundStyle.hero,
                      mirrored: rtl,
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _RoyalBackdropPainter extends CustomPainter {
  _RoyalBackdropPainter({
    required this.glowA,
    required this.glowB,
    required this.pattern,
    required this.hero,
    required this.mirrored,
  });

  final Color glowA;
  final Color glowB;
  final Color pattern;
  final bool hero;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    double x(double fx) => mirrored ? w * (1 - fx) : w * fx;

    // Soft radial glows.
    void glow(Offset center, double radius, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    final r = math.max(w, h);
    glow(Offset(x(0.12), h * 0.04), r * (hero ? 0.75 : 0.6), glowA);
    glow(Offset(x(0.95), h * 0.78), r * (hero ? 0.6 : 0.45), glowB);
    if (hero) {
      glow(
        Offset(x(0.5), h * 0.42),
        r * 0.35,
        glowA.withValues(alpha: glowA.a * 0.6),
      );
    }

    // Faint diamond lattice, fading towards the bottom.
    final lattice = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          pattern,
          pattern.withValues(alpha: pattern.a * 0.25),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const step = 46.0;
    final path = Path();
    for (double d = -h; d < w + h; d += step) {
      path
        ..moveTo(d, 0)
        ..lineTo(d + h, h)
        ..moveTo(d + h, 0)
        ..lineTo(d, h);
    }
    canvas.drawPath(path, lattice);

    // Tiny gems at a sparse subset of intersections.
    final dot = Paint()
      ..color = pattern.withValues(alpha: math.min(1, pattern.a * 2.2));
    for (double yy = step / 2; yy < h * 0.55; yy += step * 2) {
      for (
        double xx = (yy ~/ step).isEven ? step / 2 : step * 1.5;
        xx < w;
        xx += step * 3
      ) {
        final cx = xx;
        canvas.save();
        canvas.translate(cx, yy);
        canvas.rotate(math.pi / 4);
        canvas.drawRect(const Rect.fromLTWH(-1.8, -1.8, 3.6, 3.6), dot);
        canvas.restore();
      }
    }

    if (hero) _crownWatermark(canvas, size);
  }

  void _crownWatermark(Canvas canvas, Size size) {
    final w = size.width;
    final cw = math.min(w * 0.9, 420.0);
    final ch = cw * 0.55;
    final left = (w - cw) / 2;
    final top = size.height * 0.08;
    final p = Path()
      ..moveTo(left, top + ch)
      ..lineTo(left + cw * 0.06, top + ch * 0.25)
      ..lineTo(left + cw * 0.3, top + ch * 0.6)
      ..lineTo(left + cw * 0.5, top)
      ..lineTo(left + cw * 0.7, top + ch * 0.6)
      ..lineTo(left + cw * 0.94, top + ch * 0.25)
      ..lineTo(left + cw, top + ch)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..color = pattern.withValues(alpha: pattern.a * 0.6)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_RoyalBackdropPainter old) =>
      old.glowA != glowA ||
      old.glowB != glowB ||
      old.pattern != pattern ||
      old.hero != hero ||
      old.mirrored != mirrored;
}
