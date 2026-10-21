import 'package:flutter/material.dart';

import 'seat_color.dart';

export 'seat_color.dart';

/// Derived tones for one seat color. All boards, tokens and effects read
/// seat colors through these shades so light and dark themes stay coherent.
@immutable
class SeatShades {
  const SeatShades({
    required this.base,
    required this.tint,
    required this.soft,
    required this.shade,
    required this.deep,
    required this.outline,
    required this.glow,
    required this.onColor,
  });

  /// Derives the full shade set from a base color.
  ///
  /// [surface] is the board surface the tint is mixed toward (white-ish in
  /// light mode, a dark slate in dark mode).
  factory SeatShades.derive(Color base, {required bool dark, Color? surface}) {
    final hsl = HSLColor.fromColor(base);
    Color withLightness(double delta, {double satDelta = 0}) => hsl
        .withLightness((hsl.lightness + delta).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + satDelta).clamp(0.0, 1.0))
        .toColor();
    final mixSurface =
        surface ?? (dark ? const Color(0xFF1B1E26) : const Color(0xFFFFFFFF));
    // Yellow needs dark content for contrast; the others take white.
    final lum = base.computeLuminance();
    return SeatShades(
      base: base,
      tint: Color.lerp(base, mixSurface, dark ? 0.62 : 0.74)!,
      soft: withLightness(dark ? 0.10 : 0.13, satDelta: -0.02),
      shade: withLightness(-0.12),
      deep: withLightness(-0.24, satDelta: -0.05),
      outline: dark
          ? Color.lerp(base, Colors.black, 0.62)!
          : Color.lerp(base, const Color(0xFF14161C), 0.58)!,
      glow: base.withValues(alpha: dark ? 0.62 : 0.5),
      onColor: lum > 0.45 ? const Color(0xFF3A2A00) : Colors.white,
    );
  }

  /// The seat color itself.
  final Color base;

  /// Very pale (light mode) / muted (dark mode) tint for large areas such as
  /// base panels and home columns behind tokens.
  final Color tint;

  /// Lighter variant used for gradient highlights.
  final Color soft;

  /// Darker variant used for gradient shadows.
  final Color shade;

  /// Darkest variant (rims, deep shadows).
  final Color deep;

  /// Outline used around tokens/shapes so they read on any surface.
  final Color outline;

  /// Semi-transparent glow color (selection, turn emphasis, effects).
  final Color glow;

  /// Foreground color drawn on top of [base] (arrows, pips, glyphs).
  final Color onColor;

  static SeatShades lerp(SeatShades a, SeatShades b, double t) => SeatShades(
    base: Color.lerp(a.base, b.base, t)!,
    tint: Color.lerp(a.tint, b.tint, t)!,
    soft: Color.lerp(a.soft, b.soft, t)!,
    shade: Color.lerp(a.shade, b.shade, t)!,
    deep: Color.lerp(a.deep, b.deep, t)!,
    outline: Color.lerp(a.outline, b.outline, t)!,
    glow: Color.lerp(a.glow, b.glow, t)!,
    onColor: Color.lerp(a.onColor, b.onColor, t)!,
  );
}

/// Theme extension carrying the game-board colors.
///
/// Register it on the app [ThemeData] (`extensions: [GamePalette.light]`) to
/// customise; when it is not registered [GamePalette.of] falls back to the
/// built-in [light] / [dark] palettes by the ambient theme brightness.
@immutable
class GamePalette extends ThemeExtension<GamePalette> {
  GamePalette({
    required this.brightness,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.boardFrame,
    required this.boardSurface,
    required this.trackCell,
    required this.gridLine,
    required this.safeMark,
    required this.ink,
    required this.inkMuted,
    required this.tokenOutline,
    required this.tokenShadow,
    required this.highlight,
    required this.gold,
    required this.goldDeep,
    List<SeatShades>? shades,
  }) : _shades =
           shades ??
           [
             for (final c in [red, green, yellow, blue])
               SeatShades.derive(
                 c,
                 dark: brightness == Brightness.dark,
                 surface: trackCell,
               ),
           ];

  /// Built-in light palette.
  static final GamePalette light = GamePalette(
    brightness: Brightness.light,
    red: const Color(0xFFE5484D),
    green: const Color(0xFF30A46C),
    yellow: const Color(0xFFF5B800),
    blue: const Color(0xFF3E63DD),
    boardFrame: const Color(0xFFE9E1D3),
    boardSurface: const Color(0xFFF7F4EE),
    trackCell: const Color(0xFFFFFFFF),
    gridLine: const Color(0xFFC9CFD9),
    safeMark: const Color(0xFF8E97A6),
    ink: const Color(0xFF262B36),
    inkMuted: const Color(0xFF6B7383),
    tokenOutline: const Color(0xFF1A1E28),
    tokenShadow: const Color(0x47000000),
    highlight: const Color(0xFFFFC23D),
    gold: const Color(0xFFE2B33C),
    goldDeep: const Color(0xFF9C6F12),
  );

