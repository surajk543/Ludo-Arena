import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'cosmetic_names.dart';

/// Emote ids from the cosmetics catalog.
const List<String> kEmoteIds = [
  'emote_wave',
  'emote_thumbs',
  'emote_laugh',
  'emote_wow',
  'emote_crown',
];

/// Badge ids from the cosmetics catalog.
const List<String> kBadgeIds = ['badge_first_win', 'badge_friendly'];

/// Painted emote glyph (used in the in-game emote picker and chat bubbles).
class EmoteIcon extends StatelessWidget {
  const EmoteIcon({super.key, required this.emoteId, this.size = 40});

  final String emoteId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      image: true,
      label: l10n.widgetsEmoteLabel(cosmeticName(l10n, emoteId)),
      excludeSemantics: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: EmotePainter(emoteId),
      ),
    );
  }
}

/// Painted achievement badge.
class BadgeIcon extends StatelessWidget {
  const BadgeIcon({super.key, required this.badgeId, this.size = 48});

  final String badgeId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      image: true,
      label: l10n.widgetsBadgeLabel(cosmeticName(l10n, badgeId)),
      excludeSemantics: true,
      child: CustomPaint(
        size: Size(size, size * 1.15),
        painter: BadgePainter(badgeId),
      ),
    );
  }
}

const _faceYellow = Color(0xFFFFCF4A);
const _faceShade = Color(0xFFF2A922);
const _ink = Color(0xFF3A2414);
const _skin = Color(0xFFFFC98A);
const _skinShade = Color(0xFFE59E58);

/// Emote artwork.
class EmotePainter extends CustomPainter {
  const EmotePainter(this.emoteId);

