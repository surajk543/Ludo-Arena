import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Number of built-in avatars (`User.avatar` / `players[].avatar` index).
const int kAvatarCount = 12;

/// Avatar frame ids from the cosmetics catalog.
const List<String> kAvatarFrameIds = [
  'frame_none',
  'frame_bronze',
  'frame_silver',
  'frame_gold',
  'frame_royal',
];

/// A player's portrait: one of 12 painted characters, an optional seat-color
/// ring, the equipped frame, and a BOT badge for server-flagged bots.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.avatarIndex,
    this.frameId = 'frame_none',
    this.size = 56,
    this.isBot = false,
    this.seatColor,
    this.dimmed = false,
    this.semanticLabel,
  });

  /// 0–11 (wraps).
  final int avatarIndex;

  /// `frame_none|frame_bronze|frame_silver|frame_gold|frame_royal`.
  final String frameId;
  final double size;

  /// From the server room snapshot (`players[].bot`). Shows a BOT badge.
  final bool isBot;
  final SeatColor? seatColor;

  /// Desaturated look (disconnected / forfeited players).
  final bool dimmed;
  final String? semanticLabel;

  /// Fraction of [size] used by the portrait circle for a frame.
  static double portraitFraction(String frameId) => switch (frameId) {
    'frame_royal' => 0.70,
    'frame_gold' || 'frame_silver' => 0.72,
    'frame_bronze' => 0.80,
    _ => 0.90,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final frame = kAvatarFrameIds.contains(frameId) ? frameId : 'frame_none';
    final portrait = size * portraitFraction(frame);
    final seat = seatColor == null ? null : c.seats.of(seatColor!);
    final index = avatarIndex % kAvatarCount;

    Widget art = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Portrait (offset slightly down for the royal crown).
        Positioned(
          left: (size - portrait) / 2,
          top:
              (size - portrait) / 2 +
              (frame == 'frame_royal' ? size * 0.04 : 0),
          width: portrait,
          height: portrait,
          child: ClipOval(child: CustomPaint(painter: AvatarPainter(index))),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: AvatarFramePainter(
              frameId: frame,
              portraitFraction: portraitFraction(frame),
              seatColor: seat,
              plainRing: c.isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : c.outline,
              royalOffset: frame == 'frame_royal' ? 0.04 : 0,
            ),
          ),
        ),
      ],
    );

    if (dimmed) {
      art = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.33, 0.59, 0.11, 0, 0, //
          0.33, 0.59, 0.11, 0, 0, //
          0.33, 0.59, 0.11, 0, 0, //
          0, 0, 0, 0.6, 0,
        ]),
        child: art,
      );
    }

    final label = [
      semanticLabel ?? l10n.widgetsAvatarLabel,
      if (isBot) l10n.commonBotPlayerLabel,
    ].join(', ');

    return Semantics(
      image: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: art),
            if (isBot)
              PositionedDirectional(
                bottom: -size * 0.05,
                start: -size * 0.1,
                end: -size * 0.1,
                child: Center(
                  child: BotBadge(
                    height: (size * 0.28).clamp(16.0, 24.0),
                    showLabel: size >= 36,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small "BOT" pill with a painted robot glyph.
class BotBadge extends StatelessWidget {
  const BotBadge({super.key, this.height = 18, this.showLabel = true});

  final double height;

  /// Text label next to the robot glyph (glyph only on tiny avatars).
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final showText = showLabel;
    return Container(
      height: height,
      padding: EdgeInsetsDirectional.symmetric(horizontal: height * 0.28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [BrandPalette.royal600, BrandPalette.royal800],
        ),
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: c.surface, width: 1.4),
        boxShadow: c.shadow(AppElevation.low),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size.square(height * 0.62),
            painter: const RobotGlyphPainter(),
          ),
          if (showText) ...[
            SizedBox(width: height * 0.18),
            Text(
              l10n.commonBotBadge,
              maxLines: 1,
              style: context.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontSize: height * 0.56,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Robot head glyph.
class RobotGlyphPainter extends CustomPainter {
  const RobotGlyphPainter({this.color = Colors.white});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final p = Paint()..color = color;
    final head = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.1, s * 0.3, s * 0.8, s * 0.62),
      Radius.circular(s * 0.18),
    );
    canvas.drawRRect(head, p);
    canvas.drawLine(
      Offset(s * 0.5, s * 0.3),
      Offset(s * 0.5, s * 0.1),
      p..strokeWidth = s * 0.1,
    );
    canvas.drawCircle(Offset(s * 0.5, s * 0.08), s * 0.09, p);
    final eye = Paint()..color = BrandPalette.royal700;
    canvas.drawCircle(Offset(s * 0.34, s * 0.58), s * 0.09, eye);
    canvas.drawCircle(Offset(s * 0.66, s * 0.58), s * 0.09, eye);
  }

  @override
  bool shouldRepaint(RobotGlyphPainter old) => old.color != color;
}

// ----------------------------------------------------------------- avatars

enum _Hair {
  short,
  long,
  bun,
  curly,
  spiky,
  bob,
  ponytail,
  turban,
  hijab,
  wavy,
}

enum _Accessory { none, crown, glasses, bow, headband, star, headphones, cap }

enum _FacialHair { none, mustache, beard }

class _AvatarSpec {
  const _AvatarSpec({
    required this.bg,
    required this.skin,
    required this.hairColor,
    required this.hair,
    required this.shirt,
    this.accessory = _Accessory.none,
    this.accent = const Color(0xFFE5484D),
    this.facialHair = _FacialHair.none,
  });

  final List<Color> bg;
  final Color skin;
  final Color hairColor;
  final _Hair hair;
  final Color shirt;
  final _Accessory accessory;
  final Color accent;
  final _FacialHair facialHair;
}

const _skinLight = Color(0xFFFFD9BF);
const _skinLightTan = Color(0xFFF2C29B);
const _skinTan = Color(0xFFD9A066);
const _skinMedium = Color(0xFFC68B59);
const _skinMediumDark = Color(0xFF9C6640);
const _skinDark = Color(0xFF6E4429);

const List<_AvatarSpec> _specs = [
  _AvatarSpec(
    bg: [Color(0xFF8E73FF), Color(0xFF5B3FD0)],
    skin: _skinMedium,
    hairColor: Color(0xFF241A14),
    hair: _Hair.short,
    shirt: Color(0xFFF2B635),
    accessory: _Accessory.crown,
  ),
  _AvatarSpec(
    bg: [Color(0xFF5FE0C8), Color(0xFF1E9C8A)],
    skin: _skinLight,
    hairColor: Color(0xFF7A4A2A),
    hair: _Hair.long,
    shirt: Color(0xFFE5484D),
    accessory: _Accessory.bow,
    accent: Color(0xFFE5484D),
  ),
  _AvatarSpec(
    bg: [Color(0xFFFF9C8A), Color(0xFFE5484D)],
    skin: _skinDark,
    hairColor: Color(0xFF15100D),
    hair: _Hair.curly,
    shirt: Color(0xFF3E63DD),
    accessory: _Accessory.glasses,
  ),
  _AvatarSpec(
    bg: [Color(0xFFFFDD8A), Color(0xFFD4961E)],
    skin: _skinTan,
    hairColor: Color(0xFF1E1612),
    hair: _Hair.bun,
    shirt: Color(0xFF5B3FD0),
    accessory: _Accessory.headband,
    accent: Color(0xFF7A5CF0),
  ),
  _AvatarSpec(
    bg: [Color(0xFF7FA6FF), Color(0xFF3E63DD)],
    skin: _skinLightTan,
    hairColor: Color(0xFFD9692B),
    hair: _Hair.spiky,
    shirt: Color(0xFF30A46C),
  ),
  _AvatarSpec(
    bg: [Color(0xFFFFA6CF), Color(0xFFD9468F)],
    skin: _skinMediumDark,
    hairColor: Color(0xFF16100C),
    hair: _Hair.bob,
    shirt: Color(0xFFFFCB57),
    accessory: _Accessory.star,
    accent: Color(0xFFFFCB57),
  ),
  _AvatarSpec(
    bg: [Color(0xFF72D9A0), Color(0xFF268A57)],
    skin: _skinTan,
    hairColor: Color(0xFF2B1D14),
    hair: _Hair.turban,
    shirt: Color(0xFFF5F0FF),
    accent: Color(0xFFF59E0B),
    facialHair: _FacialHair.mustache,
  ),
  _AvatarSpec(
    bg: [Color(0xFF6F5BD9), Color(0xFF30205F)],
    skin: _skinLight,
    hairColor: Color(0xFFF2CF6B),
    hair: _Hair.ponytail,
    shirt: Color(0xFF4FD8F0),
    accessory: _Accessory.headphones,
    accent: Color(0xFF231846),
  ),
  _AvatarSpec(
    bg: [Color(0xFFFFB86B), Color(0xFFE5711F)],
    skin: _skinDark,
    hairColor: Color(0xFF120C09),
    hair: _Hair.short,
    shirt: Color(0xFF231846),
    accessory: _Accessory.cap,
    accent: Color(0xFF3E63DD),
  ),
  _AvatarSpec(
    bg: [Color(0xFF9BE8D8), Color(0xFF2FBF8A)],
    skin: _skinMedium,
    hairColor: Color(0xFF1A1310),
    hair: _Hair.long,
    shirt: Color(0xFF7A5CF0),
    accessory: _Accessory.glasses,
  ),
  _AvatarSpec(
    bg: [Color(0xFFCABCFF), Color(0xFF8E73FF)],
    skin: _skinLightTan,
    hairColor: Color(0xFF5A3A22),
    hair: _Hair.wavy,
    shirt: Color(0xFFE5484D),
    facialHair: _FacialHair.beard,
  ),
  _AvatarSpec(
    bg: [Color(0xFFFF8A8F), Color(0xFFB32A35)],
    skin: _skinMedium,
    hairColor: Color(0xFF1F1A16),
    hair: _Hair.hijab,
    shirt: Color(0xFF1E9C8A),
    accent: Color(0xFF26B5A0),
  ),
];

/// Paints avatar [index] (0–11) filling its square canvas (clip it to a
/// circle).
class AvatarPainter extends CustomPainter {
  const AvatarPainter(this.index);

  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    final spec = _specs[index % _specs.length];
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    _paintAvatar(canvas, s, spec);
    canvas.restore();
  }

  void _paintAvatar(Canvas canvas, double s, _AvatarSpec a) {
    final rect = Rect.fromLTWH(0, 0, s, s);
    Offset o(double x, double y) => Offset(x * s, y * s);

    // Background.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: a.bg,
        ).createShader(rect),
    );
    canvas.drawCircle(
      o(0.28, 0.22),
      s * 0.42,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.28),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: o(0.28, 0.22), radius: s * 0.42),
            ),
    );

    final cx = 0.5;
    final cy = 0.47;
    final head = o(cx, cy);
    final hr = s * 0.25;
    final hairPaint = Paint()..color = a.hairColor;
    final skinPaint = Paint()..color = a.skin;
    final skinShade = Paint()..color = Color.lerp(a.skin, Colors.black, 0.18)!;

    // Hair behind the head.
    switch (a.hair) {
      case _Hair.long:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(s * 0.2, s * 0.2, s * 0.8, s * 0.86),
            Radius.circular(s * 0.26),
          ),
          hairPaint,
        );
      case _Hair.bob:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(s * 0.21, s * 0.19, s * 0.79, s * 0.68),
            Radius.circular(s * 0.22),
          ),
          hairPaint,
        );
      case _Hair.ponytail:
        canvas.drawOval(
          Rect.fromCenter(
            center: o(0.8, 0.5),
            width: s * 0.2,
            height: s * 0.38,
          ),
          hairPaint,
        );
      case _Hair.hijab:
        final hijab = Paint()..color = a.accent;
        canvas.drawCircle(head.translate(0, -s * 0.01), s * 0.32, hijab);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(s * 0.18, s * 0.5, s * 0.82, s * 1.05),
            Radius.circular(s * 0.2),
          ),
          hijab,
        );
      default:
        break;
    }

    // Shoulders / shirt.
    final shirtRect = Rect.fromCenter(
      center: o(0.5, 1.04),
      width: s * 0.86,
      height: s * 0.56,
    );
    if (a.hair != _Hair.hijab) {
      canvas.drawOval(
        shirtRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [a.shirt, Color.lerp(a.shirt, Colors.black, 0.2)!],
          ).createShader(shirtRect),
      );
      // Neck.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(s * 0.43, s * 0.62, s * 0.57, s * 0.8),
          Radius.circular(s * 0.04),
        ),
        skinShade,
      );
      // Collar.
      final collar = Path()
        ..moveTo(s * 0.4, s * 0.77)
        ..quadraticBezierTo(s * 0.5, s * 0.86, s * 0.6, s * 0.77)
        ..lineTo(s * 0.62, s * 0.8)
        ..quadraticBezierTo(s * 0.5, s * 0.92, s * 0.38, s * 0.8)
        ..close();
      canvas.drawPath(
        collar,
        Paint()..color = Color.lerp(a.shirt, Colors.white, 0.3)!,
      );
    } else {
      // Hijab drape over the shoulders.
      canvas.drawOval(
        shirtRect,
        Paint()..color = Color.lerp(a.accent, Colors.black, 0.12)!,
      );
    }

    // Ears.
    if (a.hair != _Hair.hijab) {
      canvas.drawCircle(o(cx - 0.25, cy + 0.02), s * 0.05, skinPaint);
      canvas.drawCircle(o(cx + 0.25, cy + 0.02), s * 0.05, skinPaint);
    }

    // Head.
    final faceR = a.hair == _Hair.hijab ? hr * 0.92 : hr;
    canvas.drawCircle(head, faceR, skinPaint);
    // Subtle jaw shading.
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: head, radius: faceR)),
    );
    canvas.drawCircle(
      head.translate(s * 0.06, s * 0.08),
      faceR,
      Paint()..color = Colors.black.withValues(alpha: 0.06),
    );
    canvas.drawCircle(
      head.translate(-s * 0.02, -s * 0.02),
      faceR * 0.98,
      skinPaint,
    );
    canvas.restore();

    // Facial hair (beneath hair fringe).
    switch (a.facialHair) {
      case _FacialHair.beard:
        final beard = Path()
          ..moveTo(s * (cx - 0.24), s * (cy + 0.02))
          ..quadraticBezierTo(
            s * (cx - 0.22),
            s * (cy + 0.3),
            s * cx,
            s * (cy + 0.31),
          )
          ..quadraticBezierTo(
            s * (cx + 0.22),
            s * (cy + 0.3),
            s * (cx + 0.24),
            s * (cy + 0.02),
          )
          ..quadraticBezierTo(
            s * (cx + 0.18),
            s * (cy + 0.16),
            s * cx,
            s * (cy + 0.15),
          )
          ..quadraticBezierTo(
            s * (cx - 0.18),
            s * (cy + 0.16),
            s * (cx - 0.24),
            s * (cy + 0.02),
          )
          ..close();
        canvas.drawPath(beard, hairPaint);
      case _FacialHair.mustache:
        final m = Path()
          ..moveTo(s * (cx - 0.1), s * (cy + 0.1))
          ..quadraticBezierTo(
            s * (cx - 0.05),
            s * (cy + 0.05),
            s * cx,
            s * (cy + 0.08),
          )
          ..quadraticBezierTo(
            s * (cx + 0.05),
            s * (cy + 0.05),
            s * (cx + 0.1),
            s * (cy + 0.1),
          )
          ..quadraticBezierTo(
            s * (cx + 0.05),
            s * (cy + 0.1),
            s * cx,
            s * (cy + 0.1),
          )
          ..quadraticBezierTo(
            s * (cx - 0.05),
            s * (cy + 0.1),
            s * (cx - 0.1),
            s * (cy + 0.1),
          )
          ..close();
        canvas.drawPath(m, hairPaint);
      case _FacialHair.none:
        break;
    }

    // Hair on top.
    _paintHairTop(canvas, s, a, head, hr, hairPaint);

    // Eyes.
    final eyeY = cy + 0.01;
    for (final ex in [cx - 0.09, cx + 0.09]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: o(ex, eyeY),
          width: s * 0.06,
          height: s * 0.075,
        ),
        Paint()..color = const Color(0xFF231A2E),
      );
      canvas.drawCircle(
        o(ex + 0.012, eyeY - 0.015),
        s * 0.013,
        Paint()..color = Colors.white,
      );
    }
    // Brows.
    final brow = Paint()
      ..color = Color.lerp(a.hairColor, Colors.black, 0.2)!
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.018;
    canvas.drawArc(
      Rect.fromCenter(
        center: o(cx - 0.09, eyeY - 0.055),
        width: s * 0.09,
        height: s * 0.04,
      ),
      math.pi * 1.1,
      math.pi * 0.8,
      false,
      brow,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: o(cx + 0.09, eyeY - 0.055),
        width: s * 0.09,
        height: s * 0.04,
      ),
      math.pi * 1.1,
      math.pi * 0.8,
      false,
      brow,
    );
    // Cheeks.
    final blush = Paint()
      ..color = const Color(0xFFFF6F91).withValues(alpha: 0.28);
    canvas.drawOval(
      Rect.fromCenter(
        center: o(cx - 0.155, cy + 0.075),
        width: s * 0.08,
        height: s * 0.045,
      ),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: o(cx + 0.155, cy + 0.075),
        width: s * 0.08,
        height: s * 0.045,
      ),
      blush,
    );
    // Smile.
    final smile = Path()
      ..moveTo(s * (cx - 0.07), s * (cy + 0.095))
      ..quadraticBezierTo(
        s * cx,
        s * (cy + 0.165),
        s * (cx + 0.07),
        s * (cy + 0.095),
      )
      ..quadraticBezierTo(
        s * cx,
        s * (cy + 0.125),
        s * (cx - 0.07),
        s * (cy + 0.095),
      )
      ..close();
    if (a.facialHair == _FacialHair.beard) {
      canvas.drawPath(
        smile,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    } else {
      canvas.drawPath(smile, Paint()..color = const Color(0xFF7A2E3A));
    }

    // Accessories.
    _paintAccessory(canvas, s, a, head, hr);
  }

  void _paintHairTop(
    Canvas canvas,
    double s,
    _AvatarSpec a,
    Offset head,
    double hr,
    Paint hair,
  ) {
    final cx = head.dx;
    final cy = head.dy;
    Path cap({double fringe = 0.06, double lift = 0}) {
      final r = hr * 1.06;
      return Path()
        ..moveTo(cx - r, cy - lift)
        ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy - lift), radius: r),
          math.pi,
          math.pi,
          false,
        )
        ..quadraticBezierTo(
          cx + r * 0.6,
          cy - hr * 0.55,
          cx + r * 0.1,
          cy - hr * (0.45 - fringe),
        )
        ..quadraticBezierTo(cx - r * 0.4, cy - hr * 0.3, cx - r, cy - lift)
        ..close();
    }

    switch (a.hair) {
      case _Hair.short:
        canvas.drawPath(cap(), hair);
      case _Hair.long:
        canvas.drawPath(cap(fringe: 0.12), hair);
      case _Hair.bob:
        final p = Path()
          ..addArc(
            Rect.fromCircle(center: head, radius: hr * 1.08),
            math.pi,
            math.pi,
          )
          ..lineTo(cx + hr * 1.08, cy - hr * 0.25)
          ..lineTo(cx - hr * 1.08, cy - hr * 0.25)
          ..close();
        canvas.drawPath(p, hair);
      case _Hair.bun:
        canvas.drawCircle(Offset(cx, cy - hr * 1.15), hr * 0.38, hair);
        canvas.drawPath(cap(), hair);
      case _Hair.ponytail:
        canvas.drawPath(cap(fringe: 0.1), hair);
        canvas.drawCircle(
          Offset(cx + hr * 0.95, cy - hr * 0.35),
          hr * 0.14,
          Paint()..color = a.accent,
        );
      case _Hair.curly:
        for (var i = 0; i <= 9; i++) {
          final ang = math.pi * (0.95 + i * 0.122);
          canvas.drawCircle(
            Offset(
              cx + math.cos(ang) * hr * 0.98,
              cy + math.sin(ang) * hr * 0.98,
            ),
            hr * 0.3,
            hair,
          );
        }
        canvas.drawCircle(Offset(cx, cy - hr * 0.72), hr * 0.42, hair);
      case _Hair.spiky:
        final p = Path()..moveTo(cx - hr * 1.05, cy - hr * 0.1);
        const spikes = 6;
        for (var i = 0; i <= spikes; i++) {
          final t = i / spikes;
          final ang = math.pi + math.pi * t;
          final outer = hr * 1.42;
          final inner = hr * 0.95;
          final tip = Offset(
            cx + math.cos(ang) * outer,
            cy - hr * 0.05 + math.sin(ang) * outer,
          );
          if (i > 0) {
            final mid = math.pi + math.pi * (t - 0.5 / spikes);
            p.lineTo(cx + math.cos(mid) * inner, cy + math.sin(mid) * inner);
          }
          p.lineTo(tip.dx, tip.dy);
        }
        p
          ..lineTo(cx + hr * 1.05, cy - hr * 0.1)
          ..quadraticBezierTo(cx, cy - hr * 0.6, cx - hr * 1.05, cy - hr * 0.1)
          ..close();
        canvas.drawPath(p, hair);
      case _Hair.wavy:
        final p = Path()
          ..moveTo(cx - hr * 1.08, cy)
          ..arcTo(
            Rect.fromCircle(center: head, radius: hr * 1.08),
            math.pi,
            math.pi,
            false,
          )
          ..quadraticBezierTo(
            cx + hr * 0.9,
            cy - hr * 0.3,
            cx + hr * 0.5,
            cy - hr * 0.55,
          )
          ..quadraticBezierTo(cx, cy - hr * 0.2, cx - hr * 0.5, cy - hr * 0.62)
          ..quadraticBezierTo(cx - hr * 0.9, cy - hr * 0.3, cx - hr * 1.08, cy)
          ..close();
        canvas.drawPath(p, hair);
      case _Hair.turban:
        final wrap = Paint()..color = a.accent;
        final dome = Rect.fromCenter(
          center: Offset(cx, cy - hr * 0.45),
          width: hr * 2.35,
          height: hr * 1.7,
        );
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, s, cy - hr * 0.2));
        canvas.drawOval(dome, wrap);
        canvas.restore();
        final band = Paint()
          ..color = Color.lerp(a.accent, Colors.black, 0.22)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.02;
        for (var i = 0; i < 3; i++) {
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(cx, cy - hr * 0.2 - i * hr * 0.28),
              width: hr * 2.1 - i * hr * 0.3,
              height: hr * 0.9,
            ),
            math.pi * 1.08,
            math.pi * 0.84,
            false,
            band,
          );
        }
        canvas.drawCircle(
          Offset(cx, cy - hr * 0.62),
          hr * 0.12,
          Paint()..color = const Color(0xFFE5484D),
        );
        canvas.drawCircle(
          Offset(cx, cy - hr * 0.62),
          hr * 0.05,
          Paint()..color = Colors.white70,
        );
      case _Hair.hijab:
        // Hijab front band framing the face.
        canvas.drawArc(
          Rect.fromCircle(center: head, radius: hr * 0.98),
          math.pi * 1.05,
          math.pi * 0.9,
          false,
          Paint()
            ..color = Color.lerp(a.accent, Colors.white, 0.25)!
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.035,
        );
    }
  }

  void _paintAccessory(
    Canvas canvas,
    double s,
    _AvatarSpec a,
    Offset head,
    double hr,
  ) {
    final cx = head.dx;
    final cy = head.dy;
    switch (a.accessory) {
      case _Accessory.none:
        break;
      case _Accessory.crown:
        final w = hr * 1.2;
        final h = hr * 0.62;
        final left = cx - w / 2;
        final top = cy - hr * 1.48;
        final p = Path()
          ..moveTo(left, top + h)
          ..lineTo(left, top + h * 0.25)
          ..lineTo(left + w * 0.27, top + h * 0.6)
          ..lineTo(left + w * 0.5, top)
          ..lineTo(left + w * 0.73, top + h * 0.6)
          ..lineTo(left + w, top + h * 0.25)
          ..lineTo(left + w, top + h)
          ..close();
        canvas.drawPath(
          p,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [BrandPalette.gold300, BrandPalette.gold600],
            ).createShader(Rect.fromLTWH(left, top, w, h)),
        );
        canvas.drawCircle(
          Offset(cx, top + h * 0.72),
          hr * 0.07,
          Paint()..color = const Color(0xFFE5484D),
        );
      case _Accessory.glasses:
        final frame = Paint()
          ..color = const Color(0xFF231A2E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.018;
        final ey = cy + s * 0.01;
        for (final ex in [cx - s * 0.09, cx + s * 0.09]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(ex, ey),
                width: s * 0.13,
                height: s * 0.11,
              ),
              Radius.circular(s * 0.035),
            ),
            frame,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(ex, ey),
                width: s * 0.13,
                height: s * 0.11,
              ),
              Radius.circular(s * 0.035),
            ),
            Paint()..color = Colors.white.withValues(alpha: 0.18),
          );
        }
        canvas.drawLine(
          Offset(cx - s * 0.025, ey),
          Offset(cx + s * 0.025, ey),
          frame,
        );
      case _Accessory.bow:
        final bow = Paint()..color = a.accent;
        final c0 = Offset(cx + hr * 0.62, cy - hr * 0.86);
        final l = Path()
          ..moveTo(c0.dx, c0.dy)
          ..lineTo(c0.dx - hr * 0.42, c0.dy - hr * 0.26)
          ..lineTo(c0.dx - hr * 0.36, c0.dy + hr * 0.28)
          ..close();
        final r = Path()
          ..moveTo(c0.dx, c0.dy)
          ..lineTo(c0.dx + hr * 0.42, c0.dy - hr * 0.3)
          ..lineTo(c0.dx + hr * 0.38, c0.dy + hr * 0.24)
          ..close();
        canvas.drawPath(l, bow);
        canvas.drawPath(r, bow);
        canvas.drawCircle(
          c0,
          hr * 0.12,
          Paint()..color = Color.lerp(a.accent, Colors.black, 0.2)!,
        );
      case _Accessory.headband:
        canvas.drawArc(
          Rect.fromCircle(
            center: head.translate(0, hr * 0.12),
            radius: hr * 1.02,
          ),
          math.pi * 1.12,
          math.pi * 0.76,
          false,
          Paint()
            ..color = a.accent
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = s * 0.045,
        );
      case _Accessory.star:
        _star(
          canvas,
          Offset(cx - hr * 0.7, cy - hr * 0.62),
          hr * 0.24,
          Paint()..color = a.accent,
        );
      case _Accessory.headphones:
        final band = Paint()
          ..color = a.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.04;
        canvas.drawArc(
          Rect.fromCircle(center: head, radius: hr * 1.18),
          math.pi * 1.05,
          math.pi * 0.9,
          false,
          band,
        );
        for (final dx in [-1.0, 1.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(cx + dx * hr * 1.08, cy + hr * 0.05),
                width: hr * 0.36,
                height: hr * 0.62,
              ),
              Radius.circular(hr * 0.14),
            ),
            Paint()..color = a.accent,
          );
          canvas.drawCircle(
            Offset(cx + dx * hr * 1.08, cy + hr * 0.05),
            hr * 0.08,
            Paint()..color = const Color(0xFF4FD8F0),
          );
        }
      case _Accessory.cap:
        final capPaint = Paint()..color = a.accent;
        final dome = Path()
          ..addArc(
            Rect.fromCircle(
              center: head.translate(0, -hr * 0.36),
              radius: hr * 1.02,
            ),
            math.pi,
            math.pi,
          )
          ..close();
        canvas.drawPath(dome, capPaint);
        final brim = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - hr * 0.1, cy - hr * 0.5, hr * 1.3, hr * 0.2),
          Radius.circular(hr * 0.1),
        );
        canvas.drawRRect(
          brim,
          Paint()..color = Color.lerp(a.accent, Colors.black, 0.25)!,
        );
        canvas.drawCircle(
          Offset(cx, cy - hr * 1.38),
          hr * 0.08,
          Paint()..color = Color.lerp(a.accent, Colors.white, 0.4)!,
        );
    }
  }

  static void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final ang = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(c.dx + math.cos(ang) * rr, c.dy + math.sin(ang) * rr);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    p.close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(AvatarPainter old) => old.index != index;
}

