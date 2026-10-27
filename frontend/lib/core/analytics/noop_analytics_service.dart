import 'analytics_service.dart';

/// Does nothing. Used when Firebase is not configured, in tests, and as the
/// fallback whenever the analytics gate is closed.
class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  void setActorType(String? actorType) {}

  @override
  void tutorialBegin() {}

  @override
  void tutorialComplete() {}

  @override
  void themeChanged(String mode) {}

  @override
  void settingsChanged(String setting, bool enabled) {}

  @override
  void languageChanged(String locale) {}

  @override
  void loginStarted(LoginMethod method) {}

  @override
  void loginSucceeded(LoginMethod method) {}

  @override
  void loginFailed(LoginMethod method) {}

  @override
  void guestLoginSucceeded() {}

  @override
  void accountLinkSucceeded(LoginMethod method) {}

  @override
  void accountDeleted() {}

  @override
  void displayNameChanged() {}

  @override
  void matchmakingStarted(AnalyticsGameType game, int seatCount) {}

  @override
  void matchmakingSucceeded(AnalyticsGameType game, int seatCount) {}

  @override
  void matchmakingCancelled(AnalyticsGameType game, int seatCount) {}

  @override
  void privateRoomCreated(AnalyticsGameType game, int seatCount) {}

  @override
  void privateRoomJoined(AnalyticsGameType game) {}

  @override
  void privateRoomJoinFailed(String errorCode) {}

  @override
  void gameStarted(AnalyticsGameContext game) {}

  @override
  void gameCompleted(
    AnalyticsGameContext game, {
    required GameOutcome outcome,
    required Duration duration,
  }) {}

  @override
  void gameAbandoned(AnalyticsGameContext game, {required Duration duration}) {}

  @override
  void rematchRequested(AnalyticsGameContext game) {}

  @override
  void rematchAccepted(AnalyticsGameContext game) {}

  @override
  void gameResultViewed(AnalyticsGameContext game) {}

  @override
  void missionViewed() {}

  @override
  void missionCompleted(String period) {}

  @override
  void missionRewardClaimed(String period) {}

  @override
  void levelUp(int level) {}

  @override
  void cosmeticUnlocked(String kind, String rarity) {}

  @override
  void cosmeticEquipped(String kind) {}

  @override
  void collectionViewed() {}

  @override
  void appUpdatePromptShown(String mode) {}

  @override
  void playerReported(String reason) {}

  @override
  void friendRequestSent(String source) {}

  @override
  void coinPackPurchased({
    required String pack,
    required double value,
    required String currency,
  }) {}

  @override
  void playtimeProgressViewed(String surface) {}

  @override
  void playtimeMilestoneCompleted(int minutes) {}

  @override
  void playtimeRewardGranted({
    required int minutes,
    required int xp,
    required int coins,
  }) {}

  @override
  void playtimeToastDismissed(String method) {}

  @override
  void nextGoalShown(String kind) {}

  @override
  void nextGoalTapped(String kind) {}
}
