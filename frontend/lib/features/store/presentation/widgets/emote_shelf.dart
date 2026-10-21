import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../progression/application/meta_support.dart';
import '../../../progression/presentation/widgets/meta_scaffold.dart';
import '../../application/emote_shelf_controller.dart';
import 'picture_shelf.dart' show kPictureLoadMoreExtent;
import 'store_emote_sheet.dart';
import 'store_emote_tile.dart';

/// Asks [shelf] for its next page when [scroll] is near its end.
void maybeLoadMoreEmotes(
  WidgetRef ref,
  ScrollController scroll,
  EmoteShelfProvider shelf,
) {
  if (!scroll.hasClients) return;
  if (scroll.position.extentAfter < kPictureLoadMoreExtent) {
    ref.read(shelf.notifier).loadMore();
  }
}

/// The grid of an emote shelf (the Shop's Emotes, the Collection's bought
/// emotes) and its footer (next page spinner or Retry): a spinner while the
/// first page loads, an error with [onRetry], or [empty] (nothing when
/// null) for an empty shelf. Tap opens the emote sheet on the same [shelf].
/// [inline] keeps the spinner and the error small (a section of a longer
/// page) instead of filling the rest of the screen.
List<Widget> emoteShelfSlivers(
  BuildContext context, {
  required EmoteShelfState state,
  required EmoteShelfProvider shelf,
  required VoidCallback onRetry,
  Widget? empty,
  double maxWidth = 960,
  bool inline = false,
}) {
  final l10n = AppLocalizations.of(context);
  if (state.loading) {
    return [
      if (inline)
        const SliverToBoxAdapter(child: _InlineSpinner())
      else
        const MetaLoadingSliver(),
    ];
  }
  final error = state.error;
  if (error != null) {
    final message = metaErrorMessage(l10n, error);
    return [
      if (inline)
        SliverToBoxAdapter(
          child: _InlineRetry(message: message, onRetry: onRetry),
        )
      else
        MetaErrorSliver(message: message, onRetry: onRetry),
    ];
  }
  if (state.items.isEmpty) return [?empty];

  final screen = MediaQuery.sizeOf(context).width;
  final width = math.min(screen, maxWidth) - 2 * AppSpacing.lg;
  final columns = width >= 760 ? 5 : (width >= 540 ? 4 : 3);
  const gap = AppSpacing.md;
  final tileWidth = (width - gap * (columns - 1)) / columns;
  final textScale = MediaQuery.textScalerOf(context).scale(1);
  // Preview (≈ the tile width) + name and price lines that grow with the
  // text scale.
  final extent = tileWidth * 0.78 + 60 * textScale + 16;

  return [
    SliverPadding(
      padding: kMetaPagePadding,
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          mainAxisExtent: extent,
        ),
        itemCount: state.items.length,
        itemBuilder: (context, i) {
          final item = state.items[i];
          return StoreEmoteTile(
            key: ValueKey('em-${item.id}'),
            item: item,
            onTap: () => showStoreEmoteSheet(context, item, shelf: shelf),
          );
        },
      ),
    ),
    SliverToBoxAdapter(
      child: _ShelfFooter(state: state, shelf: shelf),
    ),
  ];
}

/// Small section title above an emote grid.
class EmoteSectionTitle extends StatelessWidget {
  const EmoteSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
    child: Row(
      children: [
        Icon(
          Icons.auto_awesome_rounded,
          size: 18,
          color: context.colors.goldStrong,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: context.textTheme.titleSmall),
          ),
        ),
      ],
    ),
  );
}

class _InlineSpinner extends StatelessWidget {
  const _InlineSpinner();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Center(
      child: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: context.colors.brand,
        ),
      ),
    ),
  );
}

class _InlineRetry extends StatelessWidget {
  const _InlineRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    child: Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        PremiumButton(
          key: const ValueKey('store-emotes-retry'),
          label: AppLocalizations.of(context).commonRetry,
          icon: Icons.refresh_rounded,
          size: PremiumButtonSize.small,
          variant: PremiumButtonVariant.secondary,
          expand: false,
          onPressed: onRetry,
        ),
      ],
    ),
  );
}

/// End of the grid: a spinner while the next page loads, or Retry.
class _ShelfFooter extends ConsumerWidget {
  const _ShelfFooter({required this.state, required this.shelf});

  final EmoteShelfState state;
  final EmoteShelfProvider shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (state.loadingMore) return const _InlineSpinner();
    if (state.moreError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          0,
        ),
        child: Column(
          children: [
            Text(
              l10n.storeEmotesLoadMoreFailed,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            PremiumButton(
              key: const ValueKey('store-emotes-load-more-retry'),
              label: l10n.commonRetry,
              icon: Icons.refresh_rounded,
              size: PremiumButtonSize.small,
              variant: PremiumButtonVariant.secondary,
              expand: false,
              onPressed: () => ref.read(shelf.notifier).loadMore(retry: true),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: AppSpacing.md);
  }
}
