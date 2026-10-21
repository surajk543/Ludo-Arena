import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../boards_l10n.dart';
import '../game_palette.dart';
import '../motion/board_motion.dart';
import '../motion/effects_renderer.dart';

/// Victory effect ids from `docs/cosmetics-catalog.md`.
abstract final class VictoryStyles {
  static const confetti = 'victory_confetti';
  static const fireworks = 'victory_fireworks';
  static const crown = 'victory_crown';

  static const all = [confetti, fireworks, crown];

  /// Known id or the starter effect.
  static String resolve(String? id) => all.contains(id) ? id! : confetti;
}

/// Full-area celebration played when a player wins.
///
/// Fills its parent (put it in a `Stack` above the board), never blocks
/// input, plays ~2.5 s then fades out (~0.4 s) and calls [onDone] once.
/// With [reducedMotion] it shows a short static composition (~1.2 s).
class VictoryOverlay extends StatefulWidget {
  const VictoryOverlay({
    super.key,
    required this.victoryId,
    required this.color,
    this.onDone,
    this.reducedMotion = false,
  });

  final String victoryId;

  /// Winner's seat color.
  final Color color;
  final VoidCallback? onDone;
  final bool reducedMotion;

  @override
  State<VictoryOverlay> createState() => _VictoryOverlayState();
}

