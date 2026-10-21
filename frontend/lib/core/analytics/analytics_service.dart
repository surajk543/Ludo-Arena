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

/// `opponent_mix` parameter, derived from the room's mode and its
/// `computerSeats` (practice and private rooms only). Seats carry no bot
/// flag, so public matches report [unknown]: the app cannot tell, and the
/// server metric `matches_started_total{mix}` is the source of truth.
enum OpponentMix {
  humanOnly('human_only'),
  mixed('mixed'),
  botOnly('bot_only'),
  unknown('unknown');

  const OpponentMix(this.param);
  final String param;

  /// [opponentIsComputer] lists, for every seat except the user's own,
  /// whether it is a known computer seat.
  static OpponentMix from(Iterable<bool> opponentIsComputer) {
    final list = opponentIsComputer.toList();
    if (list.isEmpty || list.every((b) => !b)) return humanOnly;
    if (list.every((b) => b)) return botOnly;
    return mixed;
  }

  /// The mix of a room of [mode] (`public` | `private` | `practice`):
  /// practice opponents are all computer players, private rooms list their
  /// computer seats ([opponentIsComputer]), public rooms are [unknown].
  static OpponentMix forRoom({
    required String mode,
    required Iterable<bool> opponentIsComputer,
  }) => switch (mode) {
    'practice' => botOnly,
    'private' => from(opponentIsComputer),
    _ => unknown,
  };
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

  /// The server confirmed `DELETE /account` (204). Sent before the local
  /// session is cleared, so only a human actor is ever counted. No params.
  void accountDeleted();

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

  // Social (after server confirmation only; never ids or names)

  /// [reason]: `cheating` | `offensive_name` | `abusive_behavior` |
  /// `leaving_or_stalling` | `other`.
  void playerReported(String reason);

  /// [source]: `match` | `recent` | `code`.
  void friendRequestSent(String source);

  // Shop (after the server verified and granted the purchase only)

  /// A coin pack was granted by the server (`replayed: false`). [pack] is
  /// the label slug (`starter` | `popular` | `great_value` | `best_value`);
  /// [value] and [currency] are the price paid (the store's price, or the
  /// fallback price when the store did not report one). Never ids, order
  /// numbers or purchase tokens.
  void coinPackPurchased({
    required String pack,
    required double value,
    required String currency,
  });
}
