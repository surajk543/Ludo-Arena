import '../../../l10n/generated/app_localizations.dart';
import 'mission_models.dart';

/// Client-side localization of mission and event texts by id (the server
/// only sends English fallbacks). Unknown ids (configured after this build)
/// fall back to the server text.
abstract final class MissionTexts {
  static String title(AppLocalizations l10n, Mission m) => switch (m.id) {
    'daily_ludo_match' => l10n.metaMissionLudoTimeTitle,
    'daily_snakes_match' => l10n.metaMissionClimbTitle,
    'daily_play_two' => l10n.metaMissionWarmUpTitle,
    'daily_friends_private' => l10n.metaMissionFriendlyTableTitle,
    'daily_finish_strong' => l10n.metaMissionStayToEndTitle,
    'daily_win_one' => l10n.metaMissionTasteOfVictoryTitle,
    'daily_quick_ludo' => l10n.metaMissionQuickDrawTitle,
    'weekly_ten_matches' => l10n.metaMissionWeeklyChallengeTitle,
    'autumn_quick_ludo' => l10n.metaMissionAutumnSprintTitle,
    _ => m.title.isNotEmpty ? m.title : l10n.metaMissionFallbackTitle,
  };

  static String description(AppLocalizations l10n, Mission m) {
    final n = m.target;
    return switch (m.id) {
      'daily_ludo_match' => l10n.metaMissionLudoMatchesDesc(n),
      'daily_snakes_match' => l10n.metaMissionSnakesMatchesDesc(n),
      'daily_play_two' => l10n.metaMissionAnyMatchesDesc(n),
      'daily_friends_private' => l10n.metaMissionFriendPrivateDesc(n),
      'daily_finish_strong' => l10n.metaMissionNoLeavingDesc(n),
      'daily_win_one' => l10n.metaMissionWinDesc(n),
      'daily_quick_ludo' ||
      'autumn_quick_ludo' => l10n.metaMissionQuickLudoDesc(n),
      'weekly_ten_matches' => l10n.metaMissionWeeklyDesc(n),
      _ => m.description,
    };
  }

  /// Game label for the card chip.
  static String game(AppLocalizations l10n, String game) => switch (game) {
    'ludo' => l10n.commonGameLudo,
    'snakes_ladders' => l10n.commonGameSnakesLadders,
    _ => l10n.metaGameAny,
  };

  static String eventTitle(AppLocalizations l10n, EventSet e) => switch (e.id) {
    'autumn_cup' => l10n.metaEventAutumnCupTitle,
    _ => e.title.isNotEmpty ? e.title : l10n.metaEventsTitle,
  };

  static String eventDescription(AppLocalizations l10n, EventSet e) =>
      switch (e.id) {
        'autumn_cup' => l10n.metaEventAutumnCupDesc,
        _ => e.description,
      };
}
