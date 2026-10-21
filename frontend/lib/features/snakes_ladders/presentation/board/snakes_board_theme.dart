import 'package:flutter/material.dart';

import '../../../../shared/game_visuals/game_palette.dart';

/// Snakes board cosmetic ids from `docs/cosmetics-catalog.md`.
abstract final class SnakesBoardThemes {
  static const classic = 'snakes_board_classic';
  static const jungle = 'snakes_board_jungle';
  static const candy = 'snakes_board_candy';

  static const all = [classic, jungle, candy];

  /// Known id or the starter board.
  static String resolve(String? id) => all.contains(id) ? id! : classic;

  static final Map<int, SnakesBoardStyle> _cache = <int, SnakesBoardStyle>{};

  /// Resolved colors for [id] on [palette] (light or dark).
  static SnakesBoardStyle style(String? id, GamePalette palette) {
    final resolved = resolve(id);
    final key = Object.hash(resolved, palette.cacheKey, palette.gold);
    return _cache.putIfAbsent(key, () {
      if (_cache.length > 24) _cache.clear();
      switch (resolved) {
        case jungle:
          return _jungle(palette);
        case candy:
          return _candy(palette);
        default:
          return _classic(palette);
      }
    });
  }

  static SnakesBoardStyle _classic(GamePalette p) {
    final dark = p.isDark;
    return SnakesBoardStyle(
      id: classic,
      brightness: p.brightness,
      paletteKey: p.cacheKey,
      tiles: TileKind.flat,
      frameTop: dark ? const Color(0xFF1C4A31) : const Color(0xFF3E9A62),
      frameBottom: dark ? const Color(0xFF0F2B1C) : const Color(0xFF2A7449),
      frameEdge: dark ? const Color(0xFF07170E) : const Color(0xFF1C5233),
      frameTrim: dark ? const Color(0xFFC9B37A) : const Color(0xFFF6E7B8),
      mortar: dark ? const Color(0xFF1A1D22) : const Color(0xFFE9E2CF),
      cellBase: dark ? const Color(0xFF2A2E36) : const Color(0xFFFFF9EA),
      cellColors: dark
          ? const [
              Color(0xFF5B4530),
              Color(0xFF2E4C36),
              Color(0xFF2E4060),
              Color(0xFF55354A),
              Color(0xFF575026),
            ]
          : const [
              Color(0xFFFFD6A5),
              Color(0xFFC9EFC1),
              Color(0xFFC6DEFF),
              Color(0xFFF9C6D6),
              Color(0xFFFFEFA0),
            ],
      gridLine: dark ? const Color(0x33FFFFFF) : const Color(0x1F3A2A10),
      numberInk: dark ? const Color(0xFFF3EFE4) : const Color(0xFF3A372F),
      numberHalo: dark ? const Color(0xCC14161B) : const Color(0xCCFFFFFF),
      decorA: const Color(0x00000000),
      decorB: const Color(0x00000000),
      finishLight: dark ? const Color(0xFFF2CF62) : const Color(0xFFFFE58A),
      finishDeep: dark ? const Color(0xFFB98A1B) : const Color(0xFFF2B21C),
      finishInk: const Color(0xFF5A3900),
      padFill: dark ? const Color(0xFF26402F) : const Color(0xFFFFF4D8),
      padEdge: dark ? const Color(0xFF8FB89C) : const Color(0xFFC9A04F),
      arrow: dark ? const Color(0xFFF2CF62) : const Color(0xFFE5484D),
      snakes: const [
        SnakeSkin(
          body: Color(0xFF3BAA5C),
          highlight: Color(0xFFA6E59A),
          shade: Color(0xFF1E6E39),
          pattern: Color(0xFF1C5E31),
          outline: Color(0xFF123F22),
          kind: SnakePattern.bands,
        ),
        SnakeSkin(
          body: Color(0xFFF08A24),
          highlight: Color(0xFFFFD39A),
          shade: Color(0xFFB45A0E),
          pattern: Color(0xFF8E3F05),
          outline: Color(0xFF5E2A04),
          kind: SnakePattern.diamonds,
        ),
        SnakeSkin(
          body: Color(0xFF8E5CD9),
          highlight: Color(0xFFD9C3FF),
          shade: Color(0xFF5E36A3),
          pattern: Color(0xFFF7E26B),
          outline: Color(0xFF3B1F6E),
          kind: SnakePattern.spots,
        ),
        SnakeSkin(
          body: Color(0xFFE5484D),
          highlight: Color(0xFFFFB8B4),
          shade: Color(0xFFA42A2F),
          pattern: Color(0xFFFFE3A3),
          outline: Color(0xFF6E161A),
          kind: SnakePattern.bands,
        ),
        SnakeSkin(
          body: Color(0xFF1FA7A0),
          highlight: Color(0xFF9FEAE4),
          shade: Color(0xFF0E6D68),
          pattern: Color(0xFF0B4F4B),
          outline: Color(0xFF073835),
          kind: SnakePattern.diamonds,
        ),
      ],
      ladder: const LadderStyle(
        kind: LadderKind.wood,
        railDark: Color(0xFF6E4119),
        railMid: Color(0xFFB9783F),
        railLight: Color(0xFFEDC08A),
        rungDark: Color(0xFF6E4119),
        rungMid: Color(0xFFA7692F),
        rungLight: Color(0xFFE2AE74),
        accent: Color(0xFF6E4119),
      ),
    );
  }

