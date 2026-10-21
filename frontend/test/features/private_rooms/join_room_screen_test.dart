import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/network/api_exception.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/features/private_rooms/application/rooms_repository.dart';
import 'package:ludo_royale/features/private_rooms/presentation/join_room_screen.dart';

import '../game/support/play_test_support.dart';

const _preview = RoomPreview(
  game: GameIds.ludo,
  variant: GameVariants.classic,
  capacity: 4,
  players: 2,
  status: RoomStatuses.lobby,
  entryFee: 1000,
  hostName: 'Asha',
);

Future<PlayHarness> _pump(
  WidgetTester tester, {
  String? code,
  RoomPreview? preview = _preview,
  Object? previewError,
  Locale locale = const Locale('en'),
}) async {
  final h = PlayHarness(initial: const ActiveRoomState(selfUid: 'u_0'));
  h.rooms
    ..previewResult = preview
    ..previewError = previewError;
  await h.pump(tester, JoinRoomScreen(initialCode: code), locale: locale);
  return h;
}

void main() {
  testWidgets('typing normalizes to upper case, previews, then joins', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.controller.replyRoom = ludoRoom(
      id: 'r_p',
      status: RoomStatuses.lobby,
      mode: RoomModes.private,
    );
    await tester.enterText(find.byKey(const Key('room-code-field')), 'k7q2mx');
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const Key('room-code-field')),
    );
    expect(field.controller!.text, 'K7Q2MX');
    await tester.pump(const Duration(milliseconds: 300));
    await flush(tester);
    expect(h.rooms.lookups, ['K7Q2MX']);
    expect(find.text('Hosted by Asha'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    await tester.tap(find.text('Join room'));
    await flush(tester);
    expect(h.controller.calls, ['room.join:K7Q2MX']);
    expect(find.text('LOBBY r_p'), findsOneWidget);
  });

  testWidgets('incomplete code: hint, no lookup, join disabled', (
    tester,
  ) async {
    final h = await _pump(tester);
    await tester.enterText(find.byKey(const Key('room-code-field')), 'k7q');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('3 more characters'), findsOneWidget);
    expect(h.rooms.lookups, isEmpty);
    await tester.tap(find.text('Join room'));
    await tester.pump();
    expect(h.controller.calls, isEmpty);
  });

  testWidgets('excluded characters in a shared code are flagged', (
    tester,
  ) async {
    final h = await _pump(tester, code: 'K7Q2M0');
    expect(
      find.text(
        'Room codes use the letters A–Z and the numbers 2–9 '
        '(no I, O, 0 or 1).',
      ),
      findsOneWidget,
    );
    expect(h.rooms.lookups, isEmpty);
  });

  testWidgets('unknown code → invalid code error', (tester) async {
    await _pump(
      tester,
      code: 'K7Q2MX',
      previewError: const ApiException(code: 'invalid_code', status: 404),
    );
    await flush(tester);
    expect(find.text('Hosted by Asha'), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  for (final (status, players, label) in const [
    (RoomStatuses.playing, 2, 'In progress'),
    (RoomStatuses.lobby, 4, 'Full'),
    (RoomStatuses.closed, 1, 'Closed'),
  ]) {
    testWidgets('preview "$label" blocks joining', (tester) async {
      final h = await _pump(
        tester,
        code: 'K7Q2MX',
        preview: RoomPreview(
          game: GameIds.snakesLadders,
          variant: GameVariants.classic,
          capacity: 4,
          players: players,
          status: status,
          entryFee: 500,
          hostName: 'Asha',
        ),
      );
      await flush(tester);
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text('Join room'));
      await tester.pump();
      expect(h.controller.calls, isEmpty);
    });
  }

  testWidgets('join failure (room full) is shown, localized', (tester) async {
    final h = await _pump(tester, code: 'K7Q2MX');
    await flush(tester);
    h.controller.nextErrorCode = 'room_full';
    await tester.tap(find.text('Join room'));
    await flush(tester);
    expect(h.controller.calls, ['room.join:K7Q2MX']);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('the code field stays LTR in Arabic', (tester) async {
    await _pump(tester, code: 'K7Q2MX', locale: const Locale('ar'));
    await flush(tester);
    expect(
      Directionality.of(
        tester.element(find.byKey(const Key('room-code-field'))),
      ),
      TextDirection.ltr,
    );
  });
}
