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

/// Crest artwork (also used by splash/gate illustrations).
class BrandCrestPainter extends CustomPainter {
  const BrandCrestPainter({this.dark = false});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Shield.
    final shieldTop = h * 0.30;
    final shieldRect = Rect.fromLTWH(w * 0.12, shieldTop, w * 0.76, h * 0.68);
    final shield = Path()
      ..moveTo(shieldRect.left, shieldRect.top + w * 0.08)
      ..quadraticBezierTo(
        shieldRect.left,
        shieldRect.top,
        shieldRect.left + w * 0.08,
        shieldRect.top,
      )
      ..lineTo(shieldRect.right - w * 0.08, shieldRect.top)
      ..quadraticBezierTo(
        shieldRect.right,
        shieldRect.top,
        shieldRect.right,
        shieldRect.top + w * 0.08,
      )
      ..lineTo(shieldRect.right, shieldRect.top + shieldRect.height * 0.5)
      ..quadraticBezierTo(
        shieldRect.right,
        shieldRect.bottom - shieldRect.height * 0.12,
        cx,
        shieldRect.bottom,
      )
      ..quadraticBezierTo(
        shieldRect.left,
        shieldRect.bottom - shieldRect.height * 0.12,
        shieldRect.left,
        shieldRect.top + shieldRect.height * 0.5,
      )
      ..close();

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
    final dieSize = w * 0.36;
    final dieCenter = Offset(cx, shieldRect.top + shieldRect.height * 0.46);
    canvas.save();
    canvas.translate(dieCenter.dx, dieCenter.dy);
    canvas.rotate(-0.16);
    final dieRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: dieSize, height: dieSize),
      Radius.circular(dieSize * 0.22),
    );
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
    final pr = dieSize * 0.085;
    final o = dieSize * 0.25;
    for (final d in [
      Offset(-o, -o),
      Offset(o, -o),
      Offset.zero,
      Offset(-o, o),
      Offset(o, o),
    ]) {
      canvas.drawCircle(d, pr, pip);
    }
    canvas.restore();

    // Seat-colored gems along the bottom of the shield.
    const gems = [
      Color(0xFFE5484D),
      Color(0xFF30A46C),
      Color(0xFFF5B800),
      Color(0xFF3E63DD),
    ];
    final gy = shieldRect.top + shieldRect.height * 0.78;
    for (var i = 0; i < 4; i++) {
      final gx = cx + (i - 1.5) * w * 0.1;
      canvas.drawCircle(Offset(gx, gy), w * 0.032, Paint()..color = gems[i]);
      canvas.drawCircle(
        Offset(gx - w * 0.01, gy - w * 0.01),
        w * 0.011,
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
    }

    // Crown.
    final cw = w * 0.62;
    final ch = h * 0.28;
    final left = cx - cw / 2;
    final top = h * 0.04;
    final crown = Path()
      ..moveTo(left + cw * 0.06, top + ch)
      ..lineTo(left, top + ch * 0.28)
      ..lineTo(left + cw * 0.28, top + ch * 0.58)
      ..lineTo(left + cw * 0.5, top)
      ..lineTo(left + cw * 0.72, top + ch * 0.58)
      ..lineTo(left + cw, top + ch * 0.28)
      ..lineTo(left + cw * 0.94, top + ch)
      ..close();
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
        ).createShader(Rect.fromLTWH(left, top, cw, ch)),
    );
    // Crown band.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + cw * 0.05, top + ch * 0.8, cw * 0.9, ch * 0.22),
        Radius.circular(ch * 0.08),
      ),
      Paint()..color = BrandPalette.gold700,
    );
    // Crown tips.
    for (final t in [
      Offset(left, top + ch * 0.28),
      Offset(left + cw * 0.5, top),
      Offset(left + cw, top + ch * 0.28),
    ]) {
      canvas.drawCircle(t, w * 0.035, Paint()..color = BrandPalette.gold300);
    }
    canvas.drawCircle(
      Offset(cx, top + ch * 0.9),
      w * 0.03,
      Paint()..color = const Color(0xFFE5484D),
    );
  }

  static Path _scalePath(Path p, Offset center, double factor) {
    final m = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    return p.transform(m.storage);
  }

  @override
  bool shouldRepaint(BrandCrestPainter old) => old.dark != dark;
}
