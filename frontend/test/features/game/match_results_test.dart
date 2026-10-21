import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/active_room_controller.dart';
import 'package:ludo_royale/features/game/application/match_result_view.dart';
import 'package:ludo_royale/features/game/presentation/widgets/results_panel.dart';

import 'support/play_test_support.dart';

RoomSnapshot _finished({
  int winner = 0,
  int payout = 4000,
  List<RoomPlayer>? players,
  List<int> placements = const [0, 2, 1, 3],
  String mode = RoomModes.public,
  RematchState? rematch,
}) => ludoRoom(
  status: RoomStatuses.finished,
  mode: mode,
  players: players,
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

    test('winner payout comes from the server result; bots pay nothing', () {
      final won = MatchResultView.from(_finished(), 'u_0');
      expect(won.outcome, MatchOutcome.won);
      expect(won.selfPayout, 4000);
      final bots = MatchResultView.from(
        _finished(
          payout: 0,
          players: [player(0), player(1, bot: true)],
          placements: const [0, 1],
        ),
        'u_0',
      );
      expect(bots.botMatch, isTrue);
      expect(bots.selfPayout, 0);
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
      r = r.apply(const ProgressionUpdatedEvent(xp: 100, level: 2, xpGained: 35));
      r = r.apply(const ProgressionUpdatedEvent(xp: 999, level: 9, xpGained: 1));
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
