import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../authentication/application/session_controller.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../../progression/presentation/widgets/pill_tabs.dart';
import '../../wallet/presentation/wallet_sheet.dart';
import '../../wallet/wallet_controller.dart';
import '../application/store_controller.dart';
import '../domain/store_models.dart';
import 'widgets/store_picture_sheet.dart';
import 'widgets/store_picture_tile.dart';

/// The Store: profile pictures bought with diamonds and kept forever.
/// Filter pills, an infinitely scrolling grid (the next page loads near the
/// end), pull to refresh, and a sheet per picture to buy / apply it.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  /// Remaining scroll distance below which the next page is requested.
  static const double _loadMoreExtent = 480;
  static const double _maxWidth = 960;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter < _loadMoreExtent) {
      ref.read(storeProvider.notifier).loadMore();
    }
  }

  /// A page shorter than the screen never scrolls: check after layout.
  void _checkAfterLayout() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());

  Future<void> _refresh() async {
    try {
      await ref.read(storeProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        metaErrorMessage(AppLocalizations.of(context), e),
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(storeProvider);
    ref.listen(storeProvider, (prev, next) {
      if (prev?.items.length != next.items.length ||
          prev?.loading != next.loading) {
        _checkAfterLayout();
      }
    });
    final diamonds = ref.watch(
      walletControllerProvider.select((w) => w.diamonds),
    );

    return MetaScaffold(
      title: l10n.storeTitle,
      controller: _scroll,
      onRefresh: _refresh,
      maxWidth: _maxWidth,
      actions: [
        BalanceChip(
          kind: BalanceKind.diamonds,
          value: diamonds,
          onTap: () => WalletSheet.show(context),
        ),
      ],
      slivers: [
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          sliver: SliverToBoxAdapter(child: _StoreHero()),
        ),
        SliverToBoxAdapter(
          child: MetaPillTabs<StoreFilter>(
            key: const ValueKey('store-filters'),
            selected: state.filter,
            onSelected: (f) => ref.read(storeProvider.notifier).setFilter(f),
            pills: [
              MetaPill(
                value: StoreFilter.all,
                label: l10n.metaFilterAll,
                icon: Icons.apps_rounded,
              ),
              MetaPill(
                value: StoreFilter.animated,
                label: l10n.storeFilterAnimated,
                icon: Icons.motion_photos_on_rounded,
              ),
              MetaPill(
                value: StoreFilter.still,
                label: l10n.storeFilterStatic,
                icon: Icons.image_rounded,
              ),
              MetaPill(
                value: StoreFilter.owned,
                label: l10n.metaFilterOwned,
                icon: Icons.verified_rounded,
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
        ..._body(context, state),
      ],
    );
  }

  List<Widget> _body(BuildContext context, StoreState state) {
    final l10n = AppLocalizations.of(context);
    final ctl = ref.read(storeProvider.notifier);
    if (state.loading) return const [MetaLoadingSliver()];
    final error = state.error;
    if (error != null) {
      return [
        MetaErrorSliver(
          message: metaErrorMessage(l10n, error),
          onRetry: _refresh,
        ),
      ];
    }
    if (state.items.isEmpty) {
      final owned = state.filter == StoreFilter.owned;
      return [
        MetaEmptySliver(
          title: owned ? l10n.storeEmptyOwnedTitle : l10n.storeEmptyTitle,
          message: owned ? l10n.storeEmptyOwnedMessage : l10n.storeEmptyMessage,
          action: owned
              ? PremiumButton(
                  key: const ValueKey('store-browse-all'),
                  label: l10n.storeBrowseAll,
                  icon: Icons.apps_rounded,
                  size: PremiumButtonSize.medium,
                  expand: false,
                  onPressed: () => ctl.setFilter(StoreFilter.all),
                )
              : null,
        ),
      ];
    }

    final screen = MediaQuery.sizeOf(context).width;
    final width = math.min(screen, _maxWidth) - 2 * AppSpacing.lg;
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
              onTap: () => showStorePictureSheet(context, item),
            );
          },
        ),
      ),
      SliverToBoxAdapter(child: _Footer(state: state)),
    ];
  }
}

/// The player's current look and what the Store is about.
class _StoreHero extends ConsumerWidget {
  const _StoreHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(sessionControllerProvider.select((s) => s.user));
    return SurfaceCard(
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [c.surfaceRaised, Color.lerp(c.surface, c.brandSoft, 0.7)!],
      ),
      child: Row(
        children: [
          PlayerAvatar(
            avatarIndex: user?.avatar ?? 0,
            picture: user?.picture,
            frameId: user?.loadout.frame ?? 'frame_none',
            size: 60,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.storeHeroTitle, style: context.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.storeHeroSubtitle,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// End of the grid: a spinner while the next page loads, or Retry.
class _Footer extends ConsumerWidget {
  const _Footer({required this.state});

  final StoreState state;

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
              onPressed: () =>
                  ref.read(storeProvider.notifier).loadMore(retry: true),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: AppSpacing.md);
  }
}
