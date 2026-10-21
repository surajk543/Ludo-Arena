import 'package:flutter/material.dart';

import '../../shared/game_visuals/seat_color.dart';

// One SeatColor enum for the whole app, owned by the board visuals module.
export '../../shared/game_visuals/seat_color.dart' show SeatColor;

/// Seat palette for one brightness. Both palettes are tuned so tokens stay
/// clearly distinguishable on light and dark boards.
@immutable
class SeatPalette {
  const SeatPalette({
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
  });

  final Color red;
  final Color green;
  final Color yellow;
  final Color blue;

  static const SeatPalette light = SeatPalette(
    red: Color(0xFFE5484D),
    green: Color(0xFF30A46C),
    yellow: Color(0xFFF5B800),
    blue: Color(0xFF3E63DD),
  );

  static const SeatPalette dark = SeatPalette(
    red: Color(0xFFFF6369),
    green: Color(0xFF3DD68C),
    yellow: Color(0xFFFFD43B),
    blue: Color(0xFF6E8BFF),
  );

  Color of(SeatColor seat) => switch (seat) {
    SeatColor.red => red,
    SeatColor.green => green,
    SeatColor.yellow => yellow,
    SeatColor.blue => blue,
  };

  /// Foreground (text/icon) color that reads well on top of [of] (seat).
  Color onColor(SeatColor seat) => switch (seat) {
    SeatColor.yellow => const Color(0xFF2A1F00),
    _ => Colors.white,
  };

  SeatPalette lerp(SeatPalette other, double t) => SeatPalette(
    red: Color.lerp(red, other.red, t)!,
    green: Color.lerp(green, other.green, t)!,
    yellow: Color.lerp(yellow, other.yellow, t)!,
    blue: Color.lerp(blue, other.blue, t)!,
  );
}
