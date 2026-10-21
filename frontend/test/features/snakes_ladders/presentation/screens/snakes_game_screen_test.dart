import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/features/snakes_ladders/presentation/board/board.dart';
import 'package:ludo_royale/features/snakes_ladders/presentation/screens/snakes_game_screen.dart';
import 'package:ludo_royale/shared/game_visuals/game_visuals.dart';

import '../../../game/support/play_test_support.dart';

RoomSnapshot _room({int turnSeat = 1}) => snakesRoom(
  turnSeat: turnSeat,
  players: [
    player(0, name: 'Asha Kumari Sharma'),
    player(1, name: 'Bolt', bot: true),
    player(2, name: 'محمد', connected: false),
    player(3, name: 'राहुल', strikes: 1),
  ],
  positions: const [34, 0, 99, 56],
);

void main() {
  const configs = <(String, Locale, ThemeMode)>[
    ('en light', Locale('en'), ThemeMode.light),
    ('en dark', Locale('en'), ThemeMode.dark),
    ('ar dark (RTL)', Locale('ar'), ThemeMode.dark),
    ('hi light', Locale('hi'), ThemeMode.light),
  ];
  const sizes = [Size(360, 740), Size(320, 640)];

  for (final (label, locale, theme) in configs) {
    for (final size in sizes) {
      testWidgets('Snakes game screen: $label '
          '${size.width.toInt()}x${size.height.toInt()} without overflow', (
        tester,
      ) async {
        await expectNoOverflow(tester, () async {
          final h = PlayHarness(
            initial: ActiveRoomState(room: _room(), selfUid: 'u_0'),
          );
          await h.pump(
            tester,
            const SnakesGameScreen(roomId: 'r_s'),
            locale: locale,
            themeMode: theme,
            size: size,
          );
          await flush(tester);
        });
        expect(find.byType(SnakesBoard), findsOneWidget);
        // The board keeps its own (non-square) aspect ratio and fits.
        final rect = tester.getRect(find.byType(SnakesBoard));
        expect(rect.width, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        if (locale.languageCode == 'ar') {
          expect(
            Directionality.of(tester.element(find.byType(SnakesGameScreen))),
            TextDirection.rtl,
          );
        }
      });
    }
  }

  testWidgets('roll → move with ladder → turn change animate in order', (
    tester,
  ) async {
    final room = _room(turnSeat: 0);
    final h = PlayHarness(
      initial: ActiveRoomState(room: room, selfUid: 'u_0'),
    );
    await h.pump(tester, const SnakesGameScreen(roomId: 'r_s'));
    await flush(tester);
    expect(find.text('Your turn — tap the dice!'), findsOneWidget);

    await tester.tap(find.byType(DiceView));
    await tester.pump();
    expect(h.controller.calls, ['roll:5']);

    final rolled = room.copyWith(
      v: 11,
      turn: room.turn.copyWith(dice: 2, turnSeq: 6),
    );
    h.controller.pushDelta(
      const DiceResultEvent(
        roomId: 'r_s',
        v: 11,
        seat: 0,
        value: 2,
        turnSeq: 6,
        phase: TurnPhases.awaitingRoll,
      ),
      rolled,
    );
    final moved = rolled.copyWith(
      v: 12,
      board: rolled.board.withSnakesPositions(const [44, 0, 99, 56]),
    );
    h.controller.pushDelta(
      const MoveAppliedEvent(
        roomId: 'r_s',
        v: 12,
        seat: 0,
        from: 34,
        to: 44,
        landing: 36,
        transition: BoardTransition(kind: 'ladder', from: 36, to: 44),
      ),
      moved,
    );
    final passed = moved.copyWith(
      v: 13,
      turn: moved.turn.copyWith(seat: 1, turnSeq: 7, dice: 0),
    );
    h.controller.pushDelta(
      const TurnChangedEvent(
        roomId: 'r_s',
        v: 13,
        seat: 1,
        turnSeq: 7,
        phase: TurnPhases.awaitingRoll,
      ),
      passed,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('Bolt (bot) is playing…'), findsOneWidget);
    expect(find.text('Square 44'), findsOneWidget);
    expect(h.audio.played, isNotEmpty);
  });
}