class _VictoryOverlayState extends State<VictoryOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: VictoryEffectPainter.durationFor(
      reducedMotion: widget.reducedMotion,
    ),
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_done && mounted) {
      _done = true;
      widget.onDone?.call();
    }
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
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: boardsL10n(context).boardsVictoryCelebration,
        child: SizedBox.expand(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: VictoryEffectPainter(
                victoryId: widget.victoryId,
                color: widget.color,
                progress: _controller,
                palette: palette,
                reducedMotion: widget.reducedMotion,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a victory effect at [progress] (0..1 over the whole effect,
/// including the final fade). Reusable for previews with a looping
/// controller.
class VictoryEffectPainter extends CustomPainter {
  VictoryEffectPainter({
    required String victoryId,
    required this.color,
    required this.progress,
    required this.palette,
    this.reducedMotion = false,
    this.seed = 7,
  }) : victoryId = VictoryStyles.resolve(victoryId),
       super(repaint: progress);

  /// Seconds of the main effect.
  static const double effectSeconds = 2.5;

  /// Seconds of the closing fade.
  static const double fadeSeconds = 0.4;

  /// Seconds of the reduced-motion composition.
  static const double reducedSeconds = 1.2;

  /// Total duration for [VictoryOverlay].
  static Duration durationFor({bool reducedMotion = false}) => Duration(
    milliseconds:
        ((reducedMotion ? reducedSeconds : effectSeconds + fadeSeconds) * 1000)
            .round(),
  );

  final String victoryId;
  final Color color;
  final Animation<double> progress;
  final GamePalette palette;
  final bool reducedMotion;
  final int seed;

  static final Paint _paint = Paint()..isAntiAlias = true;
  static final Path _path = Path();

  // Lazily built per painter instance (colors depend on the inputs).
  List<Color>? _front;
  List<Color>? _back;
  Shader? _goldShader;
  Shader? _bandShader;
  Shader? _jewelShader;
  Shader? _glowShader;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final p = progress.value.clamp(0.0, 1.0);
    if (reducedMotion) {
      final env = p < 0.25 ? p / 0.25 : (p > 0.7 ? (1 - p) / 0.3 : 1.0);
      _paintStatic(canvas, size, env.clamp(0.0, 1.0));
      return;
    }
    final t = p * (effectSeconds + fadeSeconds);
    final fade = t <= effectSeconds
        ? 1.0
        : (1 - (t - effectSeconds) / fadeSeconds).clamp(0.0, 1.0);
    if (fade <= 0) return;
    switch (victoryId) {
      case VictoryStyles.fireworks:
        _paintFireworks(canvas, size, t, fade);
      case VictoryStyles.crown:
        _paintCrown(canvas, size, t, fade, animate: true);
      default:
        _paintConfetti(canvas, size, t, fade);
    }
  }

  void _paintStatic(Canvas canvas, Size size, double alpha) {
    if (alpha <= 0) return;
    switch (victoryId) {
      case VictoryStyles.fireworks:
        final scene = _FireworksScene.of(seed);
        final s = size.shortestSide;
        _paintShellSparks(
          canvas,
          size,
          scene,
          0,
          0.42,
          alpha,
          overrideBurst: Offset(size.width * 0.5, size.height * 0.38),
          s: s,
        );
      case VictoryStyles.crown:
        _paintCrown(canvas, size, 1.2, alpha, animate: false);
      default:
        _paintConfetti(canvas, size, 0.6, alpha, burstOnly: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Colors.

  void _ensureColors() {
    if (_front != null) return;
    final tint = Color.lerp(color, Colors.white, 0.45)!;
    final palette8 = <Color>[
      color,
      tint,
      palette.gold,
      Colors.white,
      palette.red,
      palette.green,
      palette.yellow,
      palette.blue,
    ];
    final scene = _ConfettiScene.of(seed);
    final front = <Color>[];
    final back = <Color>[];
    for (var i = 0; i < _ConfettiScene.count; i++) {
      final c = palette8[scene.colorIndex[i]];
      front.add(c);
      back.add(Color.lerp(c, Colors.black, 0.28)!);
    }
    _front = front;
    _back = back;
  }

  // ---------------------------------------------------------------------------
  // Confetti.

  void _paintConfetti(
    Canvas canvas,
    Size size,
    double t,
    double alpha, {
    bool burstOnly = false,
  }) {
    _ensureColors();
    final scene = _ConfettiScene.of(seed);
    final s = size.shortestSide;
    final w = size.width;
    final h = size.height;
    final front = _front!;
    final back = _back!;
    _paint
      ..shader = null
      ..style = PaintingStyle.fill;
    for (var i = 0; i < _ConfettiScene.count; i++) {
      final burst = scene.isBurst[i] == 1;
      if (burstOnly && !burst) continue;
      double x, y;
      if (burst) {
        const k = 2.4;
        const vT = 0.32;
        final e = (1 - math.exp(-k * t)) / k;
        x = w * 0.5 + (scene.vx[i] * e) * s;
        y = h * 0.44 + (vT * t + (scene.vy[i] - vT) * e) * s;
      } else {
        x = scene.x0[i] * w;
        y = (scene.y0[i] + scene.vy[i] * t) * h;
      }
      x +=
          math.sin(scene.swayFreq[i] * t + scene.swayPhase[i]) *
          scene.swayAmp[i] *
          s;
      if (y < -s * 0.05 || y > h + s * 0.05) continue;
      final pieceSize = scene.size[i] * s;
      final flip = math.cos(scene.flipFreq[i] * t + scene.flipPhase[i]);
      _paint.color = (flip >= 0 ? front[i] : back[i]).withValues(alpha: alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(scene.rot0[i] + scene.spin[i] * t);
      switch (scene.shape[i]) {
        case 1:
          canvas.scale(1, math.max(0.25, flip.abs()));
          canvas.drawCircle(Offset.zero, pieceSize * 0.42, _paint);
        case 2:
          canvas.scale(math.max(0.2, flip.abs()), 1);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: pieceSize * 0.38,
                height: pieceSize * 1.6,
              ),
              Radius.circular(pieceSize * 0.15),
            ),
            _paint,
          );
        default:
          canvas.scale(1, math.max(0.12, flip.abs()));
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: pieceSize,
              height: pieceSize * 0.55,
            ),
            _paint,
          );
      }
      canvas.restore();
    }
  }

  // ---------------------------------------------------------------------------
  // Fireworks.

  Color _shellColor(int shell) {
    switch (shell % 4) {
      case 0:
        return color;
      case 1:
        return palette.gold;
      case 2:
        return Color.lerp(color, Colors.white, 0.45)!;
      default:
        return Color.lerp(color, palette.gold, 0.5)!;
    }
  }

  void _paintFireworks(Canvas canvas, Size size, double t, double alpha) {
    final scene = _FireworksScene.of(seed);
    final s = size.shortestSide;
    for (var shell = 0; shell < _FireworksScene.shells; shell++) {
      final launch = scene.launchTime[shell];
      final local = t - launch;
      if (local < 0) continue;
      final burst = Offset(
        scene.burstX[shell] * size.width,
        scene.burstY[shell] * size.height,
      );
      final from = Offset(
        scene.launchX[shell] * size.width,
        size.height * 1.02,
      );
      if (local < _FireworksScene.rise) {
        // Rising rocket with a short, fixed-length streak.
        final u = MotionCurves.easeOut(local / _FireworksScene.rise);
        final pos = Offset.lerp(from, burst, u)!;
        final dir = burst - from;
        final len = dir.distance;
        final tailLen = s * 0.07 * (1 - u * 0.6);
        final tail = len > 0 ? pos - dir * (tailLen / len) : pos;
        _paint
          ..shader = null
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s * 0.007
          ..color = palette.gold.withValues(alpha: 0.75 * alpha);
        canvas.drawLine(tail, pos, _paint);
        _paint
          ..style = PaintingStyle.fill
          ..color = Colors.white.withValues(alpha: alpha);
        canvas.drawCircle(pos, s * 0.007, _paint);
        continue;
      }
      final age = local - _FireworksScene.rise;
      _paintShellSparks(
        canvas,
        size,
        scene,
        shell,
        age,
        alpha,
        overrideBurst: burst,
        s: s,
      );
    }
  }

  void _paintShellSparks(
    Canvas canvas,
    Size size,
    _FireworksScene scene,
    int shell,
    double age,
    double alpha, {
    required Offset overrideBurst,
    required double s,
  }) {
    if (age > _FireworksScene.life) return;
    final c = _shellColor(shell);
    final light = Color.lerp(c, Colors.white, 0.55)!;
    final burst = overrideBurst;
    // Flash: soft glow + expanding ring.
    if (age < 0.4) {
      final u = age / 0.4;
      _paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFFFFFFF)
        ..shader = ui.Gradient.radial(burst, s * 0.16, [
          light.withValues(alpha: 0.55 * (1 - u) * alpha),
          c.withValues(alpha: 0),
        ]);
      canvas.drawCircle(burst, s * 0.16, _paint);
      _paint
        ..shader = null
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.006 * (1 - u) + 0.5
        ..color = c.withValues(alpha: 0.45 * (1 - u) * alpha);
      canvas.drawCircle(
        burst,
        s * (0.03 + 0.22 * MotionCurves.easeOut(u)),
        _paint,
      );
    }
    const k = 1.5;
    const vT = 0.14;
    final lifeU = age / _FireworksScene.life;
    final fadeLife = math.pow(1 - lifeU, 1.3).toDouble();
    final base = shell * _FireworksScene.sparks;
    final a0 = math.max(0.0, age - 0.17);
    final e1 = (1 - math.exp(-k * age)) / k;
    final e0 = (1 - math.exp(-k * a0)) / k;
    final width = s * 0.0065 * (1 - 0.5 * lifeU) + 0.4;
    _paint
      ..shader = null
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _FireworksScene.sparks; i++) {
      final vx = scene.vx[base + i];
      final vy = scene.vy[base + i];
      final p1 = burst + Offset(vx * e1 * s, (vT * age + (vy - vT) * e1) * s);
      final p0 = burst + Offset(vx * e0 * s, (vT * a0 + (vy - vT) * e0) * s);
      var a = fadeLife;
      if (lifeU > 0.55) {
        a *= 0.55 + 0.45 * math.sin(age * 36 + i * 1.7);
      }
      a = (a * alpha).clamp(0.0, 1.0);
      final white = i % 6 == 0;
      // Tapered streak: faint tail half, bright head half, glinting tip.
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      final streak = white ? light : c;
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.6
        ..color = streak.withValues(alpha: a * 0.35);
      canvas.drawLine(p0, mid, _paint);
      _paint
        ..strokeWidth = width
        ..color = streak.withValues(alpha: a * 0.9);
      canvas.drawLine(mid, p1, _paint);
      _paint
        ..style = PaintingStyle.fill
        ..color = light.withValues(alpha: a);
      canvas.drawCircle(p1, width * 0.6, _paint);
    }
    _paint.style = PaintingStyle.fill;
  }

  // ---------------------------------------------------------------------------
  // Crown.

  static final Path _crownPath = _buildCrown();

  static Path _buildCrown() {
    // Unit space: x in [-1, 1], y in [-0.95, 0.62].
    return Path()
      ..moveTo(-0.92, 0.5)
      ..lineTo(-1.0, -0.42)
      ..lineTo(-0.58, -0.02)
      ..lineTo(-0.48, -0.72)
      ..lineTo(-0.2, -0.08)
      ..lineTo(0, -0.92)
      ..lineTo(0.2, -0.08)
      ..lineTo(0.48, -0.72)
      ..lineTo(0.58, -0.02)
      ..lineTo(1.0, -0.42)
      ..lineTo(0.92, 0.5)
      ..quadraticBezierTo(0, 0.66, -0.92, 0.5)
      ..close();
  }

  static final Path _bandPath = Path()
    ..moveTo(-0.94, 0.22)
    ..quadraticBezierTo(0, 0.38, 0.94, 0.22)
    ..lineTo(0.92, 0.5)
    ..quadraticBezierTo(0, 0.66, -0.92, 0.5)
    ..close();

  static const List<Offset> _tips = [
    Offset(-1.0, -0.44),
    Offset(-0.48, -0.75),
    Offset(0, -0.96),
    Offset(0.48, -0.75),
    Offset(1.0, -0.44),
  ];

  void _ensureCrownShaders() {
    if (_goldShader != null) return;
    final gold = palette.gold;
    final goldLight = Color.lerp(gold, Colors.white, 0.6)!;
    final goldDeep = palette.goldDeep;
    _goldShader = ui.Gradient.linear(
      const Offset(-1, -1),
      const Offset(1, 0.7),
      [goldLight, gold, goldDeep],
      const [0.0, 0.5, 1.0],
    );
    _bandShader = ui.Gradient.linear(
      const Offset(-1, 0),
      const Offset(1, 0),
      [goldLight, gold, goldDeep],
      const [0.0, 0.4, 1.0],
    );
    _jewelShader = ui.Gradient.radial(
      const Offset(-0.35, -0.35),
      1.25,
      [
        Color.lerp(color, Colors.white, 0.6)!,
        color,
        Color.lerp(color, Colors.black, 0.4)!,
      ],
      const [0.0, 0.45, 1.0],
    );
    _glowShader = ui.Gradient.radial(
      Offset.zero,
      1,
      [
        gold.withValues(alpha: 0.5),
        gold.withValues(alpha: 0.18),
        gold.withValues(alpha: 0),
      ],
      const [0.0, 0.45, 1.0],
    );
  }

  void _paintCrown(
    Canvas canvas,
    Size size,
    double t,
    double alpha, {
    required bool animate,
  }) {
    _ensureCrownShaders();
    final s = size.shortestSide;
    final half = s * 0.23;
    final center = Offset(size.width / 2, size.height * 0.42);

    // Drop-in with a settle bounce.
    var y = center.dy;
    var scale = 1.0;
    if (animate) {
      final u = ((t - 0.05) / 0.7).clamp(0.0, 1.0);
      final e = MotionCurves.easeOutBack(u, 1.7);
      y = -half * 1.5 + (center.dy + half * 1.5) * e;
      scale = 0.8 + 0.2 * MotionCurves.easeOut(u);
    }
    final appear = animate
        ? MotionCurves.easeOut((t / 0.6).clamp(0.0, 1.0))
        : 1.0;

    // Glow + rotating rays behind the crown.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(half * 2.6);
    _paint
      ..shader = _glowShader
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: alpha * appear);
    canvas.drawCircle(Offset.zero, 1, _paint);
    _paint.shader = null;
    canvas.restore();

    const rays = 14;
    final rot = t * 0.25;
    _paint.color = palette.gold.withValues(alpha: 0.2 * alpha * appear);
    final inner = half * 0.5;
    final outer = half * 2.7;
    for (var i = 0; i < rays; i++) {
      final a = rot + i * 2 * math.pi / rays;
      const w = math.pi / rays * 0.42;
      _path
        ..reset()
        ..moveTo(
          center.dx + math.cos(a - w) * inner,
          center.dy + math.sin(a - w) * inner,
        )
        ..lineTo(
          center.dx + math.cos(a - w * 0.4) * outer,
          center.dy + math.sin(a - w * 0.4) * outer,
        )
        ..lineTo(
          center.dx + math.cos(a + w * 0.4) * outer,
          center.dy + math.sin(a + w * 0.4) * outer,
        )
        ..lineTo(
          center.dx + math.cos(a + w) * inner,
          center.dy + math.sin(a + w) * inner,
        )
        ..close();
      canvas.drawPath(_path, _paint);
    }

    // Landing ring.
    if (animate && t > 0.5 && t < 1.2) {
      final u = (t - 0.5) / 0.7;
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.01 * (1 - u) + 0.5
        ..color = palette.gold.withValues(alpha: 0.7 * (1 - u) * alpha);
      canvas.drawCircle(
        center,
        half * (1.0 + 1.6 * MotionCurves.easeOut(u)),
        _paint,
      );
      _paint.style = PaintingStyle.fill;
    }

    // Crown.
    canvas.save();
    canvas.translate(center.dx, y);
    canvas.scale(half * scale);
    final layerAlpha = alpha.clamp(0.0, 1.0);
    if (layerAlpha < 0.999) {
      canvas.saveLayer(
        const Rect.fromLTRB(-1.3, -1.3, 1.3, 1.0),
        Paint()..color = Color.fromRGBO(0, 0, 0, layerAlpha),
      );
    }
    _paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.08
      ..strokeJoin = StrokeJoin.round
      ..color = palette.goldDeep;
    canvas.drawPath(_crownPath, _paint);
    _paint
      ..style = PaintingStyle.fill
      ..shader = _goldShader;
    canvas.drawPath(_crownPath, _paint);
    _paint.shader = _bandShader;
    canvas.drawPath(_bandPath, _paint);
    // Tip pearls.
    _paint.shader = null;
    for (final tip in _tips) {
      _paint.color = palette.goldDeep;
      canvas.drawCircle(tip, 0.115, _paint);
      _paint.color = Color.lerp(palette.gold, Colors.white, 0.7)!;
      canvas.drawCircle(tip, 0.085, _paint);
    }
    // Jewels.
    void jewel(double x, double yy, double r) {
      canvas.save();
      canvas.translate(x, yy);
      canvas.scale(r);
      _paint
        ..shader = null
        ..color = palette.goldDeep;
      canvas.drawCircle(Offset.zero, 1.25, _paint);
      _paint.shader = _jewelShader;
      canvas.drawCircle(Offset.zero, 1, _paint);
      _paint
        ..shader = null
        ..color = Colors.white.withValues(alpha: 0.85);
      canvas.drawCircle(const Offset(-0.35, -0.35), 0.28, _paint);
      canvas.restore();
    }

    jewel(0, 0.42, 0.13);
    jewel(-0.55, 0.37, 0.09);
    jewel(0.55, 0.37, 0.09);
    jewel(0, -0.3, 0.1);
    // Shine sweep.
    if (animate && t > 0.85 && t < 1.55) {
      final u = (t - 0.85) / 0.7;
      final x = -1.6 + 3.2 * u;
      canvas.save();
      canvas.clipPath(_crownPath);
      _path
        ..reset()
        ..moveTo(x - 0.12, 0.7)
        ..lineTo(x + 0.18, 0.7)
        ..lineTo(x + 0.48, -1.0)
        ..lineTo(x + 0.18, -1.0)
        ..close();
      _paint
        ..shader = null
        ..color = Colors.white.withValues(alpha: 0.55 * math.sin(u * math.pi));
      canvas.drawPath(_path, _paint);
      canvas.restore();
    }
    if (layerAlpha < 0.999) canvas.restore();
    canvas.restore();

    // Sparkles.
    final scene = _SparkleScene.of(seed);
    _paint
      ..shader = null
      ..style = PaintingStyle.fill;
    for (var i = 0; i < _SparkleScene.count; i++) {
      double tw;
      if (animate) {
        final local = (t - scene.start[i]) / scene.duration[i];
        if (local <= 0 || local >= 1) continue;
        tw = math.sin(local * math.pi);
      } else {
        if (i % 3 != 0) continue;
        tw = 0.8;
      }
      final a = scene.angle[i];
      final r = scene.radius[i] * half * 2;
      final drift = animate ? (t - scene.start[i]) * s * 0.03 : 0.0;
      final pos = Offset(
        center.dx + math.cos(a) * r,
        center.dy + math.sin(a) * r * 0.8 - drift,
      );
      final which = i % 3;
      final c = which == 0
          ? Colors.white
          : (which == 1 ? palette.gold : Color.lerp(color, Colors.white, 0.3)!);
      _paint.color = c.withValues(alpha: (tw * alpha).clamp(0.0, 1.0));
      BoardEffectsRenderer.sparkle(
        canvas,
        _paint,
        pos,
        s * scene.size[i] * (0.5 + 0.5 * tw),
      );
    }
  }

  @override
  bool shouldRepaint(VictoryEffectPainter oldDelegate) =>
      oldDelegate.victoryId != victoryId ||
      oldDelegate.color != color ||
      oldDelegate.palette != palette ||
      oldDelegate.reducedMotion != reducedMotion ||
      oldDelegate.seed != seed ||
      oldDelegate.progress != progress;
}

