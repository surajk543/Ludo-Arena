import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'analytics_backend.dart';
import 'analytics_catalog.dart';
import 'analytics_consent.dart';
import 'analytics_service.dart';

/// The single analytics gate. An event is sent only when ALL hold:
///
/// 1. a backend exists (Firebase configured and initialized),
/// 2. the user granted consent,
/// 3. the server-provided actor type is `"human"`.
///
/// Events and parameters are validated against [AnalyticsCatalog]. Calls are
/// fire-and-forget and never throw.
class GatedAnalyticsService implements AnalyticsService {
  GatedAnalyticsService({
    required this._backend,
    required this._consent,
    this.dedupeCapacity = 256,
  });

  final AnalyticsBackend? Function() _backend;
  final AnalyticsConsent Function() _consent;
  final int dedupeCapacity;

  String? _actorType;

  /// Bounded LRU of dedupe keys already sent this launch.
  final LinkedHashSet<String> _sent = LinkedHashSet<String>();

  /// Whether an event would be sent right now (for tests / diagnostics).
  bool get isOpen =>
      _backend() != null &&
      _consent() == AnalyticsConsent.granted &&
      _actorType == 'human';

  @override
  void setActorType(String? actorType) => _actorType = actorType;

  void _log(
    String name, [
    Map<String, Object?> params = const {},
    String? dedupeKey,
  ]) {
    try {
      final backend = _backend();
      if (backend == null) return;
      if (_consent() != AnalyticsConsent.granted) return;
      if (_actorType != 'human') return;
      final clean = AnalyticsCatalog.sanitize(name, params);
      if (clean == null) return;
      if (dedupeKey != null) {
        final key = '$name|$dedupeKey';
        if (_sent.contains(key)) {
          // Refresh recency.
          _sent
            ..remove(key)
            ..add(key);
          return;
        }
        _sent.add(key);
        while (_sent.length > dedupeCapacity) {
          _sent.remove(_sent.first);
        }
      }
      unawaited(
        Future.sync(() => backend.logEvent(name, clean)).catchError((Object e) {
          if (kDebugMode) debugPrint('analytics: $name failed ($e)');
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('analytics: $name dropped ($e)');
    }
  }

  // Onboarding / settings ---------------------------------------------------

  @override
  void tutorialBegin() => _log('tutorial_begin');

  @override
  void tutorialComplete() => _log('tutorial_complete');

  @override
  void themeChanged(String mode) => _log('theme_changed', {'theme': mode});

  @override
  void settingsChanged(String setting, bool enabled) =>
      _log('settings_changed', {'setting': setting, 'enabled': enabled});

  @override
  void languageChanged(String locale) =>
      _log('language_changed', {'locale': locale});

  // Auth ----------------------------------------------------------------------

  @override
  void loginStarted(LoginMethod method) =>
      _log('login_started', {'method': method.name});

  @override
  void loginSucceeded(LoginMethod method) =>
      _log('login_succeeded', {'method': method.name});

  @override
  void loginFailed(LoginMethod method) =>
      _log('login_failed', {'method': method.name});

  @override
  void guestLoginSucceeded() => _log('guest_login_succeeded');

  @override
  void accountLinkSucceeded(LoginMethod method) =>
      _log('account_link_succeeded', {'method': method.name});

  // Matchmaking / rooms -------------------------------------------------------

  Map<String, Object?> _mm(AnalyticsGameType game, int seats) => {
    'game_type': game.param,
    'seat_count': seats,
  };

  @override
  void matchmakingStarted(AnalyticsGameType game, int seatCount) =>
      _log('matchmaking_started', _mm(game, seatCount));

  @override
  void matchmakingSucceeded(AnalyticsGameType game, int seatCount) =>
      _log('matchmaking_succeeded', _mm(game, seatCount));

  @override
  void matchmakingCancelled(AnalyticsGameType game, int seatCount) =>
      _log('matchmaking_cancelled', _mm(game, seatCount));

  @override
  void privateRoomCreated(AnalyticsGameType game, int seatCount) =>
      _log('private_room_created', _mm(game, seatCount));

  @override
  void privateRoomJoined(AnalyticsGameType game) =>
      _log('private_room_joined', {'game_type': game.param});

  @override
  void privateRoomJoinFailed(String errorCode) =>
      _log('private_room_join_failed', {'error_code': errorCode});

  // Games ---------------------------------------------------------------------

  @override
  void gameStarted(AnalyticsGameContext game) =>
      _log('game_started', AnalyticsCatalog.gameParams(game), game.dedupeKey);

  @override
  void gameCompleted(
    AnalyticsGameContext game, {
    required GameOutcome outcome,
    required Duration duration,
  }) => _log('game_completed', {
    ...AnalyticsCatalog.gameParams(game),
    'outcome': outcome.param,
    'duration_bucket': DurationBucket.of(duration),
  }, game.dedupeKey);

  @override
  void gameAbandoned(AnalyticsGameContext game, {required Duration duration}) =>
      _log('game_abandoned', {
        ...AnalyticsCatalog.gameParams(game),
        'duration_bucket': DurationBucket.of(duration),
      }, game.dedupeKey);

  @override
  void rematchRequested(AnalyticsGameContext game) => _log(
    'rematch_requested',
    AnalyticsCatalog.gameParams(game),
    game.dedupeKey,
  );

  @override
  void rematchAccepted(AnalyticsGameContext game) => _log(
    'rematch_accepted',
    AnalyticsCatalog.gameParams(game),
    game.dedupeKey,
  );

  @override
  void gameResultViewed(AnalyticsGameContext game) => _log(
    'game_result_viewed',
    AnalyticsCatalog.gameParams(game),
    game.dedupeKey,
  );

  // Meta ----------------------------------------------------------------------

  @override
  void missionViewed() => _log('mission_viewed');

  @override
  void missionCompleted(String period) =>
      _log('mission_completed', {'period': period});

  @override
  void missionRewardClaimed(String period) =>
      _log('mission_reward_claimed', {'period': period});

  @override
  void levelUp(int level) => _log('level_up', {'level': level}, 'level_$level');

  @override
  void cosmeticUnlocked(String kind, String rarity) =>
      _log('cosmetic_unlocked', {'item_kind': kind, 'rarity': rarity});

  @override
  void cosmeticEquipped(String kind) =>
      _log('cosmetic_equipped', {'item_kind': kind});

  @override
  void collectionViewed() => _log('collection_viewed');

  @override
  void appUpdatePromptShown(String mode) =>
      _log('app_update_prompt_shown', {'mode': mode}, mode);
}
