import 'package:flutter/foundation.dart';

import '../../../core/protocol/protocol.dart';
import '../../missions/domain/mission_models.dart';
import '../../profile/progression.dart';

/// What the next goal after a match is about ([param] is the analytics
/// `kind`).
enum NextGoalKind {
  playtime('playtime'),
  mission('mission'),
  claim('claim'),
  level('level');

  const NextGoalKind(this.param);
  final String param;
}

/// One achievable objective, chosen from server data only.
@immutable
class NextGoal {
  const NextGoal._(
    this.kind, {
    this.milestone,
    this.mission,
    this.remaining = 0,
    this.level = 0,
  });

  /// [remaining] minutes of play unlock [milestone].
  const NextGoal.playtime(PlaytimeMilestone milestone, int remaining)
    : this._(NextGoalKind.playtime, milestone: milestone, remaining: remaining);

  /// [remaining] more completions finish the daily [mission].
  const NextGoal.mission(Mission mission, int remaining)
    : this._(NextGoalKind.mission, mission: mission, remaining: remaining);

  /// [mission] is complete and its reward waits to be claimed.
  const NextGoal.claim(Mission mission)
    : this._(NextGoalKind.claim, mission: mission);

  /// [remaining] XP reach [level].
  const NextGoal.level(int level, int remaining)
    : this._(NextGoalKind.level, level: level, remaining: remaining);

  final NextGoalKind kind;
  final PlaytimeMilestone? milestone;
  final Mission? mission;

  /// Minutes (playtime), completions (mission) or XP (level).
  final int remaining;

  /// The level to reach ([NextGoalKind.level]).
  final int level;
}

/// A playtime milestone at most this far away is "within reach".
const int kPlaytimeGoalWithinMinutes = 15;

/// Picks one next goal, in priority order: a playtime milestone within
/// [kPlaytimeGoalWithinMinutes], the daily mission closest to completion, a
/// mission reward ready to claim, the XP to the next level. Null when
/// nothing applies (everything done, or no data yet).
NextGoal? pickNextGoal({
  Playtime? playtime,
  MissionsBoard? board,
  ProgressionSummary? progression,
}) {
  final next = playtime?.next;
  if (playtime != null && next != null) {
    final left = playtime.remainingMinutes(next);
    if (left > 0 && left <= kPlaytimeGoalWithinMinutes) {
      return NextGoal.playtime(next, left);
    }
  }
  if (board != null) {
    Mission? best;
    for (final m in board.daily.missions) {
      if (m.status != MissionStatus.inProgress) continue;
      if (best == null ||
          m.fraction > best.fraction ||
          (m.fraction == best.fraction &&
              m.target - m.shownProgress < best.target - best.shownProgress)) {
        best = m;
      }
    }
    if (best != null) {
      return NextGoal.mission(best, best.target - best.shownProgress);
    }
    for (final (_, m) in board.all) {
      if (m.status == MissionStatus.claimable) return NextGoal.claim(m);
    }
  }
  if (progression != null && !progression.isMaxLevel) {
    final left = progression.levelXp + progression.nextLevelXp - progression.xp;
    if (left > 0) return NextGoal.level(progression.level + 1, left);
  }
  return null;
}
