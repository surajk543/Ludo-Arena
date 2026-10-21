import 'package:flutter/material.dart';

import '../../../../shared/game_visuals/game_palette.dart';
import '../../../../shared/game_visuals/tokens/token_renderer.dart';
import 'snakes_board_painter.dart';
import 'snakes_board_theme.dart';
import 'snakes_geometry.dart';

/// A static, cheap Snakes & Ladders illustration for home cards and the
/// Collection Room (no numbers, no animation, no semantics).
class MiniSnakesBoard extends StatelessWidget {
  const MiniSnakesBoard({
    super.key,
    this.boardTheme = SnakesBoardThemes.classic,
    this.showTokens = true,
  });

  /// `snakes_board_*` cosmetic id; unknown ids fall back to classic.
  final String boardTheme;

  /// Draw a few decorative tokens.
  final bool showTokens;

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of(context);
    final style = SnakesBoardThemes.style(boardTheme, palette);
    return ExcludeSemantics(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: AspectRatio(
          aspectRatio: SnakesGeometry.aspectRatio,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: SnakesBoardPainter(style: style, detailed: false),
              foregroundPainter: showTokens
                  ? _MiniTokensPainter(palette: palette)
                  : null,
              isComplex: true,
              willChange: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTokensPainter extends CustomPainter {
  _MiniTokensPainter({required this.palette});

  final GamePalette palette;

  static const _tokens = [
    (SeatColor.yellow, 8),
    (SeatColor.red, 23),
    (SeatColor.blue, 57),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final layout = SnakesBoardLayout.fit(size);
    final r = layout.cell * TokenRenderer.cellRadiusFactor;
    for (final (color, square) in _tokens) {
      final c = layout.toPx(SnakesGeometry.centerOf(square));
      TokenRenderer.paintShadow(canvas, center: c, radius: r, palette: palette);
      TokenRenderer.paintToken(
        canvas,
        center: c,
        radius: r,
        skin: TokenSkins.classic,
        color: color,
        palette: palette,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniTokensPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
