import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';

import '../../../../shared/game_visuals/boards_l10n.dart';
import '../../../../shared/game_visuals/game_palette.dart';
import '../../../../shared/game_visuals/motion/effects_renderer.dart';
import '../../../../shared/game_visuals/tokens/token_renderer.dart';
import '../../../../shared/game_visuals/trails/trail_renderer.dart';
import 'snakes_board_controller.dart';
import 'snakes_board_painter.dart';
import 'snakes_board_theme.dart';
import 'snakes_geometry.dart';

/// The Snakes & Ladders board: a cached static board layer plus an animated
/// token layer driven by [controller].
///
/// The board keeps its own aspect ratio ([SnakesGeometry.aspectRatio]) and
/// centers itself in the given constraints. It is never mirrored for RTL
/// (the grid is wrapped in an LTR [Directionality]); accessibility labels
/// keep the ambient text direction.
class SnakesBoard extends StatefulWidget {
  const SnakesBoard({
    super.key,
    required this.controller,
    this.boardTheme = SnakesBoardThemes.classic,
    this.tokenSkins,
    this.trails,
    this.reducedMotion = false,
  });

  final SnakesBoardController controller;

  /// `snakes_board_*` cosmetic id; unknown ids fall back to the classic look.
  final String boardTheme;

  /// Token skin id per seat (`token_*`); default `token_classic`.
  final List<String>? tokenSkins;

  /// Trail id per seat (`trail_*`); default `trail_none`.
  final List<String>? trails;

  /// Replace hops/slides with quick fades.
  final bool reducedMotion;

  @override
  State<SnakesBoard> createState() => _SnakesBoardState();
}

