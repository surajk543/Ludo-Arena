import 'package:flutter/material.dart';

/// Font families declared in pubspec.yaml.
abstract final class AppFonts {
  /// Rounded display face for titles, numbers and buttons.
  static const String display = 'Fredoka';

  /// Highly legible body face.
  static const String body = 'Nunito';

  /// Script fallbacks: Baloo 2 covers Devanagari (hi), Baloo Bhaijaan 2 covers
  /// Arabic script (ar, ur). Every text style must carry this list so mixed
  /// content (e.g. a Latin player name inside a Hindi sentence) renders well.
  static const List<String> fallback = ['Baloo2', 'BalooBhaijaan2'];
}

/// Builds the app [TextTheme]. Fredoka for display/headline/title/label,
/// Nunito for body text; fallbacks applied everywhere.
TextTheme buildTextTheme(Color primary, Color secondary) {
  TextStyle display(double size, FontWeight weight, {double height = 1.15}) =>
      TextStyle(
        fontFamily: AppFonts.display,
        fontFamilyFallback: AppFonts.fallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: primary,
        leadingDistribution: TextLeadingDistribution.even,
        letterSpacing: 0,
      );
  TextStyle body(double size, FontWeight weight, {Color? color}) => TextStyle(
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: size,
    fontWeight: weight,
    height: 1.35,
    color: color ?? primary,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: 0,
  );

  return TextTheme(
    displayLarge: display(44, FontWeight.w700, height: 1.05),
    displayMedium: display(36, FontWeight.w700, height: 1.08),
    displaySmall: display(30, FontWeight.w700, height: 1.1),
    headlineLarge: display(28, FontWeight.w700),
    headlineMedium: display(24, FontWeight.w600),
    headlineSmall: display(21, FontWeight.w600),
    titleLarge: display(19, FontWeight.w600),
    titleMedium: display(16, FontWeight.w600),
    titleSmall: display(14, FontWeight.w600),
    labelLarge: display(16, FontWeight.w600, height: 1.2),
    labelMedium: display(13, FontWeight.w600, height: 1.2),
    labelSmall: display(11, FontWeight.w500, height: 1.2),
    bodyLarge: body(16, FontWeight.w600),
    bodyMedium: body(14, FontWeight.w600, color: secondary),
    bodySmall: body(12, FontWeight.w600, color: secondary),
  );
}
