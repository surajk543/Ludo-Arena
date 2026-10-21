import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/features/leaderboard/domain/leaderboard_models.dart';
import 'package:ludo_royale/features/leaderboard/presentation/leaderboard_screen.dart';

import '../progression/meta_test_support.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());

  test('weekly reset is the next Monday 00:00 UTC', () {
    expect(
      nextWeeklyResetUtc(DateTime.utc(2026, 10, 21, 6, 30)),
      DateTime.utc(2026, 10, 26),
    );
    // Exactly at the reset → the following week.
    expect(
      nextWeeklyResetUtc(DateTime.utc(2026, 10, 26)),
      DateTime.utc(2026, 11, 2),
    );
    expect(
      nextWeeklyResetUtc(DateTime.utc(2026, 10, 25, 23, 59)),
      DateTime.utc(2026, 10, 26),
    );
  });

  test('parses entries; ties share a rank; me is found', () {
    final lb = FriendsLeaderboard.fromJson(leaderboardJson());
    expect(lb.entries.map((e) => e.rank), [1, 2, 2]);
    expect(lb.me!.name, 'Asha');
    expect(lb.isAlone, isFalse);
    expect(
      FriendsLeaderboard.fromJson(leaderboardJson(alone: true)).isAlone,
      isTrue,
    );
  });

  group('screen', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('highlights me (${mode.name})', (tester) async {
        await pumpMeta(
          tester,
          env,
          fakes,
          const LeaderboardScreen(),
          themeMode: mode,
        );
        expect(byKeyString('lb-me'), findsOneWidget);
        expect(
          find.descendant(
            of: byKeyString('lb-me'),
            matching: find.text('Asha (you)'),
          ),
          findsOneWidget,
        );
        expect(find.text('Meera'), findsOneWidget);
        expect(find.text('640 XP'), findsOneWidget);
        expect(find.text('320 XP'), findsNWidgets(2));
        final semantics = tester.getSemantics(byKeyString('lb-me'));
        expect(semantics.label, contains('Rank 2'));
      });
    }

    testWidgets('alone: invites to add friends', (tester) async {
      env.backend.json(
        'GET',
        '/leaderboards/friends',
        leaderboardJson(alone: true),
      );
      await pumpMeta(tester, env, fakes, const LeaderboardScreen());
      expect(byKeyString('lb-me'), findsOneWidget);
      expect(
        find.textContaining('Add friends to see how you compare'),
        findsOneWidget,
      );
    });
  });
}