  /// Built-in dark palette.
  static final GamePalette dark = GamePalette(
    brightness: Brightness.dark,
    red: const Color(0xFFFF6369),
    green: const Color(0xFF3DD68C),
    yellow: const Color(0xFFFFD43B),
    blue: const Color(0xFF6E8BFF),
    boardFrame: const Color(0xFF14161D),
    boardSurface: const Color(0xFF1B1E26),
    trackCell: const Color(0xFF272B36),
    gridLine: const Color(0xFF3B4152),
    safeMark: const Color(0xFF8F98AB),
    ink: const Color(0xFFEFF2F7),
    inkMuted: const Color(0xFFA2AABA),
    tokenOutline: const Color(0xFF0A0B10),
    tokenShadow: const Color(0x80000000),
    highlight: const Color(0xFFFFD45C),
    gold: const Color(0xFFF0C55A),
    goldDeep: const Color(0xFFA77A1C),
  );

  /// The registered extension, or the built-in palette for the theme's
  /// brightness.
  static GamePalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<GamePalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  final Brightness brightness;
  final Color red;
  final Color green;
  final Color yellow;
  final Color blue;

  /// Outer frame around boards.
  final Color boardFrame;

  /// Board background behind cells.
  final Color boardSurface;

  /// Plain track cell fill.
  final Color trackCell;

  /// Thin grid lines between cells.
  final Color gridLine;

  /// Star / safe-square markings.
  final Color safeMark;

  /// Text (square numbers, badges).
  final Color ink;
  final Color inkMuted;

  /// Contrast outline around tokens.
  final Color tokenOutline;

  /// Drop shadow under tokens and dice.
  final Color tokenShadow;

  /// Legal-move ring / interactive highlight.
  final Color highlight;

  /// Gold accents (royal trims, crown, finish square).
  final Color gold;
  final Color goldDeep;

  final List<SeatShades> _shades;

  bool get isDark => brightness == Brightness.dark;

  /// The base color of [color].
  Color seat(SeatColor color) => _shades[color.index].base;

  /// All derived shades of [color].
  SeatShades shades(SeatColor color) => _shades[color.index];

  @override
  GamePalette copyWith({
    Brightness? brightness,
    Color? red,
    Color? green,
    Color? yellow,
    Color? blue,
    Color? boardFrame,
    Color? boardSurface,
    Color? trackCell,
    Color? gridLine,
    Color? safeMark,
    Color? ink,
    Color? inkMuted,
    Color? tokenOutline,
    Color? tokenShadow,
    Color? highlight,
    Color? gold,
    Color? goldDeep,
  }) {
    return GamePalette(
      brightness: brightness ?? this.brightness,
      red: red ?? this.red,
      green: green ?? this.green,
      yellow: yellow ?? this.yellow,
      blue: blue ?? this.blue,
      boardFrame: boardFrame ?? this.boardFrame,
      boardSurface: boardSurface ?? this.boardSurface,
      trackCell: trackCell ?? this.trackCell,
      gridLine: gridLine ?? this.gridLine,
      safeMark: safeMark ?? this.safeMark,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      tokenOutline: tokenOutline ?? this.tokenOutline,
      tokenShadow: tokenShadow ?? this.tokenShadow,
      highlight: highlight ?? this.highlight,
      gold: gold ?? this.gold,
      goldDeep: goldDeep ?? this.goldDeep,
    );
  }

  @override
  GamePalette lerp(covariant ThemeExtension<GamePalette>? other, double t) {
    if (other is! GamePalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return GamePalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      red: l(red, other.red),
      green: l(green, other.green),
      yellow: l(yellow, other.yellow),
      blue: l(blue, other.blue),
      boardFrame: l(boardFrame, other.boardFrame),
      boardSurface: l(boardSurface, other.boardSurface),
      trackCell: l(trackCell, other.trackCell),
      gridLine: l(gridLine, other.gridLine),
      safeMark: l(safeMark, other.safeMark),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      tokenOutline: l(tokenOutline, other.tokenOutline),
      tokenShadow: l(tokenShadow, other.tokenShadow),
      highlight: l(highlight, other.highlight),
      gold: l(gold, other.gold),
      goldDeep: l(goldDeep, other.goldDeep),
      shades: [
        for (var i = 0; i < 4; i++)
          SeatShades.lerp(_shades[i], other._shades[i], t),
      ],
    );
  }

  /// Stable identity for cache keys (painters cache pictures per palette).
  int get cacheKey => Object.hash(
    brightness,
    red,
    green,
    yellow,
    blue,
    trackCell,
    boardSurface,
    tokenOutline,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GamePalette &&
          other.brightness == brightness &&
          other.red == red &&
          other.green == green &&
          other.yellow == yellow &&
          other.blue == blue &&
          other.boardFrame == boardFrame &&
          other.boardSurface == boardSurface &&
          other.trackCell == trackCell &&
          other.gridLine == gridLine &&
          other.safeMark == safeMark &&
          other.ink == ink &&
          other.inkMuted == inkMuted &&
          other.tokenOutline == tokenOutline &&
          other.tokenShadow == tokenShadow &&
          other.highlight == highlight &&
          other.gold == gold &&
          other.goldDeep == goldDeep;

  @override
  int get hashCode => Object.hash(
    brightness,
    red,
    green,
    yellow,
    blue,
    boardFrame,
    boardSurface,
    trackCell,
    gridLine,
    safeMark,
    ink,
    inkMuted,
    tokenOutline,
    tokenShadow,
    highlight,
    gold,
    goldDeep,
  );
}