/// Precomputed confetti pieces (normalised, deterministic per seed).
class _ConfettiScene {
  _ConfettiScene._(int seed) {
    final rnd = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final burst = i < burstCount;
      isBurst[i] = burst ? 1 : 0;
      if (burst) {
        final a = -math.pi + 0.3 + rnd.nextDouble() * (math.pi - 0.6);
        final speed = 0.9 + rnd.nextDouble() * 0.8;
        vx[i] = math.cos(a) * speed;
        vy[i] = math.sin(a) * speed;
      } else {
        x0[i] = rnd.nextDouble();
        y0[i] = -(0.03 + rnd.nextDouble() * 0.5);
        vy[i] = 0.34 + rnd.nextDouble() * 0.16;
      }
      size[i] = 0.022 + rnd.nextDouble() * 0.014;
      rot0[i] = rnd.nextDouble() * math.pi * 2;
      spin[i] = (rnd.nextDouble() - 0.5) * 7;
      flipFreq[i] = 5 + rnd.nextDouble() * 7;
      flipPhase[i] = rnd.nextDouble() * math.pi * 2;
      swayAmp[i] = burst ? 0.012 : 0.02 + rnd.nextDouble() * 0.025;
      swayFreq[i] = 1.8 + rnd.nextDouble() * 2.2;
      swayPhase[i] = rnd.nextDouble() * math.pi * 2;
      final roll = rnd.nextDouble();
      shape[i] = roll < 0.18 ? 1 : (roll < 0.34 ? 2 : 0);
      final c = rnd.nextDouble();
      colorIndex[i] = c < 0.24
          ? 0
          : c < 0.4
          ? 1
          : c < 0.6
          ? 2
          : c < 0.7
          ? 3
          : 4 + rnd.nextInt(4);
    }
  }

  static const int burstCount = 40;
  static const int count = 100;

  static final Map<int, _ConfettiScene> _cache = {};
  static _ConfettiScene of(int seed) =>
      _cache.putIfAbsent(seed, () => _ConfettiScene._(seed));

  final Uint8List isBurst = Uint8List(count);
  final Float32List x0 = Float32List(count);
  final Float32List y0 = Float32List(count);
  final Float32List vx = Float32List(count);
  final Float32List vy = Float32List(count);
  final Float32List size = Float32List(count);
  final Float32List rot0 = Float32List(count);
  final Float32List spin = Float32List(count);
  final Float32List flipFreq = Float32List(count);
  final Float32List flipPhase = Float32List(count);
  final Float32List swayAmp = Float32List(count);
  final Float32List swayFreq = Float32List(count);
  final Float32List swayPhase = Float32List(count);
  final Uint8List shape = Uint8List(count);
  final Uint8List colorIndex = Uint8List(count);
}

