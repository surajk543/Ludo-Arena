import 'analytics_service.dart';

/// Validates one parameter value. Returns the sanitized value to send, or
/// `null` to drop the parameter.
abstract interface class ParamRule {
  Object? apply(Object? value);
}

final RegExp _safeToken = RegExp(r'^[a-z0-9_]{1,40}$');

/// Only values from [allowed]; anything else becomes [fallback] (or is
/// dropped when there is no fallback).
class EnumRule implements ParamRule {
  const EnumRule(this.allowed, {this.fallback});

  final Set<String> allowed;
  final String? fallback;

  @override
  Object? apply(Object? value) {
    if (value is String &&
        allowed.contains(value) &&
        _safeToken.hasMatch(value)) {
      return value;
    }
    return fallback;
  }
}

/// Integers within [min]..[max] (clamped when [clamp], otherwise dropped).
class IntRangeRule implements ParamRule {
  const IntRangeRule(this.min, this.max, {this.clamp = false});

  final int min;
  final int max;
  final bool clamp;

  @override
  Object? apply(Object? value) {
    if (value is! int) return null;
    if (value < min || value > max) {
      return clamp ? value.clamp(min, max) : null;
    }
    return value;
  }
}

/// Booleans, sent as `"true"` / `"false"` (Firebase params are strings or
/// numbers).
class BoolRule implements ParamRule {
  const BoolRule();

  @override
  Object? apply(Object? value) => value is bool ? '$value' : null;
}

/// Allowed value sets.
abstract final class AnalyticsValues {
  static const gameTypes = {'ludo', 'snakes_ladders'};
  static const matchTypes = {'public', 'private', 'practice'};
  static const opponentMixes = {'human_only', 'mixed', 'bot_only', 'unknown'};
  static const variants = {'classic', 'quick'};
  static const outcomes = {'win', 'loss', 'forfeit'};
  static const durationBuckets = {
    'lt_1m',
    '1_3m',
    '3_5m',
    '5_10m',
    '10_20m',
    'gt_20m',
  };
  static const loginMethods = {'google', 'facebook', 'apple', 'guest'};
  static const linkMethods = {'google', 'facebook', 'apple'};
  static const locales = {'en', 'hi', 'ur', 'id', 'ar'};
  static const themes = {'light', 'dark', 'system'};
  static const settings = {
    'sound',
    'haptics',
    'reduced_motion',
    'quick_chat_mute',
    'international_numbers',
  };
  static const periods = {'daily', 'weekly', 'event'};
  static const itemKinds = {
    'dice',
    'token',
    'ludo_board',
    'snakes_board',
    'frame',
    'title',
    'badge',
    'emote',
    'victory',
    'trail',
    // Store profile pictures (bought with diamonds; no rarity).
    'profile_picture',
  };
  static const rarities = {'common', 'rare', 'epic', 'legendary'};
  static const updateModes = {'optional_update', 'force_update'};
  static const reportReasons = {
    'cheating',
    'offensive_name',
    'abusive_behavior',
    'leaving_or_stalling',
    'other',
  };

  /// Where a friend request was sent from.
  static const friendRequestSources = {'match', 'recent', 'code'};

  /// Protocol + REST + client error codes that may be reported as
  /// `error_code` (anything else is bucketed to `other`).
  static const errorCodes = {
    // WebSocket protocol (websocket-protocol.md §9)
    'bad_request',
    'unknown_type',
    'rate_limited',
    'unauthorized',
    'update_required',
    'maintenance',
    'not_in_room',
    'room_not_found',
    'room_full',
    'room_in_progress',
    'room_closed',
    'already_in_room',
    'not_host',
    'not_enough_players',
    'players_not_ready',
    'not_your_turn',
    'invalid_phase',
    'illegal_move',
    'stale_state',
    'insufficient_funds',
    'invalid_code',
    'rematch_closed',
    'not_friends',
    'item_not_owned',
    'bots_unavailable',
    'bots_not_allowed',
    'internal',
    // REST
    'not_found',
    'forbidden',
    'provider_unavailable',
    // client-side
    'network_error',
    'timeout',
    'not_connected',
    'unknown',
  };
}

