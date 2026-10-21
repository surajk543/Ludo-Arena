import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../boards_l10n.dart';
import '../game_palette.dart';
import 'dice_controller.dart';
import 'dice_skins.dart';

/// A pseudo-3D die rendered with a real (orthographic) cube rotation.
///
/// Drive it with a [DiceController]. [enabled] shows the idle "ready" pulse
/// and makes the die tappable (taps are ignored while rolling). [accent]
/// tints the ready pulse (and the neon glow); defaults to the palette
/// highlight.
class DiceView extends StatefulWidget {
  const DiceView({
    super.key,
    required this.controller,
    this.skin = DiceSkins.classic,
    this.size = 72,
    this.enabled = false,
    this.onTap,
    this.accent,
    this.reducedMotion = false,
  });

  final DiceController controller;
  final String skin;
  final double size;
  final bool enabled;
  final VoidCallback? onTap;
  final Color? accent;
  final bool reducedMotion;

  @override
  State<DiceView> createState() => _DiceViewState();
}

class _DiceViewState extends State<DiceView> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
    _syncPulse();
  }

  void _attach(DiceController controller) {
    controller.reducedMotion = widget.reducedMotion;
    controller.attach(this);
    controller.addListener(_onControllerChanged);
  }

  void _detach(DiceController controller) {
    controller.removeListener(_onControllerChanged);
    controller.detach();
  }

  @override
  void didUpdateWidget(DiceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
    } else {
      widget.controller.reducedMotion = widget.reducedMotion;
    }
    _syncPulse();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _syncPulse();
  }

  bool get _showPulse => widget.enabled && !widget.controller.rolling;

  void _syncPulse() {
    final animate = _showPulse && !widget.reducedMotion;
    if (animate) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of(context);
    final l10n = boardsL10n(context);
    final controller = widget.controller;
    final rolling = controller.rolling;
    final canTap = widget.enabled && !rolling && widget.onTap != null;
    final style = DiceStyle.resolve(
      widget.skin,
      brightness: palette.brightness,
      accent: widget.skin == DiceSkins.neon ? widget.accent : null,
    );
    final label = rolling
        ? l10n.boardsDiceRolling
        : l10n.boardsDiceShowing(controller.value);

    return Semantics(
      container: true,
      label: label,
      button: widget.enabled,
      enabled: widget.enabled ? canTap : null,
      onTap: canTap ? widget.onTap : null,
      onTapHint: canTap ? l10n.boardsDiceRollHint : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTap ? widget.onTap : null,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: DicePainter(
              controller: controller,
              style: style,
              pulse: _pulse,
              showPulse: _showPulse,
              accent: widget.accent ?? palette.highlight,
              shadow: palette.tokenShadow,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the die for a [DiceController]'s current render state. Public so
/// previews can draw a die without a view; repaints on controller frames and
/// the [pulse] animation.
class DicePainter extends CustomPainter {
  DicePainter({
    required this.controller,
    required this.style,
    required this.pulse,
    required this.showPulse,
    required this.accent,
    required this.shadow,
  }) : super(repaint: Listenable.merge([controller.frames, pulse]));

  final DiceController controller;
  final DiceStyle style;
  final Animation<double> pulse;
  final bool showPulse;
  final Color accent;
  final Color shadow;

  // Face table: value → (normal axis, sign), (u axis, sign), (v axis, sign).
  // Axes: 0 = x (right), 1 = y (up), 2 = z (toward the viewer).
  static const List<int> _faceValues = [1, 6, 2, 5, 3, 4];
  static const List<int> _nAxis = [2, 2, 1, 1, 0, 0];
  static const List<int> _nSign = [1, -1, 1, -1, 1, -1];
  static const List<int> _uAxis = [0, 0, 0, 0, 2, 2];
  static const List<int> _uSign = [1, -1, 1, 1, -1, 1];
  static const List<int> _vAxis = [1, 1, 2, 2, 1, 1];
  static const List<int> _vSign = [-1, -1, 1, -1, -1, -1];

  // Light direction (y up), normalised.
  static const double _lx = -0.36;
  static const double _ly = 0.76;
  static const double _lz = 0.54;

  static final Float64List _rot = Float64List(9);
  static final Float64List _tilt = _buildTilt();
  static final Float64List _faceMatrix = Float64List(16)
    ..[10] = 1
    ..[15] = 1;
  static final Float64List _visible = Float64List(6);
  static final Paint _paint = Paint()..isAntiAlias = true;

  static Float64List _buildTilt() {
    const tx = DiceController.tiltX;
    const ty = DiceController.tiltY;
    final ctx = math.cos(tx), stx = math.sin(tx);
    final cty = math.cos(ty), sty = math.sin(ty);
    // T = Rx(tx) · Ry(ty)
    return Float64List.fromList([
      cty, 0, sty, //
      stx * sty, ctx, -stx * cty, //
      -ctx * sty, stx, ctx * cty, //
    ]);
  }

  /// Writes `M = T · Rz(az) · Ry(ay) · Rx(ax)` (row-major) into [_rot].
  static void _computeRotation(double ax, double ay, double az) {
    final cx = math.cos(ax), sx = math.sin(ax);
    final cy = math.cos(ay), sy = math.sin(ay);
    final cz = math.cos(az), sz = math.sin(az);
    final b00 = cz * cy,
        b01 = cz * sy * sx - sz * cx,
        b02 = cz * sy * cx + sz * sx;
    final b10 = sz * cy,
        b11 = sz * sy * sx + cz * cx,
        b12 = sz * sy * cx - cz * sx;
    final b20 = -sy, b21 = cy * sx, b22 = cy * cx;
    final t = _tilt;
    for (var r = 0; r < 3; r++) {
      final t0 = t[r * 3], t1 = t[r * 3 + 1], t2 = t[r * 3 + 2];
      _rot[r * 3] = t0 * b00 + t1 * b10 + t2 * b20;
      _rot[r * 3 + 1] = t0 * b01 + t1 * b11 + t2 * b21;
      _rot[r * 3 + 2] = t0 * b02 + t1 * b12 + t2 * b22;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) return;
    final shaders = _DiceShaders.of(style);
    final cx = size.width / 2;
    final restY = size.height / 2 - s * 0.01;
    final groundY = size.height / 2 + s * 0.325;
    final half = s * 0.235;
    final hop = controller.hop;
    final wave = showPulse
        ? 0.5 - 0.5 * math.cos(pulse.value * 2 * math.pi)
        : 0.0;
    final breathe = 1 + 0.035 * wave;
    final scale = controller.popScale * breathe;
    final opacity = controller.opacity;
    final center = Offset(cx, restY - hop * s * 0.4);

    // Ground shadow.
    final lift = (hop / 0.36).clamp(0.0, 1.0);
    _paint
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = shadow.withValues(alpha: shadow.a * (1 - 0.6 * lift) * opacity);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + s * 0.02, groundY),
        width: s * 0.66 * (1 - 0.4 * lift) * scale,
        height: s * 0.16 * (1 - 0.4 * lift) * scale,
      ),
      _paint,
    );

    // Ready pulse ring + glow.
    if (showPulse) {
      canvas.save();
      canvas.translate(cx, restY);
      canvas.scale(s * 0.5);
      _paint.shader = shaders.glowFor(accent);
      _paint.color = Colors.white.withValues(alpha: 0.55 + 0.45 * wave);
      canvas.drawCircle(Offset.zero, 1, _paint);
      _paint
        ..shader = null
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.035
        ..color = accent.withValues(alpha: 0.35 + 0.4 * (1 - pulse.value));
      canvas.drawCircle(Offset.zero, 0.86 + 0.12 * pulse.value, _paint);
      _paint.style = PaintingStyle.fill;
      canvas.restore();
    }

    // Neon halo.
    if (style.edgeGlow != null) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(s * 0.48 * scale);
      _paint
        ..shader = shaders.edgeGlow
        ..color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(Offset.zero, 1, _paint);
      _paint.shader = null;
      canvas.restore();
    }

    if (opacity < 0.999) {
      canvas.saveLayer(
        Rect.fromCenter(center: center, width: s * 1.4, height: s * 1.4),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    } else {
      canvas.save();
    }
    // Squash around the die's lower edge, plus overall scale.
    final sq = controller.squash;
    final pivotY = center.dy + half * 1.3;
    canvas.translate(center.dx, pivotY);
    canvas.scale(scale * (1 + 0.1 * sq), scale * (1 - 0.13 * sq));
    canvas.translate(-center.dx, -pivotY);

    _computeRotation(controller.angleX, controller.angleY, controller.angleZ);
    final r = _rot;
    for (var f = 0; f < 6; f++) {
      final nz = _nSign[f] * r[6 + _nAxis[f]];
      _visible[f] = nz;
    }

    // Pass 1: contrast outline; pass 2: bevel; pass 3: faces.
    for (var pass = 0; pass < 3; pass++) {
      for (var f = 0; f < 6; f++) {
        final nz = _visible[f];
        if (nz <= 0.012) continue;
        final na = _nAxis[f], ns = _nSign[f];
        final ua = _uAxis[f], us = _uSign[f];
        final va = _vAxis[f], vs = _vSign[f];
        final nx = ns * r[na], ny = ns * r[3 + na];
        final m = _faceMatrix;
        m[0] = us * r[ua] * half;
        m[1] = -us * r[3 + ua] * half;
        m[4] = vs * r[va] * half;
        m[5] = -vs * r[3 + va] * half;
        m[12] = center.dx + nx * half;
        m[13] = center.dy - ny * half;
        final light = nx * _lx + ny * _ly + nz * _lz;
        canvas.save();
        canvas.transform(m);
        switch (pass) {
          case 0:
            _paint
              ..shader = null
              ..color = style.outline.withValues(alpha: 0.9);
            canvas.drawRRect(_outlineRect, _paint);
          case 1:
            _paint
              ..shader = null
              ..color = Color.lerp(
                style.edge,
                const Color(0xFF000000),
                ((0.75 - light) * 0.35).clamp(0.0, 0.4),
              )!;
            canvas.drawRRect(_edgeRect, _paint);
          case 2:
            _paintFace(canvas, _faceValues[f], light, shaders);
        }
        canvas.restore();
      }
    }
    canvas.restore();
  }

  static final RRect _outlineRect = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-1.08, -1.08, 1.08, 1.08),
    const Radius.circular(0.44),
  );
  static final RRect _edgeRect = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-1, -1, 1, 1),
    const Radius.circular(0.38),
  );
  static final RRect _faceRect = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-0.86, -0.86, 0.86, 0.86),
    const Radius.circular(0.3),
  );

  static const double _d = 0.5;
  static const List<List<double>> _pips = [
    [0, 0],
    [-_d, -_d, _d, _d],
    [-_d, -_d, 0, 0, _d, _d],
    [-_d, -_d, _d, -_d, -_d, _d, _d, _d],
    [-_d, -_d, _d, -_d, 0, 0, -_d, _d, _d, _d],
    [-_d, -_d, -_d, 0, -_d, _d, _d, -_d, _d, 0, _d, _d],
  ];

  void _paintFace(Canvas canvas, int value, double light, _DiceShaders sh) {
    _paint
      ..shader = sh.face
      ..color = const Color(0xFFFFFFFF);
    canvas.drawRRect(_faceRect, _paint);
    _paint.shader = null;

    // Lighting overlay.
    if (light > 0.55) {
      _paint.color = Colors.white.withValues(
        alpha: ((light - 0.55) * 0.5).clamp(0.0, 0.25),
      );
      canvas.drawRRect(_faceRect, _paint);
    } else {
      _paint.color = Colors.black.withValues(
        alpha: ((0.55 - light) * 0.42).clamp(0.0, 0.5),
      );
      canvas.drawRRect(_faceRect, _paint);
    }

    if (style.motif == DiceMotif.autumnLeaves && style.veins != null) {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.035
        ..strokeCap = StrokeCap.round
        ..color = style.veins!.withValues(alpha: 0.32);
      canvas.drawPath(_DiceShaders.veinPath, _paint);
      _paint.style = PaintingStyle.fill;
    }

    final rim = style.rim;
    if (rim != null) {
      _paint.style = PaintingStyle.stroke;
      if (style.edgeGlow != null) {
        _paint
          ..strokeWidth = 0.2
          ..color = rim.withValues(alpha: 0.22);
        canvas.drawRRect(_faceRect, _paint);
      }
      _paint
        ..strokeWidth = 0.05
        ..color = rim.withValues(alpha: style.edgeGlow != null ? 0.9 : 0.65);
      canvas.drawRRect(_faceRect, _paint);
      _paint.style = PaintingStyle.fill;
    }

    if (value == 1 && style.motif == DiceMotif.autumnLeaves) {
      _paint
        ..shader = null
        ..color = style.pip;
      canvas.drawPath(_DiceShaders.leafPath, _paint);
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03
        ..color = style.veins!.withValues(alpha: 0.75);
      canvas.drawPath(_DiceShaders.leafVeins, _paint);
      _paint.style = PaintingStyle.fill;
      return;
    }

    final pips = _pips[value - 1];
    final radius = value == 1 ? 0.26 : 0.165;
    final pipShader = value == 1
        ? sh.onePip
        : (style.alternatePip != null && value.isEven ? sh.altPip : sh.pip);
    for (var i = 0; i < pips.length; i += 2) {
      canvas.save();
      canvas.translate(pips[i], pips[i + 1]);
      canvas.scale(radius);
      if (sh.pipGlow != null) {
        _paint
          ..shader = value == 1 || (style.alternatePip != null && value.isEven)
              ? sh.altPipGlow
              : sh.pipGlow
          ..color = const Color(0xFFFFFFFF);
        canvas.drawCircle(Offset.zero, 1.9, _paint);
      }
      _paint
        ..shader = pipShader
        ..color = const Color(0xFFFFFFFF);
      canvas.drawCircle(Offset.zero, 1, _paint);
      canvas.restore();
    }
    _paint.shader = null;
  }

  @override
  bool shouldRepaint(DicePainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.style != style ||
      oldDelegate.showPulse != showPulse ||
      oldDelegate.accent != accent ||
      oldDelegate.shadow != shadow ||
      oldDelegate.pulse != pulse;
}

