import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Rarity tiers of the cosmetics catalog (docs/cosmetics-catalog.md).
enum CosmeticRarity {
  common,
  rare,
  epic,
  legendary;

  static CosmeticRarity parse(String? raw) => switch (raw) {
    'rare' => rare,
    'epic' => epic,
    'legendary' => legendary,
    _ => common,
  };

  /// Accent color for chips, card borders and glows.
  Color color(AppColors c) => switch (this) {
    CosmeticRarity.common =>
      c.isDark ? const Color(0xFFB7B0D4) : const Color(0xFF7D7699),
    CosmeticRarity.rare =>
      c.isDark ? const Color(0xFF6EA8FF) : const Color(0xFF2F74D0),
    CosmeticRarity.epic =>
      c.isDark ? const Color(0xFFC08BFF) : const Color(0xFF8A3FD6),
    CosmeticRarity.legendary => c.gold,
  };
}

/// Static rarity of each catalog item (the server is authoritative; this is
/// only used to tint chips before collection data is loaded).
const Map<String, CosmeticRarity> kCatalogRarity = {
  'dice_classic': CosmeticRarity.common,
  'dice_neon': CosmeticRarity.rare,
  'dice_golden': CosmeticRarity.epic,
  'dice_autumn': CosmeticRarity.rare,
  'token_classic': CosmeticRarity.common,
  'token_gem': CosmeticRarity.rare,
  'token_royal': CosmeticRarity.epic,
  'token_crown': CosmeticRarity.legendary,
  'ludo_board_classic': CosmeticRarity.common,
  'ludo_board_midnight': CosmeticRarity.rare,
  'ludo_board_royal': CosmeticRarity.epic,
  'snakes_board_classic': CosmeticRarity.common,
  'snakes_board_jungle': CosmeticRarity.rare,
  'snakes_board_candy': CosmeticRarity.epic,
  'trail_none': CosmeticRarity.common,
  'trail_sparkle': CosmeticRarity.rare,
  'trail_comet': CosmeticRarity.epic,
  'victory_confetti': CosmeticRarity.common,
  'victory_fireworks': CosmeticRarity.rare,
  'victory_crown': CosmeticRarity.epic,
  'frame_none': CosmeticRarity.common,
  'frame_bronze': CosmeticRarity.common,
  'frame_silver': CosmeticRarity.rare,
  'frame_gold': CosmeticRarity.epic,
  'frame_royal': CosmeticRarity.legendary,
  'title_rookie': CosmeticRarity.common,
  'title_strategist': CosmeticRarity.rare,
  'title_dice_master': CosmeticRarity.epic,
  'title_royal': CosmeticRarity.legendary,
  'title_weekly_champion': CosmeticRarity.epic,
  'badge_first_win': CosmeticRarity.common,
  'badge_friendly': CosmeticRarity.rare,
  'emote_wave': CosmeticRarity.common,
  'emote_thumbs': CosmeticRarity.common,
  'emote_laugh': CosmeticRarity.common,
  'emote_wow': CosmeticRarity.rare,
  'emote_crown': CosmeticRarity.epic,
};

/// Every catalog item id (v1).
Iterable<String> get kCatalogItemIds => kCatalogRarity.keys;

/// Rarity of a catalog [itemId] (common when unknown).
CosmeticRarity cosmeticRarity(String itemId) =>
    kCatalogRarity[itemId] ?? CosmeticRarity.common;

/// Localized display name of a cosmetic item id. Unknown ids (items added to
/// the server catalog after this build) fall back to a humanized id.
String cosmeticName(AppLocalizations l10n, String itemId) =>
    cosmeticNameOrNull(l10n, itemId) ?? humanizeItemId(itemId);

