import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:ludo_royale/shared/widgets/cosmetic_names.dart';

void main() {
  // Every id from docs/cosmetics-catalog.md.
  const catalog = [
    'dice_classic',
    'dice_neon',
    'dice_golden',
    'dice_autumn',
    'token_classic',
    'token_gem',
    'token_royal',
    'token_crown',
    'ludo_board_classic',
    'ludo_board_midnight',
    'ludo_board_royal',
    'snakes_board_classic',
    'snakes_board_jungle',
    'snakes_board_candy',
    'trail_none',
    'trail_sparkle',
    'trail_comet',
    'victory_confetti',
    'victory_fireworks',
    'victory_crown',
    'frame_none',
    'frame_bronze',
    'frame_silver',
    'frame_gold',
    'frame_royal',
    'title_rookie',
    'title_strategist',
    'title_dice_master',
    'title_royal',
    'title_weekly_champion',
    'badge_first_win',
    'badge_friendly',
    'emote_wave',
    'emote_thumbs',
    'emote_laugh',
    'emote_wow',
    'emote_crown',
  ];

  test('catalog list matches the rarity table', () {
    expect(kCatalogItemIds.toSet(), catalog.toSet());
  });

  test('English names match the catalog', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(cosmeticName(en, 'dice_classic'), 'Classic Ivory');
    expect(cosmeticName(en, 'title_royal'), 'Royal Highness');
    expect(cosmeticName(en, 'frame_royal'), 'Royal Crest');
    expect(cosmeticName(en, 'emote_thumbs'), 'Thumbs Up');
  });

  for (final code in ['en', 'hi', 'ur', 'id', 'ar']) {
    test('every catalog id has a real $code name', () {
      final l10n = lookupAppLocalizations(Locale(code));
      for (final id in catalog) {
        final name = cosmeticNameOrNull(l10n, id);
        expect(name, isNotNull, reason: '$code $id has no translation');
        expect(name, isNotEmpty, reason: id);
      }
      for (final r in ['common', 'rare', 'epic', 'legendary']) {
        expect(rarityName(l10n, r), isNotEmpty);
      }
      for (final k in [
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
      ]) {
        expect(cosmeticKindNameOrNull(l10n, k), isNotNull);
      }
    });
  }

  test('unknown ids fall back to a humanized name', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(cosmeticName(en, 'dice_space_cats'), 'Space Cats');
    expect(cosmeticRarity('dice_space_cats'), CosmeticRarity.common);
    expect(cosmeticRarity('token_crown'), CosmeticRarity.legendary);
  });
}