/// Shaders and paths for one [DiceStyle], defined in unit (face-local /
/// pip-local) space and created once.
class _DiceShaders {
  _DiceShaders._(this.style)
    : face = ui.Gradient.linear(const Offset(-1, -1), const Offset(1, 1), [
        style.faceLight,
        style.faceDark,
      ]),
      pip = _pipShader(style.pip, style.pipHighlight),
      altPip = _pipShader(style.alternatePip ?? style.pip, style.pipHighlight),
      onePip = _pipShader(
        style.onePip,
        Color.lerp(style.onePip, Colors.white, 0.35)!,
      ),
      pipGlow = style.pipGlow == null ? null : _glow(style.pipGlow!, 0.65),
      altPipGlow = style.pipGlow == null
          ? null
          : _glow(style.alternatePip ?? style.pipGlow!, 0.65),
      edgeGlow = style.edgeGlow == null ? null : _glow(style.edgeGlow!, 0.5);

  static final Map<DiceStyle, _DiceShaders> _cache = {};

  static _DiceShaders of(DiceStyle style) {
    final cached = _cache[style];
    if (cached != null) return cached;
    if (_cache.length > 16) _cache.clear();
    return _cache[style] = _DiceShaders._(style);
  }

  final DiceStyle style;
  final Shader face;
  final Shader pip;
  final Shader altPip;
  final Shader onePip;
  final Shader? pipGlow;
  final Shader? altPipGlow;
  final Shader? edgeGlow;
  final Map<Color, Shader> _accentGlows = {};

