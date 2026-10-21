import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game_palette.dart';

/// Token skin ids from `docs/cosmetics-catalog.md`.
abstract final class TokenSkins {
  static const classic = 'token_classic';
  static const gem = 'token_gem';
  static const royal = 'token_royal';
  static const crown = 'token_crown';

  static const all = [classic, gem, royal, crown];

  /// Known id or the starter skin.
  static String resolve(String? id) => all.contains(id) ? id! : classic;
}

/// Draws game tokens.
///
/// Every skin is authored in a unit space (token "radius" 1, origin at the
/// cell center, y down, base contact point at `(0, [baseY])`). Each
/// skin × color × palette combination is recorded once into a [ui.Picture]
/// and replayed with a transform, so painting a token per frame costs one
/// `drawPicture` and no allocations.
abstract final class TokenRenderer {
  /// Y of the token's ground contact in unit space.
  static const double baseY = 0.6;

  /// Fraction of a cell's size used as the token radius on a board.
  static const double cellRadiusFactor = 0.43;

  static final Map<int, ui.Picture> _sprites = <int, ui.Picture>{};
  static final Paint _paint = Paint()..isAntiAlias = true;
  static final Paint _layerPaint = Paint();

  /// Paints a token of [skin] for [color] with its visual center at [center]
  /// (pixels) and the given pixel [radius].
  ///
  /// [scaleX]/[scaleY] squash and stretch around the ground contact point;
  /// [lift] raises the token (pixels) without moving the ground point (draw
  /// the shadow separately with [paintShadow]).
  static void paintToken(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required String skin,
    required SeatColor color,
    required GamePalette palette,
    double scaleX = 1,
    double scaleY = 1,
    double lift = 0,
    double opacity = 1,
    double rotation = 0,
  }) {
    if (opacity <= 0.001 || radius <= 0) return;
    final picture = sprite(skin, color, palette);
    final groundY = center.dy + baseY * radius;
    canvas.save();
    canvas.translate(center.dx, groundY - lift);
    if (rotation != 0) canvas.rotate(rotation);
    canvas.scale(radius * scaleX, radius * scaleY);
    canvas.translate(0, -baseY);
    if (opacity < 0.999) {
      _layerPaint.color = Color.fromRGBO(0, 0, 0, opacity);
      canvas.saveLayer(const Rect.fromLTRB(-1.3, -1.3, 1.3, 1.3), _layerPaint);
      canvas.drawPicture(picture);
      canvas.restore();
    } else {
      canvas.drawPicture(picture);
    }
    canvas.restore();
  }

  /// Soft ground shadow. [liftFraction] 0 = resting, 1 = highest hop.
  static void paintShadow(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required GamePalette palette,
    double liftFraction = 0,
    double opacity = 1,
  }) {
    if (opacity <= 0.001) return;
    final shrink = 1 - 0.35 * liftFraction.clamp(0.0, 1.0);
    final alpha = (1 - 0.55 * liftFraction.clamp(0.0, 1.0)) * opacity;
    final groundY = center.dy + baseY * radius + radius * 0.06;
    final base = palette.tokenShadow;
    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = base.withValues(alpha: base.a * alpha);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + radius * 0.06, groundY),
        width: radius * 1.62 * shrink,
        height: radius * 0.56 * shrink,
      ),
      _paint,
    );
  }

  /// Pulsing ring at the token's feet marking a legal move.
  /// [pulse] runs 0..1 repeatedly.
  static void paintLegalRing(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required GamePalette palette,
    required SeatShades shades,
    required double pulse,
  }) {
    final groundY = center.dy + baseY * radius * 0.55;
    final wave = 0.5 - 0.5 * math.cos(pulse * 2 * math.pi);
    final ringCenter = Offset(center.dx, groundY);
    // Expanding echo.
    _paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..color = palette.highlight.withValues(alpha: 0.55 * (1 - pulse));
    canvas.drawOval(
      Rect.fromCenter(
        center: ringCenter,
        width: radius * (2.0 + 0.9 * pulse),
        height: radius * (1.05 + 0.45 * pulse),
      ),
      _paint,
    );
    // Solid ring.
    _paint
      ..strokeWidth = radius * (0.13 + 0.04 * wave)
      ..color = palette.highlight.withValues(alpha: 0.75 + 0.25 * wave);
    canvas.drawOval(
      Rect.fromCenter(
        center: ringCenter,
        width: radius * 2.05,
        height: radius * 1.08,
      ),
      _paint,
    );
    _paint
      ..strokeWidth = radius * 0.05
      ..color = shades.outline.withValues(alpha: 0.55);
    canvas.drawOval(
      Rect.fromCenter(
        center: ringCenter,
        width: radius * 2.32,
        height: radius * 1.24,
      ),
      _paint,
    );
    _paint.style = PaintingStyle.fill;
  }

  /// Soft colored glow under a token (turn emphasis, home glow).
  static void paintGlow(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    double strength = 1,
  }) {
    if (strength <= 0.01) return;
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.radial(center, radius * 1.6, [
        color.withValues(alpha: 0.55 * strength.clamp(0.0, 1.0)),
        color.withValues(alpha: 0),
      ]);
    canvas.drawCircle(center, radius * 1.6, _paint);
    _paint.shader = null;
  }

  /// Small count badge (e.g. "3" when tokens are stacked).
  static void paintBadge(
    Canvas canvas, {
    required Offset center,
    required double size,
    required int count,
    required SeatShades shades,
    required GamePalette palette,
  }) {
    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = shades.outline;
    canvas.drawCircle(center, size * 0.62, _paint);
    _paint.color = shades.base;
    canvas.drawCircle(center, size * 0.5, _paint);
    final tp = _badgeText(count, size, shades.onColor);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static final Map<int, TextPainter> _badgeTexts = <int, TextPainter>{};

  static TextPainter _badgeText(int count, double size, Color color) {
    final key = Object.hash(count, (size * 2).round(), color);
    return _badgeTexts.putIfAbsent(key, () {
      if (_badgeTexts.length > 48) _badgeTexts.clear();
      return TextPainter(
        text: TextSpan(
          text: '$count',
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w700,
            fontSize: size * 0.72,
            height: 1,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  /// The recorded unit-space picture for a skin/color/palette combination.
  static ui.Picture sprite(String skin, SeatColor color, GamePalette palette) {
    final resolved = TokenSkins.resolve(skin);
    final shades = palette.shades(color);
    final key = Object.hash(
      resolved,
      shades.base,
      shades.outline,
      palette.tokenOutline,
      palette.gold,
      palette.brightness,
    );
    final cached = _sprites[key];
    if (cached != null) return cached;
    if (_sprites.length > 96) _sprites.clear();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTRB(-1.3, -1.3, 1.3, 1.3));
    switch (resolved) {
      case TokenSkins.gem:
        _drawGem(canvas, shades, palette);
      case TokenSkins.royal:
        _drawPawn(canvas, shades, palette, royal: true);
      case TokenSkins.crown:
        _drawCrown(canvas, shades, palette);
      default:
        _drawPawn(canvas, shades, palette, royal: false);
    }
    final picture = recorder.endRecording();
    _sprites[key] = picture;
    return picture;
  }

  // ---------------------------------------------------------------------------
  // Skins (unit space).

  /// Contrast outline around the whole silhouette. On dark palettes a soft
  /// light halo keeps the dark outline readable on dark cells.
  static void _outline(
    Canvas canvas,
    Paint paint,
    Path silhouette,
    Color outline,
    GamePalette p,
  ) {
    paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    if (p.isDark) {
      paint
        ..strokeWidth = 0.24
        ..color = Colors.white.withValues(alpha: 0.2);
      canvas.drawPath(silhouette, paint);
    }
    paint
      ..strokeWidth = 0.13
      ..color = outline;
    canvas.drawPath(silhouette, paint);
  }

  static Color _outlineFor(SeatShades s, GamePalette p) =>
      Color.lerp(s.outline, p.tokenOutline, p.isDark ? 0.55 : 0.35)!;

  static Path _pedestalSide(double topY, double bottomY, double rx, double ry) {
    return Path()
      ..moveTo(-rx, topY)
      ..lineTo(-rx, bottomY)
      ..arcTo(
        Rect.fromCenter(
          center: Offset(0, bottomY),
          width: rx * 2,
          height: ry * 2,
        ),
        math.pi,
        -math.pi,
        false,
      )
      ..lineTo(rx, topY)
      ..close();
  }

  static void _drawPawn(
    Canvas canvas,
    SeatShades s,
    GamePalette p, {
    required bool royal,
  }) {
    final outline = _outlineFor(s, p);
    final gold = p.gold;
    final goldLight = Color.lerp(gold, Colors.white, 0.55)!;
    final goldDeep = p.goldDeep;

    const pedTop = 0.44;
    const pedBottom = 0.58;
    const pedRx = 0.72;
    const pedRy = 0.24;
    final pedSide = _pedestalSide(pedTop, pedBottom, pedRx, pedRy);
    final pedTopOval = Rect.fromCenter(
      center: const Offset(0, pedTop),
      width: pedRx * 2,
      height: pedRy * 2,
    );

    final body = Path()
      ..moveTo(-0.5, 0.56)
      ..cubicTo(-0.47, 0.18, -0.24, -0.02, -0.17, -0.2)
      ..lineTo(0.17, -0.2)
      ..cubicTo(0.24, -0.02, 0.47, 0.18, 0.5, 0.56)
      ..quadraticBezierTo(0, 0.72, -0.5, 0.56)
      ..close();
    const headCenter = Offset(0, -0.5);
    const headR = 0.34;
    final collar = Rect.fromCenter(
      center: const Offset(0, -0.2),
      width: 0.66,
      height: 0.2,
    );

    // Contrast outline: stroke the union of all parts underneath the fills.
    final silhouette = Path()
      ..addPath(pedSide, Offset.zero)
      ..addOval(pedTopOval)
      ..addPath(body, Offset.zero)
      ..addOval(collar)
      ..addOval(Rect.fromCircle(center: headCenter, radius: headR));
    if (royal) {
      silhouette.addOval(
        Rect.fromCircle(center: const Offset(0, -0.9), radius: 0.1),
      );
    }
    final paint = Paint()..isAntiAlias = true;
    _outline(canvas, paint, silhouette, outline, p);
    paint.style = PaintingStyle.fill;

    // Pedestal.
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(-pedRx, 0),
        const Offset(pedRx, 0),
        royal ? [goldLight, gold, goldDeep] : [s.shade, s.deep, s.deep],
        const [0.0, 0.45, 1.0],
      );
    canvas.drawPath(pedSide, paint);
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(-pedRx, pedTop - pedRy),
        const Offset(pedRx, pedTop + pedRy),
        royal ? [goldLight, gold] : [s.soft, s.base],
      );
    canvas.drawOval(pedTopOval, paint);

    // Body.
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(-0.5, 0),
        const Offset(0.5, 0),
        [s.soft, s.base, s.shade, s.deep],
        const [0.0, 0.35, 0.78, 1.0],
      );
    canvas.drawPath(body, paint);

    if (royal) {
      // Gold band around the body.
      final band = Path()
        ..moveTo(-0.39, 0.2)
        ..quadraticBezierTo(0, 0.32, 0.39, 0.2)
        ..lineTo(0.43, 0.3)
        ..quadraticBezierTo(0, 0.43, -0.43, 0.3)
        ..close();
      paint
        ..color = const Color(0xFFFFFFFF)
        ..shader = ui.Gradient.linear(
          const Offset(-0.43, 0),
          const Offset(0.43, 0),
          [goldLight, gold, goldDeep],
          const [0.0, 0.45, 1.0],
        );
      canvas.drawPath(band, paint);
    }

    // Body highlight.
    paint
      ..shader = null
      ..color = Colors.white.withValues(alpha: p.isDark ? 0.28 : 0.38);
    final shine = Path()
      ..moveTo(-0.36, 0.48)
      ..cubicTo(-0.34, 0.2, -0.22, 0.04, -0.14, -0.12)
      ..lineTo(-0.09, -0.1)
      ..cubicTo(-0.16, 0.06, -0.24, 0.24, -0.25, 0.5)
      ..close();
    canvas.drawPath(shine, paint);

    // Collar.
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(-0.33, 0),
        const Offset(0.33, 0),
        royal ? [goldLight, gold, goldDeep] : [s.base, s.shade, s.deep],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawOval(collar, paint);

    // Head.
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.radial(
        const Offset(-0.12, -0.63),
        0.5,
        [Color.lerp(s.soft, Colors.white, 0.35)!, s.base, s.shade, s.deep],
        const [0.0, 0.38, 0.8, 1.0],
      );
    canvas.drawCircle(headCenter, headR, paint);

    if (royal) {
      // Finial.
      paint
        ..color = const Color(0xFFFFFFFF)
        ..shader = ui.Gradient.radial(
          const Offset(-0.03, -0.93),
          0.13,
          [Colors.white, goldLight, gold, goldDeep],
          const [0.0, 0.25, 0.6, 1.0],
        );
      canvas.drawCircle(const Offset(0, -0.9), 0.1, paint);
      paint
        ..shader = null
        ..color = goldDeep;
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(0, -0.82),
          width: 0.2,
          height: 0.06,
        ),
        paint,
      );
    }

    // Specular.
    paint
      ..shader = null
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(-0.13, -0.64),
        width: 0.15,
        height: 0.1,
      ),
      paint,
    );
    paint.color = Colors.white.withValues(alpha: 0.35);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(-0.32, pedTop - 0.04),
        width: 0.28,
        height: 0.08,
      ),
      paint,
    );
  }

  static void _drawGem(Canvas canvas, SeatShades s, GamePalette p) {
    final outline = _outlineFor(s, p);
    final paint = Paint()..isAntiAlias = true;
    const center = Offset(0, -0.1);
    const outerR = 0.76;
    const innerR = 0.42;
    const sides = 8;
    final outer = <Offset>[];
    final inner = <Offset>[];
    for (var i = 0; i < sides; i++) {
      final a = -math.pi / 2 + math.pi / sides + i * 2 * math.pi / sides;
      outer.add(
        center + Offset(math.cos(a) * outerR, math.sin(a) * outerR * 0.92),
      );
      inner.add(
        center + Offset(math.cos(a) * innerR, math.sin(a) * innerR * 0.92),
      );
    }

    // Setting (metal cup under the stone).
    const cupTop = 0.42;
    const cupBottom = 0.56;
    final cupSide = _pedestalSide(cupTop, cupBottom, 0.6, 0.2);
    final cupTopOval = Rect.fromCenter(
      center: const Offset(0, cupTop),
      width: 1.2,
      height: 0.4,
    );
    final outerPath = Path()..addPolygon(outer, true);

    final silhouette = Path()
      ..addPath(cupSide, Offset.zero)
      ..addOval(cupTopOval)
      ..addPath(outerPath, Offset.zero);
    _outline(canvas, paint, silhouette, outline, p);
    paint.style = PaintingStyle.fill;

    final silver = p.isDark ? const Color(0xFFB9C0CC) : const Color(0xFFD5DAE2);
    final silverDeep = p.isDark
        ? const Color(0xFF6F7786)
        : const Color(0xFF8A93A3);
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(-0.6, 0),
        const Offset(0.6, 0),
        [Colors.white, silver, silverDeep],
        const [0.0, 0.4, 1.0],
      );
    canvas.drawPath(cupSide, paint);
    canvas.drawOval(cupTopOval, paint);

    // Facets lit from the top-left.
    const lightAngle = -3 * math.pi / 4;
    paint.shader = null;
    for (var i = 0; i < sides; i++) {
      final j = (i + 1) % sides;
      final mid = (outer[i] + outer[j]) / 2 - center;
      final angle = math.atan2(mid.dy, mid.dx);
      final light = 0.5 + 0.5 * math.cos(angle - lightAngle);
      final facetColor = light > 0.5
          ? Color.lerp(
              s.base,
              Color.lerp(s.soft, Colors.white, 0.4)!,
              (light - 0.5) * 2,
            )!
          : Color.lerp(s.deep, s.base, light * 2)!;
      paint.color = facetColor;
      canvas.drawPath(
        Path()..addPolygon([outer[i], outer[j], inner[j], inner[i]], true),
        paint,
      );
    }
    // Table.
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        center + const Offset(-innerR, -innerR),
        center + const Offset(innerR, innerR),
        [Color.lerp(s.soft, Colors.white, 0.3)!, s.base, s.shade],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawPath(Path()..addPolygon(inner, true), paint);
    paint.shader = null;

    // Facet edges.
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.025
      ..color = Colors.white.withValues(alpha: 0.4);
    for (var i = 0; i < sides; i++) {
      canvas.drawLine(outer[i], inner[i], paint);
    }
    canvas.drawPath(Path()..addPolygon(inner, true), paint);
    paint.style = PaintingStyle.fill;

    // Sparkle.
    paint.color = Colors.white.withValues(alpha: 0.95);
    _star(canvas, paint, center + const Offset(-0.18, -0.2), 0.2, 0.045);
    paint.color = Colors.white.withValues(alpha: 0.6);
    canvas.drawCircle(center + const Offset(0.22, 0.12), 0.04, paint);
  }

  static void _drawCrown(Canvas canvas, SeatShades s, GamePalette p) {
    final outline = _outlineFor(s, p);
    final paint = Paint()..isAntiAlias = true;
    final gold = p.gold;
    final goldLight = Color.lerp(gold, Colors.white, 0.6)!;
    final goldDeep = p.goldDeep;

    const discTop = 0.38;
    const discBottom = 0.58;
    const rx = 0.74;
    const ry = 0.24;
    final discSide = _pedestalSide(discTop, discBottom, rx, ry);
    final discTopOval = Rect.fromCenter(
      center: const Offset(0, discTop),
      width: rx * 2,
      height: ry * 2,
    );

    final crown = Path()
      ..moveTo(-0.56, 0.34)
      ..lineTo(-0.58, -0.38)
      ..lineTo(-0.36, -0.04)
      ..lineTo(-0.28, -0.6)
      ..lineTo(-0.13, -0.06)
      ..lineTo(0, -0.78)
      ..lineTo(0.13, -0.06)
      ..lineTo(0.28, -0.6)
      ..lineTo(0.36, -0.04)
      ..lineTo(0.58, -0.38)
      ..lineTo(0.56, 0.34)
      ..quadraticBezierTo(0, 0.48, -0.56, 0.34)
      ..close();
    const tips = [
      Offset(-0.58, -0.4),
      Offset(-0.28, -0.62),
      Offset(0, -0.8),
      Offset(0.28, -0.62),
      Offset(0.58, -0.4),
    ];

    final silhouette = Path()
      ..addPath(discSide, Offset.zero)
      ..addOval(discTopOval)
      ..addPath(crown, Offset.zero);
    for (final t in tips) {
      silhouette.addOval(Rect.fromCircle(center: t, radius: 0.08));
    }
    _outline(canvas, paint, silhouette, outline, p);
    paint.style = PaintingStyle.fill;

    // Seat-colored disc.
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(-rx, 0),
        const Offset(rx, 0),
        [s.shade, s.deep, s.deep],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawPath(discSide, paint);
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(-rx, discTop - ry),
        const Offset(rx, discTop + ry),
        [s.soft, s.base, s.shade],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawOval(discTopOval, paint);

    // Gold crown.
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(-0.6, -0.8),
        const Offset(0.6, 0.45),
        [goldLight, gold, goldDeep],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawPath(crown, paint);
    // Band.
    final band = Path()
      ..moveTo(-0.56, 0.12)
      ..quadraticBezierTo(0, 0.24, 0.56, 0.12)
      ..lineTo(0.56, 0.3)
      ..quadraticBezierTo(0, 0.44, -0.56, 0.3)
      ..close();
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        const Offset(-0.56, 0),
        const Offset(0.56, 0),
        [goldLight, gold, goldDeep],
        const [0.0, 0.4, 1.0],
      );
    canvas.drawPath(band, paint);
    paint.shader = null;
    // Tip balls.
    for (final t in tips) {
      paint
        ..color = const Color(0xFFFFFFFF)
        ..shader = ui.Gradient.radial(
          t + const Offset(-0.025, -0.025),
          0.1,
          [Colors.white, goldLight, gold],
          const [0.0, 0.35, 1.0],
        );
      canvas.drawCircle(t, 0.075, paint);
    }
    // Jewels in the seat color.
    void jewel(Offset c, double r) {
      paint
        ..color = const Color(0xFFFFFFFF)
        ..shader = ui.Gradient.radial(
          c + Offset(-r * 0.35, -r * 0.35),
          r * 1.2,
          [Color.lerp(s.soft, Colors.white, 0.5)!, s.base, s.deep],
          const [0.0, 0.45, 1.0],
        );
      canvas.drawCircle(c, r, paint);
      paint
        ..shader = null
        ..color = Colors.white.withValues(alpha: 0.85);
      canvas.drawCircle(c + Offset(-r * 0.35, -r * 0.35), r * 0.25, paint);
    }

    jewel(const Offset(0, 0.25), 0.1);
    jewel(const Offset(-0.33, 0.21), 0.07);
    jewel(const Offset(0.33, 0.21), 0.07);
    jewel(const Offset(0, -0.3), 0.08);
    // Crown shine.
    paint
      ..shader = null
      ..color = Colors.white.withValues(alpha: 0.45);
    canvas.drawPath(
      Path()
        ..moveTo(-0.47, 0.06)
        ..lineTo(-0.5, -0.24)
        ..lineTo(-0.4, -0.06)
        ..close(),
      paint,
    );
  }

  /// Four-point sparkle star.
  static void _star(Canvas canvas, Paint paint, Offset c, double r, double w) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }
}
