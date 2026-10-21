import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/features/ludo/presentation/board/board.dart';
import 'package:ludo_royale/features/ludo/presentation/screens/ludo_game_screen.dart';
import 'package:ludo_royale/shared/game_visuals/game_visuals.dart';

import '../../../game/support/play_test_support.dart';

/// A busy 4-player Ludo position: long names, a bot, a disconnected player,
/// strikes and tokens home.
RoomSnapshot _busyRoom({String phase = TurnPhases.awaitingRoll}) => ludoRoom(
  turnSeat: 0,
  phase: phase,
  legal: phase == TurnPhases.awaitingMove ? const [0, 2] : const [],
  dice: phase == TurnPhases.awaitingMove ? 6 : 0,
  players: [
    player(0, name: 'Asha Kumari Sharma', frame: 'frame_gold'),
    player(1, name: 'Bolt'),
    player(2, name: 'محمد عبد الله', connected: false, strikes: 2),
    player(3, name: 'राहुल', frame: 'frame_royal'),
  ],
  tokens: const [
    [56, 12, 0, -1],
    [13, 56, 56, -1],
    [26, -1, -1, 30],
    [39, 51, -1, -1],
  ],
);

void main() {
  const configs = <(String, Locale, ThemeMode)>[
    ('en light', Locale('en'), ThemeMode.light),
    ('en dark', Locale('en'), ThemeMode.dark),
    ('ar dark (RTL)', Locale('ar'), ThemeMode.dark),
    ('ar light (RTL)', Locale('ar'), ThemeMode.light),
    ('hi light', Locale('hi'), ThemeMode.light),
    ('hi dark', Locale('hi'), ThemeMode.dark),
  ];
  const sizes = [Size(360, 740), Size(320, 640)];

  for (final (label, locale, theme) in configs) {
    for (final size in sizes) {
      testWidgets('Ludo game screen: $label '
          '${size.width.toInt()}x${size.height.toInt()} without overflow', (
        tester,
      ) async {
        await expectNoOverflow(tester, () async {
          final h = PlayHarness(
            initial: ActiveRoomState(
              room: _busyRoom(phase: TurnPhases.awaitingMove),
              selfUid: 'u_0',
            ),
          );
          await h.pump(
            tester,
            const LudoGameScreen(roomId: 'r_1'),
            locale: locale,
            themeMode: theme,
            size: size,
          );
          await flush(tester);
        });
        expect(find.byType(LudoBoard), findsOneWidget);
        expect(find.byType(DiceView), findsOneWidget);
        // The board fits on screen (responsive sizing).
        final board = tester.getRect(find.byType(LudoBoard));
        expect(board.width, lessThanOrEqualTo(size.width));
        expect(board.bottom, lessThanOrEqualTo(size.height));
        if (locale.languageCode == 'ar') {
          final ctx = tester.element(find.byType(LudoGameScreen));
          expect(Directionality.of(ctx), TextDirection.rtl);
        }
      });
    }
  }
}
