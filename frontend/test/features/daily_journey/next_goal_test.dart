import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/features/daily_journey/application/next_goal.dart';
import 'package:ludo_arena/features/missions/domain/mission_models.dart';
import 'package:ludo_arena/features/profile/progression.dart';

import '../progression/meta_test_support.dart';
import 'journey_test_support.dart';

void main() {
  Playtime pt(int seconds) => Playtime.fromJson(playtimeJson(seconds: seconds));

  MissionsBoard board({List<Map<String, dynamic>>? daily}) =>
      MissionsBoard.fromJson(missionsJson(daily: daily));

  const level4 = ProgressionSummary(
    level: 4,
    xp: 520,
    levelXp: 450,
    nextLevelXp: 250,
    title: 'title_rookie',
  );

  test('a playtime milestone within 15 minutes comes first', () {
    final g = pickNextGoal(
      playtime: pt(18 * 60),
      board: board(),
      progression: level4,
    )!;
    expect(g.kind, NextGoalKind.playtime);
    expect(g.milestone!.id, 'playtime_30m');
    expect(g.remaining, 12);
  });

  test('a far playtime milestone yields to the closest daily mission', () {
    final g = pickNextGoal(
      playtime: pt(2 * 60), // 8 min to the first: within reach
      board: board(),
    )!;
    expect(g.kind, NextGoalKind.playtime);
    final far = pickNextGoal(
      playtime: pt(31 * 60), // 29 min to the 60-minute milestone
      board: board(
        daily: [
          missionJson('daily_play_two', progress: 1, target: 2),
          missionJson('daily_win_one', progress: 0, target: 1),
        ],
      ),
    )!;
    expect(far.kind, NextGoalKind.mission);
    expect(far.mission!.id, 'daily_play_two');
    expect(far.remaining, 1);
  });

  test('a ready-to-claim mission when every daily mission is done', () {
    final g = pickNextGoal(
      playtime: pt(65 * 60),
      board: board(
        daily: [
          missionJson('daily_ludo_match', progress: 1, target: 1),
          missionJson('daily_play_two', progress: 2, target: 2, claimed: true),
        ],
      ),
      progression: level4,
    )!;
    expect(g.kind, NextGoalKind.claim);
    expect(g.mission!.id, 'daily_ludo_match');
  });

  test('XP to the next level last; nothing when nothing applies', () {
    final g = pickNextGoal(playtime: pt(65 * 60), progression: level4)!;
    expect(g.kind, NextGoalKind.level);
    expect(g.level, 5);
    expect(g.remaining, 180);
    expect(pickNextGoal(), isNull);
    expect(
      pickNextGoal(
        progression: const ProgressionSummary(
          level: 50,
          xp: 70000,
          levelXp: 63700,
          nextLevelXp: 2550,
          title: 'title_royal',
        ),
      ),
      isNull,
    );
  });

  test('completed playtime (reward pending) is never a goal', () {
    final p = Playtime.fromJson(
      playtimeJson(seconds: 30 * 60, completed: {'playtime_10m'}),
    );
    final g = pickNextGoal(playtime: p, progression: level4)!;
    expect(g.kind, NextGoalKind.level);
  });
}
