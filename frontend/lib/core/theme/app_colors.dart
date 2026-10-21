import 'package:flutter/material.dart';

import 'seat_colors.dart';
import 'tokens.dart';

/// Raw brand palette. Prefer the semantic [AppColors] extension in widgets;
/// these are exposed for painters that need a fixed brand hue.
abstract final class BrandPalette {
  // Royal indigo / violet ramp.
  static const Color royal950 = Color(0xFF0B0718);
  static const Color royal900 = Color(0xFF140D2B);
  static const Color royal850 = Color(0xFF1B1238);
  static const Color royal800 = Color(0xFF231846);
  static const Color royal700 = Color(0xFF30205F);
  static const Color royal600 = Color(0xFF412B86);
  static const Color royal500 = Color(0xFF5B3FD0);
  static const Color royal400 = Color(0xFF7A5CF0);
  static const Color royal300 = Color(0xFFA48BFF);
  static const Color royal200 = Color(0xFFCABCFF);
  static const Color royal100 = Color(0xFFECE6FF);
  static const Color royal50 = Color(0xFFF7F4FF);

  // Warm gold ramp.
  static const Color gold800 = Color(0xFF7A520B);
  static const Color gold700 = Color(0xFFA9740F);
  static const Color gold600 = Color(0xFFD4961E);
  static const Color gold500 = Color(0xFFF2B635);
  static const Color gold400 = Color(0xFFFFCB57);
  static const Color gold300 = Color(0xFFFFDD8A);
  static const Color gold100 = Color(0xFFFFF4D6);

  // Supporting hues.
  static const Color diamond = Color(0xFF4FD8F0);
  static const Color diamondDeep = Color(0xFF2B8FD6);
  static const Color mint = Color(0xFF2FBF8A);
  static const Color coral = Color(0xFFE5484D);
  static const Color amber = Color(0xFFF59E0B);
  static const Color sky = Color(0xFF3E9BF0);

  // Saturated violet ramp for hero surfaces (Quick Play).
  static const Color hero300 = Color(0xFF9466FF);
  static const Color hero400 = Color(0xFF7C4DFF);
  static const Color hero500 = Color(0xFF6A3BF2);
  static const Color hero600 = Color(0xFF5A2BE0);
  static const Color hero700 = Color(0xFF4422B8);
}

