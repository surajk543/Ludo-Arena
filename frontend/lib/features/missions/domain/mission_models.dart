import 'package:flutter/foundation.dart';

import '../../../core/network/api_models.dart';
import '../../../core/protocol/json_read.dart';
import '../../../core/protocol/protocol.dart' show MissionProgress, Playtime;
import '../../progression/domain/progression_models.dart';

/// Mission period kinds; [param] is the analytics `period` value.
enum MissionPeriod {
  daily('daily'),
  weekly('weekly'),
  event('event');

  const MissionPeriod(this.param);
  final String param;

  /// `d2026-10-21` → daily, `w2026-W43` → weekly, `e-autumn_cup` → event.
  static MissionPeriod ofKey(String periodKey) {
    if (periodKey.startsWith('e-')) return event;
    if (periodKey.startsWith('w')) return weekly;
    return daily;
  }
}

/// Visual state of a mission card.
enum MissionStatus { inProgress, claimable, claimed }

DateTime? _utc(Object? raw) {
  final s = readStringOrNull(raw);
  return s == null ? null : DateTime.tryParse(s)?.toUtc();
}

/// `reward` of a Mission.
@immutable
class MissionReward {
  const MissionReward({
    this.coins = 0,
    this.diamonds = 0,
    this.xp = 0,
    this.items = const [],
  });

  factory MissionReward.fromJson(Map<String, dynamic> j) => MissionReward(
    coins: readInt(j['coins']),
    diamonds: readInt(j['diamonds']),
    xp: readInt(j['xp']),
    items: ItemRef.listFrom(j['items']),
  );

  final int coins;
  final int diamonds;
  final int xp;
  final List<ItemRef> items;

  bool get isEmpty => coins <= 0 && diamonds <= 0 && xp <= 0 && items.isEmpty;
}

/// `Mission`.
@immutable
class Mission {
  const Mission({
    required this.id,
    this.title = '',
    this.description = '',
    this.game = 'any',
    this.progress = 0,
    this.target = 1,
    this.reward = const MissionReward(),
    this.completed = false,
    this.claimed = false,
  });

  factory Mission.fromJson(Map<String, dynamic> j) {
    final target = readInt(j['target'], 1);
    final progress = readInt(j['progress']);
    return Mission(
      id: readString(j['id']),
      title: readString(j['title']),
      description: readString(j['description']),
      game: readString(j['game'], 'any'),
      progress: progress,
      target: target < 1 ? 1 : target,
      reward: MissionReward.fromJson(readMap(j['reward'])),
      completed: readBool(j['completed'], progress >= target),
      claimed: readBool(j['claimed']),
    );
  }

  final String id;

  /// Server English fallback (the UI localizes by [id]).
  final String title;
  final String description;

  /// `any` | `ludo` | `snakes_ladders`.
  final String game;
  final int progress;
  final int target;
  final MissionReward reward;
  final bool completed;
  final bool claimed;

  MissionStatus get status => claimed
      ? MissionStatus.claimed
      : completed
      ? MissionStatus.claimable
      : MissionStatus.inProgress;

  /// Progress clamped to the target.
  int get shownProgress => progress.clamp(0, target);

  double get fraction => target <= 0 ? 1 : shownProgress / target;

  Mission copyWith({
    int? progress,
    int? target,
    bool? completed,
    bool? claimed,
  }) => Mission(
    id: id,
    title: title,
    description: description,
    game: game,
    progress: progress ?? this.progress,
    target: target ?? this.target,
    reward: reward,
    completed: completed ?? this.completed,
    claimed: claimed ?? this.claimed,
  );
}

/// Daily or weekly `MissionSet`.
@immutable
class MissionSet {
  const MissionSet({
    required this.periodKey,
    required this.resetsAtUtc,
    this.missions = const [],
  });

  factory MissionSet.fromJson(Map<String, dynamic> j) => MissionSet(
    periodKey: readString(j['periodKey']),
    resetsAtUtc: _utc(j['resetsAtUtc']),
    missions: List.unmodifiable(
      readList(j['missions']).map((m) => Mission.fromJson(readMap(m))),
    ),
  );

  final String periodKey;

  /// End of the period (UTC); null if the server omitted it.
  final DateTime? resetsAtUtc;
  final List<Mission> missions;

  MissionSet withMissions(List<Mission> list) => MissionSet(
    periodKey: periodKey,
    resetsAtUtc: resetsAtUtc,
    missions: List.unmodifiable(list),
  );
}

/// A running event (`EventSet`).
@immutable
class EventSet {
  const EventSet({
    required this.id,
    required this.periodKey,
    this.title = '',
    this.description = '',
    this.startsAtUtc,
    this.endsAtUtc,
    this.missions = const [],
  });