  Shader glowFor(Color accent) => _accentGlows.putIfAbsent(accent, () {
    if (_accentGlows.length > 8) _accentGlows.clear();
    return _glow(accent, 0.4);
  });

  static Shader _pipShader(Color pip, Color highlight) => ui.Gradient.radial(
    const Offset(0.22, 0.28),
    1.15,
    [highlight, pip, pip],
    const [0.0, 0.55, 1.0],
  );

  static Shader _glow(Color c, double alpha) => ui.Gradient.radial(
    Offset.zero,
    1,
    [
      c.withValues(alpha: alpha),
      c.withValues(alpha: alpha * 0.35),
      c.withValues(alpha: 0),
    ],
    const [0.0, 0.45, 1.0],
  );

  static final Path veinPath = Path()
    ..moveTo(-0.62, 0.62)
    ..quadraticBezierTo(-0.2, 0.15, 0.55, -0.6)
    ..moveTo(-0.3, 0.3)
    ..quadraticBezierTo(-0.42, 0.05, -0.38, -0.12)
    ..moveTo(0.02, 0.0)
    ..quadraticBezierTo(0.25, 0.05, 0.36, 0.2)
    ..moveTo(0.18, -0.22)
    ..quadraticBezierTo(0.05, -0.42, 0.08, -0.55);

