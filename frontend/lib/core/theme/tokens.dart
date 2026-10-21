import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Spacing scale (logical pixels). Use these instead of ad-hoc numbers so
/// every screen shares one rhythm.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Horizontal gutter for full-width screens.
  static const double gutter = 20;

  /// Max content width on tablets / landscape.
  static const double maxContentWidth = 560;
}

/// Corner radii.
abstract final class AppRadii {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Motion tokens. Always gate decorative motion through `ReducedMotion`.
abstract final class AppDurations {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration countUp = Duration(milliseconds: 900);
  static const Duration theme = Duration(milliseconds: 350);
}

abstract final class AppCurves {
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
  static const Curve exit = Curves.easeInCubic;
}

/// Elevation levels, resolved to concrete shadows by [AppColors.shadow].
enum AppElevation { flat, low, medium, high }
