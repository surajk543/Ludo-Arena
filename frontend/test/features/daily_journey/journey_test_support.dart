import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/core/realtime/realtime_providers.dart';

import '../progression/meta_test_support.dart';

/// `PlaytimeMilestone` JSON (server shape).
Map<String, dynamic> milestoneJson(
  String id,
  int minutes, {
  int coins = 5000,
  int xp = 25,
  String status = 'locked',
}) => {
  'id': id,
  'minutes': minutes,
  'reward': {'coins': coins, 'diamonds': 0, 'xp': xp, 'items': []},
  'status': status,
};

/// `Playtime` JSON with the default 10 / 30 / 60 minute milestones; the
/// statuses follow [seconds] unless [completed] says otherwise.
Map<String, dynamic> playtimeJson({
  int seconds = 18 * 60,
  String periodKey = 'd2026-10-21',
  String resetsAt = '2026-10-22T00:00:00Z',
  Set<String>? completed,
  List<Map<String, dynamic>> granted = const [],
}) {
  const defs = [
    ('playtime_10m', 10, 5000, 25),
    ('playtime_30m', 30, 10000, 40),
    ('playtime_60m', 60, 20000, 60),
  ];
  final done =
      completed ??
      {
        for (final d in defs)
          if (seconds >= d.$2 * 60) d.$1,
      };
  final next = defs.where((d) => !done.contains(d.$1)).firstOrNull?.$1;
  return {
    'periodKey': periodKey,
    'resetsAtUtc': resetsAt,
    'seconds': seconds,
    'milestones': [
      for (final d in defs)
        milestoneJson(
          d.$1,
          d.$2,
          coins: d.$3,
          xp: d.$4,
          status: done.contains(d.$1)
              ? 'completed'
              : d.$1 == next
              ? 'in_progress'
              : 'locked',
        ),
    ],
    'granted': granted,
  };
}

/// Records the Daily Play Journey analytics events too.
class JourneyAnalytics extends MetaAnalytics {
  @override
  void playtimeProgressViewed(String surface) =>
      events.add('playtime_progress_viewed:$surface');
  @override
  void playtimeMilestoneCompleted(int minutes) =>
      events.add('playtime_milestone_completed:$minutes');
  @override
  void playtimeRewardGranted({
    required int minutes,
    required int xp,
    required int coins,
  }) => events.add('playtime_reward_granted:$minutes:$xp:$coins');
  @override
  void playtimeToastDismissed(String method) =>
      events.add('playtime_toast_dismissed:$method');
  @override
  void nextGoalShown(String kind) => events.add('next_goal_shown:$kind');
  @override
  void nextGoalTapped(String kind) => events.add('next_goal_tapped:$kind');
}

/// Meta fakes plus a `playtime.updated` push stream and journey analytics.
class JourneyFakes extends MetaFakes {
  final playtime = StreamController<PlaytimeUpdatedEvent>.broadcast();

  final JourneyAnalytics _analytics = JourneyAnalytics();

  @override
  JourneyAnalytics get analytics => _analytics;

  @override
  List<Override> get overrides => [
    ...super.overrides,
    playtimeUpdatesProvider.overrideWith((ref) => playtime.stream),
  ];

  /// Pushes a server `playtime.updated`.
  void push(Map<String, dynamic> json) =>
      playtime.add(PlaytimeUpdatedEvent.fromJson(json));

  @override
  Future<void> close() async {
    await playtime.close();
    await super.close();
  }
}