  static SnakesBoardStyle _jungle(GamePalette p) {
    final dark = p.isDark;
    return SnakesBoardStyle(
      id: jungle,
      brightness: p.brightness,
      paletteKey: p.cacheKey,
      tiles: TileKind.stone,
      frameTop: dark ? const Color(0xFF3A3A30) : const Color(0xFF7A745C),
      frameBottom: dark ? const Color(0xFF23241D) : const Color(0xFF59553F),
      frameEdge: dark ? const Color(0xFF121310) : const Color(0xFF38351F),
      frameTrim: dark ? const Color(0xFF8C8259) : const Color(0xFFC9BC88),
      mortar: dark ? const Color(0xFF16180F) : const Color(0xFF4B4A36),
      cellBase: dark ? const Color(0xFF3D4034) : const Color(0xFFD3CCAA),
      cellColors: dark
          ? const [Color(0xFF34392B), Color(0xFF41432F), Color(0xFF2F3B2A)]
          : const [Color(0xFFBEBB97), Color(0xFFC8BE96), Color(0xFFA9B486)],
      gridLine: const Color(0x00000000),
      numberInk: dark ? const Color(0xFFEDE7CC) : const Color(0xFF2E2A18),
      numberHalo: dark ? const Color(0xCC1A1C14) : const Color(0xB3F4EED6),
      decorA: dark ? const Color(0xFF3F6A2E) : const Color(0xFF5E8F3E),
      decorB: dark ? const Color(0x66000000) : const Color(0x55433C22),
      finishLight: dark ? const Color(0xFFE8C463) : const Color(0xFFF4D77E),
      finishDeep: dark ? const Color(0xFFA27419) : const Color(0xFFC38E26),
      finishInk: const Color(0xFF3F2700),
      padFill: dark ? const Color(0xFF4A4A3B) : const Color(0xFFCFC6A0),
      padEdge: dark ? const Color(0xFF9C9370) : const Color(0xFF6E6748),
      arrow: dark ? const Color(0xFF8CCB5E) : const Color(0xFF3F7A2A),
      snakes: const [
        SnakeSkin(
          body: Color(0xFF1E9E6A),
          highlight: Color(0xFF9BE3B9),
          shade: Color(0xFF0F6642),
          pattern: Color(0xFF0B3B26),
          outline: Color(0xFF082C1C),
          kind: SnakePattern.bands,
        ),
        SnakeSkin(
          body: Color(0xFFE2B714),
          highlight: Color(0xFFFFE680),
          shade: Color(0xFFA27F05),
          pattern: Color(0xFF262421),
          outline: Color(0xFF3B2F05),
          kind: SnakePattern.bands,
        ),
        SnakeSkin(
          body: Color(0xFF9A6533),
          highlight: Color(0xFFD9AE7E),
          shade: Color(0xFF64401C),
          pattern: Color(0xFF3B240F),
          outline: Color(0xFF2E1B0A),
          kind: SnakePattern.spots,
        ),
        SnakeSkin(
          body: Color(0xFF6CBF3A),
          highlight: Color(0xFFC6EE97),
          shade: Color(0xFF3F7F1C),
          pattern: Color(0xFF2B5A12),
          outline: Color(0xFF1C3D0B),
          kind: SnakePattern.diamonds,
        ),
      ],
      ladder: const LadderStyle(
        kind: LadderKind.bamboo,
        railDark: Color(0xFF6B6E1E),
        railMid: Color(0xFFC2C451),
        railLight: Color(0xFFF0F2A8),
        rungDark: Color(0xFF6B6E1E),
        rungMid: Color(0xFFADB040),
        rungLight: Color(0xFFE2E58C),
        accent: Color(0xFF8B6A3E),
      ),
    );
  }