/// Precomputed firework shells and sparks.
class _FireworksScene {
  _FireworksScene._(int seed) {
    final rnd = math.Random(seed * 31 + 5);
    const launchTimes = [0.0, 0.38, 0.8, 1.22];
    const xs = [0.3, 0.7, 0.5, 0.24];
    for (var s = 0; s < shells; s++) {
      launchTime[s] = launchTimes[s];
      launchX[s] = xs[s] + (rnd.nextDouble() - 0.5) * 0.1;
      burstX[s] = (xs[s] + (rnd.nextDouble() - 0.5) * 0.16).clamp(0.18, 0.82);
      burstY[s] = 0.18 + rnd.nextDouble() * 0.2;
      for (var i = 0; i < sparks; i++) {
        // 20 sparks on the outer shell, 12 on a slower inner ring.
        final outer = i < 20;
        final n = outer ? 20 : 12;
        final j = outer ? i : i - 20;
        final a =
            j * 2 * math.pi / n +
            (outer ? 0 : math.pi / n) +
            (rnd.nextDouble() - 0.5) * 0.12;
        final speed = (outer ? 0.6 : 0.34) * (0.9 + 0.2 * rnd.nextDouble());
        vx[s * sparks + i] = math.cos(a) * speed;
        vy[s * sparks + i] = math.sin(a) * speed;
      }
    }
  }

