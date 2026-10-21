import 'package:flutter/material.dart';

import '../../../../shared/game_visuals/game_palette.dart';

/// Ludo board cosmetic ids from `docs/cosmetics-catalog.md`.
abstract final class LudoBoardThemes {
  static const classic = 'ludo_board_classic';
  static const midnight = 'ludo_board_midnight';
  static const royal = 'ludo_board_royal';

  static const all = [classic, midnight, royal];

  /// Known id or the starter board.
  static String resolve(String? id) => all.contains(id) ? id! : classic;

  static final Map<int, LudoBoardStyle> _cache = <int, LudoBoardStyle>{};

  /// Resolved colors for [id] on [palette] (cached).
  static LudoBoardStyle style(String? id, GamePalette palette) {
    final resolved = resolve(id);
    final key = Object.hash(resolved, palette);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length > 24) _cache.clear();
    final style = switch (resolved) {
      midnight => LudoBoardStyle._midnight(palette),
      royal => LudoBoardStyle._royal(palette),
      _ => LudoBoardStyle._classic(palette),
    };
    _cache[key] = style;
    return style;
  }
}

/// Surface texture drawn over a Ludo board.
enum LudoBoardTexture { none, marble, damask }

/// Fully resolved colors of one Ludo board theme for one brightness.
@immutable
class LudoBoardStyle {
  const LudoBoardStyle({
    required this.id,
    required this.dark,
    required this.seats,
    required this.frameTop,
    required this.frameBottom,
    required this.frameTrim,
    required this.surface,
    required this.trackCell,
    required this.trackCellEdge,
    required this.gridLine,
    required this.star,
    required this.starEdge,
    required this.basePanel,
    required this.basePanelEdge,
    required this.wellRim,
    this.baseTrim,
    required this.centerEmblem,
    required this.centerEmblemEdge,
    required this.accent,
    required this.texture,
    required this.textureColor,
    required this.cellRadius,
    required this.cellGap,
    required this.shadow,
  });

  /// Theme id (`ludo_board_*`).
  final String id;
  final bool dark;

  /// Seat shades as used on this board (indexed by [SeatColor.index]).
  final List<SeatShades> seats;

  /// Frame gradient (top → bottom) and optional trim (gold/silver lines).
  final Color frameTop;
  final Color frameBottom;
  final Color? frameTrim;

  /// Background visible between cells.
  final Color surface;
  final Color trackCell;
  final Color trackCellEdge;
  final Color gridLine;

  /// Safe-square star fill and edge.
  final Color star;
  final Color starEdge;

  /// Inner panel of each base and its edge.
  final Color basePanel;
  final Color basePanelEdge;

  /// Ring around the token wells (null → seat color).
  final Color? wellRim;

  /// Thin ornamental line inside each base (null = none).
  final Color? baseTrim;

  /// Center medallion.
  final Color centerEmblem;
  final Color centerEmblemEdge;

  /// Decorative accent (arrows, emblem glyph, trims).
  final Color accent;

  final LudoBoardTexture texture;
  final Color textureColor;

  /// Rounded corners of cells (grid units) and the gap between cells.
  final double cellRadius;
  final double cellGap;

  /// Shadow color used for depth (wells, panel, frame).
  final Color shadow;

  SeatShades seat(SeatColor color) => seats[color.index];

  static List<SeatShades> _derive(
    GamePalette p, {
    required bool dark,
    required Color surface,
  }) => [
    for (final c in SeatColor.values)
      SeatShades.derive(p.seat(c), dark: dark, surface: surface),
  ];

  factory LudoBoardStyle._classic(GamePalette p) {
    final dark = p.isDark;
    return LudoBoardStyle(
      id: LudoBoardThemes.classic,
      dark: dark,
      seats: [for (final c in SeatColor.values) p.shades(c)],
      frameTop: dark ? const Color(0xFF232733) : const Color(0xFFF3ECDF),
      frameBottom: dark ? const Color(0xFF15171E) : const Color(0xFFDCCFB8),
      frameTrim: dark ? const Color(0xFF3A4050) : const Color(0xFFC7B796),
      surface: dark ? const Color(0xFF181B22) : const Color(0xFFE4E7EE),
      trackCell: p.trackCell,
      trackCellEdge: dark ? const Color(0xFF323745) : const Color(0xFFD3D8E1),
      gridLine: p.gridLine,
      star: dark ? const Color(0xFF3A4152) : const Color(0xFFEDEFF4),
      starEdge: p.safeMark,
      basePanel: dark ? const Color(0xFF1F222B) : const Color(0xFFFFFFFF),
      basePanelEdge: dark ? const Color(0xFF0F1116) : const Color(0x24000000),
      wellRim: null,
      centerEmblem: dark ? const Color(0xFF232733) : const Color(0xFFFFFFFF),
      centerEmblemEdge: p.gold,
      accent: p.gold,
      texture: LudoBoardTexture.none,
      textureColor: Colors.transparent,
      cellRadius: 0.14,
      cellGap: 0.05,
      shadow: dark ? const Color(0x99000000) : const Color(0x33000000),
    );
  }

