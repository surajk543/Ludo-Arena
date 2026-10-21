import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../boards_l10n.dart';
import '../game_palette.dart';
import '../motion/board_motion.dart';
import '../motion/effects_renderer.dart';

/// Compact radial burst for level-ups (~1.2 s): expanding ring, tapered
/// rays and sparkles, with [child] (e.g. the new level number) scaling in.
/// Calls [onDone] once when finished; the child stays visible.
class LevelUpBurst extends StatefulWidget {
  const LevelUpBurst({
    super.key,
    this.color,
    this.size = 160,
    this.child,
    this.onDone,
    this.reducedMotion = false,
  });

  /// Burst color; defaults to the palette gold.
  final Color? color;
  final double size;
  final Widget? child;
  final VoidCallback? onDone;
  final bool reducedMotion;

  /// Duration of the burst.
  static Duration durationFor({bool reducedMotion = false}) =>
      Duration(milliseconds: reducedMotion ? 800 : 1200);

  @override
  State<LevelUpBurst> createState() => _LevelUpBurstState();
}

class _LevelUpBurstState extends State<LevelUpBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LevelUpBurst.durationFor(reducedMotion: widget.reducedMotion),
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_done && mounted) {
        _done = true;
        widget.onDone?.call();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _done = true;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of(context);
    final color = widget.color ?? palette.gold;
    final child = widget.child;
    return Semantics(
      liveRegion: true,
      label: boardsL10n(context).boardsLevelUp,
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _LevelUpPainter(
                      progress: _controller,
                      color: color,
                      palette: palette,
                      reducedMotion: widget.reducedMotion,
                    ),
                  ),
                ),
              ),
            ),
            if (child != null)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final p = _controller.value;
                  final double scale;
                  if (widget.reducedMotion) {
                    scale = 1;
                  } else {
                    scale = p < 0.45
                        ? MotionCurves.easeOutBack(p / 0.45, 1.8)
                        : 1.0;
                  }
                  final opacity = (p / 0.15).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale.clamp(0.0, 1.4),
                      child: child,
                    ),
                  );
                },
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}

class _LevelUpPainter extends CustomPainter {
  _LevelUpPainter({
    required this.progress,
    required this.color,
    required this.palette,
    required this.reducedMotion,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final GamePalette palette;
  final bool reducedMotion;

  static final Paint _paint = Paint()..isAntiAlias = true;
  static final Path _path = Path();
  Shader? _glow;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    final r = size.shortestSide / 2;
    if (r <= 0) return;
    final c = size.center(Offset.zero);
    _glow ??= ui.Gradient.radial(
      Offset.zero,
      1,
      [
        color.withValues(alpha: 0.55),
        color.withValues(alpha: 0.18),
        color.withValues(alpha: 0),
      ],
      const [0.0, 0.5, 1.0],
    );

    // Glow.
    final glowA = reducedMotion
        ? math.sin(p * math.pi)
        : (p < 0.2 ? p / 0.2 : 1 - (p - 0.2) / 0.8 * 0.6);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(r * (0.7 + 0.3 * MotionCurves.easeOut(p)));
    _paint
      ..shader = _glow
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: glowA.clamp(0.0, 1.0));
    canvas.drawCircle(Offset.zero, 1, _paint);
    _paint.shader = null;
    canvas.restore();
    if (reducedMotion) return;

    // Expanding ring.
    final ringU = MotionCurves.easeOut(p);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.05 * (1 - p) + 0.5
      ..color = Colors.white.withValues(alpha: 0.85 * (1 - p));
    canvas.drawCircle(c, r * (0.22 + 0.74 * ringU), _paint);
    _paint
      ..strokeWidth = r * 0.03 * (1 - p) + 0.5
      ..color = color.withValues(alpha: 0.9 * (1 - p));
    canvas.drawCircle(c, r * (0.18 + 0.62 * ringU), _paint);
    _paint.style = PaintingStyle.fill;

    // Tapered rays.
    final e = MotionCurves.easeOut((p / 0.6).clamp(0.0, 1.0));
    final rayAlpha = math.pow(1 - p, 1.2).toDouble() * 0.85;
    const rays = 12;
    final rot = p * 0.3;
    for (var i = 0; i < rays; i++) {
      final long = i.isEven;
      final a = rot + i * 2 * math.pi / rays;
      final inner = r * (0.2 + 0.25 * e);
      final outer = r * ((long ? 0.42 : 0.32) + (long ? 0.56 : 0.4) * e);
      const half = 0.07;
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
      _paint.color = (long ? color : Colors.white).withValues(
        alpha: rayAlpha.clamp(0.0, 1.0),
      );
      canvas.drawPath(_path, _paint);
    }

    // Sparkles.
    const n = 10;
    for (var i = 0; i < n; i++) {
      final h = MotionCurves.hash(41, i);
      final delay = h * 0.4;
      final local = ((p - delay) / 0.5).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final a = i * 2 * math.pi / n + h * 0.6;
      final d = r * (0.45 + 0.45 * MotionCurves.easeOut(local));
      final tw = math.sin(local * math.pi);
      _paint.color = (i % 3 == 0 ? palette.gold : Colors.white).withValues(
        alpha: tw.clamp(0.0, 1.0),
      );
      BoardEffectsRenderer.sparkle(
        canvas,
        _paint,
        Offset(c.dx + math.cos(a) * d, c.dy + math.sin(a) * d),
        r * (0.06 + 0.05 * h) * tw,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelUpPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.palette != palette ||
      oldDelegate.reducedMotion != reducedMotion;
}