  final String emoteId;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    switch (emoteId) {
      case 'emote_wave':
        _wave(canvas, s);
      case 'emote_thumbs':
        _thumbs(canvas, s);
      case 'emote_laugh':
        _laugh(canvas, s);
      case 'emote_wow':
        _wow(canvas, s);
      case 'emote_crown':
        _crown(canvas, s);
      default:
        _bubble(canvas, s);
    }
    canvas.restore();
  }

  void _face(Canvas canvas, double s) {
    final c = Offset(s / 2, s / 2);
    canvas.drawCircle(
      c.translate(0, s * 0.03),
      s * 0.44,
      Paint()..color = _faceShade.withValues(alpha: 0.6),
    );
    canvas.drawCircle(
      c,
      s * 0.44,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFFFFE58A), _faceYellow, _faceShade],
          stops: [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: s * 0.44)),
    );
  }

  void _laugh(Canvas canvas, double s) {
    _face(canvas, s);
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.05;
    // Squeezed eyes ^ ^
    for (final x in [0.34, 0.66]) {
      final p = Path()
        ..moveTo(s * (x - 0.08), s * 0.4)
        ..lineTo(s * x, s * 0.33)
        ..lineTo(s * (x + 0.08), s * 0.4);
      canvas.drawPath(p, stroke);
    }
    // Big open mouth.
    final mouth = Path()
      ..moveTo(s * 0.26, s * 0.52)
      ..quadraticBezierTo(s * 0.5, s * 0.56, s * 0.74, s * 0.52)
      ..quadraticBezierTo(s * 0.7, s * 0.82, s * 0.5, s * 0.82)
      ..quadraticBezierTo(s * 0.3, s * 0.82, s * 0.26, s * 0.52)
      ..close();
    canvas.drawPath(mouth, Paint()..color = const Color(0xFF7A2E3A));
    canvas.save();
    canvas.clipPath(mouth);
    canvas.drawCircle(
      Offset(s * 0.5, s * 0.86),
      s * 0.14,
      Paint()..color = const Color(0xFFFF7A8A),
    );
    canvas.drawRect(
      Rect.fromLTWH(s * 0.26, s * 0.5, s * 0.48, s * 0.07),
      Paint()..color = Colors.white,
    );
    canvas.restore();
    // Tears of joy.
    final tear = Paint()..color = const Color(0xFF6EC8FF);
    for (final side in [-1.0, 1.0]) {
      final base = Offset(s * (0.5 + side * 0.3), s * 0.46);
      final p = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(
          base.dx + side * s * 0.12,
          base.dy + s * 0.08,
          base.dx + side * s * 0.06,
          base.dy + s * 0.16,
        )
        ..quadraticBezierTo(
          base.dx - side * s * 0.02,
          base.dy + s * 0.12,
          base.dx,
          base.dy,
        )
        ..close();
      canvas.drawPath(p, tear);
    }
  }

  void _wow(Canvas canvas, double s) {
    _face(canvas, s);
    for (final x in [0.35, 0.65]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(s * x, s * 0.4),
          width: s * 0.12,
          height: s * 0.16,
        ),
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(s * x, s * 0.41),
        s * 0.04,
        Paint()..color = _ink,
      );
    }
    final brow = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.035;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(s * 0.35, s * 0.27),
        width: s * 0.14,
        height: s * 0.08,
      ),
      math.pi * 1.15,
      math.pi * 0.7,
      false,
      brow,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(s * 0.65, s * 0.27),
        width: s * 0.14,
        height: s * 0.08,
      ),
      math.pi * 1.15,
      math.pi * 0.7,
      false,
      brow,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.5, s * 0.67),
        width: s * 0.16,
        height: s * 0.2,
      ),
      Paint()..color = const Color(0xFF7A2E3A),
    );
    // Sparkles.
    _sparkle(
      canvas,
      Offset(s * 0.86, s * 0.14),
      s * 0.08,
      BrandPalette.gold400,
    );
    _sparkle(canvas, Offset(s * 0.12, s * 0.2), s * 0.06, BrandPalette.gold400);
  }

  void _wave(Canvas canvas, double s) {
    // Motion arcs.
    final arc = Paint()
      ..color = BrandPalette.royal300
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.045;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s * 0.5, s * 0.52), radius: s * 0.44),
      -math.pi * 0.42,
      math.pi * 0.22,
      false,
      arc,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s * 0.5, s * 0.52), radius: s * 0.44),
      -math.pi * 0.8,
      math.pi * 0.18,
      false,
      arc,
    );

    canvas.save();
    canvas.translate(s * 0.5, s * 0.6);
    canvas.rotate(-0.28);
    final skin = Paint()..color = _skin;
    final shade = Paint()..color = _skinShade;
    // Fingers.
    const fingers = [
      [-0.17, -0.38, 0.27],
      [-0.06, -0.44, 0.32],
      [0.05, -0.42, 0.31],
      [0.15, -0.34, 0.25],
    ];
    for (final f in fingers) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(s * (f[0] - 0.045), s * f[1], s * 0.09, s * f[2]),
        Radius.circular(s * 0.045),
      );
      canvas.drawRRect(r.shift(Offset(s * 0.01, s * 0.01)), shade);
      canvas.drawRRect(r, skin);
    }
    // Thumb.
    canvas.save();
    canvas.translate(-s * 0.2, s * 0.02);
    canvas.rotate(-0.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-s * 0.045, -s * 0.2, s * 0.09, s * 0.22),
        Radius.circular(s * 0.045),
      ),
      skin,
    );
    canvas.restore();
    // Palm.
    final palm = RRect.fromRectAndRadius(
      Rect.fromLTWH(-s * 0.22, -s * 0.16, s * 0.42, s * 0.36),
      Radius.circular(s * 0.14),
    );
    canvas.drawRRect(palm.shift(Offset(0, s * 0.015)), shade);
    canvas.drawRRect(palm, skin);
    // Cuff.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-s * 0.16, s * 0.18, s * 0.3, s * 0.12),
        Radius.circular(s * 0.04),
      ),
      Paint()..color = BrandPalette.royal500,
    );
    canvas.restore();
  }

  void _thumbs(Canvas canvas, double s) {
    final skin = Paint()..color = _skin;
    final shade = Paint()..color = _skinShade;
    // Thumb.
    final thumb = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.3, s * 0.1, s * 0.17, s * 0.42),
      Radius.circular(s * 0.085),
    );
    canvas.drawRRect(thumb.shift(Offset(s * 0.012, s * 0.012)), shade);
    canvas.drawRRect(thumb, skin);
    // Fist.
    final fist = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.26, s * 0.4, s * 0.48, s * 0.42),
      Radius.circular(s * 0.12),
    );
    canvas.drawRRect(fist.shift(Offset(0, s * 0.02)), shade);
    canvas.drawRRect(fist, skin);
    // Finger creases.
    final crease = Paint()
      ..color = _skinShade
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.03;
    for (var i = 1; i <= 3; i++) {
      final y = s * (0.4 + i * 0.1);
      canvas.drawLine(Offset(s * 0.5, y), Offset(s * 0.72, y), crease);
    }
    // Cuff.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.14, s * 0.44, s * 0.14, s * 0.4),
        Radius.circular(s * 0.04),
      ),
      Paint()..color = BrandPalette.royal500,
    );
    _sparkle(canvas, Offset(s * 0.82, s * 0.2), s * 0.08, BrandPalette.gold400);
  }

  void _crown(Canvas canvas, double s) {
    final left = s * 0.1;
    final top = s * 0.2;
    final w = s * 0.8;
    final h = s * 0.6;
    final p = Path()
      ..moveTo(left + w * 0.06, top + h)
      ..lineTo(left, top + h * 0.22)
      ..lineTo(left + w * 0.28, top + h * 0.52)
      ..lineTo(left + w * 0.5, top)
      ..lineTo(left + w * 0.72, top + h * 0.52)
      ..lineTo(left + w, top + h * 0.22)
      ..lineTo(left + w * 0.94, top + h)
      ..close();
    canvas.drawPath(
      p.shift(Offset(0, s * 0.03)),
      Paint()..color = BrandPalette.gold800.withValues(alpha: 0.5),
    );
    canvas.drawPath(
      p,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BrandPalette.gold300,
            BrandPalette.gold500,
            BrandPalette.gold600,
          ],
        ).createShader(Rect.fromLTWH(left, top, w, h)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + w * 0.06, top + h * 0.78, w * 0.88, h * 0.2),
        Radius.circular(s * 0.03),
      ),
      Paint()..color = BrandPalette.gold700,
    );
    const gems = [Color(0xFFE5484D), Color(0xFF3E63DD), Color(0xFF30A46C)];
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(left + w * (0.25 + i * 0.25), top + h * 0.88),
        s * 0.04,
        Paint()..color = gems[i],
      );
    }
    for (final t in [
      Offset(left, top + h * 0.22),
      Offset(left + w * 0.5, top),
      Offset(left + w, top + h * 0.22),
    ]) {
      canvas.drawCircle(t, s * 0.05, Paint()..color = BrandPalette.gold300);
    }
    _sparkle(canvas, Offset(s * 0.85, s * 0.12), s * 0.07, Colors.white);
  }

  void _bubble(Canvas canvas, double s) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.1, s * 0.14, s * 0.8, s * 0.56),
      Radius.circular(s * 0.2),
    );
    final tail = Path()
      ..moveTo(s * 0.3, s * 0.66)
      ..lineTo(s * 0.24, s * 0.86)
      ..lineTo(s * 0.46, s * 0.68)
      ..close();
    final paint = Paint()..color = BrandPalette.royal400;
    canvas.drawRRect(r, paint);
    canvas.drawPath(tail, paint);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(s * (0.33 + i * 0.17), s * 0.42),
        s * 0.05,
        Paint()..color = Colors.white,
      );
    }
  }

  static void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(EmotePainter old) => old.emoteId != emoteId;
}

