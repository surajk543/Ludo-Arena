/// Seat colors shared by Ludo and Snakes & Ladders.
///
/// Order matches `backend/docs/game-rules.md` ("Colors in clockwise order:
/// red, green, yellow, blue", color index 0..3).
enum SeatColor {
  red,
  green,
  yellow,
  blue;

  /// Color index 0..3 as used by the rules (`start = 13 × colorIndex`).
  int get colorIndex => index;

  /// Clockwise quarter turns of the board that bring this color's corner
  /// (red top-left, green top-right, yellow bottom-right, blue bottom-left)
  /// to the bottom-left, where the local player is shown.
  int get turnsToBottomLeft => (SeatColor.blue.index - index) % 4;

  /// The color whose corner this color occupies after [quarterTurns]
  /// clockwise quarter turns of the board.
  SeatColor rotated(int quarterTurns) =>
      SeatColor.values[(index + quarterTurns) % 4];

  /// Parses the protocol name (`"red"`, `"green"`, `"yellow"`, `"blue"`),
  /// case-insensitively. Throws [ArgumentError] for anything else.
  static SeatColor fromName(String name) {
    final parsed = tryFromName(name);
    if (parsed == null) {
      throw ArgumentError.value(name, 'name', 'Unknown seat color');
    }
    return parsed;
  }

  /// Like [fromName] but returns `null` for unknown or null names.
  static SeatColor? tryFromName(String? name) {
    if (name == null) return null;
    final lower = name.trim().toLowerCase();
    for (final c in SeatColor.values) {
      if (c.name == lower) return c;
    }
    return null;
  }

  /// The documented seat → color mapping for [players] seated players
  /// (2 → red, yellow; 3 → red, green, yellow; 4 → all four).
  static List<SeatColor> forPlayerCount(int players) {
    switch (players) {
      case 2:
        return const [SeatColor.red, SeatColor.yellow];
      case 3:
        return const [SeatColor.red, SeatColor.green, SeatColor.yellow];
      default:
        return SeatColor.values;
    }
  }
}
