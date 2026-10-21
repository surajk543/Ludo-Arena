import 'package:flutter/material.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/collection_models.dart';
import '../../domain/collection_texts.dart';
import 'item_preview.dart';

/// Grid tile of the Collection Room: live preview, localized name, rarity
/// styling and an owned / equipped / locked footer with the acquisition.
class CollectionItemCard extends StatelessWidget {
  const CollectionItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.isNew = false,
  });

  final CollectionItem item;
  final VoidCallback onTap;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final rarity = CosmeticRarity.parse(item.rarity);
    final tint = rarity.color(c);
    final name = cosmeticName(l10n, item.id);
    final fancy =
        rarity == CosmeticRarity.epic || rarity == CosmeticRarity.legendary;
    final acquisition = CollectionTexts.acquisition(l10n, locale, item);
    final state = item.equipped
        ? l10n.metaEquipped
        : item.owned
        ? l10n.metaOwned
        : l10n.metaLocked;

    return Semantics(
      button: true,
      selected: item.equipped,
      label: l10n.metaItemSemantics(
        name,
        rarityName(l10n, item.rarity),
        state,
        item.owned ? '' : acquisition,
      ),
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadii.lgAll,
          boxShadow: [
            ...c.shadow(AppElevation.low),
            if (fancy && item.owned)
              BoxShadow(
                color: tint.withValues(alpha: c.isDark ? 0.25 : 0.18),
                blurRadius: 16,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: AppRadii.lgAll,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(c.surface, tint, c.isDark ? 0.16 : 0.12)!,
                  c.surface,
                ],
              ),
              border: Border.all(
                color: item.equipped
                    ? c.brand
                    : tint.withValues(alpha: item.owned ? 0.55 : 0.28),
                width: item.equipped ? 2 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: AppRadii.lgAll,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final side =
                                    (box.maxWidth < box.maxHeight
                                        ? box.maxWidth
                                        : box.maxHeight) *
                                    0.86;
                                return Center(
                                  child: CosmeticItemPreview(
                                    id: item.id,
                                    kind: item.kind,
                                    size: side < 24 ? 24 : side,
                                    dimmed: !item.owned,
                                  ),
                                );
                              },
                            ),
                          ),
                          PositionedDirectional(
                            top: 0,
                            start: 0,
                            child: _cornerBadge(context, l10n),
                          ),
                          if (!item.owned)
                            PositionedDirectional(
                              top: 0,
                              end: 0,
                              child: Icon(
                                Icons.lock_rounded,
                                size: 16,
                                color: c.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    _Footer(item: item, tint: tint, acquisition: acquisition),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cornerBadge(BuildContext context, AppLocalizations l10n) {
    final c = context.colors;
    if (item.equipped) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: 14, color: c.onBrand),
      );
    }
    if (isNew) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          gradient: c.goldGradient,
          borderRadius: AppRadii.pillAll,
        ),
        child: Text(
          l10n.metaNewBadge,
          style: context.textTheme.labelSmall?.copyWith(color: c.onGold),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.item,
    required this.tint,
    required this.acquisition,
  });

  final CollectionItem item;
  final Color tint;
  final String acquisition;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final style = context.textTheme.labelSmall;

    if (item.owned) {
      return Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              item.equipped ? l10n.metaEquipped : rarityName(l10n, item.rarity),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(color: item.equipped ? c.brand : tint),
            ),
          ),
        ],
      );
    }
    final price = item.acquisition.price;
    if (item.canPurchase && price != null) {
      return Row(
        children: [
          price.inDiamonds
              ? const DiamondIcon(size: 14)
              : const CoinIcon(size: 14),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              price.inDiamonds
                  ? formatNumberFull(price.diamonds, locale)
                  : formatCoins(price.coins, locale),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      );
    }
    return Text(
      acquisition,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style?.copyWith(color: c.textSecondary),
    );
  }
}
