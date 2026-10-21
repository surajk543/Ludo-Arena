import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/storage/preferences_store.dart';
import '../../authentication/application/session_controller.dart';
import '../../collection/application/collection_controller.dart';
import '../../progression/application/level_up_controller.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/application/progression_controller.dart';
import '../../wallet/wallet_controller.dart';
import '../data/missions_api.dart';
import '../domain/mission_models.dart';

/// Result of a claim tap.
@immutable
sealed class ClaimOutcome {
  const ClaimOutcome();
}

/// Server-confirmed claim (wallet, XP and items already applied).
final class ClaimSucceeded extends ClaimOutcome {
  const ClaimSucceeded(this.result);
  final ClaimResult result;
}

/// A claim for the same mission is already in flight (double tap).
final class ClaimIgnored extends ClaimOutcome {
  const ClaimIgnored();
}

/// The claim failed. [canRetry]: the same intent (and Idempotency-Key)
/// will be reused by the next tap.
final class ClaimFailed extends ClaimOutcome {
  const ClaimFailed(this.error, {required this.canRetry});
  final ApiException error;
  final bool canRetry;
}

/// Missions board (`GET /missions`), live progress from
/// `progression.updated`, and exactly-once reward claims.
///
/// Claims: one Idempotency-Key per tap-intent. A tap while the same claim is
/// in flight is ignored; after a transient failure (network, timeout, 5xx,
/// 429, `request_in_progress`) the next tap retries the SAME intent with the
/// SAME key, so the server either replays the stored result or executes it
/// once. After success or a definitive error the key is discarded.
class MissionsController extends AsyncNotifier<MissionsBoard> {
  static const _seenKey = 'meta.missions.completed_seen';

  final Set<String> _inFlight = {};
  final Map<String, String> _intentKeys = {};

  MissionsApi get _api => ref.read(missionsApiProvider);
  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  @override
  Future<MissionsBoard> build() async {
    ref.listen<AsyncValue<ProgressionUpdatedEvent>>(
      progressionUpdatesProvider,
      (_, next) {
        final e = next.value;
        if (e != null) _onPush(e);
      },
    );
    final board = await _api.fetch();
    _trackCompleted(board);
    return board;
  }

  /// True while a claim for this mission is in flight.
  bool isClaiming(String periodKey, String missionId) =>
      _inFlight.contains(_k(periodKey, missionId));

  /// The Idempotency-Key that the next claim of this mission will use, if an
  /// earlier attempt failed transiently (exposed for tests/diagnostics).
  @visibleForTesting
  String? pendingIntentKey(String periodKey, String missionId) =>
      _intentKeys[_k(periodKey, missionId)];

  static String _k(String periodKey, String missionId) =>
      '$periodKey/$missionId';

  void _onPush(ProgressionUpdatedEvent e) {
    final board = state.value;
    if (board == null || e.missions.isEmpty) return;
    final next = board.applyProgress(e.missions);
    state = AsyncData(next);
    _trackCompleted(next);
  }

  /// Pull-to-refresh. Keeps the previous board on failure and rethrows.
  Future<void> refresh() async {
    try {
      final board = await _api.fetch();
      if (!ref.mounted) return;
      state = AsyncData(board);
      _trackCompleted(board);
    } catch (e, s) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, s);
      rethrow;
    }
  }

  /// Claims a completed mission's reward. Never throws.
  Future<ClaimOutcome> claim(String periodKey, String missionId) async {
    final k = _k(periodKey, missionId);
    if (!_inFlight.add(k)) return const ClaimIgnored();
    final key = _intentKeys[k] ??= ref.read(idempotencyKeyFactoryProvider)();
    try {
      final result = await _api.claim(
        periodKey: periodKey,
        missionId: missionId,
        idempotencyKey: key,
      );
      _intentKeys.remove(k);
      // If the screen closed meanwhile, the `wallet.updated` /
      // `progression.updated` pushes still bring the app up to date.
      if (ref.mounted) _applyClaim(periodKey, result);
      return ClaimSucceeded(result);
    } on ApiException catch (e) {
      final transient = isTransientFailure(e);
      if (!transient) _intentKeys.remove(k);
      if (ref.mounted) {
        if (e.code == 'already_claimed') {
          // Claimed earlier (e.g. a lost response): resync balances too.
          _markClaimed(periodKey, missionId);
          unawaited(
            ref
                .read(walletControllerProvider.notifier)
                .refresh()
                .catchError((Object _) {}),
          );
        }
        if (!transient) unawaited(refresh().catchError((Object _) {}));
      }
      return ClaimFailed(e, canRetry: transient);
    } finally {
      _inFlight.remove(k);
    }
  }

  void _markClaimed(String periodKey, String missionId) {
    final board = state.value;
    if (board == null) return;
    for (final (pk, m) in board.all) {
      if (pk == periodKey && m.id == missionId) {
        state = AsyncData(board.replace(pk, m.copyWith(claimed: true)));
        return;
      }
    }
  }

  void _applyClaim(String periodKey, ClaimResult r) {
    // Server-confirmed balances and XP.
    ref.read(walletControllerProvider.notifier).setFromServer(r.wallet);
    final session = ref.read(sessionControllerProvider);
    final user = session.user;
    if (user != null) {
      ref
          .read(sessionControllerProvider.notifier)
          .updateUser(
            user.copyWith(
              level: r.progression.level,
              xp: r.progression.xp,
              levelXp: r.progression.levelXp,
              nextLevelXp: r.progression.nextLevelXp,
            ),
          );
    }
    _analytics.missionRewardClaimed(MissionPeriod.ofKey(periodKey).param);
    if (r.progression.levelUp) {
      // Deduplicated per level by the analytics service (the push logs too).
      _analytics.levelUp(r.progression.level);
      ref
          .read(levelUpControllerProvider.notifier)
          .enqueue(r.progression.level, r.granted.map((i) => i.id));
    }
    if (r.granted.isNotEmpty) ref.invalidate(collectionProvider);
    ref.invalidate(progressionViewProvider);

    final board = state.value;
    if (board != null && r.mission.id.isNotEmpty) {
      state = AsyncData(
        board.replace(periodKey, r.mission.copyWith(claimed: true)),
      );
    }
  }

  // ------------------------------------------------- mission_completed

  /// Logs `mission_completed` once per (period, mission) the first time the
  /// user sees it completed-but-unclaimed. Seen keys are kept locally (never
  /// sent) and pruned to the running periods.
  void _trackCompleted(MissionsBoard board) {
    final PreferencesStore prefs;
    try {
      prefs = ref.read(preferencesStoreProvider);
    } catch (_) {
      return;
    }
    final seen = <String>{};
    try {
      final raw = prefs.getString(_seenKey);
      if (raw != null) {
        seen.addAll((jsonDecode(raw) as List).whereType<String>());
      }
    } catch (_) {}
    final periods = board.periodKeys;
    final kept = seen
        .where((k) => periods.any((p) => k.startsWith('$p/')))
        .toSet();
    var changed = kept.length != seen.length;
    for (final (pk, m) in board.all) {
      if (m.status != MissionStatus.claimable) continue;
      if (kept.add(_k(pk, m.id))) {
        changed = true;
        _analytics.missionCompleted(MissionPeriod.ofKey(pk).param);
      }
    }
    if (changed) {
      unawaited(prefs.setString(_seenKey, jsonEncode(kept.toList())));
    }
  }
}

final missionsProvider =
    AsyncNotifierProvider<MissionsController, MissionsBoard>(
      MissionsController.new,
      isAutoDispose: true,
      retry: noRetry,
    );