  static SnakesBoardStyle _candy(GamePalette p) {
    final dark = p.isDark;
    return SnakesBoardStyle(
      id: candy,
      brightness: p.brightness,
      paletteKey: p.cacheKey,
      tiles: TileKind.candy,
      frameTop: dark ? const Color(0xFF8A3462) : const Color(0xFFF58DB8),
      frameBottom: dark ? const Color(0xFF5E1F42) : const Color(0xFFE5679C),
      frameEdge: dark ? const Color(0xFF3A1129) : const Color(0xFFB8436F),
      frameTrim: dark ? const Color(0xFFF6D9E7) : const Color(0xFFFFFFFF),
      mortar: dark ? const Color(0xFF2A1E2B) : const Color(0xFFFFE8F2),
      cellBase: dark ? const Color(0xFF332838) : const Color(0xFFFFF7FB),
      cellColors: dark
          ? const [
              Color(0xFF5E2F49),
              Color(0xFF25493F),
              Color(0xFF524B27),
              Color(0xFF41356A),
              Color(0xFF23445C),
            ]
          : const [
              Color(0xFFFFC2DC),
              Color(0xFFC3F1E1),
              Color(0xFFFFF0A3),
              Color(0xFFDCCBFF),
              Color(0xFFBDE5FF),
            ],
      gridLine: const Color(0x00000000),
      numberInk: dark ? const Color(0xFFFFF0F7) : const Color(0xFF5A2647),
      numberHalo: dark ? const Color(0xCC2A1E2B) : const Color(0xCCFFFFFF),
      decorA: const Color(0xFFFF6FA5),
      decorB: const Color(0xFF41C9E2),
      finishLight: dark ? const Color(0xFFF7D87A) : const Color(0xFFFFE89A),
      finishDeep: dark ? const Color(0xFFD08A2C) : const Color(0xFFFFB547),
      finishInk: const Color(0xFF6A2F00),
      padFill: dark ? const Color(0xFF4A2A40) : const Color(0xFFFFF4FA),
      padEdge: dark ? const Color(0xFFE9A9C8) : const Color(0xFFE5679C),
      arrow: dark ? const Color(0xFFFFC93C) : const Color(0xFF8E5CD9),
      snakes: const [
        SnakeSkin(
          body: Color(0xFFFF6FA5),
          highlight: Color(0xFFFFC9DE),
          shade: Color(0xFFC93D74),
          pattern: Color(0xFFFFFFFF),
          outline: Color(0xFF8A1F4B),
          kind: SnakePattern.candyStripes,
        ),
        SnakeSkin(
          body: Color(0xFF3FD1A2),
          highlight: Color(0xFFB9F5E1),
          shade: Color(0xFF1E9671),
          pattern: Color(0xFFFFFFFF),
          outline: Color(0xFF0F5E46),
          kind: SnakePattern.candyStripes,
        ),
        SnakeSkin(
          body: Color(0xFFFFC93C),
          highlight: Color(0xFFFFF0B3),
          shade: Color(0xFFD99A0B),
          pattern: Color(0xFFFF7A3D),
          outline: Color(0xFF8A5A00),
          kind: SnakePattern.candyStripes,
        ),
        SnakeSkin(
          body: Color(0xFFA56BFF),
          highlight: Color(0xFFE2D0FF),
          shade: Color(0xFF6F3DD1),
          pattern: Color(0xFFFFFFFF),
          outline: Color(0xFF41208A),
          kind: SnakePattern.candyStripes,
        ),
      ],
      ladder: const LadderStyle(
        kind: LadderKind.candyCane,
        railDark: Color(0xFFC9B8BF),
        railMid: Color(0xFFFFFFFF),
        railLight: Color(0xFFFFFFFF),
        rungDark: Color(0xFF3E1F10),
        rungMid: Color(0xFF6E3B22),
        rungLight: Color(0xFFA9694A),
        accent: Color(0xFFE5484D),
      ),
    );
  }
}

