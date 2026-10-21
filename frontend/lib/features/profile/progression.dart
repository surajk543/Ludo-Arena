import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_models.dart';
import '../authentication/application/session_controller.dart';

/// Level math mirrored from the backend (display only; the server is
/// authoritative for `xp` and `level`).
abstract final class LevelMath {
  static const int maxLevel = 50;

  /// XP needed from [level] to [level] + 1 (the `nextLevelXp` API field).
  static int toNext(int level) => 100 + 50 * ((level < 1 ? 1 : level) - 1);

  /// Total XP at which [level] starts (the `levelXp` API field).
  static int levelStart(int level) {
    if (level <= 1) return 0;
    final l = (level > maxLevel ? maxLevel : level) - 1;
    return 100 * l + 25 * l * (l - 1);
  }
}

/// Level / XP / title summary for headers and the profile.
@immutable
class ProgressionSummary {
  const ProgressionSummary({
    required this.level,
    required this.xp,
    required this.levelXp,
    required this.nextLevelXp,
    required this.title,
  });

  factory ProgressionSummary.fromUser(User u) => ProgressionSummary(
    level: u.level,
    xp: u.xp,
    levelXp: u.levelXp,
    nextLevelXp: u.nextLevelXp,
    title: u.loadout.title.isNotEmpty ? u.loadout.title : u.title,
  );

  final int level;

  /// Total XP.
  final int xp;

  /// XP at which the current level started.
  final int levelXp;

  /// XP needed to go from this level to the next.
  final int nextLevelXp;

  /// Equipped title id (`title_rookie`, …).
  final String title;

  bool get isMaxLevel => level >= LevelMath.maxLevel;

  /// XP earned inside the current level (0..nextLevelXp).
  int get xpIntoLevel {
    final v = xp - levelXp;
    if (v < 0) return 0;
    return v > nextLevelXp ? nextLevelXp : v;
  }

  /// XP still missing for the next level.
  int get xpRemaining => isMaxLevel ? 0 : nextLevelXp - xpIntoLevel;

  double get fraction =>
      isMaxLevel || nextLevelXp <= 0 ? 1 : xpIntoLevel / nextLevelXp;
}

/// Current user's progression (from `/me`, auth responses and
/// `progression.updated`), or null when signed out.
final progressionSummaryProvider = Provider<ProgressionSummary?>((ref) {
  final user = ref.watch(sessionControllerProvider.select((s) => s.user));
  return user == null ? null : ProgressionSummary.fromUser(user);
});