/// Semantic color tokens for the "royal" design language, available through
/// `context.colors` (see `app_theme.dart`). Designed separately for light and
/// dark rather than derived, so both modes feel deliberate.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.brand,
    required this.brandStrong,
    required this.brandSoft,
    required this.onBrand,
    required this.gold,
    required this.goldStrong,
    required this.goldSoft,
    required this.onGold,
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.backgroundGlow,
    required this.pattern,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.glassFill,
    required this.glassBorder,
    required this.outline,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.onDanger,
    required this.coin,
    required this.diamond,
    required this.shadowColor,
    required this.highlight,
    required this.seats,
  });

  final Brightness brightness;

  final Color brand;
  final Color brandStrong;
  final Color brandSoft;
  final Color onBrand;

  final Color gold;
  final Color goldStrong;
  final Color goldSoft;
  final Color onGold;

  final Color backgroundTop;
  final Color backgroundBottom;
  final Color backgroundGlow;
  final Color pattern;

  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color glassFill;
  final Color glassBorder;
  final Color outline;
  final Color divider;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color onDanger;

  final Color coin;
  final Color diamond;

  final Color shadowColor;
  final Color highlight;

  final SeatPalette seats;

  bool get isDark => brightness == Brightness.dark;

  /// Signature violet gradient (primary buttons, hero headers).
  LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark
        ? const [BrandPalette.royal400, BrandPalette.royal600]
        : const [BrandPalette.royal400, BrandPalette.royal500],
  );

  /// Warm gold gradient (rewards, premium highlights).
  LinearGradient get goldGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [BrandPalette.gold300, BrandPalette.gold500, BrandPalette.gold600],
    stops: [0, 0.55, 1],
  );

  /// Saturated violet gradient for hero cards (Quick Play).
  LinearGradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark
        ? const [
            BrandPalette.hero400,
            BrandPalette.hero600,
            BrandPalette.hero700,
          ]
        : const [
            BrandPalette.hero300,
            BrandPalette.hero500,
            BrandPalette.hero600,
          ],
    stops: const [0, 0.55, 1],
  );

  /// Fill and foreground of the light controls placed on a hero card
  /// (selectors on Quick Play): white pills with royal text in both modes.
  Color get onHeroControl => Colors.white;
  Color get onHeroControlText => BrandPalette.royal800;

  /// Accent hues for lobby tiles and icon badges, tuned per brightness.
  Color get accentCoral =>
      isDark ? const Color(0xFFFF6B70) : BrandPalette.coral;
  Color get accentMint => isDark ? const Color(0xFF3DD68C) : BrandPalette.mint;
  Color get accentSky => isDark ? const Color(0xFF5B8CFF) : BrandPalette.sky;
  Color get accentAmber =>
      isDark ? BrandPalette.gold400 : const Color(0xFFF5B400);
  Color get accentViolet =>
      isDark ? BrandPalette.royal400 : const Color(0xFF7B4DFF);

  /// Text on [goldSoft] (fee pills): ≥ 4.5:1 in both modes.
  Color get onGoldSoft => isDark ? BrandPalette.gold300 : BrandPalette.gold800;

  /// Hairline border for cards: subtle borders replace heavy shadows in dark.
  Color get cardBorder => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : outline.withValues(alpha: 0.7);

  /// Diagonal fill for a small icon badge in [color] (lighter top-start).
  LinearGradient badgeGradient(Color color) => LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [Color.lerp(color, Colors.white, 0.22)!, color],
  );

  /// Foreground that reads on top of [color] (dark ink on light hues).
  Color onAccent(Color color) =>
      color.computeLuminance() > 0.45 ? const Color(0xFF2A1F00) : Colors.white;

  /// Page background gradient.
  LinearGradient get backgroundGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, backgroundBottom],
  );

  /// Soft shadows for each elevation level.
  List<BoxShadow> shadow(AppElevation level) {
    final double a = isDark ? 0.55 : 0.16;
    return switch (level) {
      AppElevation.flat => const [],
      AppElevation.low => [
        BoxShadow(
          color: shadowColor.withValues(alpha: a * 0.8),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
      AppElevation.medium => [
        BoxShadow(
          color: shadowColor.withValues(alpha: a),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: shadowColor.withValues(alpha: a * 0.4),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
      AppElevation.high => [
        BoxShadow(
          color: shadowColor.withValues(alpha: a * 1.2),
          blurRadius: 36,
          offset: const Offset(0, 16),
        ),
        BoxShadow(
          color: shadowColor.withValues(alpha: a * 0.5),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    };
  }

  static const AppColors light = AppColors(
    brightness: Brightness.light,
    brand: BrandPalette.royal500,
    brandStrong: BrandPalette.royal700,
    brandSoft: BrandPalette.royal100,
    onBrand: Colors.white,
    gold: BrandPalette.gold500,
    goldStrong: BrandPalette.gold700,
    goldSoft: BrandPalette.gold100,
    onGold: Color(0xFF3A2600),
    backgroundTop: Color(0xFFF8F5FF),
    backgroundBottom: Color(0xFFEDE6FF),
    backgroundGlow: Color(0x33FFCB57),
    pattern: Color(0x145B3FD0),
    surface: Colors.white,
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF1ECFE),
    glassFill: Color(0xB3FFFFFF),
    glassBorder: Color(0x66FFFFFF),
    outline: Color(0xFFDCD3F7),
    divider: Color(0xFFE8E2FA),
    textPrimary: Color(0xFF1B1433),
    textSecondary: Color(0xFF574E7A),
    textMuted: Color(0xFF8A82A8),
    success: Color(0xFF1F9D64),
    warning: Color(0xFFC77A06),
    danger: Color(0xFFD93A40),
    info: Color(0xFF2F74D0),
    onDanger: Colors.white,
    coin: BrandPalette.gold500,
    diamond: BrandPalette.diamondDeep,
    shadowColor: Color(0xFF2A1A66),
    highlight: Color(0xCCFFFFFF),
    seats: SeatPalette.light,
  );

  static const AppColors dark = AppColors(
    brightness: Brightness.dark,
    brand: BrandPalette.royal400,
    brandStrong: BrandPalette.royal300,
    brandSoft: Color(0xFF2A1E55),
    onBrand: Colors.white,
    gold: BrandPalette.gold400,
    goldStrong: BrandPalette.gold300,
    goldSoft: Color(0xFF3A2A0E),
    onGold: Color(0xFF2B1C00),
    backgroundTop: Color(0xFF17102F),
    backgroundBottom: BrandPalette.royal950,
    backgroundGlow: Color(0x2E7A5CF0),
    pattern: Color(0x0FFFFFFF),
    surface: Color(0xFF1A1334),
    surfaceRaised: Color(0xFF231A44),
    surfaceSunken: Color(0xFF120C26),
    glassFill: Color(0x99231A44),
    glassBorder: Color(0x26FFFFFF),
    outline: Color(0xFF3A2F66),
    divider: Color(0xFF2C2350),
    textPrimary: Color(0xFFF5F1FF),
    textSecondary: Color(0xFFC0B6E6),
    textMuted: Color(0xFF8E85B4),
    success: Color(0xFF3DD68C),
    warning: Color(0xFFFFB224),
    danger: Color(0xFFFF6369),
    info: Color(0xFF6EA8FF),
    onDanger: Color(0xFF2A0608),
    coin: BrandPalette.gold400,
    diamond: BrandPalette.diamond,
    shadowColor: Colors.black,
    highlight: Color(0x1FFFFFFF),
    seats: SeatPalette.dark,
  );

  @override
  AppColors copyWith({Color? brand, Color? gold}) => AppColors(
    brightness: brightness,
    brand: brand ?? this.brand,
    brandStrong: brandStrong,
    brandSoft: brandSoft,
    onBrand: onBrand,
    gold: gold ?? this.gold,
    goldStrong: goldStrong,
    goldSoft: goldSoft,
    onGold: onGold,
    backgroundTop: backgroundTop,
    backgroundBottom: backgroundBottom,
    backgroundGlow: backgroundGlow,
    pattern: pattern,
    surface: surface,
    surfaceRaised: surfaceRaised,
    surfaceSunken: surfaceSunken,
    glassFill: glassFill,
    glassBorder: glassBorder,
    outline: outline,
    divider: divider,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textMuted: textMuted,
    success: success,
    warning: warning,
    danger: danger,
    info: info,
    onDanger: onDanger,
    coin: coin,
    diamond: diamond,
    shadowColor: shadowColor,
    highlight: highlight,
    seats: seats,
  );

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      brand: l(brand, other.brand),
      brandStrong: l(brandStrong, other.brandStrong),
      brandSoft: l(brandSoft, other.brandSoft),
      onBrand: l(onBrand, other.onBrand),
      gold: l(gold, other.gold),
      goldStrong: l(goldStrong, other.goldStrong),
      goldSoft: l(goldSoft, other.goldSoft),
      onGold: l(onGold, other.onGold),
      backgroundTop: l(backgroundTop, other.backgroundTop),
      backgroundBottom: l(backgroundBottom, other.backgroundBottom),
      backgroundGlow: l(backgroundGlow, other.backgroundGlow),
      pattern: l(pattern, other.pattern),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      glassFill: l(glassFill, other.glassFill),
      glassBorder: l(glassBorder, other.glassBorder),
      outline: l(outline, other.outline),
      divider: l(divider, other.divider),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      onDanger: l(onDanger, other.onDanger),
      coin: l(coin, other.coin),
      diamond: l(diamond, other.diamond),
      shadowColor: l(shadowColor, other.shadowColor),
      highlight: l(highlight, other.highlight),
      seats: seats.lerp(other.seats, t),
    );
  }
}
