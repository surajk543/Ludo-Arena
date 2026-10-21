import 'package:flutter/material.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/store_models.dart';

/// Round preview of a Store picture on a soft backdrop. Shows a neutral
/// glyph while the picture downloads (or when it is unavailable).
class StorePicturePreview extends StatelessWidget {
  const StorePicturePreview({
    super.key,
    required this.item,
    required this.size,
    this.animate = true,
  });

  final ProfilePicture item;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placeholder = Center(
      child: Icon(
        item.isAnimated
            ? Icons.motion_photos_on_rounded
            : Icons.face_retouching_natural,
        size: size * 0.38,
        color: c.textMuted.withValues(alpha: 0.6),
      ),
    );
    final picture = item.picture;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [c.surfaceRaised, Color.lerp(c.surface, c.brand, 0.16)!],
          ),
          border: Border.all(color: c.cardBorder),
        ),
        child: ClipOval(
          child: picture == null
              ? placeholder
              : ProfilePictureView(
                  picture: picture,
                  size: size,
                  placeholder: placeholder,
                  animate: animate,
                ),
        ),
      ),
    );
  }
}

/// Grid tile of the Store: preview, name and the diamond price, or the
/// Owned / Equipped state.
class StorePictureTile extends StatelessWidget {
  const StorePictureTile({super.key, required this.item, required this.onTap});

  final ProfilePicture item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final status = item.equipped
        ? l10n.metaEquipped
        : item.owned
        ? l10n.metaOwned
        : l10n.metaPriceDiamonds(formatNumberFull(item.priceDiamonds, locale));

    return Semantics(
      button: true,
      selected: item.equipped,
      label: l10n.storeTileSemantics(item.name, status),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppRadii.lgAll,
            color: c.surface,
            boxShadow: c.shadow(AppElevation.low),
            border: Border.all(
              color: item.equipped ? c.brand : c.cardBorder,
              width: item.equipped ? 2 : 1,
            ),
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
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final side = box.maxWidth < box.maxHeight
                                  ? box.maxWidth
                                  : box.maxHeight;
                              return Center(
                                child: StorePicturePreview(
                                  item: item,
                                  size: side < 24 ? 24 : side,
                                ),
                              );
                            },
                          ),
                        ),
                        if (item.equipped)
                          PositionedDirectional(
                            top: 0,
                            start: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: c.brand,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: c.onBrand,
                              ),
                            ),
                          ),
                        if (item.isAnimated)
                          PositionedDirectional(
                            top: 0,
                            end: 0,
                            child: Icon(
                              Icons.motion_photos_on_rounded,
                              size: 16,
                              color: c.textMuted,
                            ),
                          ),
                      ],
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

  final ProfilePicture item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final style = context.textTheme.labelSmall;

    if (item.owned) {
      final color = item.equipped ? c.brand : c.success;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.equipped ? Icons.check_circle_rounded : Icons.verified_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              item.equipped ? l10n.metaEquipped : l10n.metaOwned,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(color: color),
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
