import 'package:flutter/foundation.dart';

/// How the user signed in / linked.
enum LoginMethod { google, facebook, apple, guest }

/// `game_type` parameter.
enum AnalyticsGameType {
  ludo('ludo'),
  snakesLadders('snakes_ladders');

  const AnalyticsGameType(this.param);
  final String param;

  static AnalyticsGameType parse(String raw) =>
      raw == 'snakes_ladders' ? snakesLadders : ludo;
}

/// `match_type` parameter (from the room's `mode`).
enum AnalyticsMatchType {
  public('public'),
  private('private'),
  practice('practice');

  const AnalyticsMatchType(this.param);
  final String param;

  static AnalyticsMatchType parse(String mode) => switch (mode) {
    'private' => private,
    'practice' => practice,
    _ => public,
  };
}

/// `opponent_mix` parameter, derived from server room metadata
/// (`players[].bot`) for the user's opponents.
enum OpponentMix {
  humanOnly('human_only'),
  mixed('mixed'),
  botOnly('bot_only');

  const OpponentMix(this.param);
  final String param;

  /// [opponentIsBot] lists `bot` for every seat except the user's own.
  static OpponentMix from(Iterable<bool> opponentIsBot) {
    final list = opponentIsBot.toList();
    if (list.isEmpty || list.every((b) => !b)) return humanOnly;
    if (list.every((b) => b)) return botOnly;
    return mixed;
  }
}

/// `outcome` parameter.
enum GameOutcome {
  win('win'),
  loss('loss'),
  forfeit('forfeit');

  const GameOutcome(this.param);
  final String param;
}

/// Low-cardinality `duration_bucket`.
abstract final class DurationBucket {
  static String of(Duration d) {
    final m = d.inSeconds / 60.0;
    if (m < 1) return 'lt_1m';
    if (m < 3) return '1_3m';
    if (m < 5) return '3_5m';
    if (m < 10) return '5_10m';
    if (m < 20) return '10_20m';
    return 'gt_20m';
  }
}

/// Non-identifying description of a match for analytics. [dedupeKey] is
/// only used locally to avoid double counting (e.g. `"$roomId#$round"`) and
/// is NEVER sent.
@immutable
class AnalyticsGameContext {
  const AnalyticsGameContext({
    required this.gameType,
    required this.matchType,
    required this.seatCount,
    required this.opponentMix,
    required this.dedupeKey,
    this.variant,
  });

  final AnalyticsGameType gameType;
  final AnalyticsMatchType matchType;

  /// 2..4.
  final int seatCount;
  final OpponentMix opponentMix;

  /// `classic` | `quick` (Ludo only).
  final String? variant;
  final String dedupeKey;
}

/// The app's analytics surface. **Firebase Analytics only**, behind a single
/// gate: Firebase configured AND user consent granted AND the server says
/// `user.actorType == "human"`. Every method is fire-and-forget, never
/// throws, never blocks UI, and only sends whitelisted names/params (never
/// room codes, names, ids, tokens or emails).
abstract interface class AnalyticsService {
  /// Called by the session layer whenever the server user changes (null on
  /// sign-out). Only `"human"` actors are ever tracked.
  void setActorType(String? actorType);

  // Onboarding / settings
  void tutorialBegin();
  void tutorialComplete();
  void themeChanged(String mode);
  void settingsChanged(String setting, bool enabled);
  void languageChanged(String locale);

  // Auth (explicit user actions only; automatic session restore is NOT a
  // login and must not be reported).
  void loginStarted(LoginMethod method);
  void loginSucceeded(LoginMethod method);
  void loginFailed(LoginMethod method);
  void guestLoginSucceeded();
  void accountLinkSucceeded(LoginMethod method);

  // Profile
  /// The server accepted a new display name. Never carries the name.
  void displayNameChanged();

  // Matchmaking / rooms
  void matchmakingStarted(AnalyticsGameType game, int seatCount);
  void matchmakingSucceeded(AnalyticsGameType game, int seatCount);
  void matchmakingCancelled(AnalyticsGameType game, int seatCount);
  void privateRoomCreated(AnalyticsGameType game, int seatCount);
  void privateRoomJoined(AnalyticsGameType game);

  /// [errorCode] must be a known protocol/REST error code (bucketed to
  /// `other` otherwise).
  void privateRoomJoinFailed(String errorCode);

  // Games
  void gameStarted(AnalyticsGameContext game);
  void gameCompleted(
    AnalyticsGameContext game, {
    required GameOutcome outcome,
    required Duration duration,
  });
  void gameAbandoned(AnalyticsGameContext game, {required Duration duration});
  void rematchRequested(AnalyticsGameContext game);
  void rematchAccepted(AnalyticsGameContext game);
  void gameResultViewed(AnalyticsGameContext game);

  // Meta
  void missionViewed();
  void missionCompleted(String period);
  void missionRewardClaimed(String period);
  void levelUp(int level);
  void cosmeticUnlocked(String kind, String rarity);
  void cosmeticEquipped(String kind);
  void collectionViewed();

  /// [mode]: `optional_update` | `force_update`.
  void appUpdatePromptShown(String mode);
}