/// Badge artwork: ribbon + medal disc with an emblem.
class BadgePainter extends CustomPainter {
  const BadgePainter(this.badgeId);

  final String badgeId;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final (List<Color> ribbon, List<Color> disc) = switch (badgeId) {
      'badge_first_win' => (
        const [BrandPalette.royal500, Color(0xFFE5484D)],
        const [
          BrandPalette.gold300,
          BrandPalette.gold500,
          BrandPalette.gold700,
        ],
      ),
      'badge_friendly' => (
        const [Color(0xFF26B5A0), Color(0xFF3E63DD)],
        const [Color(0xFFFFD6C9), Color(0xFFF0A08A), Color(0xFFC0654F)],
      ),
      _ => (
        const [BrandPalette.royal400, BrandPalette.royal600],
        const [Color(0xFFE8ECF4), Color(0xFFB6C0D0), Color(0xFF7E8A9E)],
      ),
    };

    // Ribbons.
    final left = Path()
      ..moveTo(w * 0.3, 0)
      ..lineTo(w * 0.48, 0)
      ..lineTo(w * 0.5, h * 0.42)
      ..lineTo(w * 0.36, h * 0.46)
      ..close();
    final right = Path()
      ..moveTo(w * 0.52, 0)
      ..lineTo(w * 0.7, 0)
      ..lineTo(w * 0.64, h * 0.46)
      ..lineTo(w * 0.5, h * 0.42)
      ..close();
    canvas.drawPath(left, Paint()..color = ribbon[0]);
    canvas.drawPath(right, Paint()..color = ribbon[1]);

    // Disc.
    final c = Offset(w / 2, h * 0.62);
    final r = math.min(w, h) * 0.36;
    canvas.drawCircle(
      c.translate(0, r * 0.08),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: disc,
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    switch (badgeId) {
      case 'badge_first_win':
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final rr = i.isEven ? r * 0.56 : r * 0.24;
          final ang = -math.pi / 2 + i * math.pi / 5;
          final pt = Offset(
            c.dx + math.cos(ang) * rr,
            c.dy + math.sin(ang) * rr,
          );
          i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
        }
        star.close();
        canvas.drawPath(star, Paint()..color = Colors.white);
        canvas.drawPath(
          star,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.05
            ..color = BrandPalette.gold700,
        );
      case 'badge_friendly':
        _heart(
          canvas,
          c.translate(-r * 0.2, -r * 0.05),
          r * 0.36,
          const Color(0xFFE5484D),
        );
        _heart(
          canvas,
          c.translate(r * 0.2, r * 0.08),
          r * 0.36,
          const Color(0xFFFF7AA8),
        );
      default:
        canvas.drawCircle(
          c,
          r * 0.28,
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
    }
    // Highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: c.translate(-r * 0.35, -r * 0.45),
        width: r * 0.6,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  static void _heart(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy + r * 0.9)
      ..cubicTo(
        c.dx - r * 1.4,
        c.dy,
        c.dx - r * 0.8,
        c.dy - r * 1.1,
        c.dx,
        c.dy - r * 0.4,
      )
      ..cubicTo(
        c.dx + r * 0.8,
        c.dy - r * 1.1,
        c.dx + r * 1.4,
        c.dy,
        c.dx,
        c.dy + r * 0.9,
      )
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(BadgePainter old) => old.badgeId != badgeId;
}