class _SnakesBoardState extends State<SnakesBoard>
    with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.controller.attach(this, reducedMotion: widget.reducedMotion);
  }

  @override
  void didUpdateWidget(SnakesBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detach();
      widget.controller.attach(this, reducedMotion: widget.reducedMotion);
    } else if (oldWidget.reducedMotion != widget.reducedMotion) {
      widget.controller.attach(this, reducedMotion: widget.reducedMotion);
    }
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambient = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final palette = GamePalette.of(context);
    final style = SnakesBoardThemes.style(widget.boardTheme, palette);
    final l10n = boardsL10n(context);
    final controller = widget.controller;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Semantics(
        container: true,
        label: l10n.boardsSnakesBoardLabel,
        textDirection: ambient,
        child: Center(
          child: AspectRatio(
            aspectRatio: SnakesGeometry.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: SnakesBoardPainter(style: style),
                    isComplex: true,
                    willChange: false,
                  ),
                ),
                RepaintBoundary(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final positions = controller.positions;
                      final labels = <String>[
                        for (var seat = 0; seat < controller.seatCount; seat++)
                          _label(l10n, controller, seat, positions[seat]),
                      ];
                      return CustomPaint(
                        painter: SnakesTokenPainter(
                          controller: controller,
                          palette: palette,
                          skins: [
                            for (var s = 0; s < controller.seatCount; s++)
                              TokenSkins.resolve(_at(widget.tokenSkins, s)),
                          ],
                          trails: [
                            for (var s = 0; s < controller.seatCount; s++)
                              TrailStyles.resolve(_at(widget.trails, s)),
                          ],
                          labels: labels,
                          semanticsDirection: ambient,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _at(List<String>? list, int i) =>
      list != null && i < list.length ? list[i] : null;

  static String _label(
    AppLocalizations l10n,
    SnakesBoardController controller,
    int seat,
    int square,
  ) {
    final color = boardsColorName(l10n, controller.seatColors[seat]);
    final base = square <= 0
        ? l10n.boardsSnakesTokenAtStart(color)
        : l10n.boardsSnakesTokenOnSquare(color, square);
    if (controller.turnSeat == seat) {
      return '$base, ${l10n.boardsCurrentTurn}';
    }
    return base;
  }
}

/// Paints the tokens, trails and effects of a [SnakesBoardController].
///
/// Repaints every animation frame through `controller.frames` without
/// rebuilding widgets; per-frame painting allocates nothing beyond the
/// offsets handed to the canvas.
class SnakesTokenPainter extends CustomPainter {
  SnakesTokenPainter({
    required this.controller,
    required this.palette,
    required this.skins,
    required this.trails,
    this.labels = const [],
    this.semanticsDirection = TextDirection.ltr,
  }) : revision = controller.revision,
       turnSeat = controller.turnSeat,
       super(repaint: controller.frames);

  final SnakesBoardController controller;
  final GamePalette palette;

  /// Resolved token skin per seat.
  final List<String> skins;

  /// Resolved trail id per seat.
  final List<String> trails;

  /// Accessibility label per seat (empty = no semantics).
  final List<String> labels;
  final TextDirection semanticsDirection;
  final int revision;
  final int? turnSeat;

  final List<int> _order = List<int>.filled(4, 0);

  double _sortKey(int seat) {
    final m = controller.motionOf(seat);
    final y = m.active ? m.y : controller.restingCenter(seat).dy;
    return (m.onTop && m.active ? 1000 : 0) + y;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final layout = SnakesBoardLayout.fit(size);
    final n = controller.seatCount.clamp(0, 4);
    for (var i = 0; i < n; i++) {
      _order[i] = i;
    }
    // Insertion sort by depth (allocation free).
    for (var i = 1; i < n; i++) {
      final seat = _order[i];
      final key = _sortKey(seat);
      var j = i - 1;
      while (j >= 0 && _sortKey(_order[j]) > key) {
        _order[j + 1] = _order[j];
        j--;
      }
      _order[j + 1] = seat;
    }

    final cell = layout.cell;
    for (var i = 0; i < n; i++) {
      final seat = _order[i];
      final color = controller.seatColors[seat];
      final shades = palette.shades(color);
      final m = controller.motionOf(seat);
      final grid = controller.debugVisualCenter(seat);
      final scale = controller.visualScale(seat);
      final r = cell * TokenRenderer.cellRadiusFactor * scale;
      final px = layout.toPx(grid);
      final active = m.active;
      final opacity = active ? m.opacity : 1.0;

      if (seat == turnSeat) {
        TokenRenderer.paintGlow(
          canvas,
          center: px.translate(0, r * 0.25),
          radius: r * 1.05,
          color: shades.base,
          strength: 0.85 * opacity,
        );
      }
      if (active && m.trailEnabled) {
        TrailRenderer.paint(
          canvas,
          m.trail,
          trailId: seat < trails.length ? trails[seat] : TrailStyles.none,
          now: controller.now,
          cell: cell,
          origin: layout.gridOrigin,
          color: shades.base,
          opacity: opacity,
        );
      }
      TokenRenderer.paintShadow(
        canvas,
        center: px,
        radius: r,
        palette: palette,
        liftFraction: active ? m.liftFraction : 0,
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
        lift: active ? m.lift * cell : 0,
        opacity: opacity,
        rotation: active ? m.rotation : 0,
      );
    }

    BoardEffectsRenderer.paintAll(
      canvas,
      controller.effects,
      controller.now,
      cell: cell,
      origin: layout.gridOrigin,
      palette: palette,
    );
  }

  @override
  bool shouldRepaint(covariant SnakesTokenPainter oldDelegate) =>
      !identical(oldDelegate.controller, controller) ||
      oldDelegate.revision != revision ||
      oldDelegate.turnSeat != turnSeat ||
      oldDelegate.palette != palette ||
      !listEquals(oldDelegate.skins, skins) ||
      !listEquals(oldDelegate.trails, trails);

  @override
  SemanticsBuilderCallback? get semanticsBuilder {
    if (labels.isEmpty) return null;
    return (Size size) {
      final layout = SnakesBoardLayout.fit(size);
      final nodes = <CustomPainterSemantics>[];
      for (
        var seat = 0;
        seat < labels.length && seat < controller.seatCount;
        seat++
      ) {
        final center = layout.toPx(controller.restingCenter(seat));
        final r =
            layout.cell *
            TokenRenderer.cellRadiusFactor *
            controller.restingScale(seat);
        nodes.add(
          CustomPainterSemantics(
            key: ValueKey<String>('snakes-token-$seat'),
            rect: Rect.fromCenter(
              center: center,
              width: r * 2,
              height: r * 2.2,
            ),
            properties: SemanticsProperties(
              label: labels[seat],
              textDirection: semanticsDirection,
            ),
          ),
        );
      }
      return nodes;
    };
  }

  @override
  bool shouldRebuildSemantics(covariant SnakesTokenPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      !listEquals(oldDelegate.labels, labels);
}
