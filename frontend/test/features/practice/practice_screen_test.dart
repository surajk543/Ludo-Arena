import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/features/game/application/play_config.dart';
import 'package:ludo_royale/features/practice/presentation/practice_screen.dart';

import '../game/support/play_test_support.dart';

RoomSnapshot _practice(List<RoomPlayer> players, {String? status}) => ludoRoom(
  id: 'r_pr',
  mode: RoomModes.practice,
  status: status ?? RoomStatuses.lobby,
  capacity: 3,
  players: players,
);

Future<PlayHarness> _pump(
  WidgetTester tester, {
  bool explicit = true,
  Locale locale = const Locale('en'),
  Size size = const Size(360, 740),
}) async {
  final h = PlayHarness(initial: const ActiveRoomState(selfUid: 'u_0'));
  h.controller.replyRoom = _practice([player(0)]);
  await h.pump(
    tester,
    PracticeScreen(
      request: PlayRequest(bots: 2, capacity: 3, explicit: explicit),
    ),
    locale: locale,
    size: size,
  );
  return h;
}

void main() {
  testWidgets('starts practice, shows bots joining (never labelled), then '
      'enters the game', (tester) async {
    final h = await _pump(tester);
    await flush(tester);
    expect(h.controller.calls, ['practice.start:ludo:classic:2']);
    expect(find.text('Bots joining… 0/2'), findsOneWidget);

    h.controller.pushSnapshot(
      _practice([player(0), player(1, name: 'Bolt', bot: true)]),
      reason: 'joined',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Bots joining… 1/2'), findsOneWidget);
    expect(find.text('BOT'), findsNothing);

    h.controller.pushSnapshot(
      _practice([
        player(0),
        player(1, bot: true),
        player(2, bot: true),
      ], status: RoomStatuses.playing),
      game: true,
    );
    await flush(tester);
    expect(find.text('GAME r_pr'), findsOneWidget);
  });

  testWidgets('bots_unavailable shows a friendly retry', (tester) async {
    final h = await _pump(tester);
    await flush(tester);
    h.controller.emit(
      const RoomErrorReceived(ServerErrorEvent(code: 'bots_unavailable')),
    );
    await tester.pump();
    expect(find.text('Bots are busy'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await flush(tester);
    expect(
      h.controller.calls.where((c) => c.startsWith('practice.start')),
      hasLength(2),
    );
  });

  testWidgets('without a preset, the user picks game / bots first', (
    tester,
  ) async {
    final h = await _pump(tester, explicit: false);
    expect(h.controller.calls, isEmpty);
    await tester.tap(find.text('3 bots'));
    await tester.pump();
    await scrollTo(tester, find.text('Start practice'));
    await tester.tap(find.text('Start practice'));
    await flush(tester);
    expect(h.controller.calls, ['practice.start:ludo:classic:3']);
  });

  for (final locale in const [Locale('ar'), Locale('hi')]) {
    testWidgets('no overflow at 320x640 (${locale.languageCode})', (
      tester,
    ) async {
      await expectNoOverflow(tester, () async {
        await _pump(
          tester,
          explicit: false,
          locale: locale,
          size: const Size(320, 640),
        );
        await tester.pump();
      });
    });
  }
}
