import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../progression/application/meta_support.dart';
import '../../../progression/presentation/widgets/meta_scaffold.dart';
import '../../application/store_controller.dart';
import 'store_picture_sheet.dart';
import 'store_picture_tile.dart';

/// Remaining scroll distance below which a picture shelf asks for its next
/// page.
const double kPictureLoadMoreExtent = 480;

/// Asks [shelf] for its next page when [scroll] is near its end.
void maybeLoadMorePictures(
  WidgetRef ref,
  ScrollController scroll,
  PictureShelfProvider shelf,
) {
  if (!scroll.hasClients) return;
  if (scroll.position.extentAfter < kPictureLoadMoreExtent) {
    ref.read(shelf.notifier).loadMore();
  }
}

/// The slivers of a picture shelf (the Shop's Pictures, the Collection's
/// Pictures): a full-height spinner, error with Retry or [empty] state, else
/// the grid (tap opens the picture sheet on the same [shelf]) and its
/// footer (next page spinner or Retry).
List<Widget> pictureShelfSlivers(
  BuildContext context, {
  required StoreState state,
  required PictureShelfProvider shelf,
  required Widget empty,
  required VoidCallback onRetry,
  double maxWidth = 960,
}) {
  final l10n = AppLocalizations.of(context);
  if (state.loading) return const [MetaLoadingSliver()];
  final error = state.error;
  if (error != null) {
    return [
      MetaErrorSliver(message: metaErrorMessage(l10n, error), onRetry: onRetry),
    ];
  }
  if (state.items.isEmpty) return [empty];

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
          return StorePictureTile(
            key: ValueKey('pp-${item.id}'),
            item: item,
            onTap: () => showStorePictureSheet(context, item, shelf: shelf),
          );
        },
      ),
    ),
    SliverToBoxAdapter(
      child: _ShelfFooter(state: state, shelf: shelf),
    ),
  ];
}

/// End of the grid: a spinner while the next page loads, or Retry.
class _ShelfFooter extends ConsumerWidget {
  const _ShelfFooter({required this.state, required this.shelf});

  final StoreState state;
  final PictureShelfProvider shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    if (state.loadingMore) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: c.brand),
          ),
        ),
      );
    }
    final error = state.moreError;
    if (error != null) {
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
              l10n.storeLoadMoreFailed,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            PremiumButton(
              key: const ValueKey('store-load-more-retry'),
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
