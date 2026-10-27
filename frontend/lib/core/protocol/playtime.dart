import 'package:flutter/foundation.dart';

import 'json_read.dart';

/// Daily playtime (`GET /playtime`, `GET /missions` → `playtime`,
/// `playtime.updated`; docs/rest-api.md → Playtime). The server counts the
/// time; the app only renders it.

/// `PlaytimeMilestone.status`.
enum PlaytimeMilestoneStatus {
  /// The reward was granted (coins and XP already credited).
  completed,

  /// The first milestone not completed yet.
  inProgress,

  /// Every later milestone.
  locked;

  static PlaytimeMilestoneStatus parse(String? s) => switch (s) {
    'completed' => completed,
    'in_progress' => inProgress,
    _ => locked,
  };
}

/// `PlaytimeMilestone.reward` (coins, diamonds, XP; never items).
@immutable
class PlaytimeReward {
  const PlaytimeReward({this.coins = 0, this.diamonds = 0, this.xp = 0});

  factory PlaytimeReward.fromJson(Map<String, dynamic> j) => PlaytimeReward(
    coins: readInt(j['coins']),
    diamonds: readInt(j['diamonds']),
    xp: readInt(j['xp']),
  );

  final int coins;
  final int diamonds;
  final int xp;

  PlaytimeReward operator +(PlaytimeReward o) => PlaytimeReward(
    coins: coins + o.coins,
    diamonds: diamonds + o.diamonds,
    xp: xp + o.xp,
  );

  @override
  bool operator ==(Object other) =>
      other is PlaytimeReward &&
      other.coins == coins &&
      other.diamonds == diamonds &&
      other.xp == xp;

  @override
  int get hashCode => Object.hash(coins, diamonds, xp);
}

/// One daily playtime milestone (`playtime_10m`, …).
@immutable
class PlaytimeMilestone {
  const PlaytimeMilestone({
    required this.id,
    required this.minutes,
    this.reward = const PlaytimeReward(),
    this.status = PlaytimeMilestoneStatus.locked,
  });

  factory PlaytimeMilestone.fromJson(Map<String, dynamic> j) =>
      PlaytimeMilestone(
        id: readString(j['id']),
        minutes: readInt(j['minutes']),
        reward: PlaytimeReward.fromJson(readMap(j['reward'])),
        status: PlaytimeMilestoneStatus.parse(readStringOrNull(j['status'])),
      );

  static List<PlaytimeMilestone> listFrom(Object? raw) =>
      List<PlaytimeMilestone>.unmodifiable(
        readList(raw)
            .map((m) => PlaytimeMilestone.fromJson(readMap(m)))
            .where((m) => m.id.isNotEmpty && m.minutes > 0),
      );

  final String id;
  final int minutes;
  final PlaytimeReward reward;
  final PlaytimeMilestoneStatus status;

  int get thresholdSeconds => minutes * 60;
  bool get completed => status == PlaytimeMilestoneStatus.completed;

  PlaytimeMilestone withStatus(PlaytimeMilestoneStatus s) => s == status
      ? this
      : PlaytimeMilestone(id: id, minutes: minutes, reward: reward, status: s);
}

/// Today's qualifying playtime.
@immutable
class Playtime {
  const Playtime({
    required this.periodKey,
    this.resetsAtUtc,
    this.seconds = 0,
    this.milestones = const [],
  });

  factory Playtime.fromJson(Map<String, dynamic> j) {
    final reset = readStringOrNull(j['resetsAtUtc']);
    final seconds = readInt(j['seconds']);
    return Playtime(
      periodKey: readString(j['periodKey']),
      resetsAtUtc: reset == null ? null : DateTime.tryParse(reset)?.toUtc(),
      seconds: seconds < 0 ? 0 : seconds,
      milestones: PlaytimeMilestone.listFrom(j['milestones']),
    );
  }

  /// Daily period key (`d2026-10-27`), shared with the daily missions.
  final String periodKey;

  /// When today's playtime resets (UTC); null if the server omitted it.
  final DateTime? resetsAtUtc;

  /// Qualifying seconds played today (server-counted).
  final int seconds;

  /// In threshold order.
  final List<PlaytimeMilestone> milestones;

  /// Whole minutes played today.
  int get minutes => seconds ~/ 60;

  /// The last milestone's minutes (the day's goal), 0 without milestones.
  int get goalMinutes => milestones.isEmpty ? 0 : milestones.last.minutes;

  /// Progress toward the last milestone (0..1).
  double get fraction {
    final goal = goalMinutes * 60;
    if (goal <= 0) return 0;
    return (seconds / goal).clamp(0.0, 1.0);
  }

  /// The first milestone not completed yet (null when all are done).
  PlaytimeMilestone? get next {
    for (final m in milestones) {
      if (!m.completed) return m;
    }
    return null;
  }

  bool get allCompleted => milestones.isNotEmpty && next == null;

  Set<String> get completedIds => {
    for (final m in milestones)
      if (m.completed) m.id,
  };

  int get completedCount => completedIds.length;

  /// Whole minutes still needed for [m] (rounded up; 0 once reached).
  int remainingMinutes(PlaytimeMilestone m) {
    final left = m.thresholdSeconds - seconds;
    if (left <= 0) return 0;
    return (left + 59) ~/ 60;
  }

  /// Combines a newer server value: a later period replaces this one; within
  /// the same period `seconds` never decreases and a completed milestone
  /// stays completed (pushes may arrive out of order).
  Playtime merge(Playtime incoming) {
    if (incoming.periodKey != periodKey) {
      return incoming.periodKey.compareTo(periodKey) > 0 ? incoming : this;
    }
    final done = {...completedIds, ...incoming.completedIds};
    var inProgressSet = false;
    final ms = <PlaytimeMilestone>[];
    for (final m in incoming.milestones) {
      if (done.contains(m.id)) {
        ms.add(m.withStatus(PlaytimeMilestoneStatus.completed));
      } else if (!inProgressSet) {
        inProgressSet = true;
        ms.add(m.withStatus(PlaytimeMilestoneStatus.inProgress));
      } else {
        ms.add(m.withStatus(PlaytimeMilestoneStatus.locked));
      }
    }
    return Playtime(
      periodKey: incoming.periodKey,
      resetsAtUtc: incoming.resetsAtUtc ?? resetsAtUtc,
      seconds: incoming.seconds > seconds ? incoming.seconds : seconds,
      milestones: List.unmodifiable(ms),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Playtime &&
      other.periodKey == periodKey &&
      other.resetsAtUtc == resetsAtUtc &&
      other.seconds == seconds &&
      listEquals(other.milestones.map((m) => (m.id, m.status)).toList(), [
        for (final m in milestones) (m.id, m.status),
      ]);

  @override
  int get hashCode => Object.hash(
    periodKey,
    resetsAtUtc,
    seconds,
    Object.hashAll([for (final m in milestones) (m.id, m.status)]),
  );
}
