import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/core/realtime/active_room_controller.dart';
import 'package:ludo_arena/features/game/application/match_result_view.dart';
import 'package:ludo_arena/features/game/presentation/widgets/results_panel.dart';

import 'support/play_test_support.dart';

RoomSnapshot _finished({
  int winner = 0,
  int payout = 4000,
  List<RoomPlayer>? players,
  List<int> placements = const [0, 2, 1, 3],
  String mode = RoomModes.public,
  RematchState? rematch,
  List<int> computerSeats = const [],
  int? pot,
}) => ludoRoom(
  status: RoomStatuses.finished,
  mode: mode,
  players: players,
  computerSeats: computerSeats,
  pot: pot,
  result: RoomResult(
    winnerSeat: winner,
    placements: placements,
    payout: payout,
  ),
  rematch: rematch ?? RematchState(open: true, deadline: kNowMs + 30000),
);

void main() {
  group('MatchResultView', () {
    test('placements follow result.placements; forfeits go last', () {
      final room = _finished(
        placements: const [2, 0],
        players: [
          player(0),
          player(1, forfeited: true),
          player(2),
          player(3, forfeited: true),
        ],
        winner: 2,
      );
      final v = MatchResultView.from(room, 'u_0');
      expect(v.rows.map((r) => r.player.seat), [2, 0, 1, 3]);
      expect(v.rows.map((r) => r.place), [1, 2, 3, 4]);
      expect(v.rows.first.isWinner, isTrue);
      expect(v.outcome, MatchOutcome.lost);
      expect(v.selfPayout, 0, reason: 'only the winner is paid');
    });

    test('winner payout comes from the server result; no-coin matches', () {
      final won = MatchResultView.from(_finished(), 'u_0');
      expect(won.outcome, MatchOutcome.won);
      expect(won.selfPayout, 4000);
      expect(won.noCoinMatch, isFalse);
      // A match the server played without fees has an empty pot (practice);
      // seats carry no bot flag.
      final free = MatchResultView.from(
        _finished(
          mode: RoomModes.practice,
          payout: 0,
          pot: 0,
          players: [player(0), player(1)],
          placements: const [0, 1],
        ),
        'u_0',
      );
      expect(free.noCoinMatch, isTrue);
      expect(free.selfPayout, 0);
      // Only the server's pot decides: computer players pay the entry fee
      // like people, so a room with computer seats and a pot pays coins.
      final two = [player(0), player(1)];
      for (final (room, want) in [
        (_finished(mode: RoomModes.practice, players: two, pot: 0), true),
        (
          _finished(
            mode: RoomModes.private,
            players: two,
            computerSeats: const [1],
          ),
          false,
        ),
        (_finished(mode: RoomModes.private, players: two), false),
        (_finished(mode: RoomModes.public, players: two), false),
        (_finished(mode: RoomModes.public, players: two, pot: 0), true),
      ]) {
        expect(
          MatchResultView.from(room, 'u_0').noCoinMatch,
          want,
          reason: '${room.mode} ${room.computerSeats}',
        );
      }
    });

    test('forfeited local player', () {
      final v = MatchResultView.from(
        _finished(
          winner: 1,
          players: [player(0, forfeited: true), player(1)],
          placements: const [1],
        ),
        'u_0',
      );
      expect(v.outcome, MatchOutcome.forfeited);
    });
  });

  group('MatchRewards', () {
    test('keeps the payout wallet update and the first progression', () {
      var r = const MatchRewards();
      r = r.apply(
        const WalletUpdatedEvent(
          coins: 10,
          diamonds: 0,
          deltaCoins: -1000,
          reason: 'entry_fee',
        ),
      );
      expect(r.payout, isNull);
      r = r.apply(
        const WalletUpdatedEvent(
          coins: 5000,
          diamonds: 0,
          deltaCoins: 4000,
          reason: 'payout',
        ),
      );
      expect(r.payout?.coins, 5000);
      r = r.apply(
        const ProgressionUpdatedEvent(xp: 100, level: 2, xpGained: 35),
      );
      r = r.apply(
        const ProgressionUpdatedEvent(xp: 999, level: 9, xpGained: 1),
      );
      expect(r.progression?.xpGained, 35);
    });
  });

  group('ResultsPanel', () {
    Future<ValueNotifier<MatchRewards>> pumpPanel(
      WidgetTester tester, {
      required RoomSnapshot room,
      MatchRewards rewards = const MatchRewards(),
      List<bool>? rematchAnswers,
    }) async {
      final notifier = ValueNotifier<MatchRewards>(rewards);
      addTearDown(notifier.dispose);
      final h = PlayHarness(
        initial: ActiveRoomState(room: room, selfUid: 'u_0'),
      );
      await h.pump(
        tester,
        Scaffold(
          body: ValueListenableBuilder<MatchRewards>(
            valueListenable: notifier,
            builder: (context, value, _) => ResultsPanel(
              room: room,
              selfUid: 'u_0',
              rewards: value,
              onRematch: (accept) async => rematchAnswers?.add(accept),
              onPlayAgain: () {},
              onHome: () {},
            ),
          ),
        ),
      );
      return notifier;
    }

    testWidgets('shows the server payout, then XP when it arrives late', (
      tester,
    ) async {
      final rewards = await pumpPanel(tester, room: _finished());
      expect(find.text('You won!'), findsOneWidget);
      expect(find.text('+4,000 coins'), findsOneWidget);
      expect(find.text('Calculating XP…'), findsOneWidget);
      expect(find.text('+35 XP'), findsNothing);

      // wallet.updated (payout) and progression.updated arrive afterwards.
      rewards.value = rewards.value
          .apply(
            const WalletUpdatedEvent(
              coins: 1004000,
              diamonds: 0,
              deltaCoins: 4000,
              reason: 'payout',
            ),
          )
          .apply(
            const ProgressionUpdatedEvent(
              xp: 735,
              level: 5,
              xpGained: 35,
              levelUp: true,
              unlocked: ['dice_neon'],
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('+35 XP'), findsOneWidget);
      expect(find.textContaining('level 5'), findsOneWidget);
      expect(find.text('Neon Pulse'), findsOneWidget);
      expect(find.text('Calculating XP…'), findsNothing);
      expect(find.textContaining('Wallet:'), findsOneWidget);
    });

    testWidgets('no progression in time → graceful message, no invented XP', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        room: _finished(),
        rewards: const MatchRewards(progressionTimedOut: true),
      );
      expect(
        find.text('Your XP will show on your profile shortly.'),
        findsOneWidget,
      );
      expect(find.textContaining('XP', findRichText: false), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\+\d+ XP$')), findsNothing);
    });

    testWidgets('loser sees the winner and no coins', (tester) async {
      await pumpPanel(
        tester,
        room: _finished(winner: 2, placements: const [2, 0, 1, 3]),
      );
      expect(find.text('Player2 wins!'), findsOneWidget);
      expect(find.text('You finished #2'), findsOneWidget);
      expect(
        find.text('No coins this time — the winner takes the pot.'),
        findsOneWidget,
      );
    });

    testWidgets('bot opponents are never labelled in the results', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpPanel(
        tester,
        room: _finished(
          winner: 1,
          payout: 0,
          pot: 0,
          players: [
            player(0),
            player(1, name: 'Bolt'),
          ],
          placements: const [1, 0],
        ),
      );
      expect(find.text('Bolt wins!'), findsOneWidget);
      expect(find.text("This match doesn't pay coins."), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'\bbot\b', caseSensitive: false)),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp('bot|computer', caseSensitive: false)),
        findsNothing,
      );
      semantics.dispose();
    });

    testWidgets('incoming rematch request offers explicit accept / decline', (
      tester,
    ) async {
      final answers = <bool>[];
      await pumpPanel(
        tester,
        room: _finished(
          rematch: RematchState(
            open: true,
            deadline: kNowMs + 30000,
            accepted: const [1],
          ),
        ),
        rematchAnswers: answers,
      );
      expect(find.text('Player1 wants a rematch!'), findsOneWidget);
      await tester.ensureVisible(find.text('Decline'));
      await tester.tap(find.text('Decline'));
      await tester.pump();
      expect(answers, [false]);
      await tester.tap(find.text('Accept'));
      await tester.pump();
      expect(answers, [false, true]);
      // Never answered automatically.
      expect(answers, hasLength(2));
    });
  });
}
