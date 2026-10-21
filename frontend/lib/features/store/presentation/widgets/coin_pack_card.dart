import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/coin_pack_models.dart';
import '../../domain/coin_pack_texts.dart';
import '../../iap/iap_store.dart';

/// One coin pack in the Shop: label badge (Popular / Best Value
/// highlighted), coins in the player's number format, bonus diamonds and a
/// Buy button showing the price (the store's localized price, else the
/// fallback price).
class CoinPackCard extends StatelessWidget {
  const CoinPackCard({
    super.key,
    required this.pack,
    required this.onBuy,
    this.product,
    this.busy = false,
  });

  final CoinPack pack;

  /// The store's product (null: not known to the store yet).
  final ProductDetails? product;

  /// A purchase of this pack is being opened or delivered.
  final bool busy;
  final FutureOr<void> Function() onBuy;

  /// Below this width the Buy button goes under the amounts.
  static const double _stackBelow = 340;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final label = CoinPackTexts.label(l10n, pack);
    final coins = formatCoins(pack.coins, locale);
    final diamonds = formatNumberFull(pack.diamonds, locale);
    final price = CoinPackTexts.price(locale, pack, product);
    final highlight = pack.highlighted;

    // Its own semantics node: the card reads the pack, the button buys it.
    final buy = Semantics(
      container: true,
      child: PremiumButton(
        key: ValueKey('coin-pack-buy-${pack.id}'),
        label: price,
        semanticLabel: l10n.coinsBuyFor(price),
        onPressed: busy ? null : onBuy,
        loading: busy,
        variant: highlight
            ? PremiumButtonVariant.gold
            : PremiumButtonVariant.primary,
        size: PremiumButtonSize.small,
        expand: false,
      ),
    );
    final amounts = ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LabelBadge(label: label, highlight: highlight),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.coinsPackCoins(coins),
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              const DiamondIcon(size: 16),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  l10n.coinsPackDiamonds(diamonds),
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: c.diamond,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: l10n.coinsPackSemantics(label, coins, diamonds, price),
      child: SurfaceCard(
        key: ValueKey('coin-pack-${pack.id}'),
        padding: const EdgeInsets.all(AppSpacing.md),
        gradient: highlight
            ? LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  c.surfaceRaised,
                  Color.lerp(c.surface, c.goldSoft, c.isDark ? 0.35 : 0.6)!,
                ],
              )
            : null,
        border: highlight
            ? Border.all(color: c.goldStrong.withValues(alpha: 0.8), width: 1.5)
            : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < _stackBelow;
            final art = _PackArt(size: stacked ? 44 : 52, highlight: highlight);
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      art,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: amounts),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  buy,
                ],
              );
            }
            return Row(
              children: [
                art,
                const SizedBox(width: AppSpacing.md),
                Expanded(child: amounts),
                const SizedBox(width: AppSpacing.sm),
                buy,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The pack's name as a pill; gold for the highlighted packs.
class _LabelBadge extends StatelessWidget {
  const _LabelBadge({required this.label, required this.highlight});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        gradient: highlight ? c.goldGradient : null,
        color: highlight ? null : c.brandSoft,
        borderRadius: AppRadii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (highlight) ...[
            Icon(Icons.star_rounded, size: 14, color: c.onGold),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelMedium?.copyWith(
                color: highlight ? c.onGold : c.brandStrong,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A coin in a soft (or gold) disc.
class _PackArt extends StatelessWidget {
  const _PackArt({required this.size, required this.highlight});

  final double size;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.coin.withValues(alpha: highlight ? 0.24 : 0.14),
          border: Border.all(color: c.coin.withValues(alpha: 0.45)),
        ),
        child: CoinIcon(size: size * 0.6),
      ),
    );
  }
}