/// Shared rule sets.
abstract final class _P {
  static const gameType = EnumRule(AnalyticsValues.gameTypes);
  static const matchType = EnumRule(AnalyticsValues.matchTypes);
  static const seatCount = IntRangeRule(2, 4);
  static const opponentMix = EnumRule(AnalyticsValues.opponentMixes);
  static const variant = EnumRule(AnalyticsValues.variants);
  static const outcome = EnumRule(AnalyticsValues.outcomes);
  static const duration = EnumRule(AnalyticsValues.durationBuckets);
  static const loginMethod = EnumRule(AnalyticsValues.loginMethods);
  static const linkMethod = EnumRule(AnalyticsValues.linkMethods);
  static const period = EnumRule(AnalyticsValues.periods);

  static const Map<String, ParamRule> game = {
    'game_type': gameType,
    'match_type': matchType,
    'seat_count': seatCount,
    'opponent_mix': opponentMix,
    'variant': variant,
  };
  static const Map<String, ParamRule> matchmaking = {
    'game_type': gameType,
    'seat_count': seatCount,
  };
}

/// The complete whitelist: event name → allowed parameters. Events not
/// listed here are never sent; parameters not listed for an event are
/// dropped.
abstract final class AnalyticsCatalog {
  static const Map<String, Map<String, ParamRule>> events = {
    'tutorial_begin': {},
    'tutorial_complete': {},
    'theme_changed': {'theme': EnumRule(AnalyticsValues.themes)},
    'settings_changed': {
      'setting': EnumRule(AnalyticsValues.settings),
      'enabled': BoolRule(),
    },
    'language_changed': {'locale': EnumRule(AnalyticsValues.locales)},
    'login_started': {'method': _P.loginMethod},
    'login_succeeded': {'method': _P.loginMethod},
    'login_failed': {'method': _P.loginMethod},
    'guest_login_succeeded': {},
    'account_link_succeeded': {'method': _P.linkMethod},
    // No parameters (never ids, providers or reasons).
    'account_deleted': {},
    // No parameters: the name itself is PII and never sent.
    'display_name_changed': {},
    'matchmaking_started': _P.matchmaking,
    'matchmaking_succeeded': _P.matchmaking,
    'matchmaking_cancelled': _P.matchmaking,
    'private_room_created': _P.matchmaking,
    'private_room_joined': {'game_type': _P.gameType},
    'private_room_join_failed': {
      'error_code': EnumRule(AnalyticsValues.errorCodes, fallback: 'other'),
    },
    'game_started': _P.game,
    'game_completed': {
      ..._P.game,
      'outcome': _P.outcome,
      'duration_bucket': _P.duration,
    },
    'game_abandoned': {..._P.game, 'duration_bucket': _P.duration},
    'rematch_requested': _P.game,
    'rematch_accepted': _P.game,
    'game_result_viewed': _P.game,
    'mission_viewed': {},
    'mission_completed': {'period': _P.period},
    'mission_reward_claimed': {'period': _P.period},
    'level_up': {'level': IntRangeRule(1, 50, clamp: true)},
    'cosmetic_unlocked': {
      'item_kind': EnumRule(AnalyticsValues.itemKinds),
      'rarity': EnumRule(AnalyticsValues.rarities),
    },
    'cosmetic_equipped': {'item_kind': EnumRule(AnalyticsValues.itemKinds)},
    'collection_viewed': {},
    'app_update_prompt_shown': {'mode': EnumRule(AnalyticsValues.updateModes)},
    'player_reported': {'reason': EnumRule(AnalyticsValues.reportReasons)},
    'friend_request_sent': {
      'source': EnumRule(AnalyticsValues.friendRequestSources),
    },
  };

  static bool isKnown(String name) => events.containsKey(name);

  /// Validates [raw] for [name]. Returns `null` for an unknown event;
  /// otherwise only allowed, valid parameters (in insertion order).
  static Map<String, Object>? sanitize(String name, Map<String, Object?> raw) {
    final rules = events[name];
    if (rules == null) return null;
    final out = <String, Object>{};
    raw.forEach((key, value) {
      final rule = rules[key];
      if (rule == null) return;
      final v = rule.apply(value);
      if (v != null) out[key] = v;
    });
    return out;
  }

  /// Standard parameters for a match context.
  static Map<String, Object?> gameParams(AnalyticsGameContext g) => {
    'game_type': g.gameType.param,
    'match_type': g.matchType.param,
    'seat_count': g.seatCount,
    'opponent_mix': g.opponentMix.param,
    'variant': ?g.variant,
  };
}
