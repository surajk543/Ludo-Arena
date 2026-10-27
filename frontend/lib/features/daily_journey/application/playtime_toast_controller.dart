import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/protocol/json_read.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/storage/preferences_store.dart';
import '../../authentication/application/session_controller.dart';
import 'playtime_controller.dart';

/// One milestone toast: every milestone completed together (combined, so
/// two rewards earned at once never stack two toasts).
@immutable
class PlaytimeToast {
  const PlaytimeToast(this.milestones);

  /// In threshold order (never empty).
  final List<PlaytimeMilestone> milestones;

  /// The highest threshold reached ("You played for 30 minutes today.").
  int get minutes => milestones.last.minutes;

  /// The rewards of every milestone in this toast (server values).
  PlaytimeReward get reward =>
      milestones.fold(const PlaytimeReward(), (sum, m) => sum + m.reward);
}

@immutable
class PlaytimeToastState {
  const PlaytimeToastState({this.pending = const [], this.showing = false});

  /// Completed milestones waiting to be announced (threshold order).
  final List<PlaytimeMilestone> pending;

  /// A toast is on screen right now.
  final bool showing;

  bool get hasPending => pending.isNotEmpty;
}

/// Announces each server-confirmed playtime milestone once per device.
///
/// Sources: `playtime.updated` pushes (their `granted`) and every fresh
/// server value ([playtimeControllerProvider]) — a milestone completed while
/// this device was offline or closed is announced on the next refresh.
/// Announced ids are acknowledged in [PreferencesStore] per account and day
/// (pruned to the current day), so a restart never repeats a toast. The
/// reward itself never depends on the toast: it is already credited.
class PlaytimeToastController extends Notifier<PlaytimeToastState> {
  static const _ackKey = 'meta.playtime.acknowledged';

  @override
  PlaytimeToastState build() {
    ref.listen<AsyncValue<PlaytimeUpdatedEvent>>(playtimeUpdatesProvider, (
      _,
      next,
    ) {
      final e = next.value;
      if (e == null) return;
      final analytics = ref.read(analyticsServiceProvider);
      for (final m in e.granted) {
        analytics.playtimeRewardGranted(
          minutes: m.minutes,
          xp: m.reward.xp,
          coins: m.reward.coins,
        );
      }
      // The merged value may already list them (controller listened first);
      // reconcile against the push itself too.
      _reconcile(e.playtime);
    });
    ref.listen<PlaytimeState>(playtimeControllerProvider, (_, next) {
      final p = next.playtime;
      if (p != null) _reconcile(p);
    }, fireImmediately: true);
    ref.listen<String?>(sessionControllerProvider.select((s) => s.user?.id), (
      prev,
      next,
    ) {
      if (prev != next) state = const PlaytimeToastState();
    });
    return const PlaytimeToastState();
  }

  /// Takes everything pending as ONE toast, or null when nothing is pending
  /// or a toast is already showing. Call [markShown] when it closes.
  PlaytimeToast? takeNext() {
    if (state.showing || state.pending.isEmpty) return null;
    final list = [...state.pending]
      ..sort((a, b) => a.minutes.compareTo(b.minutes));
    state = const PlaytimeToastState(showing: true);
    return PlaytimeToast(List.unmodifiable(list));
  }

  /// Puts an interrupted toast back in front of the queue (e.g. a match
  /// started while it was showing).
  void requeue(PlaytimeToast toast) {
    final ids = {for (final m in state.pending) m.id};
    final list = [
      for (final m in toast.milestones)
        if (!ids.contains(m.id)) m,
      ...state.pending,
    ]..sort((a, b) => a.minutes.compareTo(b.minutes));
    state = PlaytimeToastState(pending: List.unmodifiable(list));
  }

  void markShown() {
    if (state.showing) {
      state = PlaytimeToastState(pending: state.pending);
    }
  }

  void _reconcile(Playtime p) {
    final completed = [
      for (final m in p.milestones)
        if (m.completed) m,
    ];
    if (completed.isEmpty || p.periodKey.isEmpty) return;
    final user = ref.read(sessionControllerProvider).user?.id;
    if (user == null) return;
    final acked = _readAcks(user, p.periodKey);
    final fresh = [
      for (final m in completed)
        if (!acked.contains(m.id)) m,
    ];
    if (fresh.isEmpty) return;
    final analytics = ref.read(analyticsServiceProvider);
    for (final m in fresh) {
      analytics.playtimeMilestoneCompleted(m.minutes);
    }
    _writeAcks(user, p.periodKey, {...acked, for (final m in fresh) m.id});
    final ids = {for (final m in state.pending) m.id};
    state = PlaytimeToastState(
      pending: List.unmodifiable(
        [
          ...state.pending,
          for (final m in fresh)
            if (!ids.contains(m.id)) m,
        ]..sort((a, b) => a.minutes.compareTo(b.minutes)),
      ),
      showing: state.showing,
    );
  }

  /// Acknowledged milestone ids of [user] for [periodKey] (only the current
  /// day of one account is kept).
  Set<String> _readAcks(String user, String periodKey) {
    try {
      final raw = ref.read(preferencesStoreProvider).getString(_ackKey);
      if (raw == null) return {};
      final j = jsonDecode(raw);
      if (j is! Map || j['user'] != user || j['period'] != periodKey) {
        return {};
      }
      return {...readStringList(j['ids'])};
    } catch (_) {
      return {};
    }
  }

  void _writeAcks(String user, String periodKey, Set<String> ids) {
    try {
      final prefs = ref.read(preferencesStoreProvider);
      unawaited(
        prefs
            .setString(
              _ackKey,
              jsonEncode({
                'user': user,
                'period': periodKey,
                'ids': [...ids],
              }),
            )
            .catchError((Object _) {}),
      );
    } catch (_) {
      // Preferences unavailable: the toast may repeat after a restart.
    }
  }
}

final playtimeToastControllerProvider =
    NotifierProvider<PlaytimeToastController, PlaytimeToastState>(
      PlaytimeToastController.new,
    );
