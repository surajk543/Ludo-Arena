import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/audio_haptics/reduced_motion.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/core/realtime/active_room_controller.dart';
import 'package:ludo_arena/core/theme/app_theme.dart';
import 'package:ludo_arena/features/game/presentation/game_route_screen.dart';
import 'package:ludo_arena/features/game/presentation/widgets/player_panel.dart';
import 'package:ludo_arena/features/ludo/presentation/board/ludo_board.dart';
import 'package:ludo_arena/features/snakes_ladders/presentation/board/snakes_board.dart';
import 'package:ludo_arena/features/social/application/muted_players.dart';
import 'package:ludo_arena/l10n/generated/app_localizations.dart';
import 'package:ludo_arena/shared/game_visuals/game_visuals.dart';
import 'package:ludo_arena/shared/widgets/widgets.dart';

import 'support/play_test_support.dart';

const _column = ValueKey('pod-progress-column');

/// Pumps one [PlayerPanel] [width] wide, in the real theme + localizations.
Future<void> _pumpPanel(
  WidgetTester tester, {
  required double width,
  bool stacked = true,
  double? height,
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
                height: height,
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
  EdgeInsets safeArea = EdgeInsets.zero,
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
    safeArea: safeArea,
    textScale: textScale,
    locale: locale,
  );
  await flush(tester);
  return h;
}

/// iPhone 17 Pro / 16 / 15-style insets (status bar + home indicator).
const _iphoneInsets = EdgeInsets.only(top: 62, bottom: 34);

/// The board itself (its aspect box), Ludo or Snakes.
Rect _boardRect(WidgetTester tester) {
  final ludo = find.byType(LudoBoard);
  return tester.getRect(
    find
        .descendant(
          of: ludo.evaluate().isEmpty ? find.byType(SnakesBoard) : ludo,
          matching: find.byType(AspectRatio),
        )
        .first,
  );
}

Finder _podOf(int seat) =>
    find.byWidgetPredicate((w) => w is PlayerPanel && w.player.seat == seat);

Size _podSize(WidgetTester tester) => tester.getSize(find.byType(PlayerPanel));

double _avatar(WidgetTester tester, [Finder? pod]) => tester
    .getSize(
      find.descendant(
        of: pod ?? find.byType(PlayerPanel),
        matching: find.byType(PlayerAvatar),
      ),
    )
    .width;

Rect _panelRect(WidgetTester tester, int seat) => tester.getRect(_podOf(seat));