  /// Five-lobed maple-like leaf, unit space (~0.5 radius), with a stem.
  static final Path leafPath = _buildLeaf();
  static final Path leafVeins = Path()
    ..moveTo(0, 0.42)
    ..lineTo(0, -0.42)
    ..moveTo(0, 0.08)
    ..lineTo(-0.36, -0.22)
    ..moveTo(0, 0.08)
    ..lineTo(0.36, -0.22)
    ..moveTo(0, 0.14)
    ..lineTo(-0.3, 0.2)
    ..moveTo(0, 0.14)
    ..lineTo(0.3, 0.2);

  static Path _buildLeaf() {
    // Alternating tip / notch radii around the leaf, starting at the top.
    const tips = [
      [-90.0, 0.5],
      [-62.0, 0.2],
      [-35.0, 0.46],
      [-5.0, 0.2],
      [22.0, 0.34],
      [62.0, 0.16],
      [90.0, 0.12],
      [118.0, 0.16],
      [158.0, 0.34],
      [185.0, 0.2],
      [215.0, 0.46],
      [242.0, 0.2],
    ];
    final path = Path();
    for (var i = 0; i < tips.length; i++) {
      final a = tips[i][0] * math.pi / 180;
      final rr = tips[i][1];
      final p = Offset(math.cos(a) * rr, math.sin(a) * rr + 0.04);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    // Stem.
    path.addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-0.025, 0.1, 0.025, 0.5),
        const Radius.circular(0.02),
      ),
    );
    return path;
  }
}
