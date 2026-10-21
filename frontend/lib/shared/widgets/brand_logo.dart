import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Painted royal crest: a gold crown over a violet shield carrying a die.
/// Optional wordmark (`appTitle`) in a gold gradient below.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 96, this.showWordmark = false});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final crest = CustomPaint(
      size: Size(size, size * 1.08),
      painter: BrandCrestPainter(dark: c.isDark),
    );
    final Widget body;
    if (!showWordmark) {
      body = crest;
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          crest,
          SizedBox(height: size * 0.12),
          ShaderMask(
            shaderCallback: (r) => c.goldGradient.createShader(r),
            blendMode: BlendMode.srcIn,
            child: Text(
              l10n.appTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: context.textTheme.displaySmall?.copyWith(
                fontSize: math.max(22, size * 0.34),
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: c.shadowColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Semantics(
      image: true,
      label: l10n.widgetsLogoLabel(l10n.appTitle),
      excludeSemantics: true,
      child: body,
    );
  }
}

/// Crest artwork (also used by splash/gate illustrations and, through
/// `tool/generate_brand_assets.dart`, the native app icons and launch
/// screens).
///
/// [monochrome] paints a single-color silhouette (crown, shield rim, die
/// with pip cut-outs) in [monochromeColor]; it is the source of the Android
/// 13+ themed icon.
class BrandCrestPainter extends CustomPainter {
  const BrandCrestPainter({
    this.dark = false,
    this.monochrome = false,
    this.monochromeColor = Colors.white,
  });

  final bool dark;
  final bool monochrome;
  final Color monochromeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (monochrome) {
      _paintMonochrome(canvas, size);
      return;
    }
    final w = size.width;
    final h = size.height;

    // Shield.
    final shieldRect = _shieldRect(size);
    final shield = _shieldPath(size);

    canvas.drawShadow(shield, Colors.black, w * 0.05, false);
    // Gold border.
    canvas.drawPath(
      shield,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BrandPalette.gold300, BrandPalette.gold600],
        ).createShader(shieldRect),
    );
    // Inner violet field.
    final inner = _scalePath(shield, shieldRect.center, 0.86);
    canvas.drawPath(
      inner,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BrandPalette.royal400,
            BrandPalette.royal600,
            BrandPalette.royal800,
          ],
        ).createShader(shieldRect),
    );
    // Sheen.
    canvas.save();
    canvas.clipPath(inner);
    canvas.drawRect(
      Rect.fromLTWH(
        shieldRect.left,
        shieldRect.top,
        shieldRect.width,
        shieldRect.height * 0.4,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(shieldRect),
    );
    canvas.restore();

    // Die.
    final dieSize = _dieSize(size);
    canvas.save();
    canvas.translate(_dieCenter(size).dx, _dieCenter(size).dy);
    canvas.rotate(_dieRotation);
    final dieRect = _dieRect(size);
    canvas.drawRRect(
      dieRect.shift(Offset(0, dieSize * 0.06)),
      Paint()..color = BrandPalette.royal950.withValues(alpha: 0.45),
    );
    canvas.drawRRect(
      dieRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFE9E3FF)],
        ).createShader(dieRect.outerRect),
    );
    final pip = Paint()..color = BrandPalette.royal700;
    for (final d in _pipOffsets(size)) {
      canvas.drawCircle(d, _pipRadius(size), pip);
    }
    canvas.restore();

    // Seat-colored gems along the bottom of the shield.
    const gems = [
      Color(0xFFE5484D),
      Color(0xFF30A46C),
      Color(0xFFF5B800),
      Color(0xFF3E63DD),
    ];
    final gemCenters = _gemCenters(size);
    for (var i = 0; i < 4; i++) {
      final g = gemCenters[i];
      canvas.drawCircle(g, w * 0.032, Paint()..color = gems[i]);
      canvas.drawCircle(
        Offset(g.dx - w * 0.01, g.dy - w * 0.01),
        w * 0.011,
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
    }

    // Crown.
    final crownRect = _crownRect(size);
    final crown = _crownPath(size);
    canvas.drawPath(
      crown.shift(Offset(0, h * 0.015)),
      Paint()..color = BrandPalette.gold800.withValues(alpha: 0.6),
    );
    canvas.drawPath(
      crown,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BrandPalette.gold300,
            BrandPalette.gold500,
            BrandPalette.gold600,
          ],
        ).createShader(crownRect),
    );
    // Crown band.
    canvas.drawRRect(_crownBand(size), Paint()..color = BrandPalette.gold700);
    // Crown tips.
    for (final t in _crownTips(size)) {
      canvas.drawCircle(t, w * 0.035, Paint()..color = BrandPalette.gold300);
    }
    canvas.drawCircle(
      _crownJewel(size),
      w * 0.03,
      Paint()..color = const Color(0xFFE5484D),
    );
  }

  /// Single-color silhouette: crown with a jewel cut-out, the shield rim,
  /// the die with pip cut-outs and the four gems. No shadows or gradients.
  void _paintMonochrome(Canvas canvas, Size size) {
    final w = size.width;
    final fill = Paint()..color = monochromeColor;
    final clear = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(Offset.zero & size, Paint());

    // Shield rim (the field inside is cut out).
    final shield = _shieldPath(size);
    canvas.drawPath(shield, fill);
    canvas.drawPath(_scalePath(shield, _shieldRect(size).center, 0.86), clear);

    // Die with pip holes.
    canvas.save();
    canvas.translate(_dieCenter(size).dx, _dieCenter(size).dy);
    canvas.rotate(_dieRotation);
    canvas.drawRRect(_dieRect(size), fill);
    for (final d in _pipOffsets(size)) {
      canvas.drawCircle(d, _pipRadius(size), clear);
    }
    canvas.restore();

    for (final g in _gemCenters(size)) {
      canvas.drawCircle(g, w * 0.032, fill);
    }

    // Crown, band and tips, with the center jewel cut out.
    canvas.drawPath(_crownPath(size), fill);
    canvas.drawRRect(_crownBand(size), fill);
    for (final t in _crownTips(size)) {
      canvas.drawCircle(t, w * 0.035, fill);
    }
    canvas.drawCircle(_crownJewel(size), w * 0.03, clear);
    canvas.restore();
  }

  // ---- Geometry (shared by the color and monochrome renderings) ----

  static const double _dieRotation = -0.16;

  static Rect _shieldRect(Size s) => Rect.fromLTWH(
    s.width * 0.12,
    s.height * 0.30,
    s.width * 0.76,
    s.height * 0.68,
  );

  static Path _shieldPath(Size s) {
    final w = s.width;
    final cx = w / 2;
    final r = _shieldRect(s);
    return Path()
      ..moveTo(r.left, r.top + w * 0.08)
      ..quadraticBezierTo(r.left, r.top, r.left + w * 0.08, r.top)
      ..lineTo(r.right - w * 0.08, r.top)
      ..quadraticBezierTo(r.right, r.top, r.right, r.top + w * 0.08)
      ..lineTo(r.right, r.top + r.height * 0.5)
      ..quadraticBezierTo(r.right, r.bottom - r.height * 0.12, cx, r.bottom)
      ..quadraticBezierTo(
        r.left,
        r.bottom - r.height * 0.12,
        r.left,
        r.top + r.height * 0.5,
      )
      ..close();
  }

  static double _dieSize(Size s) => s.width * 0.36;

  static Offset _dieCenter(Size s) {
    final r = _shieldRect(s);
    return Offset(s.width / 2, r.top + r.height * 0.46);
  }

  /// Die body, centered on the origin (callers translate and rotate).
  static RRect _dieRect(Size s) {
    final d = _dieSize(s);
    return RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: d, height: d),
      Radius.circular(d * 0.22),
    );
  }

  static double _pipRadius(Size s) => _dieSize(s) * 0.085;

  static List<Offset> _pipOffsets(Size s) {
    final o = _dieSize(s) * 0.25;
    return [
      Offset(-o, -o),
      Offset(o, -o),
      Offset.zero,
      Offset(-o, o),
      Offset(o, o),
    ];
  }

  static List<Offset> _gemCenters(Size s) {
    final r = _shieldRect(s);
    final gy = r.top + r.height * 0.78;
    return [
      for (var i = 0; i < 4; i++)
        Offset(s.width / 2 + (i - 1.5) * s.width * 0.1, gy),
    ];
  }

  static Rect _crownRect(Size s) {
    final cw = s.width * 0.62;
    return Rect.fromLTWH(
      s.width / 2 - cw / 2,
      s.height * 0.04,
      cw,
      s.height * 0.28,
    );
  }

  static Path _crownPath(Size s) {
    final c = _crownRect(s);
    final (left, top, cw, ch) = (c.left, c.top, c.width, c.height);
    return Path()
      ..moveTo(left + cw * 0.06, top + ch)
      ..lineTo(left, top + ch * 0.28)
      ..lineTo(left + cw * 0.28, top + ch * 0.58)
      ..lineTo(left + cw * 0.5, top)
      ..lineTo(left + cw * 0.72, top + ch * 0.58)
      ..lineTo(left + cw, top + ch * 0.28)
      ..lineTo(left + cw * 0.94, top + ch)
      ..close();
  }

  static RRect _crownBand(Size s) {
    final c = _crownRect(s);
    return RRect.fromRectAndRadius(
      Rect.fromLTWH(
        c.left + c.width * 0.05,
        c.top + c.height * 0.8,
        c.width * 0.9,
        c.height * 0.22,
      ),
      Radius.circular(c.height * 0.08),
    );
  }

  static List<Offset> _crownTips(Size s) {
    final c = _crownRect(s);
    return [
      Offset(c.left, c.top + c.height * 0.28),
      Offset(c.left + c.width * 0.5, c.top),
      Offset(c.right, c.top + c.height * 0.28),
    ];
  }

  static Offset _crownJewel(Size s) {
    final c = _crownRect(s);
    return Offset(s.width / 2, c.top + c.height * 0.9);
  }

  static Path _scalePath(Path p, Offset center, double factor) {
    final m = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    return p.transform(m.storage);
  }

  @override
  bool shouldRepaint(BrandCrestPainter old) =>
      old.dark != dark ||
      old.monochrome != monochrome ||
      old.monochromeColor != monochromeColor;
}
