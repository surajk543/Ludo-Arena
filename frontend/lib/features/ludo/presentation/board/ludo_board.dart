import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';

import '../../../../shared/game_visuals/boards_l10n.dart';
import '../../../../shared/game_visuals/game_palette.dart';
import '../../../../shared/game_visuals/motion/effects_renderer.dart';
import '../../../../shared/game_visuals/tokens/token_renderer.dart';
import '../../../../shared/game_visuals/trails/trail_renderer.dart';
import 'ludo_board_controller.dart';
import 'ludo_board_painter.dart';
import 'ludo_board_theme.dart';
import 'ludo_geometry.dart';

/// Token radius as a fraction of a Ludo cell.
const double kLudoTokenRadius = 0.47;

/// The Ludo board: a cached static board layer plus an animated token layer
/// driven by [controller].
///
/// The board is square and centers itself in the given constraints. It is
/// never mirrored for RTL (the board is wrapped in an LTR
/// [Directionality]); accessibility labels keep the ambient direction.
class LudoBoard extends StatefulWidget {
  const LudoBoard({
    super.key,
    required this.controller,
    this.boardTheme = LudoBoardThemes.classic,
    this.tokenSkins,
    this.trails,
    this.onTokenTap,
    this.reducedMotion = false,
  });

  final LudoBoardController controller;

  /// `ludo_board_*` cosmetic id; unknown ids fall back to the classic look.
  final String boardTheme;

  /// Token skin id per seat (`token_*`); default `token_classic`.
  final List<String>? tokenSkins;

  /// Trail id per seat (`trail_*`); default `trail_none`.
  final List<String>? trails;

  /// Called with the legal token index the local player tapped (only for
  /// tokens of `controller.interactiveSeat` listed in `legalTokens`).
  final ValueChanged<int>? onTokenTap;

  /// Replace hops with quick fades and keep highlights still.
  final bool reducedMotion;

  @override
  State<LudoBoard> createState() => _LudoBoardState();
}