  factory LudoBoardStyle._midnight(GamePalette p) {
    // Midnight Marble is a dark board in both app themes; it uses the
    // luminous seat tones so colors glow against the stone.
    const cell = Color(0xFF1B2136);
    final seats = _derive(
      GamePalette.dark.copyWith(
        red: Color.lerp(p.red, GamePalette.dark.red, p.isDark ? 0 : 0.6),
        green: Color.lerp(p.green, GamePalette.dark.green, p.isDark ? 0 : 0.6),
        yellow: Color.lerp(
          p.yellow,
          GamePalette.dark.yellow,
          p.isDark ? 0 : 0.6,
        ),
        blue: Color.lerp(p.blue, GamePalette.dark.blue, p.isDark ? 0 : 0.6),
      ),
      dark: true,
      surface: cell,
    );
    // Jewel tones: the luminous seat color as the highlight, deepened body.
    final jewels = [
      for (final s in seats)
        SeatShades(
          base: Color.lerp(s.base, const Color(0xFF05060C), 0.22)!,
          tint: Color.lerp(s.tint, const Color(0xFF05060C), 0.25)!,
          soft: s.base,
          shade: Color.lerp(s.shade, const Color(0xFF05060C), 0.38)!,
          deep: Color.lerp(s.deep, const Color(0xFF05060C), 0.45)!,
          outline: s.outline,
          glow: s.glow,
          onColor: s.onColor,
        ),
    ];
    return LudoBoardStyle(
      id: LudoBoardThemes.midnight,
      dark: true,
      seats: jewels,
      frameTop: const Color(0xFF1A1F30),
      frameBottom: const Color(0xFF070912),
      frameTrim: const Color(0xFFA9B4CC),
      surface: const Color(0xFF0C1020),
      trackCell: cell,
      trackCellEdge: const Color(0xFF2C3554),
      gridLine: const Color(0xFF2C3554),
      star: const Color(0xFF2A3250),
      starEdge: const Color(0xFFC9D1E3),
      basePanel: const Color(0xFF111628),
      basePanelEdge: const Color(0xFF050710),
      wellRim: const Color(0xFFC9D1E3),
      baseTrim: const Color(0xFFC9D1E3),
      centerEmblem: const Color(0xFF111628),
      centerEmblemEdge: const Color(0xFFC9D1E3),
      accent: const Color(0xFFC9D1E3),
      texture: LudoBoardTexture.marble,
      textureColor: const Color(0xFFDDE4F5),
      cellRadius: 0.12,
      cellGap: 0.06,
      shadow: const Color(0xB3000000),
    );
  }

  factory LudoBoardStyle._royal(GamePalette p) {
    final dark = p.isDark;
    final cell = dark ? const Color(0xFF2E2438) : const Color(0xFFFFF8EA);
    return LudoBoardStyle(
      id: LudoBoardThemes.royal,
      dark: dark,
      seats: _derive(p, dark: dark, surface: cell),
      frameTop: dark ? const Color(0xFF3A1F5D) : const Color(0xFF4A2775),
      frameBottom: dark ? const Color(0xFF170A29) : const Color(0xFF2A1247),
      frameTrim: const Color(0xFFE2B33C),
      surface: dark ? const Color(0xFF1E1528) : const Color(0xFFE9DCC0),
      trackCell: cell,
      trackCellEdge: dark ? const Color(0xFF5B4A2A) : const Color(0xFFD9C48F),
      gridLine: dark ? const Color(0xFF5B4A2A) : const Color(0xFFD9C48F),
      star: dark ? const Color(0xFF3C2F45) : const Color(0xFFFFF1CC),
      starEdge: const Color(0xFFC99A1E),
      basePanel: dark ? const Color(0xFF261C30) : const Color(0xFFFFFAF0),
      basePanelEdge: const Color(0xFFC99A1E),
      wellRim: const Color(0xFFE2B33C),
      baseTrim: const Color(0xFFE2B33C),
      centerEmblem: dark ? const Color(0xFF2A1247) : const Color(0xFF4A2775),
      centerEmblemEdge: const Color(0xFFE2B33C),
      accent: const Color(0xFFE2B33C),
      texture: LudoBoardTexture.damask,
      textureColor: const Color(0xFFC99A1E),
      cellRadius: 0.1,
      cellGap: 0.05,
      shadow: dark ? const Color(0x99000000) : const Color(0x40301A00),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LudoBoardStyle &&
          other.id == id &&
          other.dark == dark &&
          other.trackCell == trackCell &&
          other.surface == surface &&
          other.frameTop == frameTop &&
          other.seats[0].base == seats[0].base &&
          other.seats[1].base == seats[1].base &&
          other.seats[2].base == seats[2].base &&
          other.seats[3].base == seats[3].base;

  @override
  int get hashCode => Object.hash(
    id,
    dark,
    trackCell,
    surface,
    frameTop,
    seats[0].base,
    seats[1].base,
    seats[2].base,
    seats[3].base,
  );
}
