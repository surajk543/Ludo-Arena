import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../collection/presentation/widgets/item_preview.dart';
import '../../../progression/domain/progression_models.dart';

/// Server-confirmed new collection items after a claim (no randomness: the
/// exact items the mission promised, plus any level milestones).
abstract final class GrantedItemsDialog {
  /// Returns true when the user chose "View collection".
  static Future<bool> show(BuildContext context, List<ItemRef> items) async {
    final l10n = AppLocalizations.of(context);
    final result = await AppDialog.show<bool>(
      context,
      title: l10n.metaNewItemsTitle,
      message: l10n.metaNewItemsMessage(items.length),
      content: GrantedItemsGrid(items: items),
      actions: [
        AppDialogAction(
          label: l10n.metaNice,
          variant: PremiumButtonVariant.primary,
          value: false,
        ),
        AppDialogAction(
          label: l10n.metaViewCollection,
          variant: PremiumButtonVariant.secondary,
          value: true,
        ),
      ],
    );
    return result ?? false;
  }
}

/// Item tiles (preview + name + rarity) used by reward dialogs.
class GrantedItemsGrid extends StatelessWidget {
  const GrantedItemsGrid({super.key, required this.items});

  final List<ItemRef> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final item in items)
          Builder(
            builder: (context) {
              final rarity = CosmeticRarity.parse(item.rarity);
              final tint = rarity.color(c);
              final name = cosmeticName(l10n, item.id);
              return Semantics(
                label: l10n.metaRewardItemLabel(
                  name,
                  cosmeticKindName(l10n, item.kind),
                ),
                excludeSemantics: true,
                child: Container(
                  width: 104,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: c.isDark ? 0.14 : 0.08),
                    borderRadius: AppRadii.mdAll,
                    border: Border.all(color: tint.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CosmeticItemPreview(
                        id: item.id,
                        kind: item.kind,
                        size: 64,
                        animate: true,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelMedium,
                      ),
                      Text(
                        rarityName(l10n, item.rarity),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: tint,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
