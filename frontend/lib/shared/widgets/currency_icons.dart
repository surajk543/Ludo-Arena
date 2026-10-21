import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Painted gold coin with an embossed crown.
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: const CoinPainter()),
  );
}

/// Painted faceted diamond.
class DiamondIcon extends StatelessWidget {
  const DiamondIcon({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: const DiamondPainter(),
    ),
  );
}

/// Coin artwork, reusable by other painters (e.g. reward bursts).
class CoinPainter extends CustomPainter {
  const CoinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);
    final r = s / 2;

    // Drop shadow / rim.
    canvas.drawCircle(
      center.translate(0, s * 0.04),
      r * 0.96,
      Paint()..color = BrandPalette.gold800.withValues(alpha: 0.55),
    );
    // Outer rim.
    canvas.drawCircle(
      center,
      r * 0.96,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BrandPalette.gold300,
            BrandPalette.gold600,
            BrandPalette.gold700,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    // Face.
    canvas.drawCircle(
      center,
      r * 0.76,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.35),
          radius: 0.95,
          colors: [
            BrandPalette.gold300,
            BrandPalette.gold500,
            BrandPalette.gold600,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r * 0.76)),
    );
    // Inner engraved ring.
    canvas.drawCircle(
      center,
      r * 0.76,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035
        ..color = BrandPalette.gold700.withValues(alpha: 0.7),
    );

    // Embossed crown.
    final cw = s * 0.46;
    final ch = s * 0.3;
    final left = center.dx - cw / 2;
    final top = center.dy - ch / 2 + s * 0.02;
    final crown = Path()
      ..moveTo(left, top + ch)
      ..lineTo(left, top + ch * 0.3)
      ..lineTo(left + cw * 0.27, top + ch * 0.62)
      ..lineTo(left + cw * 0.5, top)
      ..lineTo(left + cw * 0.73, top + ch * 0.62)
      ..lineTo(left + cw, top + ch * 0.3)
      ..lineTo(left + cw, top + ch)
      ..close();
    canvas.drawPath(
      crown.shift(Offset(0, s * 0.025)),
      Paint()..color = BrandPalette.gold800.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      crown,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BrandPalette.gold100, BrandPalette.gold400],
        ).createShader(Rect.fromLTWH(left, top, cw, ch)),
    );

    // Specular highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-r * 0.32, -r * 0.42),
        width: r * 0.62,
        height: r * 0.3,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(CoinPainter oldDelegate) => false;
}

/// Diamond artwork, reusable by other painters.
class DiamondPainter extends CustomPainter {
  const DiamondPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final dx = (size.width - s) / 2;
    final dy = (size.height - s) / 2;
    Offset p(double x, double y) => Offset(dx + x * s, dy + y * s);

    final tl = p(0.30, 0.14);
    final tr = p(0.70, 0.14);
    final gl = p(0.04, 0.38);
    final gr = p(0.96, 0.38);
    final bottom = p(0.5, 0.94);
    final tm = p(0.5, 0.14);
    final gm1 = p(0.30, 0.38);
    final gm2 = p(0.70, 0.38);

    // Shadow.
    final outline = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(gr.dx, gr.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(gl.dx, gl.dy)
      ..close();
    canvas.drawPath(
      outline.shift(Offset(0, s * 0.04)),
      Paint()..color = const Color(0xFF16507E).withValues(alpha: 0.45),
    );

    void facet(List<Offset> pts, Color color) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    // Crown facets.
    facet([tl, tm, gm1], const Color(0xFFB8F4FF));
    facet([tm, tr, gm2], const Color(0xFF7FE3F7));
    facet([tm, gm1, gm2], const Color(0xFFD9FAFF));
    facet([tl, gm1, gl], const Color(0xFF8BE6F8));
    facet([tr, gr, gm2], const Color(0xFF4FC8EA));
    // Pavilion facets.
    facet([gl, gm1, bottom], const Color(0xFF3FB6E6));
    facet([gm1, gm2, bottom], const Color(0xFF5DD3F2));
    facet([gm2, gr, bottom], const Color(0xFF2B8FD6));

    // Edge stroke.
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s * 0.03
        ..color = const Color(0xFF1C6FB0).withValues(alpha: 0.55),
    );
    // Sparkle.
    final c = p(0.36, 0.25);
    final spark = Path()
      ..moveTo(c.dx, c.dy - s * 0.08)
      ..lineTo(c.dx + s * 0.02, c.dy - s * 0.02)
      ..lineTo(c.dx + s * 0.08, c.dy)
      ..lineTo(c.dx + s * 0.02, c.dy + s * 0.02)
      ..lineTo(c.dx, c.dy + s * 0.08)
      ..lineTo(c.dx - s * 0.02, c.dy + s * 0.02)
      ..lineTo(c.dx - s * 0.08, c.dy)
      ..lineTo(c.dx - s * 0.02, c.dy - s * 0.02)
      ..close();
    canvas.drawPath(
      spark,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(DiamondPainter oldDelegate) => false;
}
