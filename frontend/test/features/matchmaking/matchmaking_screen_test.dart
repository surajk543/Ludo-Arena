import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/audio_haptics/audio_service.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/core/realtime/active_room_controller.dart';
import 'package:ludo_arena/features/game/application/play_config.dart';
import 'package:ludo_arena/features/matchmaking/presentation/matchmaking_screen.dart';

import '../game/support/play_test_support.dart';

RoomSnapshot _lobby(List<RoomPlayer> players) => ludoRoom(
  id: 'r_mm',
  status: RoomStatuses.lobby,
  players: players,
  fillDeadline: kNowMs + 25000,
);

Future<PlayHarness> _pump(
  WidgetTester tester, {
  String? errorCode,
  Locale locale = const Locale('en'),
  Size size = const Size(360, 740),
  ThemeMode themeMode = ThemeMode.light,
}) async {
  final h = PlayHarness(initial: const ActiveRoomState(selfUid: 'u_0'));
  h.controller.nextErrorCode = errorCode;
  await h.pump(
    tester,
    const MatchmakingScreen(
      request: PlayRequest(
        game: GameIds.ludo,
        variant: GameVariants.classic,
        capacity: 4,
        explicit: true,
      ),
    ),
    locale: locale,
    size: size,
    themeMode: themeMode,
  );
  return h;
}

void main() {
  testWidgets('joins, fills seats from room.updated, enters the game on '
      'game.started', (tester) async {
    final h = await _pump(tester);
    expect(h.controller.calls, ['matchmaking.join:ludo:classic:4']);

    h.controller.emit(
      const MatchmakingUpdated(
        MatchmakingStatusEvent(status: MatchmakingStatuses.searching),
      ),
    );
    h.controller.pushSnapshot(
      _lobby([player(0), player(1, name: 'Ravi')]),
      reason: 'joined',
    );
    await tester.pump();
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('2/4'), findsOneWidget);
    expect(find.text('Looking for opponents…'), findsOneWidget);

    h.controller.pushSnapshot(
      _lobby([player(0), player(1, name: 'Ravi'), player(2, name: 'Bo')]),
      reason: 'joined',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Bo'), findsOneWidget);
    expect(find.text('BOT'), findsNothing);
    // Seats filling is not "match found".
    expect(h.audio.played, isEmpty);

    h.controller.pushSnapshot(
      _lobby([
        player(0),
        player(1),
        player(2),
      ]).copyWith(status: RoomStatuses.playing),
      game: true,
    );
    await flush(tester);
    expect(find.text('GAME r_mm'), findsOneWidget);
    // Server-confirmed match found: one match-start cue.
    expect(h.audio.played, [Sfx.matchStart]);
  });

  testWidgets('cancel sends matchmaking.cancel and leaves', (tester) async {
    final h = await _pump(tester);
    h.controller.pushSnapshot(_lobby([player(0)]), reason: 'created');
    await tester.pump();
    await tester.tap(find.text('Cancel search'));
    await flush(tester);
    expect(h.controller.calls.last, 'matchmaking.cancel');
    expect(find.text('HOME'), findsOneWidget);
    expect(h.audio.played, [Sfx.uiClose]);
  });

  testWidgets('timeout offers try again / home', (tester) async {
    final h = await _pump(tester);
    h.controller.emit(
      const MatchmakingUpdated(
        MatchmakingStatusEvent(status: MatchmakingStatuses.timeout),
      ),
    );
    await tester.pump();
    expect(find.text('No opponents right now'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await flush(tester);
    expect(
      h.controller.calls.where((c) => c.startsWith('matchmaking.join')),
      hasLength(2),
    );
  });

  testWidgets('insufficient coins is explained without a retry', (
    tester,
  ) async {
    await _pump(tester, errorCode: 'insufficient_funds');
    await flush(tester);
    expect(find.text('Not enough coins'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  for (final locale in const [Locale('ar'), Locale('hi'), Locale('en')]) {
    for (final size in const [Size(360, 740), Size(320, 640)]) {
      testWidgets('no overflow: ${locale.languageCode} '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await expectNoOverflow(tester, () async {
          final h = await _pump(
            tester,
            locale: locale,
            size: size,
            themeMode: locale.languageCode == 'ar'
                ? ThemeMode.dark
                : ThemeMode.light,
          );
          h.controller.pushSnapshot(
            _lobby([
              player(0, name: 'Asha Kumari Sharma'),
              player(1, name: 'Ravi'),
              player(2, name: 'محمد'),
            ]),
          );
          await tester.pump(const Duration(milliseconds: 500));
        });
      });
    }
  }
}
