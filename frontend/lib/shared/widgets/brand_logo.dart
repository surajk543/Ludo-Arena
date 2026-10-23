import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Painted brand emblem: a Ludo board in a gold arena ring with a die.
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

/// Emblem artwork (also used by splash/gate illustrations and, through
/// `tool/generate_brand_assets.dart`, the native app icons and launch
/// screens): a Ludo board (four seat-colored homes and the cross track) in a
/// gold arena ring, with a die in the middle. The box is `width x width *
/// 1.08` (the launch screens are laid out for it); the round emblem is
/// centered in it.
///
/// [monochrome] paints a single-color silhouette (ring, cross track and the
/// die with pip cut-outs) in [monochromeColor]; it is the source of the
/// Android 13+ themed icon. [shadow] false omits the drop shadows (for
/// artwork the system clips to a circle, like the Android 12+ splash icon).
class BrandCrestPainter extends CustomPainter {
  const BrandCrestPainter({
    this.dark = false,
    this.monochrome = false,
    this.monochromeColor = Colors.white,
    this.shadow = true,
  });

  final bool dark;
  final bool monochrome;
  final Color monochromeColor;
  final bool shadow;

  /// Seat colors of the four homes, clockwise from the top-left.
  static const List<Color> seatColors = [
    Color(0xFFE5484D),
    Color(0xFF30A46C),
    Color(0xFFF5B800),
    Color(0xFF3E63DD),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (monochrome) {
      _paintMonochrome(canvas, size);
      return;
    }
    final w = size.width;
    final c = _center(size);
    final rb = _boardRadius(size);
    final board = Rect.fromCircle(center: c, radius: rb);
    final rr = _ringRadius(size);
    final rw = _ringWidth(size);

    if (shadow) {
      canvas.drawShadow(
        Path()..addOval(Rect.fromCircle(center: c, radius: _outerRadius(size))),
        Colors.black,
        w * 0.05,
        false,
      );
    }

    // Board: the four homes, lit from the center.
    canvas.save();
    canvas.clipPath(Path()..addOval(board));
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(
        board,
        math.pi + i * math.pi / 2,
        math.pi / 2,
        true,
        Paint()..color = seatColors[i],
      );
    }
    canvas.drawRect(
      board,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.18),
          ],
        ).createShader(board),
    );

    // Cross track, three cells wide.
    final arm = _armWidth(size);
    final cell = arm / 3;
    final track = Paint()..color = BrandPalette.royal50;
    canvas.drawRect(
      Rect.fromCenter(center: c, width: arm, height: rb * 2),
      track,
    );
    canvas.drawRect(
      Rect.fromCenter(center: c, width: rb * 2, height: arm),
      track,
    );
    final line = Paint()
      ..color = BrandPalette.royal200
      ..strokeWidth = w * 0.007;
    for (final k in const [-0.5, 0.5]) {
      canvas.drawLine(
        c.translate(k * cell, -rb),
        c.translate(k * cell, rb),
        line,
      );
      canvas.drawLine(
        c.translate(-rb, k * cell),
        c.translate(rb, k * cell),
        line,
      );
    }
    for (var t = arm / 2 + cell; t < rb; t += cell) {
      for (final sgn in const [-1.0, 1.0]) {
        canvas.drawLine(
          c.translate(-arm / 2, sgn * t),
          c.translate(arm / 2, sgn * t),
          line,
        );
        canvas.drawLine(
          c.translate(sgn * t, -arm / 2),
          c.translate(sgn * t, arm / 2),
          line,
        );
      }
    }
    // Home columns: each seat's three cells leading to the center.
    const homeColumns = [
      (Offset(-1, 0), 0),
      (Offset(0, -1), 1),
      (Offset(1, 0), 2),
      (Offset(0, 1), 3),
    ];
    for (final (dir, seat) in homeColumns) {
      for (var n = 1; n <= 3; n++) {
        canvas.drawRect(
          Rect.fromCenter(
            center: c + dir * (arm / 2 + cell * (n - 0.5)),
            width: cell * 0.86,
            height: cell * 0.86,
          ),
          Paint()..color = seatColors[seat],
        );
      }
    }
    canvas.restore();

    // Gold arena ring.
    if (shadow) {
      canvas.drawCircle(
        c.translate(0, rw * 0.35),
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rw
          ..color = BrandPalette.royal950.withValues(alpha: 0.45),
      );
    }
    canvas.drawCircle(
      c,
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rw
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BrandPalette.gold300,
            BrandPalette.gold500,
            BrandPalette.gold600,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: rr + rw / 2)),
    );
    canvas.drawCircle(
      c,
      rr - rw * 0.28,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rw * 0.12
        ..color = BrandPalette.gold100.withValues(alpha: 0.55),
    );

    // Die.
    final d = _dieSize(size);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_dieRotation);
    final die = _dieRect(size);
    canvas.drawRRect(
      die.shift(Offset(0, d * 0.07)),
      Paint()..color = BrandPalette.royal950.withValues(alpha: 0.5),
    );
    canvas.drawRRect(
      die,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFE9E3FF)],
        ).createShader(die.outerRect),
    );
    final pip = Paint()..color = BrandPalette.royal700;
    for (final o in _pipOffsets(size)) {
      canvas.drawCircle(o, _pipRadius(size), pip);
    }
    canvas.restore();
  }

  /// Single-color silhouette: the ring, the cross track and the die (set off
  /// from the track by a cut-out outline) with pip cut-outs. No shadows or
  /// gradients.
  void _paintMonochrome(Canvas canvas, Size size) {
    final w = size.width;
    final c = _center(size);
    final rb = _boardRadius(size);
    final fill = Paint()..color = monochromeColor;
    final clear = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(Offset.zero & size, Paint());

    canvas.drawCircle(
      c,
      _ringRadius(size),
      Paint()
        ..color = monochromeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringWidth(size),
    );

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: c, radius: rb)),
    );
    final arm = _armWidth(size);
    canvas.drawRect(
      Rect.fromCenter(center: c, width: arm, height: rb * 2),
      fill,
    );
    canvas.drawRect(
      Rect.fromCenter(center: c, width: rb * 2, height: arm),
      fill,
    );
    canvas.restore();

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_dieRotation);
    final die = _dieRect(size);
    canvas.drawRRect(die.inflate(w * 0.03), clear);
    canvas.drawRRect(die, fill);
    for (final o in _pipOffsets(size)) {
      canvas.drawCircle(o, _pipRadius(size), clear);
    }
    canvas.restore();
    canvas.restore();
  }

  // ---- Geometry (shared by the color and monochrome renderings) ----

  static const double _dieRotation = -0.16;

  static Offset _center(Size s) => s.center(Offset.zero);

  /// Outer edge of the ring; the margin to the box leaves room for the
  /// drop shadow.
  static double _outerRadius(Size s) => s.width * 0.48;

  static double _ringWidth(Size s) => _outerRadius(s) * 0.124;

  static double _ringRadius(Size s) => _outerRadius(s) - _ringWidth(s) / 2;

  /// Slightly larger than the ring's inner edge, so no gap shows.
  static double _boardRadius(Size s) => _outerRadius(s) * 0.883;

  static double _armWidth(Size s) => _outerRadius(s) * 0.423;

  static double _dieSize(Size s) => _outerRadius(s) * 0.6;

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

  @override
  bool shouldRepaint(BrandCrestPainter old) =>
      old.dark != dark ||
      old.monochrome != monochrome ||
      old.monochromeColor != monochromeColor ||
      old.shadow != shadow;
}
