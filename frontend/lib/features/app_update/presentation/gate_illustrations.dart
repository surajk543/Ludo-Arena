import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Which gate illustration to paint.
enum GateArt { update, maintenance, unreachable, notFound }

/// Vector illustrations for the gate screens (no raster/emoji art).
class GateIllustration extends StatelessWidget {
  const GateIllustration({super.key, required this.art, this.size = 168});

  final GateArt art;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _GatePainter(art: art, colors: c),
        ),
      ),
    );
  }
}

class _GatePainter extends CustomPainter {
  _GatePainter({required this.art, required this.colors});

  final GateArt art;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    _halo(canvas, center, s);
    switch (art) {
      case GateArt.update:
        _paintUpdate(canvas, s);
      case GateArt.maintenance:
        _paintMaintenance(canvas, s);
      case GateArt.unreachable:
        _paintUnreachable(canvas, s);
      case GateArt.notFound:
        _paintNotFound(canvas, s);
    }
  }

  void _halo(Canvas canvas, Offset c, double s) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          colors.gold.withValues(alpha: colors.isDark ? 0.28 : 0.32),
          colors.brand.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: c, radius: s * 0.5));
    canvas.drawCircle(c, s * 0.5, glow);
    final disc = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.surfaceRaised, colors.brandSoft],
      ).createShader(Rect.fromCircle(center: c, radius: s * 0.36));
    canvas.drawCircle(c, s * 0.36, disc);
    canvas.drawCircle(
      c,
      s * 0.36,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012
        ..color = colors.gold.withValues(alpha: 0.65),
    );
  }

  Paint _fill(Color a, Color b, Rect r) => Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [a, b],
    ).createShader(r);

  // Phone with a golden upward arrow and a tiny crown.
  void _paintUpdate(Canvas canvas, double s) {
    final phone = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(s * 0.5, s * 0.53),
        width: s * 0.34,
        height: s * 0.52,
      ),
      Radius.circular(s * 0.06),
    );
    canvas.drawRRect(
      phone.shift(Offset(0, s * 0.015)),
      Paint()..color = colors.shadowColor.withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      phone,
      _fill(BrandPalette.royal500, BrandPalette.royal700, phone.outerRect),
    );
    final screen = phone.deflate(s * 0.022);
    canvas.drawRRect(
      screen,
      _fill(BrandPalette.royal300, BrandPalette.royal500, screen.outerRect),
    );
    // Arrow
    final ax = s * 0.5;
    final arrow = Path()
      ..moveTo(ax, s * 0.36)
      ..lineTo(ax + s * 0.09, s * 0.47)
      ..lineTo(ax + s * 0.035, s * 0.47)
      ..lineTo(ax + s * 0.035, s * 0.62)
      ..lineTo(ax - s * 0.035, s * 0.62)
      ..lineTo(ax - s * 0.035, s * 0.47)
      ..lineTo(ax - s * 0.09, s * 0.47)
      ..close();
    canvas.drawPath(
      arrow,
      _fill(BrandPalette.gold300, BrandPalette.gold600, arrow.getBounds()),
    );
    // Progress bar
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.4, s * 0.67, s * 0.2, s * 0.025),
      Radius.circular(s * 0.02),
    );
    canvas.drawRRect(
      bar,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.4, s * 0.67, s * 0.13, s * 0.025),
        Radius.circular(s * 0.02),
      ),
      Paint()..color = BrandPalette.gold400,
    );
    _crown(canvas, Offset(s * 0.5, s * 0.22), s * 0.16);
    _sparkle(canvas, Offset(s * 0.76, s * 0.32), s * 0.035);
    _sparkle(canvas, Offset(s * 0.25, s * 0.7), s * 0.028);
  }

  // A Ludo board corner with a gear and a wrench.
  void _paintMaintenance(Canvas canvas, double s) {
    final board = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(s * 0.46, s * 0.55),
        width: s * 0.42,
        height: s * 0.42,
      ),
      Radius.circular(s * 0.05),
    );
    canvas.drawRRect(
      board,
      _fill(colors.surfaceRaised, colors.surfaceSunken, board.outerRect),
    );
    final q = s * 0.21;
    final seats = [
      colors.seats.red,
      colors.seats.green,
      colors.seats.blue,
      colors.seats.yellow,
    ];
    for (var i = 0; i < 4; i++) {
      final dx = (i % 2) * q;
      final dy = (i ~/ 2) * q;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          board.left + dx + s * 0.012,
          board.top + dy + s * 0.012,
          q - s * 0.024,
          q - s * 0.024,
        ),
        Radius.circular(s * 0.03),
      );
      canvas.drawRRect(r, Paint()..color = seats[i].withValues(alpha: 0.85));
      canvas.drawCircle(
        r.center,
        q * 0.2,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }
    // Gear
    final gc = Offset(s * 0.68, s * 0.36);
    final gr = s * 0.12;
    final gear = Path();
    const teeth = 8;
    for (var i = 0; i < teeth * 2; i++) {
      final a = i * math.pi / teeth;
      final r = i.isEven ? gr : gr * 0.78;
      final p = gc + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? gear.moveTo(p.dx, p.dy) : gear.lineTo(p.dx, p.dy);
    }
    gear.close();
    canvas.drawPath(
      gear,
      _fill(BrandPalette.gold300, BrandPalette.gold600, gear.getBounds()),
    );
    canvas.drawCircle(gc, gr * 0.38, Paint()..color = colors.surfaceRaised);
    // Wrench
    canvas.save();
    canvas.translate(s * 0.34, s * 0.76);
    canvas.rotate(-math.pi / 4);
    final handle = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: s * 0.3, height: s * 0.05),
      Radius.circular(s * 0.025),
    );
    canvas.drawRRect(
      handle,
      _fill(BrandPalette.royal400, BrandPalette.royal600, handle.outerRect),
    );
    final head = Offset(s * 0.15, 0);
    canvas.drawCircle(head, s * 0.05, Paint()..color = BrandPalette.royal500);
    canvas.drawCircle(
      head + Offset(s * 0.02, 0),
      s * 0.022,
      Paint()..color = colors.surfaceRaised,
    );
    canvas.restore();
    _sparkle(canvas, Offset(s * 0.22, s * 0.3), s * 0.03);
  }

  // A cloud with a broken signal arc.
  void _paintUnreachable(Canvas canvas, double s) {
    final cloud = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(s * 0.4, s * 0.52), radius: s * 0.11),
      )
      ..addOval(
        Rect.fromCircle(center: Offset(s * 0.54, s * 0.46), radius: s * 0.14),
      )
      ..addOval(
        Rect.fromCircle(center: Offset(s * 0.66, s * 0.55), radius: s * 0.095),
      )
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.3, s * 0.52, s * 0.45, s * 0.12),
          Radius.circular(s * 0.06),
        ),
      );
    canvas.drawPath(
      cloud.shift(Offset(0, s * 0.012)),
      Paint()..color = colors.shadowColor.withValues(alpha: 0.15),
    );
    canvas.drawPath(
      cloud,
      _fill(BrandPalette.royal300, BrandPalette.royal500, cloud.getBounds()),
    );
    // Signal arcs, the outer one broken.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.03
      ..color = colors.gold;
    final o = Offset(s * 0.53, s * 0.8);
    canvas.drawCircle(o, s * 0.025, Paint()..color = colors.gold);
    canvas.drawArc(
      Rect.fromCircle(center: o, radius: s * 0.08),
      -math.pi * 0.8,
      math.pi * 0.6,
      false,
      stroke,
    );
    stroke.color = colors.gold.withValues(alpha: 0.45);
    canvas.drawArc(
      Rect.fromCircle(center: o, radius: s * 0.14),
      -math.pi * 0.82,
      math.pi * 0.22,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: o, radius: s * 0.14),
      -math.pi * 0.4,
      math.pi * 0.2,
      false,
      stroke,
    );
    // Small "x" on the cloud.
    final x = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.025
      ..color = Colors.white;
    final xc = Offset(s * 0.53, s * 0.53);
    final d = s * 0.04;
    canvas.drawLine(xc + Offset(-d, -d), xc + Offset(d, d), x);
    canvas.drawLine(xc + Offset(d, -d), xc + Offset(-d, d), x);
  }

  // A die showing a question-mark-free "blank" face with a compass star.
  void _paintNotFound(Canvas canvas, double s) {
    final die = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(s * 0.5, s * 0.52),
        width: s * 0.36,
        height: s * 0.36,
      ),
      Radius.circular(s * 0.07),
    );
    canvas.drawRRect(
      die.shift(Offset(0, s * 0.015)),
      Paint()..color = colors.shadowColor.withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      die,
      _fill(Colors.white, const Color(0xFFEDE6FF), die.outerRect),
    );
    final pip = Paint()..color = BrandPalette.royal500;
    for (final p in const [
      Offset(0.42, 0.44),
      Offset(0.58, 0.6),
      Offset(0.5, 0.52),
    ]) {
      canvas.drawCircle(Offset(s * p.dx, s * p.dy), s * 0.028, pip);
    }
    _sparkle(canvas, Offset(s * 0.74, s * 0.3), s * 0.04);
    _sparkle(canvas, Offset(s * 0.27, s * 0.72), s * 0.03);
    _crown(canvas, Offset(s * 0.5, s * 0.26), s * 0.12);
  }

  void _crown(Canvas canvas, Offset c, double w) {
    final h = w * 0.62;
    final path = Path()
      ..moveTo(c.dx - w / 2, c.dy + h / 2)
      ..lineTo(c.dx - w / 2, c.dy - h * 0.15)
      ..lineTo(c.dx - w / 4, c.dy + h * 0.1)
      ..lineTo(c.dx, c.dy - h / 2)
      ..lineTo(c.dx + w / 4, c.dy + h * 0.1)
      ..lineTo(c.dx + w / 2, c.dy - h * 0.15)
      ..lineTo(c.dx + w / 2, c.dy + h / 2)
      ..close();
    canvas.drawPath(
      path,
      _fill(BrandPalette.gold300, BrandPalette.gold600, path.getBounds()),
    );
    canvas.drawCircle(
      Offset(c.dx, c.dy + h * 0.2),
      w * 0.07,
      Paint()..color = BrandPalette.royal500,
    );
  }

  void _sparkle(Canvas canvas, Offset c, double r) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = colors.gold);
  }

  @override
  bool shouldRepaint(_GatePainter old) =>
      old.art != art || old.colors != colors;
}
