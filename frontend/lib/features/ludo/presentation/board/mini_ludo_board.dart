import 'package:flutter/material.dart';

import '../../../../shared/game_visuals/game_palette.dart';
import '../../../../shared/game_visuals/tokens/token_renderer.dart';
import 'ludo_board.dart' show kLudoTokenRadius;
import 'ludo_board_painter.dart';
import 'ludo_board_theme.dart';
import 'ludo_geometry.dart';

/// A static, cheap Ludo board illustration for home cards and previews.
///
/// Square; sizes itself to the incoming constraints (or [size]). No
/// semantics (decorative) and no tickers.
class MiniLudoBoard extends StatelessWidget {
  const MiniLudoBoard({
    super.key,
    this.boardTheme = LudoBoardThemes.classic,
    this.showTokens = true,
    this.tokenSkin = TokenSkins.classic,
    this.size,
  });

  /// `ludo_board_*` id; unknown ids fall back to the classic look.
  final String boardTheme;

  /// Draw a few decorative tokens.
  final bool showTokens;

  /// Skin used for the decorative tokens.
  final String tokenSkin;

  /// Optional fixed side length.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of(context);
    final style = LudoBoardThemes.style(boardTheme, palette);
    Widget board = AspectRatio(
      aspectRatio: LudoBoardLayout.aspectRatio,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: LudoBoardPainter(style: style, detailed: false),
          foregroundPainter: showTokens
              ? _MiniTokensPainter(
                  palette: palette,
                  skin: TokenSkins.resolve(tokenSkin),
                )
              : null,
          isComplex: true,
          willChange: false,
        ),
      ),
    );
    if (size != null) board = SizedBox.square(dimension: size, child: board);
    return ExcludeSemantics(
      child: Directionality(textDirection: TextDirection.ltr, child: board),
    );
  }
}

class _MiniTokensPainter extends CustomPainter {
  _MiniTokensPainter({required this.palette, required this.skin});

  final GamePalette palette;
  final String skin;

  static const _tokens = <(SeatColor, int, int)>[
    (SeatColor.red, 4, 0),
    (SeatColor.red, -1, 1),
    (SeatColor.green, 52, 0),
    (SeatColor.green, -1, 2),
    (SeatColor.yellow, 9, 0),
    (SeatColor.yellow, -1, 3),
    (SeatColor.blue, 30, 0),
    (SeatColor.blue, -1, 0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final layout = LudoBoardLayout.fit(size);
    final r = layout.cell * kLudoTokenRadius;
    for (final (color, progress, token) in _tokens) {
      final spot = LudoGeometry.cellFor(
        color,
        progress,
        tokenIndex: token,
        tokensPerPlayer: 4,
      );
      final px = layout.toPx(spot.center);
      TokenRenderer.paintShadow(
        canvas,
        center: px,
        radius: r,
        palette: palette,
      );
      TokenRenderer.paintToken(
        canvas,
        center: px,
        radius: r,
        skin: skin,
        color: color,
        palette: palette,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniTokensPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.skin != skin;
}