/// How cells are drawn.
enum TileKind {
  /// Edge-to-edge colorful checker with thin grid lines.
  flat,

  /// Carved stone tiles with mortar gaps, moss and cracks.
  stone,

  /// Rounded candy tiles on frosting with sprinkles.
  candy,
}

/// Snake body pattern.
enum SnakePattern { bands, diamonds, spots, candyStripes }

/// Ladder construction.
enum LadderKind { wood, bamboo, candyCane }

/// Colors of one snake.
@immutable
class SnakeSkin {
  const SnakeSkin({
    required this.body,
    required this.highlight,
    required this.shade,
    required this.pattern,
    required this.outline,
    required this.kind,
  });

  final Color body;
  final Color highlight;
  final Color shade;
  final Color pattern;
  final Color outline;
  final SnakePattern kind;
}

/// Colors and construction of ladders.
@immutable
class LadderStyle {
  const LadderStyle({
    required this.kind,
    required this.railDark,
    required this.railMid,
    required this.railLight,
    required this.rungDark,
    required this.rungMid,
    required this.rungLight,
    required this.accent,
  });

  final LadderKind kind;
  final Color railDark;
  final Color railMid;
  final Color railLight;
  final Color rungDark;
  final Color rungMid;
  final Color rungLight;

  /// Stripes (candy cane), lashing twine (bamboo) or grain (wood).
  final Color accent;
}

/// A fully resolved Snakes board look for one theme and brightness.
@immutable
class SnakesBoardStyle {
  const SnakesBoardStyle({
    required this.id,
    required this.brightness,
    required this.paletteKey,
    required this.tiles,
    required this.frameTop,
    required this.frameBottom,
    required this.frameEdge,
    required this.frameTrim,
    required this.mortar,
    required this.cellBase,
    required this.cellColors,
    required this.gridLine,
    required this.numberInk,
    required this.numberHalo,
    required this.decorA,
    required this.decorB,
    required this.finishLight,
    required this.finishDeep,
    required this.finishInk,
    required this.padFill,
    required this.padEdge,
    required this.arrow,
    required this.snakes,
    required this.ladder,
  });

  /// Catalog id.
  final String id;
  final Brightness brightness;
  final int paletteKey;
  final TileKind tiles;

  final Color frameTop;
  final Color frameBottom;
  final Color frameEdge;
  final Color frameTrim;

  /// Background behind tiles (gaps / mortar / frosting).
  final Color mortar;

  /// Even (plain) cells.
  final Color cellBase;

  /// Colored cells, cycled by row (flat/candy) or by hash (stone).
  final List<Color> cellColors;
  final Color gridLine;
  final Color numberInk;
  final Color numberHalo;

  /// Theme decoration colors (moss / sprinkles).
  final Color decorA;
  final Color decorB;

  final Color finishLight;
  final Color finishDeep;
  final Color finishInk;

  final Color padFill;
  final Color padEdge;
  final Color arrow;

  /// Snake skins, cycled by snake index.
  final List<SnakeSkin> snakes;
  final LadderStyle ladder;

  bool get isDark => brightness == Brightness.dark;

  /// Fill of the cell at ([col], [row]).
  Color cellColor(int col, int row) {
    switch (tiles) {
      case TileKind.stone:
        final h = (col * 73 + row * 151 + col * row * 7) % 11;
        return h < 4 ? cellBase : cellColors[h % cellColors.length];
      case TileKind.flat:
      case TileKind.candy:
        if ((col + row).isEven) return cellBase;
        return cellColors[row % cellColors.length];
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SnakesBoardStyle &&
      other.id == id &&
      other.brightness == brightness &&
      other.paletteKey == paletteKey;

  @override
  int get hashCode => Object.hash(id, brightness, paletteKey);
}