  static const int shells = 4;
  static const int sparks = 32;
  static const double rise = 0.45;
  static const double life = 1.25;

  static final Map<int, _FireworksScene> _cache = {};
  static _FireworksScene of(int seed) =>
      _cache.putIfAbsent(seed, () => _FireworksScene._(seed));

  final Float32List launchTime = Float32List(shells);
  final Float32List launchX = Float32List(shells);
  final Float32List burstX = Float32List(shells);
  final Float32List burstY = Float32List(shells);
  final Float32List vx = Float32List(shells * sparks);
  final Float32List vy = Float32List(shells * sparks);
}

/// Precomputed twinkling sparkles around the crown.
class _SparkleScene {
  _SparkleScene._(int seed) {
    final rnd = math.Random(seed * 17 + 3);
    for (var i = 0; i < count; i++) {
      angle[i] = rnd.nextDouble() * math.pi * 2;
      radius[i] = 0.55 + rnd.nextDouble() * 0.6;
      start[i] = 0.45 + rnd.nextDouble() * 1.85;
      duration[i] = 0.45 + rnd.nextDouble() * 0.35;
      size[i] = 0.018 + rnd.nextDouble() * 0.02;
    }
  }

  static const int count = 36;

  static final Map<int, _SparkleScene> _cache = {};
  static _SparkleScene of(int seed) =>
      _cache.putIfAbsent(seed, () => _SparkleScene._(seed));

  final Float32List angle = Float32List(count);
  final Float32List radius = Float32List(count);
  final Float32List start = Float32List(count);
  final Float32List duration = Float32List(count);
  final Float32List size = Float32List(count);
}