void main() {
  // Pod sizes measured before the progress column moved beside the avatar
  // (classic card: 56 dp avatar with the "★○○○ 0/4" line under the name).
  // The redesign must keep every one of them. These are pods at their
  // natural size (no fill height: the landscape side column, or portrait
  // rows too short to fill); portrait pods fill their row (see below).
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
  });

  // Portrait: the board keeps its full width (body − 12) and the two pod
  // rows split the height it leaves:
  //   area = body − top bar (56) − status line (40)
  //   pod  = ⌊(area − 4 (top gap) − 12 (board padding) − board) / 2⌋
  // with board = (width − 12) × 1.1 for Ludo, ÷ 0.8225 for Snakes. A filled
  // card's avatar row is pod − 35 (paddings 2 × 5, turn border 2 × 2, gap 3,
  // 18 dp name line), its avatar that minus a 10–12 dp turn-ring gap,
  // within width − 58 and 96 dp. All four pods are the same size, on turn
  // or not. Before this, these phones had 64–80 dp row pods (40–48 dp
  // avatars) with up to 44 dp of empty space above and below the board.
  group('portrait pods fill the height around the full-width board', () {
    for (final c in [
      // iPhone 17 Pro (owner's report): body 778 → area 682; board 390 ×
      // 429 → pods 118; avatar row 83 → 71 dp avatars (were 48 in 78 dp
      // row pods). Pods need 129 dp of width, so the dice dock takes 8 dp
      // of the rest (88 dp dock, pods 147 wide).
      (
        size: const Size(402, 874),
        safeArea: _iphoneInsets,
        snakes: false,
        avatar: 71.0,
        rects: {
          1: const Rect.fromLTRB(8, 122, 155, 240),
          2: const Rect.fromLTRB(247, 122, 394, 240),
          0: const Rect.fromLTRB(8, 682, 155, 800),
          3: const Rect.fromLTRB(247, 682, 394, 800),
        },
      ),
      // Snakes' board is taller (390 × 474.2) → pods 95; avatar row 60 →
      // 50 dp avatars (were 48), full names under them; 80 dp dock.
      (
        size: const Size(402, 874),
        safeArea: _iphoneInsets,
        snakes: true,
        avatar: 50.0,
        rects: {
          1: const Rect.fromLTRB(8, 122, 159, 217),
          2: const Rect.fromLTRB(243, 122, 394, 217),
          0: const Rect.fromLTRB(8, 705, 159, 800),
          3: const Rect.fromLTRB(243, 705, 394, 800),
        },
      ),
      // No insets: area 756, board 381 × 419.1 → pods 160; the 146.5 dp
      // width caps the avatar at 88 (was a 133 dp card with 74).
      (
        size: const Size(393, 852),
        safeArea: EdgeInsets.zero,
        snakes: false,
        avatar: 88.0,
        rects: {
          1: const Rect.fromLTRB(8, 60, 154.5, 220),
          2: const Rect.fromLTRB(238.5, 60, 385, 220),
          0: const Rect.fromLTRB(8, 652, 154.5, 812),
          3: const Rect.fromLTRB(238.5, 652, 385, 812),
        },
      ),
      // Area 644, board 348 × 382.8 → pods 122; 130 dp wide → 72 dp
      // avatars (were 44 in 70 dp row pods).
      (
        size: const Size(360, 740),
        safeArea: EdgeInsets.zero,
        snakes: false,
        avatar: 72.0,
        rects: {
          1: const Rect.fromLTRB(8, 60, 138, 182),
          2: const Rect.fromLTRB(222, 60, 352, 182),
          0: const Rect.fromLTRB(8, 578, 138, 700),
          3: const Rect.fromLTRB(222, 578, 352, 700),
        },
      ),
      // Area 544, board 308 × 338.8 → pods 94; avatar row 59 → 49 dp
      // avatars (were 40 in 64 dp row pods).
      (
        size: const Size(320, 640),
        safeArea: EdgeInsets.zero,
        snakes: false,
        avatar: 49.0,
        rects: {
          1: const Rect.fromLTRB(8, 60, 118, 154),
          2: const Rect.fromLTRB(202, 60, 312, 154),
          0: const Rect.fromLTRB(8, 506, 118, 600),
          3: const Rect.fromLTRB(202, 506, 312, 600),
        },
      ),
    ]) {
      testWidgets('${c.snakes ? 'Snakes' : 'Ludo'} at '
          '${c.size.width}×${c.size.height}, insets '
          '${c.safeArea.top}/${c.safeArea.bottom}', (tester) async {
        await _pumpGame(
          tester,
          c.snakes ? snakesRoom() : ludoRoom(),
          size: c.size,
          safeArea: c.safeArea,
        );
        for (final MapEntry(key: seat, value: rect) in c.rects.entries) {
          expect(_panelRect(tester, seat), rect, reason: 'seat $seat');
          expect(_avatar(tester, _podOf(seat)), c.avatar, reason: '$seat');
        }
      });
    }

    testWidgets('a portrait tablet (height-limited board): natural pods, '
        'the default 80 dp dock', (tester) async {
      // Area 928, a full-width board would be 756 × 831.6 → 40 dp rows:
      // too short to fill, so the pods keep their natural row size and the
      // board gives way, as before.
      await _pumpGame(tester, ludoRoom(), size: const Size(768, 1024));
      expect(_panelRect(tester, 1).size, const Size(334, 90));
      expect(_panelRect(tester, 0).size, const Size(334, 92)); // turn
      expect(tester.getSize(find.byType(DiceView)), const Size.square(56));
      expect(_boardRect(tester).width, lessThan(768 - 12));
    });

    for (final c in [
      (size: const Size(402, 874), safeArea: _iphoneInsets),
      (size: const Size(390, 844), safeArea: _iphoneInsets),
      // Android: status bar; gesture bar.
      (size: const Size(360, 740), safeArea: const EdgeInsets.only(top: 24)),
      (
        size: const Size(412, 915),
        safeArea: const EdgeInsets.only(top: 24, bottom: 24),
      ),
      (size: const Size(320, 640), safeArea: EdgeInsets.zero),
    ]) {
      for (final snakes in [false, true]) {
        testWidgets('${snakes ? 'Snakes' : 'Ludo'} at '
            '${c.size.width}×${c.size.height} (insets ${c.safeArea.top}/'
            '${c.safeArea.bottom}): no gap, full-width board', (tester) async {
          await _pumpGame(
            tester,
            snakes ? snakesRoom(positions: [0, 12, 34, 57]) : ludoRoom(),
            size: c.size,
            safeArea: c.safeArea,
          );
          final bodyBottom = c.size.height - c.safeArea.bottom;
          final board = _boardRect(tester);
          expect(board.width, c.size.width - 12);
          final pods = {
            for (final s in [0, 1, 2, 3]) s: _panelRect(tester, s),
          };
          // All four the same size (seat 0 has the turn).
          for (final s in [1, 2, 3]) {
            expect(pods[s]!.size, pods[0]!.size, reason: 'seat $s');
          }
          // Top pods (seats 1, 2) right above the board, bottom pods
          // (0, 3) right below it: no more than the 6 dp board padding
          // (plus rounding).
          for (final s in [1, 2]) {
            final gap = board.top - pods[s]!.bottom;
            expect(gap, inInclusiveRange(0, 12), reason: 'top gap, seat $s');
            expect(pods[s]!.top, greaterThanOrEqualTo(c.safeArea.top));
          }
          for (final s in [0, 3]) {
            final gap = pods[s]!.top - board.bottom;
            expect(gap, inInclusiveRange(0, 12), reason: 'bottom gap $s');
            // Right above the 40 dp status line, inside the safe area.
            expect(pods[s]!.bottom, bodyBottom - 40);
          }
          // The dice dock sits between the bottom pods, centered on them.
          final dice = tester.getRect(find.byType(DiceView));
          expect(dice.center.dy, moreOrLessEquals(pods[0]!.center.dy));
          expect(dice.left, greaterThan(pods[0]!.right));
          expect(dice.right, lessThan(pods[3]!.left));
        });
      }
    }
  });

  group('card (stacked) pods', () {
    testWidgets('the avatar grows from 56 to 74 dp', (tester) async {
      for (final w in [150.5, 134.0]) {
        await _pumpPanel(tester, width: w);
        expect(_avatar(tester), 74);
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

  group('filled pods (portrait rows)', () {
    testWidgets('a card fills the height, the same on and off turn', (
      tester,
    ) async {
      for (final turn in [false, true]) {
        for (final p in [
          player(1),
          player(1, name: 'Riya', frame: 'frame_royal'),
          player(1, connected: false, strikes: 2),
          player(1, forfeited: true),
        ]) {
          await _pumpPanel(tester, width: 147, height: 118, p: p, isTurn: turn);
          expect(_podSize(tester), const Size(147, 118), reason: p.name);
          // Avatar row 118 − 35 = 83, minus the 12 dp turn-ring gap.
          expect(_avatar(tester), 71, reason: p.name);
        }
      }
      // Larger text: a taller name line, a smaller avatar, the same pod.
      await _pumpPanel(tester, width: 147, height: 118, textScale: 1.35);
      expect(_podSize(tester), const Size(147, 118));
      expect(_avatar(tester), 65);
    });

    for (final (locale, rtl) in [
      (const Locale('en'), false),
      (const Locale('ar'), true),
    ]) {
      testWidgets('card: progress column on the avatar\'s '
          '${rtl ? 'left (RTL)' : 'right'}, the full name under both', (
        tester,
      ) async {
        await _pumpPanel(tester, width: 147, height: 118, locale: locale);
        final avatar = tester.getRect(find.byType(PlayerAvatar));
        final column = tester.getRect(find.byKey(_column));
        final name = tester.getRect(find.text('Player1'));
        if (rtl) {
          expect(column.right, lessThan(avatar.left));
        } else {
          expect(column.left, greaterThan(avatar.right));
        }
        expect(
          find.descendant(of: find.byKey(_column), matching: find.text('0/4')),
          findsOneWidget,
        );
        expect(name.top, greaterThan(avatar.bottom));
        expect(name.top, greaterThan(column.bottom));
        // Centered in the pod, both ways.
        final pod = tester.getRect(find.byType(PlayerPanel));
        expect(avatar.top - pod.top, greaterThan(0));
        expect(name.center.dx, moreOrLessEquals(pod.center.dx, epsilon: 12));
      });
    }

    testWidgets('a short card keeps four marks and drops the count', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpPanel(tester, width: 110, height: 94);
      expect(_podSize(tester), const Size(110, 94));
      expect(_avatar(tester), 49);
      expect(
        find.descendant(of: find.byKey(_column), matching: find.byType(Icon)),
        findsNWidgets(4),
      );
      expect(find.text('0/4'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'Player1, .*0 of 4 tokens home')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('Snakes & Ladders: the square beside a 50 dp avatar', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        width: 151,
        height: 95,
        room: snakesRoom(positions: [0, 12, 0, 0]),
      );
      expect(_podSize(tester), const Size(151, 95));
      expect(_avatar(tester), 50);
      expect(
        find.descendant(of: find.byKey(_column), matching: find.text('12')),
        findsOneWidget,
      );
    });

    testWidgets('a wide pod stays a row; its avatar grows with the height', (
      tester,
    ) async {
      // A row's avatar is 120 − 2 × 2 − 2 × 6 − 12 = 92; a card's would be
      // 120 − 35 − 12 = 73.
      await _pumpPanel(tester, width: 300, height: 120);
      expect(_podSize(tester), const Size(300, 120));
      expect(_avatar(tester), 92);
      final avatar = tester.getRect(find.byType(PlayerAvatar));
      final column = tester.getRect(find.byKey(_column));
      final name = tester.getRect(find.text('Player1'));
      expect(column.left, greaterThan(avatar.right));
      expect(name.left, greaterThan(column.right));
    });

    testWidgets('shorter than a row pod: the natural row pod', (tester) async {
      await _pumpPanel(tester, width: 151, height: 70, stacked: false);
      expect(_podSize(tester), const Size(151, 78));
      expect(_avatar(tester), 48);
    });

    testWidgets('at most 176 dp tall, 96 dp avatar', (tester) async {
      await _pumpPanel(tester, width: 170, height: 400);
      expect(_podSize(tester), const Size(170, 176));
      expect(_avatar(tester), 96);
    });

    testWidgets('the turn ring wraps the filled avatar', (tester) async {
      await _pumpPanel(tester, width: 147, height: 118, isTurn: true);
      expect(tester.getSize(find.byType(CountdownRing)), const Size.square(83));
      expect(
        tester.getRect(find.byType(CountdownRing)).center,
        tester.getRect(find.byType(PlayerAvatar)).center,
      );
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
    const none = EdgeInsets.zero;
    const android = EdgeInsets.only(top: 24, bottom: 24);
    for (final c in [
      (size: const Size(320, 640), insets: none, ts: 1.0, locale: 'en'),
      (size: const Size(320, 640), insets: none, ts: 1.35, locale: 'en'),
      (size: const Size(393, 852), insets: none, ts: 1.35, locale: 'en'),
      (size: const Size(360, 740), insets: none, ts: 1.35, locale: 'ar'),
      (size: const Size(393, 852), insets: none, ts: 1.0, locale: 'ur'),
      (
        size: const Size(402, 874),
        insets: _iphoneInsets,
        ts: 1.35,
        locale: 'ar',
      ),
      (
        size: const Size(402, 874),
        insets: _iphoneInsets,
        ts: 1.35,
        locale: 'ur',
      ),
      (
        size: const Size(390, 844),
        insets: _iphoneInsets,
        ts: 1.35,
        locale: 'en',
      ),
      (size: const Size(412, 915), insets: android, ts: 1.35, locale: 'ar'),
    ]) {
      testWidgets('${c.size.width}×${c.size.height}'
          '${c.insets == none ? '' : ' (insets)'}, text ×${c.ts}, '
          '${c.locale}', (tester) async {
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
            safeArea: c.insets,
            textScale: c.ts,
            locale: Locale(c.locale),
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
            safeArea: c.insets,
            textScale: c.ts,
            locale: Locale(c.locale),
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

    // Every pod width a phone gives (110 dp on a 320 dp screen up to 430 dp
    // screens, and a wide row) at row heights from a row pod's to the cap
    // (shorter: the natural row pod): Ludo and Snakes, offline with strikes
    // and muted on the turn, text ×1.35, RTL.
    testWidgets('every filled pod, text ×1.35, dark, ar', (tester) async {
      await expectNoOverflow(tester, () async {
        for (final room in [
          ludoRoom(),
          snakesRoom(positions: [0, 100, 0, 0]),
        ]) {
          for (final w in [110.0, 112.0, 124.0, 130.0, 147.0, 151.0, 220.0]) {
            for (final h in [
              66.0,
              76.0,
              88.0,
              95.0,
              110.0,
              118.0,
              140.0,
              176.0,
            ]) {
              for (final connected in [false, true]) {
                await _pumpPanel(
                  tester,
                  width: w,
                  stacked: false,
                  height: h,
                  room: room,
                  p: player(1, connected: connected, strikes: 3),
                  isTurn: true,
                  muted: true,
                  textScale: 1.35,
                  locale: const Locale('ar'),
                  themeMode: ThemeMode.dark,
                );
              }
            }
          }
        }
      });
    });
  });
}