  factory EventSet.fromJson(Map<String, dynamic> j) => EventSet(
    id: readString(j['id']),
    title: readString(j['title']),
    description: readString(j['description']),
    periodKey: readString(j['periodKey']),
    startsAtUtc: _utc(j['startsAtUtc']),
    endsAtUtc: _utc(j['endsAtUtc']),
    missions: List.unmodifiable(
      readList(j['missions']).map((m) => Mission.fromJson(readMap(m))),
    ),
  );

  final String id;
  final String title;
  final String description;

  /// `e-{eventId}`.
  final String periodKey;
  final DateTime? startsAtUtc;
  final DateTime? endsAtUtc;
  final List<Mission> missions;

  EventSet withMissions(List<Mission> list) => EventSet(
    id: id,
    periodKey: periodKey,
    title: title,
    description: description,
    startsAtUtc: startsAtUtc,
    endsAtUtc: endsAtUtc,
    missions: List.unmodifiable(list),
  );
}

/// `GET /missions`.
@immutable
class MissionsBoard {
  const MissionsBoard({
    required this.daily,
    required this.weekly,
    this.events = const [],
    this.playtime,
  });

  factory MissionsBoard.fromJson(Map<String, dynamic> j) {
    final playtime = readMapOrNull(j['playtime']);
    return MissionsBoard(
      daily: MissionSet.fromJson(readMap(j['daily'])),
      weekly: MissionSet.fromJson(readMap(j['weekly'])),
      events: List.unmodifiable(
        readList(j['events']).map((e) => EventSet.fromJson(readMap(e))),
      ),
      playtime: playtime == null ? null : Playtime.fromJson(playtime),
    );
  }

  final MissionSet daily;
  final MissionSet weekly;
  final List<EventSet> events;

  /// Today's playtime when the server sent it (null: daily playtime is
  /// disabled). The live value is `playtimeControllerProvider`'s.
  final Playtime? playtime;

  /// Daily missions completed (claimable or claimed).
  int get dailyCompletedCount =>
      daily.missions.where((m) => m.status != MissionStatus.inProgress).length;

  /// Every (periodKey, mission) pair.
  Iterable<(String, Mission)> get all sync* {
    for (final m in daily.missions) {
      yield (daily.periodKey, m);
    }
    for (final m in weekly.missions) {
      yield (weekly.periodKey, m);
    }
    for (final e in events) {
      for (final m in e.missions) {
        yield (e.periodKey, m);
      }
    }
  }

  Set<String> get periodKeys => {
    daily.periodKey,
    weekly.periodKey,
    for (final e in events) e.periodKey,
  };

  int get claimableCount =>
      all.where((p) => p.$2.status == MissionStatus.claimable).length;

  bool get isEmpty => all.isEmpty;

  /// Returns a copy with [f] applied to every mission.
  MissionsBoard _map(Mission Function(String periodKey, Mission m) f) =>
      MissionsBoard(
        daily: daily.withMissions([
          for (final m in daily.missions) f(daily.periodKey, m),
        ]),
        weekly: weekly.withMissions([
          for (final m in weekly.missions) f(weekly.periodKey, m),
        ]),
        events: List.unmodifiable([
          for (final e in events)
            e.withMissions([for (final m in e.missions) f(e.periodKey, m)]),
        ]),
        playtime: playtime,
      );

  /// Replaces the mission [updated] of [periodKey].
  MissionsBoard replace(String periodKey, Mission updated) =>
      _map((pk, m) => pk == periodKey && m.id == updated.id ? updated : m);

  /// Applies `progression.updated.missions` (ids are unique across periods).
  MissionsBoard applyProgress(List<MissionProgress> changes) {
    if (changes.isEmpty) return this;
    final byId = {for (final c in changes) c.id: c};
    return _map((_, m) {
      final c = byId[m.id];
      if (c == null) return m;
      return m.copyWith(
        progress: c.progress,
        target: c.target < 1 ? m.target : c.target,
        completed: m.completed || c.completed,
      );
    });
  }
}

/// `POST /missions/{periodKey}/{missionId}/claim` response.
@immutable
class ClaimResult {
  const ClaimResult({
    required this.mission,
    required this.wallet,
    required this.progression,
    this.granted = const [],
  });

  factory ClaimResult.fromJson(Map<String, dynamic> j) => ClaimResult(
    mission: Mission.fromJson(readMap(j['mission'])),
    wallet: Wallet.fromJson(readMap(j['wallet'])),
    progression: ProgressSnapshot.fromJson(readMap(j['progression'])),
    granted: ItemRef.listFrom(j['granted']),
  );

  final Mission mission;
  final Wallet wallet;
  final ProgressSnapshot progression;

  /// Items newly added to the collection (rewards + level milestones).
  final List<ItemRef> granted;
}
