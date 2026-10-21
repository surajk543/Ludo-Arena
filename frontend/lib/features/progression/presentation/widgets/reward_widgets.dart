import 'package:flutter/material.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../collection/presentation/widgets/item_preview.dart';
import '../../domain/progression_models.dart';

/// Reward kinds shown as chips.
enum RewardKind { coins, diamonds, xp }

/// `+500` with a coin / diamond / XP glyph. Numbers stay LTR-readable.
class RewardChip extends StatelessWidget {
  const RewardChip({
    super.key,
    required this.kind,
    required this.amount,
    this.muted = false,
  });

  final RewardKind kind;
  final int amount;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final value = switch (kind) {
      RewardKind.coins => formatCoins(amount, locale),
      _ => formatNumberFull(amount, locale),
    };
    final text = kind == RewardKind.xp
        ? l10n.metaRewardXp(value)
        : l10n.metaRewardAmount(value);
    final label = switch (kind) {
      RewardKind.coins => l10n.metaRewardCoinsLabel(value),
      RewardKind.diamonds => l10n.metaRewardDiamondsLabel(value),
      RewardKind.xp => l10n.metaRewardXpLabel(value),
    };
    final tint = switch (kind) {
      RewardKind.coins => c.coin,
      RewardKind.diamonds => c.diamond,
      RewardKind.xp => c.brand,
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(5, 4, 10, 4),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: c.isDark ? 0.16 : 0.12),
          borderRadius: AppRadii.pillAll,
          border: Border.all(color: tint.withValues(alpha: muted ? 0.2 : 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            switch (kind) {
              RewardKind.coins => const CoinIcon(size: 18),
              RewardKind.diamonds => const DiamondIcon(size: 18),
              RewardKind.xp => _XpGlyph(color: tint),
            },
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // "+500" must not become "500+" in RTL.
                textDirection: kind == RewardKind.xp ? null : TextDirection.ltr,
                style: context.textTheme.labelMedium?.copyWith(
                  color: muted ? c.textSecondary : c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _XpGlyph extends StatelessWidget {
  const _XpGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [color.withValues(alpha: 0.85), color],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
    child: const Icon(Icons.star_rounded, size: 13, color: Colors.white),
  );
}

/// A cosmetic reward: small preview + localized name, tinted by rarity.
class ItemRewardChip extends StatelessWidget {
  const ItemRewardChip({super.key, required this.item, this.muted = false});

  final ItemRef item;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final rarity = CosmeticRarity.parse(item.rarity);
    final tint = rarity.color(c);
    final name = cosmeticName(l10n, item.id);
    return Semantics(
      label: l10n.metaRewardItemLabel(name, cosmeticKindName(l10n, item.kind)),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(3, 3, 10, 3),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: c.isDark ? 0.16 : 0.1),
          borderRadius: AppRadii.pillAll,
          border: Border.all(color: tint.withValues(alpha: muted ? 0.25 : 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.surface,
                border: Border.all(color: tint.withValues(alpha: 0.4)),
              ),
              child: ClipOval(
                child: CosmeticItemPreview(
                  id: item.id,
                  kind: item.kind,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelMedium?.copyWith(
                  color: muted ? c.textSecondary : c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wrap of reward chips.
class RewardChips extends StatelessWidget {
  const RewardChips({
    super.key,
    this.coins = 0,
    this.diamonds = 0,
    this.xp = 0,
    this.items = const [],
    this.muted = false,
  });

  final int coins;
  final int diamonds;
  final int xp;
  final List<ItemRef> items;
  final bool muted;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xs + 2,
    runSpacing: AppSpacing.xs + 2,
    children: [
      if (coins > 0)
        RewardChip(kind: RewardKind.coins, amount: coins, muted: muted),
      if (diamonds > 0)
        RewardChip(kind: RewardKind.diamonds, amount: diamonds, muted: muted),
      if (xp > 0) RewardChip(kind: RewardKind.xp, amount: xp, muted: muted),
      for (final i in items) ItemRewardChip(item: i, muted: muted),
    ],
  );
}
