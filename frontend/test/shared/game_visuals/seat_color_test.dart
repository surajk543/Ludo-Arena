import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/shared/game_visuals/seat_color.dart';

void main() {
  test('turnsToBottomLeft brings every color to the blue corner', () {
    expect(SeatColor.red.turnsToBottomLeft, 3);
    expect(SeatColor.green.turnsToBottomLeft, 2);
    expect(SeatColor.yellow.turnsToBottomLeft, 1);
    expect(SeatColor.blue.turnsToBottomLeft, 0);
    for (final c in SeatColor.values) {
      expect(c.rotated(c.turnsToBottomLeft), SeatColor.blue);
    }
  });

  test('rotated follows the clockwise corner order and wraps', () {
    expect(SeatColor.red.rotated(0), SeatColor.red);
    expect(SeatColor.red.rotated(1), SeatColor.green);
    expect(SeatColor.blue.rotated(1), SeatColor.red);
    expect(SeatColor.yellow.rotated(6), SeatColor.red);
  });
}
