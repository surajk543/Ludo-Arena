import 'package:flutter/material.dart';

import '../../../core/localization/number_format.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'collection_models.dart';

/// Client-side texts for the Collection Room (the server only sends English
/// fallbacks).
abstract final class CollectionTexts {
  /// Plural tab label of a kind.
  static String tab(AppLocalizations l10n, String kind) => switch (kind) {
    'dice' => l10n.metaTabDice,
    'token' => l10n.metaTabTokens,
    'ludo_board' => l10n.metaTabLudoBoards,
    'snakes_board' => l10n.metaTabSnakesBoards,
    'trail' => l10n.metaTabTrails,
    'victory' => l10n.metaTabVictory,
    'frame' => l10n.metaTabFrames,
    'title' => l10n.metaTabTitles,
    'badge' => l10n.metaTabBadges,
    'emote' => l10n.metaTabEmotes,
    _ => kind,
  };

  static IconData icon(String kind) => switch (kind) {
    'dice' => Icons.casino_rounded,
    'token' => Icons.person_pin_circle_rounded,
    'ludo_board' => Icons.grid_view_rounded,
    'snakes_board' => Icons.stairs_rounded,
    'trail' => Icons.auto_awesome_rounded,
    'victory' => Icons.celebration_rounded,
    'frame' => Icons.account_circle_rounded,
    'title' => Icons.military_tech_rounded,
    'badge' => Icons.workspace_premium_rounded,
    'emote' => Icons.emoji_emotions_rounded,
    _ => Icons.category_rounded,
  };

  /// Price text, e.g. "40 diamonds" / "1.5 Lakh coins".
  static String price(AppLocalizations l10n, Locale locale, Price p) =>
      p.inDiamonds
      ? l10n.metaPriceDiamonds(formatNumberFull(p.diamonds, locale))
      : l10n.metaPriceCoins(formatCoins(p.coins, locale));

  /// How the item is obtained.
  static String acquisition(
    AppLocalizations l10n,
    Locale locale,
    CollectionItem item,
  ) {
    final a = item.acquisition;
    return switch (a.type) {
      AcquisitionType.starter => l10n.metaAcqStarter,
      AcquisitionType.level => l10n.metaAcqLevel(a.level ?? 1),
      AcquisitionType.mission => switch (item.id) {
        'badge_first_win' => l10n.metaAcqFirstWin,
        'title_weekly_champion' ||
        'badge_friendly' => l10n.metaAcqWeeklyChallenge,
        _ => l10n.metaAcqMission,
      },
      AcquisitionType.event => switch (item.id) {
        'dice_autumn' => l10n.metaAcqAutumnCup,
        _ => l10n.metaAcqEvent,
      },
      AcquisitionType.purchase =>
        a.price == null ? a.label : price(l10n, locale, a.price!),
      AcquisitionType.unknown => a.label,
    };
  }

  /// Localized description of a catalog item.
  static String description(AppLocalizations l10n, CollectionItem item) =>
      switch (item.id) {
        'dice_classic' => l10n.metaDescDiceClassic,
        'dice_neon' => l10n.metaDescDiceNeon,
        'dice_golden' => l10n.metaDescDiceGolden,
        'dice_autumn' => l10n.metaDescDiceAutumn,
        'token_classic' => l10n.metaDescTokenClassic,
        'token_gem' => l10n.metaDescTokenGem,
        'token_royal' => l10n.metaDescTokenRoyal,
        'token_crown' => l10n.metaDescTokenCrown,
        'ludo_board_classic' => l10n.metaDescLudoBoardClassic,
        'ludo_board_midnight' => l10n.metaDescLudoBoardMidnight,
        'ludo_board_royal' => l10n.metaDescLudoBoardRoyal,
        'snakes_board_classic' => l10n.metaDescSnakesBoardClassic,
        'snakes_board_jungle' => l10n.metaDescSnakesBoardJungle,
        'snakes_board_candy' => l10n.metaDescSnakesBoardCandy,
        'trail_none' => l10n.metaDescTrailNone,
        'trail_sparkle' => l10n.metaDescTrailSparkle,
        'trail_comet' => l10n.metaDescTrailComet,
        'victory_confetti' => l10n.metaDescVictoryConfetti,
        'victory_fireworks' => l10n.metaDescVictoryFireworks,
        'victory_crown' => l10n.metaDescVictoryCrown,
        'frame_none' => l10n.metaDescFrameNone,
        'frame_bronze' => l10n.metaDescFrameBronze,
        'frame_silver' => l10n.metaDescFrameSilver,
        'frame_gold' => l10n.metaDescFrameGold,
        'frame_royal' => l10n.metaDescFrameRoyal,
        'title_rookie' => l10n.metaDescTitleRookie,
        'title_strategist' => l10n.metaDescTitleStrategist,
        'title_dice_master' => l10n.metaDescTitleDiceMaster,
        'title_royal' => l10n.metaDescTitleRoyal,
        'title_weekly_champion' => l10n.metaDescTitleWeeklyChampion,
        'badge_first_win' => l10n.metaDescBadgeFirstWin,
        'badge_friendly' => l10n.metaDescBadgeFriendly,
        'emote_wave' => l10n.metaDescEmoteWave,
        'emote_thumbs' => l10n.metaDescEmoteThumbs,
        'emote_laugh' => l10n.metaDescEmoteLaugh,
        'emote_wow' => l10n.metaDescEmoteWow,
        'emote_crown' => l10n.metaDescEmoteCrown,
        _ => item.description,
      };
}
