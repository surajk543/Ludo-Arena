import 'package:flutter/material.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/store_models.dart';

/// Preview of a Store emote on a soft rounded backdrop: its animation from
/// the emote cache, or a neutral glyph while it downloads (or when it is
/// unavailable).
class StoreEmotePreview extends StatelessWidget {
  const StoreEmotePreview({
    super.key,
    required this.item,
    required this.size,
    this.animate = true,
  });

  final ShopEmote item;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placeholder = Center(
      child: Icon(
        Icons.emoji_emotions_rounded,
        size: size * 0.42,
        color: c.textMuted.withValues(alpha: 0.6),
      ),
    );
    final asset = item.asset;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: RadialGradient(
            colors: [c.surfaceRaised, Color.lerp(c.surface, c.gold, 0.14)!],
          ),
          border: Border.all(color: c.cardBorder),
        ),
        child: asset == null
            ? placeholder
            : EmoteAssetView(
                asset: asset,
                size: size * 0.84,
                placeholder: placeholder,
                animate: animate,
              ),
      ),
    );
  }
}

/// Grid tile of a Store emote: preview, name and the diamond price, or
/// Owned.
class StoreEmoteTile extends StatelessWidget {
  const StoreEmoteTile({super.key, required this.item, required this.onTap});

  final ShopEmote item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final status = item.owned
        ? l10n.metaOwned
        : l10n.metaPriceDiamonds(formatNumberFull(item.priceDiamonds, locale));

    return Semantics(
      button: true,
      label: l10n.storeTileSemantics(item.name, status),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppRadii.lgAll,
            color: c.surface,
            boxShadow: c.shadow(AppElevation.low),
            border: Border.all(color: c.cardBorder),
          ),
          child: InkWell(
            borderRadius: AppRadii.lgAll,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final side = box.maxWidth < box.maxHeight
                            ? box.maxWidth
                            : box.maxHeight;
                        return Center(
                          child: StoreEmotePreview(
                            item: item,
                            size: side < 24 ? 24 : side,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  _Footer(item: item),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.item});

  final ShopEmote item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final style = context.textTheme.labelSmall;
    if (item.owned) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_rounded, size: 14, color: c.success),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              l10n.metaOwned,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(color: c.success),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const DiamondIcon(size: 14),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            formatNumberFull(item.priceDiamonds, locale),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(color: c.textPrimary),
          ),
        ),
      ],
    );
  }
}
