import 'package:flutter/foundation.dart';

import '../../../core/protocol/json_read.dart';
import '../../../core/protocol/models.dart' show PlayerPicture;

/// One row of the weekly friends leaderboard.
@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.rank,
    this.avatar = 0,
    this.picture,
    this.level = 1,
    this.weeklyXp = 0,
    this.isMe = false,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
    uid: readString(j['uid']),
    name: readString(j['name']),
    avatar: readInt(j['avatar']),
    picture: PlayerPicture.tryParse(j['picture']),
    level: readInt(j['level'], 1),
    weeklyXp: readInt(j['weeklyXp']),
    rank: readInt(j['rank'], 1),
    isMe: readBool(j['isMe']),
  );

  final String uid;
  final String name;
  final int avatar;

  /// Store profile picture (null: the built-in [avatar]).
  final PlayerPicture? picture;
  final int level;
  final int weeklyXp;

  /// Competition ranking: equal XP share a rank.
  final int rank;
  final bool isMe;
}

/// `GET /leaderboards/friends`.
@immutable
class FriendsLeaderboard {
  const FriendsLeaderboard({required this.periodKey, this.entries = const []});

  factory FriendsLeaderboard.fromJson(Map<String, dynamic> j) =>
      FriendsLeaderboard(
        periodKey: readString(j['periodKey']),
        entries: List.unmodifiable(
          readList(
            j['entries'],
          ).map((e) => LeaderboardEntry.fromJson(readMap(e))),
        ),
      );

  /// ISO week, e.g. `w2026-W43`.
  final String periodKey;
  final List<LeaderboardEntry> entries;

  LeaderboardEntry? get me {
    for (final e in entries) {
      if (e.isMe) return e;
    }
    return null;
  }

  /// Only the player themself (no friends yet).
  bool get isAlone => entries.where((e) => !e.isMe).isEmpty;
}

/// Next weekly reset (Monday 00:00 UTC) after [nowUtc].
DateTime nextWeeklyResetUtc(DateTime nowUtc) {
  final n = nowUtc.toUtc();
  final day = DateTime.utc(n.year, n.month, n.day);
  final daysToMonday = (DateTime.monday - day.weekday + 7) % 7;
  final candidate = day.add(Duration(days: daysToMonday));
  return candidate.isAfter(n)
      ? candidate
      : candidate.add(const Duration(days: 7));
}
