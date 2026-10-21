import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/state/in_match_provider.dart';
import 'package:ludo_royale/features/progression/application/level_up_controller.dart';
import 'package:ludo_royale/features/progression/domain/progression_models.dart';
import 'package:ludo_royale/features/progression/presentation/level_up_celebration_host.dart';
import 'package:ludo_royale/features/progression/presentation/progression_screen.dart';

import 'meta_test_support.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());

  group('LevelUpController', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    LevelUpController ctl() => c.read(levelUpControllerProvider.notifier);

    test('merges same-level duplicates (claim + push) into one', () {
      ctl()
        ..enqueue(5, ['dice_neon'])
        ..enqueue(5, ['dice_neon', 'title_strategist']);
      final s = c.read(levelUpControllerProvider);
      expect(s.pending, hasLength(1));
      expect(s.pending.single.unlocked, ['dice_neon', 'title_strategist']);
    });

    test('takes all pending as one celebration and ignores repeats', () {
      ctl()
        ..enqueue(6, ['emote_wow'])
        ..enqueue(5, ['dice_neon']);
      final next = ctl().takeNext()!;
      expect(next.level, 6);
      expect(next.unlocked, containsAll(['dice_neon', 'emote_wow']));
      // Single flight while showing.
      expect(ctl().takeNext(), isNull);
      ctl().markShown();
      // A late duplicate of a celebrated level is ignored.
      ctl().enqueue(6, ['emote_wow']);
      expect(ctl().takeNext(), isNull);
    });
  });

  group('celebration host', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    Widget host() => const LevelUpCelebrationHost(
      afterMatchDelay: Duration(milliseconds: 300),
      child: Scaffold(body: Text('home')),
    );

    testWidgets('a level-up during a match waits until the match closes', (
      tester,
    ) async {
      final c = await pumpMeta(tester, env, fakes, host());
      c.read(inMatchProvider.notifier).set(true);
      await tester.pump();

      fakes.progression.add(
        const ProgressionUpdatedEvent(
          xp: 705,
          level: 5,
          xpGained: 35,
          levelUp: true,
          unlocked: ['dice_neon', 'title_strategist'],
        ),
      );
      await flush(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Level up!'), findsNothing);
      expect(c.read(levelUpControllerProvider).hasPending, isTrue);

      // Match screen closes → shown after the short delay.
      c.read(inMatchProvider.notifier).set(false);
      await tester.pump();
      expect(find.text('Level up!'), findsNothing);
      await tester.pump(const Duration(milliseconds: 350));
      await settleRoute(tester);
      expect(find.text('Level up!'), findsOneWidget);
      expect(find.text('You reached level 5.'), findsOneWidget);
      expect(find.text('Neon Pulse'), findsOneWidget);
      expect(find.text('Strategist'), findsWidgets);

      await tester.tap(find.text('Awesome!'));
      await settleRoute(tester);
      expect(find.text('Level up!'), findsNothing);
      expect(c.read(levelUpControllerProvider).showing, isFalse);
    });

    testWidgets('outside a match the celebration shows right away', (
      tester,
    ) async {
      await pumpMeta(tester, env, fakes, host());
      fakes.progression.add(
        const ProgressionUpdatedEvent(xp: 705, level: 5, levelUp: true),
      );
      await settleRoute(tester);
      expect(find.text('Level up!'), findsOneWidget);
      // No unlocked items → no "View collection".
      expect(find.text('View collection'), findsNothing);
    });

    testWidgets('pushes without levelUp never celebrate', (tester) async {
      await pumpMeta(tester, env, fakes, host());
      fakes.progression.add(
        const ProgressionUpdatedEvent(xp: 540, level: 4, xpGained: 20),
      );
      await settleRoute(tester);
      expect(find.text('Level up!'), findsNothing);
    });
  });

  group('level road', () {
    test('LevelNumbers: progress = (xp − levelXp) / nextLevelXp', () {
      final p = ProgressionView.fromJson(progressionJson());
      expect(p.xpIntoLevel, 70);
      expect(p.xpRemaining, 180);
      expect(p.fraction, closeTo(0.28, 1e-9));
      expect(p.nextMilestone!.level, 5);
      const max = ProgressionView(
        level: 50,
        xp: 70000,
        levelXp: 63700,
        nextLevelXp: 2550,
      );
      expect(max.isMaxLevel, isTrue);
      expect(max.fraction, 1);
      expect(max.xpRemaining, 0);
    });

    testWidgets('shows reached, next and locked milestones', (tester) async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      final fakes = MetaFakes();
      addTearDown(fakes.close);
      await pumpMeta(tester, env, fakes, const ProgressionScreen());
      expect(find.text('Level 4'), findsOneWidget);
      expect(find.text('180 XP to level 5'), findsOneWidget);
      expect(find.text('Unlocked'), findsNWidgets(2));
      await scrollTo(tester, find.text('Next milestone · 180 XP to go'));
      expect(find.text('Next milestone · 180 XP to go'), findsOneWidget);
      // Level 6 starts at 100·5 + 25·5·4 = 1,000 XP → 480 to go.
      await scrollTo(tester, find.text('480 XP to go'));
      expect(find.text('480 XP to go'), findsOneWidget);
    });
  });
}
