import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/audio_haptics/reduced_motion.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/core/theme/app_theme.dart';
import 'package:ludo_royale/features/game/presentation/game_route_screen.dart';
import 'package:ludo_royale/features/game/presentation/widgets/player_panel.dart';
import 'package:ludo_royale/features/social/application/muted_players.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import 'support/play_test_support.dart';

const _column = ValueKey('pod-progress-column');

/// Pumps one [PlayerPanel] [width] wide, in the real theme + localizations.
Future<void> _pumpPanel(
  WidgetTester tester, {
  required double width,
  bool stacked = true,
  RoomSnapshot? room,
  RoomPlayer? p,
  bool isTurn = false,
  bool muted = false,
  double textScale = 1,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final r = room ?? ludoRoom();
  final h = PlayHarness(
    initial: ActiveRoomState(room: r, selfUid: 'u_0'),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: await h.overrides(),
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: ReducedMotionScope(child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: PlayerPanel(
                player: p ?? player(1),
                room: r,
                isSelf: false,
                isTurn: isTurn,
                stacked: stacked,
                muted: muted,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<PlayHarness> _pumpGame(
  WidgetTester tester,
  RoomSnapshot room, {
  required Size size,
  double textScale = 1,
  Locale locale = const Locale('en'),
}) async {
  final h = PlayHarness(
    initial: ActiveRoomState(room: room, selfUid: 'u_0'),
  );
  await h.pump(
    tester,
    GameRouteScreen(roomId: room.id),
    size: size,
    textScale: textScale,
    locale: locale,
  );
  await flush(tester);
  return h;
}

Size _podSize(WidgetTester tester) => tester.getSize(find.byType(PlayerPanel));

double _avatar(WidgetTester tester, [Finder? pod]) => tester
    .getSize(
      find.descendant(
        of: pod ?? find.byType(PlayerPanel),
        matching: find.byType(PlayerAvatar),
      ),
    )
    .width;

Rect _panelRect(WidgetTester tester, int seat) => tester.getRect(
  find.byWidgetPredicate((w) => w is PlayerPanel && w.player.seat == seat),
);

void main() {
  // Pod sizes measured before the progress column moved beside the avatar
  // (classic card: 56 dp avatar with the "★○○○ 0/4" line under the name).
  // The redesign must keep every one of them.
  group('the outer pod size is unchanged', () {
    for (final c in [
      // Card at the pod widths of 393, 360 and narrower phones.
      (w: 150.5, stacked: true, turn: false, ts: 1.0, h: 133.0),
      (w: 150.5, stacked: true, turn: true, ts: 1.0, h: 135.0),
      (w: 150.5, stacked: true, turn: false, ts: 1.35, h: 145.0),
      (w: 150.5, stacked: true, turn: true, ts: 1.35, h: 147.0),
      (w: 134.0, stacked: true, turn: false, ts: 1.0, h: 133.0),
      (w: 134.0, stacked: true, turn: true, ts: 1.0, h: 135.0),
      (w: 134.0, stacked: true, turn: false, ts: 1.35, h: 145.0),
      (w: 240.0, stacked: true, turn: false, ts: 1.0, h: 133.0),
      // Row tiers: ≥ 220, ≥ 150, ≥ 124, narrowest.
      (w: 240.0, stacked: false, turn: false, ts: 1.0, h: 90.0),
      (w: 240.0, stacked: false, turn: true, ts: 1.0, h: 92.0),
      (w: 240.0, stacked: false, turn: false, ts: 1.35, h: 90.0),
      (w: 160.0, stacked: false, turn: false, ts: 1.0, h: 78.0),
      (w: 160.0, stacked: false, turn: true, ts: 1.0, h: 80.0),
      (w: 130.0, stacked: false, turn: false, ts: 1.0, h: 70.0),
      (w: 130.0, stacked: false, turn: true, ts: 1.0, h: 72.0),
      (w: 114.0, stacked: false, turn: false, ts: 1.0, h: 64.0),
      (w: 114.0, stacked: false, turn: true, ts: 1.0, h: 66.0),
    ]) {
      testWidgets('${c.stacked ? 'card' : 'row'} ${c.w} dp'
          '${c.turn ? ', turn' : ''}, text ×${c.ts}', (tester) async {
        for (final p in [
          player(1),
          player(1, name: 'Riya', frame: 'frame_royal'),
          player(1, connected: false, strikes: 2),
          player(1, forfeited: true),
        ]) {
          await _pumpPanel(
            tester,
            width: c.w,
            stacked: c.stacked,
            p: p,
            isTurn: c.turn,
            textScale: c.ts,
          );
          expect(_podSize(tester), Size(c.w, c.h), reason: p.name);
        }
      });
    }

    for (final c in [
      (
        size: const Size(393, 852),
        rects: {
          1: const Rect.fromLTRB(8, 60, 158.5, 193),
          2: const Rect.fromLTRB(234.5, 60, 385, 193),
          0: const Rect.fromLTRB(8, 677, 158.5, 812),
          3: const Rect.fromLTRB(234.5, 678, 385, 811),
        },
      ),
      (
        size: const Size(360, 740),
        rects: {
          1: const Rect.fromLTRB(8, 60, 142, 193),
          2: const Rect.fromLTRB(218, 60, 352, 193),
          0: const Rect.fromLTRB(8, 565, 142, 700),
          3: const Rect.fromLTRB(218, 566, 352, 699),
        },
      ),
      (
        size: const Size(320, 640),
        rects: {
          1: const Rect.fromLTRB(8, 60, 122, 124),
          2: const Rect.fromLTRB(198, 60, 312, 124),
          0: const Rect.fromLTRB(8, 531, 122, 597),
          3: const Rect.fromLTRB(198, 532, 312, 596),
        },
      ),
    ]) {
      testWidgets('4-player game at ${c.size.width}×${c.size.height}', (
        tester,
      ) async {
        await _pumpGame(tester, ludoRoom(), size: c.size);
        for (final MapEntry(key: seat, value: rect) in c.rects.entries) {
          expect(_panelRect(tester, seat), rect, reason: 'seat $seat');
        }
      });
    }
  });

  group('card (stacked) pods', () {
    testWidgets('the avatar grows from 56 to 74 dp', (tester) async {
      for (final w in [150.5, 134.0]) {
        await _pumpPanel(tester, width: w);
        expect(_avatar(tester), 74);
      }
    });

    testWidgets('all four cards of a game on a 393 × 852 phone', (
      tester,
    ) async {
      await _pumpGame(tester, ludoRoom(), size: const Size(393, 852));
      for (final seat in [0, 1, 2, 3]) {
        expect(
          _avatar(
            tester,
            find.byWidgetPredicate(
              (w) => w is PlayerPanel && w.player.seat == seat,
            ),
          ),
          74,
        );
      }
    });

    testWidgets('the avatar shrinks with the width, never below 56 dp', (
      tester,
    ) async {
      await _pumpPanel(tester, width: 130);
      expect(_avatar(tester), 72);
      await _pumpPanel(tester, width: 114);
      expect(_avatar(tester), 56);
      // Too narrow for a column beside the classic avatar: classic card.
      await _pumpPanel(tester, width: 100);
      expect(_avatar(tester), 56);
      expect(find.byKey(_column), findsNothing);
      expect(find.text('0/4'), findsOneWidget);
    });

    testWidgets('token progress is a vertical column beside the avatar', (
      tester,
    ) async {
      final room = ludoRoom(
        tokens: [
          [-1, -1, -1, -1],
          [56, 57, 12, -1],
          [-1, -1, -1, -1],
          [-1, -1, -1, -1],
        ],
      );
      await _pumpPanel(tester, width: 150.5, room: room);
      final marks = find.descendant(
        of: find.byKey(_column),
        matching: find.byType(Icon),
      );
      expect(marks, findsNWidgets(4));
      final centers = [
        for (var i = 0; i < 4; i++) tester.getCenter(marks.at(i)),
      ];
      for (var i = 1; i < 4; i++) {
        expect(centers[i].dy, greaterThan(centers[i - 1].dy));
        expect(centers[i].dx, moreOrLessEquals(centers[0].dx));
      }
      expect(
        [for (var i = 0; i < 4; i++) tester.widget<Icon>(marks.at(i)).icon],
        [
          Icons.star_rounded,
          Icons.star_rounded,
          Icons.circle_outlined,
          Icons.circle_outlined,
        ],
      );
      // The count sits under the marks, inside the column.
      final count = tester.getRect(find.text('2/4'));
      expect(count.top, greaterThan(centers.last.dy));
      expect(
        find.descendant(of: find.byKey(_column), matching: find.text('2/4')),
        findsOneWidget,
      );
      // On the avatar's trailing side, within the avatar row.
      final avatar = tester.getRect(find.byType(PlayerAvatar));
      final column = tester.getRect(find.byKey(_column));
      expect(column.left, greaterThan(avatar.right));
      expect(column.top, greaterThanOrEqualTo(avatar.top - 6));
      expect(column.bottom, lessThanOrEqualTo(avatar.bottom + 6));
      // The name is under both.
      final name = tester.getRect(find.text('Player1'));
      expect(name.top, greaterThan(column.bottom));
      expect(name.top, greaterThan(avatar.bottom));
    });

    testWidgets('RTL: the column is on the avatar\'s left', (tester) async {
      await _pumpPanel(tester, width: 150.5, locale: const Locale('ar'));
      final avatar = tester.getRect(find.byType(PlayerAvatar));
      final column = tester.getRect(find.byKey(_column));
      expect(column.right, lessThan(avatar.left));
    });

    testWidgets('the progress keeps its accessibility label', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpPanel(tester, width: 150.5);
      expect(
        find.bySemanticsLabel(RegExp(r'Player1, .*0 of 4 tokens home')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('offline / left: a stamp on the avatar, strikes by the name; '
        'progress stays visible', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpPanel(
        tester,
        width: 150.5,
        p: player(1, connected: false, strikes: 2),
      );
      final avatar = tester.getRect(find.byType(PlayerAvatar));
      final stamp = tester.getRect(find.text('Offline'));
      // Across the top of the avatar, inside its turn-ring box.
      expect(stamp.left, greaterThanOrEqualTo(avatar.left - 6));
      expect(stamp.right, lessThanOrEqualTo(avatar.right + 6));
      expect(stamp.center.dy, lessThan(avatar.center.dy));
      expect(stamp.top, greaterThanOrEqualTo(avatar.top - 6));
      expect(
        find.bySemanticsLabel(RegExp(r'Player1, .*Offline')),
        findsOneWidget,
      );
      expect(find.byKey(_column), findsOneWidget);
      expect(find.text('0/4'), findsOneWidget);
      final avatarWidget = tester.widget<PlayerAvatar>(
        find.byType(PlayerAvatar),
      );
      expect(avatarWidget.dimmed, isTrue);

      await _pumpPanel(tester, width: 150.5, p: player(1, forfeited: true));
      expect(find.text('Left'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the turn ring wraps the larger avatar', (tester) async {
      await _pumpPanel(tester, width: 150.5, isTurn: true);
      final ring = tester.getSize(find.byType(CountdownRing));
      expect(ring, const Size.square(86));
      final avatar = tester.getRect(find.byType(PlayerAvatar));
      final ringRect = tester.getRect(find.byType(CountdownRing));
      expect(ringRect.center, avatar.center);
    });

    testWidgets('bots are never labelled (no badge, no bot wording)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpPanel(tester, width: 150.5, p: player(1, name: 'Riya'));
      // Seats carry no bot flag: a computer opponent is just a player.
      expect(find.text('Riya'), findsOneWidget);
      expect(
        find.textContaining(RegExp('bot', caseSensitive: false)),
        findsNothing,
      );
      final label = tester
          .getSemantics(find.byType(PlayerPanel))
          .label
          .toLowerCase();
      expect(label, isNot(contains('bot')));
      expect(label, isNot(contains('computer')));
      semantics.dispose();
    });

    testWidgets('Snakes & Ladders: the square beside the avatar', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpPanel(
        tester,
        width: 150.5,
        room: snakesRoom(positions: [0, 12, 0, 0]),
      );
      expect(_avatar(tester), 74);
      expect(_podSize(tester), const Size(150.5, 133));
      expect(
        find.descendant(of: find.byKey(_column), matching: find.text('12')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Player1, .*Square 12')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('row pods', () {
    testWidgets('≥ 220 dp: progress column beside a 64 dp avatar', (
      tester,
    ) async {
      await _pumpPanel(tester, width: 300, stacked: false);
      expect(_avatar(tester), 64);
      final marks = find.descendant(
        of: find.byKey(_column),
        matching: find.byType(Icon),
      );
      expect(marks, findsNWidgets(4));
      expect(
        tester.getCenter(marks.at(3)).dy,
        greaterThan(tester.getCenter(marks.at(0)).dy),
      );
      final avatar = tester.getRect(find.byType(PlayerAvatar));
      final column = tester.getRect(find.byKey(_column));
      final name = tester.getRect(find.text('Player1'));
      expect(column.left, greaterThan(avatar.right));
      expect(name.left, greaterThan(column.right));
    });

    testWidgets('narrower rows keep the progress line under the name', (
      tester,
    ) async {
      for (final (w, avatar) in [(160.0, 48.0), (130.0, 44.0), (114.0, 40.0)]) {
        await _pumpPanel(
          tester,
          width: w,
          stacked: false,
          p: player(1, name: 'Riya'),
        );
        expect(_avatar(tester), avatar);
        expect(find.byKey(_column), findsNothing);
        expect(find.text('Riya'), findsOneWidget);
      }
    });
  });

  group('presence and mute', () {
    Finder online(int seat) => find.byKey(ValueKey('pod-online-$seat'));
    Finder offline(int seat) => find.byKey(ValueKey('pod-offline-$seat'));
    // The pod's merged label (it starts with the player's name).
    String label(WidgetTester tester) =>
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Player1, '))).label;

    for (final stacked in [true, false]) {
      testWidgets('${stacked ? 'card' : 'row'}: a green dot while connected, '
          'a wifi-off badge while disconnected, none once left', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pumpPanel(tester, width: 150, stacked: stacked);
        expect(online(1), findsOneWidget);
        expect(offline(1), findsNothing);
        expect(label(tester), contains('Online'));

        await _pumpPanel(
          tester,
          width: 150,
          stacked: stacked,
          p: player(1, connected: false),
        );
        expect(online(1), findsNothing);
        expect(offline(1), findsOneWidget);
        expect(
          find.descendant(
            of: offline(1),
            matching: find.byIcon(Icons.wifi_off_rounded),
          ),
          findsOneWidget,
        );
        expect(label(tester), contains('Offline'));
        expect(label(tester), isNot(contains('Online')));

        await _pumpPanel(
          tester,
          width: 150,
          stacked: stacked,
          p: player(1, connected: false, forfeited: true),
        );
        expect(online(1), findsNothing);
        expect(offline(1), findsNothing);
        semantics.dispose();
      });
    }

    for (final (locale, rtl) in [
      (const Locale('en'), false),
      (const Locale('ar'), true),
    ]) {
      testWidgets('the mark sits on the avatar edge, bottom '
          '${rtl ? 'left (RTL)' : 'right'}', (tester) async {
        for (final (stacked, width) in [(true, 150.0), (false, 220.0)]) {
          for (final connected in [true, false]) {
            await _pumpPanel(
              tester,
              width: width,
              stacked: stacked,
              locale: locale,
              p: player(1, connected: connected),
            );
            final avatar = tester.getRect(find.byType(PlayerAvatar));
            final mark = tester.getRect(connected ? online(1) : offline(1));
            expect(mark.center.dy, greaterThan(avatar.center.dy));
            expect(
              rtl
                  ? mark.center.dx < avatar.center.dx
                  : mark.center.dx > avatar.center.dx,
              isTrue,
            );
            // On the avatar's edge, not floating away from it.
            final reach = (mark.center - avatar.center).distance;
            expect(reach, lessThan(avatar.width / 2 + mark.width));
            expect(reach, greaterThan(avatar.width / 2 - mark.width));
          }
        }
      });
    }

    testWidgets('a muted player: an icon by the name, "Muted" for screen '
        'readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpPanel(tester, width: 124, stacked: false, muted: true);
      expect(find.byKey(const ValueKey('pod-muted-1')), findsOneWidget);
      expect(label(tester), contains('Muted'));
      await _pumpPanel(tester, width: 124, stacked: false);
      expect(find.byKey(const ValueKey('pod-muted-1')), findsNothing);
      expect(label(tester), isNot(contains('Muted')));
      semantics.dispose();
    });
  });

  group('no overflow', () {
    for (final c in [
      (size: const Size(320, 640), ts: 1.0, locale: const Locale('en')),
      (size: const Size(320, 640), ts: 1.35, locale: const Locale('en')),
      (size: const Size(393, 852), ts: 1.35, locale: const Locale('en')),
      (size: const Size(360, 740), ts: 1.35, locale: const Locale('ar')),
      (size: const Size(393, 852), ts: 1.0, locale: const Locale('ur')),
    ]) {
      testWidgets('${c.size.width}×${c.size.height}, text ×${c.ts}, '
          '${c.locale.languageCode}', (tester) async {
        await expectNoOverflow(tester, () async {
          final h = await _pumpGame(
            tester,
            ludoRoom(
              turnSeat: 1,
              players: [
                player(0),
                player(1, name: 'Riya', frame: 'frame_royal'),
                player(2, connected: false, strikes: 2),
                player(3, forfeited: true),
              ],
            ),
            size: c.size,
            textScale: c.ts,
            locale: c.locale,
          );
          // Muted opponents (online, offline and left): the icon by the name.
          final muted = h.container.read(mutedPlayersProvider.notifier);
          for (final uid in ['u_1', 'u_2', 'u_3']) {
            await muted.setMuted(uid, muted: true);
          }
          await tester.pump();
          expect(find.byKey(const ValueKey('pod-muted-2')), findsOneWidget);
          await _pumpGame(
            tester,
            snakesRoom(positions: [0, 12, 100, 57]),
            size: c.size,
            textScale: c.ts,
            locale: c.locale,
          );
        });
      });
    }

    testWidgets('every card and row width, text ×1.35, dark', (tester) async {
      await expectNoOverflow(tester, () async {
        for (final (stacked, widths) in [
          // Cards down to the classic fallback; rows from the narrowest pod
          // a 320 dp screen gives (114 dp) to the landscape side column.
          (true, [96.0, 108.0, 114.0, 124.0, 150.0, 219.0, 340.0]),
          (false, [114.0, 124.0, 150.0, 219.0, 220.0, 340.0]),
        ]) {
          for (final w in widths) {
            for (final connected in [false, true]) {
              await _pumpPanel(
                tester,
                width: w,
                stacked: stacked,
                p: player(1, connected: connected, strikes: 3),
                isTurn: true,
                muted: true,
                textScale: 1.35,
                themeMode: ThemeMode.dark,
              );
            }
          }
        }
      });
    });
  });
}