/// Localized name of a known catalog item, or null for unknown ids.
String? cosmeticNameOrNull(AppLocalizations l10n, String itemId) =>
    switch (itemId) {
      'dice_classic' => l10n.cosmeticDiceClassic,
      'dice_neon' => l10n.cosmeticDiceNeon,
      'dice_golden' => l10n.cosmeticDiceGolden,
      'dice_autumn' => l10n.cosmeticDiceAutumn,
      'token_classic' => l10n.cosmeticTokenClassic,
      'token_gem' => l10n.cosmeticTokenGem,
      'token_royal' => l10n.cosmeticTokenRoyal,
      'token_crown' => l10n.cosmeticTokenCrown,
      'ludo_board_classic' => l10n.cosmeticLudoBoardClassic,
      'ludo_board_midnight' => l10n.cosmeticLudoBoardMidnight,
      'ludo_board_royal' => l10n.cosmeticLudoBoardRoyal,
      'snakes_board_classic' => l10n.cosmeticSnakesBoardClassic,
      'snakes_board_jungle' => l10n.cosmeticSnakesBoardJungle,
      'snakes_board_candy' => l10n.cosmeticSnakesBoardCandy,
      'trail_none' => l10n.cosmeticTrailNone,
      'trail_sparkle' => l10n.cosmeticTrailSparkle,
      'trail_comet' => l10n.cosmeticTrailComet,
      'victory_confetti' => l10n.cosmeticVictoryConfetti,
      'victory_fireworks' => l10n.cosmeticVictoryFireworks,
      'victory_crown' => l10n.cosmeticVictoryCrown,
      'frame_none' => l10n.cosmeticFrameNone,
      'frame_bronze' => l10n.cosmeticFrameBronze,
      'frame_silver' => l10n.cosmeticFrameSilver,
      'frame_gold' => l10n.cosmeticFrameGold,
      'frame_royal' => l10n.cosmeticFrameRoyal,
      'title_rookie' => l10n.cosmeticTitleRookie,
      'title_strategist' => l10n.cosmeticTitleStrategist,
      'title_dice_master' => l10n.cosmeticTitleDiceMaster,
      'title_royal' => l10n.cosmeticTitleRoyal,
      'title_weekly_champion' => l10n.cosmeticTitleWeeklyChampion,
      'badge_first_win' => l10n.cosmeticBadgeFirstWin,
      'badge_friendly' => l10n.cosmeticBadgeFriendly,
      'emote_wave' => l10n.cosmeticEmoteWave,
      'emote_thumbs' => l10n.cosmeticEmoteThumbs,
      'emote_laugh' => l10n.cosmeticEmoteLaugh,
      'emote_wow' => l10n.cosmeticEmoteWow,
      'emote_crown' => l10n.cosmeticEmoteCrown,
      _ => null,
    };

/// Localized rarity name (`common|rare|epic|legendary`).
String rarityName(AppLocalizations l10n, String rarity) =>
    switch (CosmeticRarity.parse(rarity)) {
      CosmeticRarity.common => l10n.cosmeticRarityCommon,
      CosmeticRarity.rare => l10n.cosmeticRarityRare,
      CosmeticRarity.epic => l10n.cosmeticRarityEpic,
      CosmeticRarity.legendary => l10n.cosmeticRarityLegendary,
    };

/// Localized name of a cosmetic kind / equip slot (`dice`, `token`,
/// `ludo_board`, `snakes_board`, `frame`, `title`, `badge`, `emote`,
/// `victory`, `trail`).
String cosmeticKindName(AppLocalizations l10n, String kind) =>
    cosmeticKindNameOrNull(l10n, kind) ?? humanizeItemId(kind);

/// Localized kind name, or null for unknown kinds.
String? cosmeticKindNameOrNull(AppLocalizations l10n, String kind) =>
    switch (kind) {
      'dice' => l10n.cosmeticKindDice,
      'token' => l10n.cosmeticKindToken,
      'ludo_board' => l10n.cosmeticKindLudoBoard,
      'snakes_board' => l10n.cosmeticKindSnakesBoard,
      'frame' => l10n.cosmeticKindFrame,
      'title' => l10n.cosmeticKindTitle,
      'badge' => l10n.cosmeticKindBadge,
      'emote' => l10n.cosmeticKindEmote,
      'victory' => l10n.cosmeticKindVictory,
      'trail' => l10n.cosmeticKindTrail,
      _ => null,
    };

/// Last-resort fallback: `title_weekly_champion` → `Weekly Champion`.
String humanizeItemId(String id) {
  final parts = id.split('_').where((p) => p.isNotEmpty).toList();
  if (parts.length > 1) parts.removeAt(0);
  return parts
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join(' ');
}
