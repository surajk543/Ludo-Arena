import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/features/private_rooms/presentation/room_lobby_screen.dart';

import '../game/support/play_test_support.dart';

RoomSnapshot _lobby({
  List<RoomPlayer>? players,
  bool allowBots = false,
  int capacity = 4,
}) => ludoRoom(
  id: 'r_p',
  status: RoomStatuses.lobby,
  mode: RoomModes.private,
  hostSeat: 0,
  code: 'K7Q2MX',
  allowBots: allowBots,
  capacity: capacity,
  players:
      players ??
      [
        player(0, name: 'Asha', frame: 'frame_gold'),
        player(1, name: 'Ravi'),
        player(2, name: 'Robo', bot: true),
      ],
);

Future<PlayHarness> _pump(
  WidgetTester tester, {
  required String selfUid,
  RoomSnapshot? room,
  Locale locale = const Locale('en'),
  Size size = const Size(360, 740),
}) async {
  final h = PlayHarness(
    initial: ActiveRoomState(room: room ?? _lobby(), selfUid: selfUid),
  );
  await h.pump(
    tester,
    const RoomLobbyScreen(roomId: 'r_p'),
    locale: locale,
    size: size,
  );
  return h;
}

void main() {
  testWidgets('host sees Start, Allow bots, remove-bot and invite', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      selfUid: 'u_0',
      room: _lobby(allowBots: true),
    );
    expect(find.text('K7Q2MX'), findsOneWidget);
    expect(find.text('BOT'), findsNothing);
    expect(find.byTooltip('Remove Robo'), findsOneWidget);
    await scrollTo(tester, find.text('Start game'));
    expect(find.text('Start game'), findsOneWidget);
    expect(find.text('Allow bots'), findsOneWidget);
    expect(find.text('Waiting for the host to start…'), findsNothing);

    await tester.tap(find.text('Start game'));
    await tester.pump();
    expect(h.controller.calls, contains('game.start'));

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove Robo'));
    await tester.pump();
    expect(h.controller.calls, contains('room.remove_bot:2'));
  });

  testWidgets('guest sees "waiting for host" and no host controls', (
    tester,
  ) async {
    await _pump(tester, selfUid: 'u_1');
    await scrollTo(tester, find.text('Leave room'));
    expect(find.textContaining('Waiting for Asha (host)'), findsOneWidget);
    expect(find.text('Start game'), findsNothing);
    expect(find.text('Allow bots'), findsNothing);
    expect(find.byTooltip('Remove Robo'), findsNothing);
    expect(find.text('Add bot'), findsNothing);
  });

  testWidgets('Start is disabled with one player or a disconnected player', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      selfUid: 'u_0',
      room: _lobby(players: [player(0), player(1, connected: false)]),
    );
    await scrollTo(tester, find.text('Leave room'));
    expect(find.text('Waiting for everyone to reconnect.'), findsOneWidget);
    await tester.tap(find.text('Start game'));
    await tester.pump();
    expect(h.controller.calls, isNot(contains('game.start')));
  });

  testWidgets('add bot shows "bot joining" and blocks Start until seated', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      selfUid: 'u_0',
      room: _lobby(allowBots: true, players: [player(0), player(1)]),
    );
    await scrollTo(tester, find.text('Add bot').first);
    await tester.tap(find.text('Add bot').first);
    await tester.pump();
    expect(h.controller.calls, contains('room.add_bot'));
    await tester.pump();
    expect(find.text('Bot joining…'), findsOneWidget);
    await scrollTo(tester, find.text('Bots are taking their seats…'));

    // The bot sits down (room.updated).
    h.controller.pushSnapshot(
      _lobby(
        allowBots: true,
        players: [player(0), player(1), player(2, bot: true)],
      ),
      reason: 'joined',
    );
    await tester.pump();
    expect(find.text('Bot joining…'), findsNothing);
    expect(find.text('Bots are taking their seats…'), findsNothing);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('share sends a friendly invite with only the code', (
    tester,
  ) async {
    final h = await _pump(tester, selfUid: 'u_1');
    await tester.tap(find.text('Share invite'));
    await tester.pump();
    expect(h.shared, hasLength(1));
    expect(h.shared.single, contains('K7Q2MX'));
    expect(h.shared.single, isNot(contains('r_p')));
    expect(h.shared.single, isNot(contains('u_')));
  });

  testWidgets('game.started navigates straight to the game', (tester) async {
    final h = await _pump(tester, selfUid: 'u_1');
    h.controller.pushSnapshot(
      _lobby().copyWith(status: RoomStatuses.playing),
      game: true,
    );
    await flush(tester);
    expect(find.text('GAME r_p'), findsOneWidget);
  });

  for (final locale in const [Locale('ar'), Locale('hi')]) {
    for (final size in const [Size(360, 740), Size(320, 640)]) {
      testWidgets('lays out without overflow: ${locale.languageCode} '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await expectNoOverflow(tester, () async {
          await _pump(tester, selfUid: 'u_0', locale: locale, size: size);
          await tester.pump();
        });
        if (locale.languageCode == 'ar') {
          // The room code stays LTR in RTL locales.
          final code = tester.widget<Text>(find.text('K7Q2MX'));
          expect(code.data, 'K7Q2MX');
          expect(
            Directionality.of(tester.element(find.text('K7Q2MX'))),
            TextDirection.ltr,
          );
        }
      });
    }
  }
}
