import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../authentication/application/session_controller.dart';
import '../../domain/collection_models.dart';
import '../../domain/collection_texts.dart';
import 'item_preview.dart';

/// "Your look": avatar with the equipped frame, title, dice and token, plus
/// collection progress. Tapping a slot opens that tab.
class LoadoutSummaryCard extends ConsumerWidget {
  const LoadoutSummaryCard({
    super.key,
    required this.data,
    required this.onOpenKind,
  });

  final CollectionData data;
  final ValueChanged<String> onOpenKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final user = ref.watch(sessionControllerProvider.select((s) => s.user));
    final lo = data.loadout;
    final owned = data.ownedCount;
    final total = data.items.length;

    return SurfaceCard(
      elevation: AppElevation.medium,
      padding: const EdgeInsets.all(AppSpacing.lg),
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [c.surfaceRaised, Color.lerp(c.surface, c.brandSoft, 0.7)!],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => onOpenKind('frame'),
                child: PlayerAvatar(
                  avatarIndex: user?.avatar ?? 0,
                  frameId: lo.frame,
                  size: 68,
                  semanticLabel: l10n.metaYourLook,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? l10n.metaYourLook,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    GestureDetector(
                      onTap: () => onOpenKind('title'),
                      child: TitleChip(titleId: lo.title),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.metaCollectedCount(
                        formatNumberFull(owned, locale),
                        formatNumberFull(total, locale),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: AppRadii.pillAll,
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : owned / total,
                        minHeight: 6,
                        color: c.gold,
                        backgroundColor: c.surfaceSunken,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final (kind, id) in [
                ('dice', lo.dice),
                ('token', lo.token),
                ('ludo_board', lo.ludoBoard),
                ('snakes_board', lo.snakesBoard),
              ]) ...[
                if (kind != 'dice') const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _SlotTile(
                    kind: kind,
                    itemId: id,
                    onTap: () => onOpenKind(kind),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.kind,
    required this.itemId,
    required this.onTap,
  });

  final String kind;
  final String itemId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final label = CollectionTexts.tab(l10n, kind);
    return Semantics(
      button: true,
      label: '$label: ${cosmeticName(l10n, itemId)}',
      excludeSemantics: true,
      child: Material(
        color: c.surface.withValues(alpha: 0.7),
        borderRadius: AppRadii.mdAll,
        child: InkWell(
          borderRadius: AppRadii.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.xs,
            ),
            child: Column(
              children: [
                CosmeticItemPreview(id: itemId, kind: kind, size: 40),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