class _LudoBoardState extends State<LudoBoard> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this, reducedMotion: widget.reducedMotion);
    widget.controller.addListener(_syncPulse);
    _syncPulse();
  }

  @override
  void didUpdateWidget(LudoBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_syncPulse);
      oldWidget.controller.detach();
      widget.controller.attach(this, reducedMotion: widget.reducedMotion);
      widget.controller.addListener(_syncPulse);
    } else if (oldWidget.reducedMotion != widget.reducedMotion) {
      widget.controller.attach(this, reducedMotion: widget.reducedMotion);
    }
    _syncPulse();
  }

  /// The legal-move pulse only ticks while there is something to pick.
  void _syncPulse() {
    final c = widget.controller;
    final wanted =
        !widget.reducedMotion &&
        c.interactiveSeat != null &&
        c.legalTokens.isNotEmpty;
    if (wanted) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPulse);
    widget.controller.detach();
    _pulse.dispose();
    super.dispose();
  }

  void _handleTap(Offset local, Size size) {
    final onTap = widget.onTokenTap;
    if (onTap == null) return;
    final layout = LudoBoardLayout.fit(size);
    final index = widget.controller.hitTest(layout.toGrid(local));
    if (index != null) onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final ambient = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final palette = GamePalette.of(context);
    final style = LudoBoardThemes.style(widget.boardTheme, palette);
    final l10n = boardsL10n(context);
    final controller = widget.controller;
    final seats = controller.seatCount;
    final skins = [
      for (var s = 0; s < seats; s++)
        TokenSkins.resolve(_at(widget.tokenSkins, s)),
    ];
    final trails = [
      for (var s = 0; s < seats; s++)
        TrailStyles.resolve(_at(widget.trails, s)),
    ];

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Semantics(
        container: true,
        label: l10n.boardsLudoBoardLabel,
        textDirection: ambient,
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: LudoBoardPainter(
                          style: style,
                          tokensPerPlayer: controller.tokensPerPlayer,
                          activeColors: controller.seatColors.toSet(),
                          quarterTurns: controller.quarterTurns,
                        ),
                        isComplex: true,
                        willChange: false,
                      ),
                    ),
                    RepaintBoundary(
                      child: ListenableBuilder(
                        listenable: controller,
                        builder: (context, _) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: widget.onTokenTap == null
                                ? null
                                : (d) => _handleTap(d.localPosition, size),
                            child: CustomPaint(
                              size: size,
                              painter: LudoTokenPainter(
                                controller: controller,
                                palette: palette,
                                pulse: _pulse,
                                skins: skins,
                                trails: trails,
                                labels: _labels(l10n, controller),
                                semanticsDirection: ambient,
                                onTokenTap: widget.onTokenTap,
                                moveHint: l10n.boardsTokenMoveHint,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static String? _at(List<String>? list, int i) =>
      list != null && i < list.length ? list[i] : null;

  static List<List<String>> _labels(
    AppLocalizations l10n,
    LudoBoardController c,
  ) {
    final positions = c.positions;
    return [
      for (var s = 0; s < c.seatCount; s++)
        [
          for (var t = 0; t < c.tokensPerPlayer; t++)
            _label(l10n, c, s, t, positions[s][t]),
        ],
    ];
  }

  static String _label(
    AppLocalizations l10n,
    LudoBoardController c,
    int seat,
    int token,
    int progress,
  ) {
    final color = boardsColorName(l10n, c.seatColors[seat]);
    final number = token + 1;
    final String base;
    if (progress < 0) {
      base = l10n.boardsTokenInBase(color, number);
    } else if (progress >= LudoGeometry.homeProgress) {
      base = l10n.boardsTokenHome(color, number);
    } else {
      base = l10n.boardsTokenStepsFromHome(
        color,
        number,
        LudoGeometry.stepsToHome(progress),
      );
    }
    final parts = <String>[base];
    if (c.isLegalHighlighted(seat, token)) parts.add(l10n.boardsTokenCanMove);
    if (c.turnSeat == seat) parts.add(l10n.boardsCurrentTurn);
    return parts.join(', ');
  }
}

/// Paints the tokens, highlights, trails and effects of a
/// [LudoBoardController].
///
/// Repaints every animation frame through `controller.frames` (and the
/// legal-move [pulse]) without rebuilding widgets. Per-frame painting reuses
/// preallocated buffers and cached token pictures.
class LudoTokenPainter extends CustomPainter {
  LudoTokenPainter({
    required this.controller,
    required this.palette,
    required this.pulse,
    required this.skins,
    required this.trails,
    this.labels = const [],
    this.semanticsDirection = TextDirection.ltr,
    this.onTokenTap,
    this.moveHint,
  }) : revision = controller.revision,
       _order = Int32List(controller.seatCount * controller.tokensPerPlayer),
       _keys = Float64List(controller.seatCount * controller.tokensPerPlayer),
       super(repaint: Listenable.merge([controller.frames, pulse]));

  final LudoBoardController controller;
  final GamePalette palette;
  final Animation<double> pulse;

  /// Resolved token skin / trail id per seat.
  final List<String> skins;
  final List<String> trails;

  /// Accessibility label per `[seat][token]` (empty = no semantics).
  final List<List<String>> labels;
  final TextDirection semanticsDirection;
  final ValueChanged<int>? onTokenTap;
  final String? moveHint;
  final int revision;

  final Int32List _order;
  final Float64List _keys;
  static final Paint _paint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final c = controller;
    final layout = LudoBoardLayout.fit(size);
    final cell = layout.cell;
    final tpp = c.tokensPerPlayer;
    final pulseValue = pulse.value;
    final wave = 0.5 - 0.5 * math.cos(pulseValue * 2 * math.pi);

    _paintTurnBase(canvas, layout, wave);

    // Depth sort (allocation free insertion sort).
    var n = 0;
    for (var s = 0; s < c.seatCount; s++) {
      if (!c.isSeatVisible(s)) continue;
      for (var t = 0; t < tpp; t++) {
        final m = c.motionOf(s, t);
        final center = m.active ? m.center : c.restingCenter(s, t);
        final key =
            center.dy +
            (m.active && m.onTop ? 1000.0 : (m.active ? 500.0 : 0.0));
        var j = n - 1;
        while (j >= 0 && _keys[j] > key) {
          _keys[j + 1] = _keys[j];
          _order[j + 1] = _order[j];
          j--;
        }
        _keys[j + 1] = key;
        _order[j + 1] = s * tpp + t;
        n++;
      }
    }

    for (var k = 0; k < n; k++) {
      final seat = _order[k] ~/ tpp;
      final token = _order[k] % tpp;
      final color = c.seatColors[seat];
      final shades = palette.shades(color);
      final m = c.motionOf(seat, token);
      final active = m.active;
      final grid = active ? m.center : c.restingCenter(seat, token);
      final scale = c.visualScale(seat, token);
      final r = cell * kLudoTokenRadius * scale;
      final px = layout.toPx(grid);
      final opacity = active ? m.opacity : 1.0;
      final legal = !active && c.isLegalHighlighted(seat, token);
      final bob = legal
          ? cell * 0.09 * math.sin(pulseValue * 2 * math.pi).abs()
          : 0.0;

      if (seat == c.turnSeat && !active) {
        TokenRenderer.paintGlow(
          canvas,
          center: px.translate(0, r * 0.3),
          radius: r * 0.95,
          color: shades.base,
          strength: 0.55,
        );
      }
      if (active && m.trailEnabled) {
        TrailRenderer.paint(
          canvas,
          m.trail,
          trailId: seat < trails.length ? trails[seat] : TrailStyles.none,
          now: c.now,
          cell: cell,
          origin: layout.gridOrigin,
          color: shades.base,
          opacity: opacity,
        );
      }
      if (m.glow > 0.01) {
        TokenRenderer.paintGlow(
          canvas,
          center: px,
          radius: math.max(r * 2.2, cell * 0.7),
          color: shades.base,
          strength: m.glow,
        );
        TokenRenderer.paintGlow(
          canvas,
          center: px,
          radius: math.max(r * 1.2, cell * 0.4),
          color: Colors.white,
          strength: 0.6 * m.glow,
        );
      }
      if (legal) {
        TokenRenderer.paintLegalRing(
          canvas,
          center: px,
          radius: r,
          palette: palette,
          shades: shades,
          pulse: pulseValue,
        );
      }
      final lift = active ? m.lift * cell : bob;
      TokenRenderer.paintShadow(
        canvas,
        center: px,
        radius: r,
        palette: palette,
        liftFraction: active ? m.liftFraction : (bob / (cell * 0.3)),
        opacity: opacity,
      );
      TokenRenderer.paintToken(
        canvas,
        center: px,
        radius: r,
        skin: seat < skins.length ? skins[seat] : TokenSkins.classic,
        color: color,
        palette: palette,
        scaleX: active ? m.scaleX : 1,
        scaleY: active ? m.scaleY : 1,
        lift: lift,
        opacity: opacity,
        rotation: active ? m.rotation : 0,
      );
      if (!active) {
        final badge = c.restingBadge(seat, token);
        if (badge > 1) {
          TokenRenderer.paintBadge(
            canvas,
            center: px.translate(r * 0.95, -r * 1.2),
            size: cell * 0.36,
            count: badge,
            shades: shades,
            palette: palette,
          );
        }
      }
    }

    BoardEffectsRenderer.paintAll(
      canvas,
      c.effects,
      c.now,
      cell: cell,
      origin: layout.gridOrigin,
      palette: palette,
    );
  }

  /// Glowing outline around the base of the seat whose turn it is.
  void _paintTurnBase(Canvas canvas, LudoBoardLayout layout, double wave) {
    final seat = controller.turnSeat;
    if (seat == null ||
        seat < 0 ||
        seat >= controller.seatCount ||
        !controller.isSeatVisible(seat)) {
      return;
    }
    final color = controller.seatColors[seat];
    final g = LudoGeometry.baseRect(
      color.rotated(controller.quarterTurns),
    ).deflate(0.06);
    final shades = palette.shades(color);
    final rect = Rect.fromLTRB(
      layout.gridOrigin.dx + g.left * layout.cell,
      layout.gridOrigin.dy + g.top * layout.cell,
      layout.gridOrigin.dx + g.right * layout.cell,
      layout.gridOrigin.dy + g.bottom * layout.cell,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(layout.cell * 0.42),
    );
    _paint
      ..style = PaintingStyle.stroke
      ..shader = null
      ..strokeWidth = layout.cell * (0.26 + 0.08 * wave)
      ..color = shades.glow.withValues(alpha: 0.24 + 0.16 * wave);
    canvas.drawRRect(rrect, _paint);
    _paint
      ..strokeWidth = layout.cell * 0.1
      ..color = Color.lerp(
        shades.soft,
        Colors.white,
        0.45,
      )!.withValues(alpha: 0.9);
    canvas.drawRRect(rrect.deflate(layout.cell * 0.02), _paint);
    _paint.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(covariant LudoTokenPainter oldDelegate) =>
      !identical(oldDelegate.controller, controller) ||
      oldDelegate.revision != revision ||
      oldDelegate.palette != palette ||
      !listEquals(oldDelegate.skins, skins) ||
      !listEquals(oldDelegate.trails, trails);

  @override
  SemanticsBuilderCallback? get semanticsBuilder {
    if (labels.isEmpty) return null;
    return (Size size) {
      final c = controller;
      final layout = LudoBoardLayout.fit(size);
      final nodes = <CustomPainterSemantics>[];
      for (var s = 0; s < c.seatCount && s < labels.length; s++) {
        if (!c.isSeatVisible(s)) continue;
        for (var t = 0; t < c.tokensPerPlayer && t < labels[s].length; t++) {
          final center = layout.toPx(c.restingCenter(s, t));
          final r = layout.cell * kLudoTokenRadius * c.restingScale(s, t);
          final legal = c.isLegalHighlighted(s, t) && onTokenTap != null;
          final tap = onTokenTap;
          nodes.add(
            CustomPainterSemantics(
              key: ValueKey<String>('ludo-token-$s-$t'),
              rect: Rect.fromCenter(
                center: center.translate(0, -r * 0.1),
                width: r * 2.1,
                height: r * 2.3,
              ),
              properties: SemanticsProperties(
                label: labels[s][t],
                textDirection: semanticsDirection,
                button: legal ? true : null,
                hint: legal ? moveHint : null,
                onTap: legal && tap != null ? () => tap(t) : null,
              ),
            ),
          );
        }
      }
      return nodes;
    };
  }

  @override
  bool shouldRebuildSemantics(covariant LudoTokenPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.onTokenTap != onTokenTap ||
      !_labelsEqual(oldDelegate.labels, labels);

  static bool _labelsEqual(List<List<String>> a, List<List<String>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!listEquals(a[i], b[i])) return false;
    }
    return true;
  }
}
