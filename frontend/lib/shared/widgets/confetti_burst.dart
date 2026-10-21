import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/audio_haptics/reduced_motion.dart';
import '../../core/theme/app_theme.dart';

/// Lightweight painted confetti. Place it in a `Stack` (e.g. with
/// `Positioned.fill`); it fills its parent, ignores touches, and plays once
/// each time [play] flips from false to true. Nothing is drawn under reduced
/// motion.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    required this.play,
    this.duration = const Duration(milliseconds: 1400),
  });

  final bool play;
  final Duration duration;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  List<_Particle> _particles = const [];
  int _seed = 7;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.play && _particles.isEmpty && !_c.isAnimating) _start();
  }

  @override
  void didUpdateWidget(covariant ConfettiBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    _c.duration = widget.duration;
    if (widget.play && !oldWidget.play) _start();
  }

  void _start() {
    if (ReducedMotion.of(context)) return;
    final seats = context.colors.seats;
    final palette = [
      seats.red,
      seats.green,
      seats.yellow,
      seats.blue,
      BrandPalette.gold400,
      BrandPalette.royal300,
    ];
    final rnd = math.Random(_seed++);
    _particles = List.generate(64, (i) {
      final angle = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 0.9;
      final speed = 0.55 + rnd.nextDouble() * 0.75;
      return _Particle(
        origin: Offset(0.5 + (rnd.nextDouble() - 0.5) * 0.3, 0.42),
        velocity: Offset(
          math.cos(angle) * speed * 0.7,
          math.sin(angle) * speed,
        ),
        color: palette[i % palette.length],
        size: 5 + rnd.nextDouble() * 6,
        spin: (rnd.nextDouble() - 0.5) * 14,
        ribbon: rnd.nextBool(),
      );
    });
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => SizedBox.expand(
            child: (_c.isAnimating && _particles.isNotEmpty)
                ? CustomPaint(painter: _ConfettiPainter(_particles, _c.value))
                : null,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.origin,
    required this.velocity,
    required this.color,
    required this.size,
    required this.spin,
    required this.ribbon,
  });

  final Offset origin;
  final Offset velocity;
  final Color color;
  final double size;
  final double spin;
  final bool ribbon;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const gravity = 1.6;
    final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
    for (final p in particles) {
      final x = p.origin.dx + p.velocity.dx * t;
      final y = p.origin.dy + p.velocity.dy * t + gravity * t * t * 0.5;
      final pos = Offset(x * size.width, y * size.height);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      if (p.ribbon) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * 0.5,
              height: p.size * 1.6 * (0.4 + 0.6 * math.cos(p.spin * t).abs()),
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, p.size * 0.42, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.t != t || !identical(old.particles, particles);
}