// ------------------------------------------------------------------ frames

/// Paints the avatar frame + optional seat ring around a centered portrait
/// circle occupying [portraitFraction] of the canvas.
class AvatarFramePainter extends CustomPainter {
  const AvatarFramePainter({
    required this.frameId,
    required this.portraitFraction,
    required this.plainRing,
    this.seatColor,
    this.royalOffset = 0,
  });

  final String frameId;
  final double portraitFraction;
  final Color plainRing;
  final Color? seatColor;
  final double royalOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2 + royalOffset * s);
    final pr = s * portraitFraction / 2;

    // Seat ring hugging the portrait.
    if (seatColor != null) {
      canvas.drawCircle(
        center,
        pr + s * 0.018,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.04
          ..color = seatColor!,
      );
    }

    switch (frameId) {
      case 'frame_bronze':
        _metalRing(canvas, center, pr, s, const [
          Color(0xFFF0B07A),
          Color(0xFFB8733A),
          Color(0xFF7E4A1E),
        ]);
      case 'frame_silver':
        _laurel(
          canvas,
          center,
          pr,
          s,
          const Color(0xFFDCE3EE),
          const Color(0xFF8C98AB),
          leaves: 5,
        );
        _metalRing(canvas, center, pr, s, const [
          Color(0xFFFFFFFF),
          Color(0xFFC3CCDA),
          Color(0xFF7E8A9E),
        ]);
      case 'frame_gold':
        _laurel(
          canvas,
          center,
          pr,
          s,
          BrandPalette.gold300,
          BrandPalette.gold700,
          leaves: 6,
        );
        _metalRing(canvas, center, pr, s, const [
          BrandPalette.gold100,
          BrandPalette.gold500,
          BrandPalette.gold700,
        ]);
        AvatarPainter._star(
          canvas,
          Offset(center.dx, center.dy + pr + s * 0.07),
          s * 0.06,
          Paint()..color = BrandPalette.gold400,
        );
      case 'frame_royal':
        _metalRing(canvas, center, pr, s, const [
          BrandPalette.gold300,
          BrandPalette.gold500,
          BrandPalette.gold700,
        ], width: 0.07);
        canvas.drawCircle(
          center,
          pr + s * 0.035,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.018
            ..color = BrandPalette.royal500,
        );
        const gems = [
          Color(0xFFE5484D),
          Color(0xFF30A46C),
          Color(0xFF3E63DD),
          Color(0xFF4FD8F0),
        ];
        for (var i = 0; i < 4; i++) {
          final ang = math.pi * (0.25 + i * 0.5);
          final gc = Offset(
            center.dx + math.cos(ang) * (pr + s * 0.035),
            center.dy + math.sin(ang) * (pr + s * 0.035),
          );
          canvas.drawCircle(
            gc,
            s * 0.034,
            Paint()..color = BrandPalette.gold600,
          );
          canvas.drawCircle(gc, s * 0.024, Paint()..color = gems[i]);
          canvas.drawCircle(
            gc.translate(-s * 0.008, -s * 0.008),
            s * 0.008,
            Paint()..color = Colors.white.withValues(alpha: 0.8),
          );
        }
        // Crown on top.
        final w = s * 0.34;
        final h = s * 0.17;
        final left = center.dx - w / 2;
        final top = center.dy - pr - s * 0.035 - h * 0.92;
        final crown = Path()
          ..moveTo(left + w * 0.06, top + h)
          ..lineTo(left, top + h * 0.22)
          ..lineTo(left + w * 0.28, top + h * 0.55)
          ..lineTo(left + w * 0.5, top)
          ..lineTo(left + w * 0.72, top + h * 0.55)
          ..lineTo(left + w, top + h * 0.22)
          ..lineTo(left + w * 0.94, top + h)
          ..close();
        canvas.drawPath(
          crown.shift(Offset(0, s * 0.01)),
          Paint()..color = BrandPalette.gold800.withValues(alpha: 0.5),
        );
        canvas.drawPath(
          crown,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [BrandPalette.gold300, BrandPalette.gold600],
            ).createShader(Rect.fromLTWH(left, top, w, h)),
        );
        canvas.drawCircle(
          Offset(center.dx, top + h * 0.7),
          s * 0.018,
          Paint()..color = const Color(0xFFE5484D),
        );
      default:
        if (seatColor == null) {
          canvas.drawCircle(
            center,
            pr + s * 0.008,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.2, s * 0.02)
              ..color = plainRing,
          );
        }
    }
  }

  void _metalRing(
    Canvas canvas,
    Offset center,
    double pr,
    double s,
    List<Color> colors, {
    double width = 0.055,
  }) {
    final r = pr + s * width / 2 + (seatColor != null ? s * 0.035 : 0);
    final rect = Rect.fromCircle(center: center, radius: r + s * width);
    canvas.drawCircle(
      center.translate(0, s * 0.012),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * width
        ..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * width
        ..shader = SweepGradient(
          colors: [...colors, colors.first],
          transform: const GradientRotation(-math.pi / 3),
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      r - s * width * 0.32,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.008
        ..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  void _laurel(
    Canvas canvas,
    Offset center,
    double pr,
    double s,
    Color light,
    Color dark, {
    required int leaves,
  }) {
    // Leaves sprout from the outer edge of the metal ring and climb both
    // sides from the bottom, tilted slightly outward.
    final base = pr + s * 0.055 + (seatColor != null ? s * 0.035 : 0);
    final leafLen = s * 0.085;
    final leafPaint = Paint();
    for (final side in [1.0, -1.0]) {
      for (var i = 0; i < leaves; i++) {
        final t = i / (leaves - 1);
        // side 1 → left half (angles grow from 100° to 215°).
        final ang = math.pi / 2 + side * (0.22 + t * 1.85);
        final pos = Offset(
          center.dx + math.cos(ang) * base,
          center.dy + math.sin(ang) * base,
        );
        final heading = side > 0
            ? ang + math.pi / 2 - 0.5
            : ang - math.pi / 2 + 0.5;
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(heading);
        final leaf = Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(leafLen * 0.45, -leafLen * 0.34, leafLen, 0)
          ..quadraticBezierTo(leafLen * 0.45, leafLen * 0.34, 0, 0)
          ..close();
        leafPaint.shader = LinearGradient(colors: [dark, light]).createShader(
          Rect.fromLTWH(0, -leafLen * 0.4, leafLen, leafLen * 0.8),
        );
        canvas.drawPath(leaf, leafPaint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(AvatarFramePainter old) =>
      old.frameId != frameId ||
      old.portraitFraction != portraitFraction ||
      old.seatColor != seatColor ||
      old.plainRing != plainRing ||
      old.royalOffset != royalOffset;
}
