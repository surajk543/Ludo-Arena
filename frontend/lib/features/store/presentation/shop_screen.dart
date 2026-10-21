import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../authentication/application/session_controller.dart';
import '../../collection/application/collection_controller.dart';
import '../../collection/domain/collection_models.dart';
import '../../collection/domain/collection_texts.dart';
import '../../collection/presentation/widgets/item_card.dart';
import '../../collection/presentation/widgets/item_detail_sheet.dart';
import '../../meta_routes.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../../progression/presentation/widgets/pill_tabs.dart';
import '../../wallet/presentation/wallet_sheet.dart';
import '../../wallet/wallet_controller.dart';
import '../application/shop_category.dart';
import '../application/store_controller.dart';
import '../application/coin_packs_controller.dart';
import '../domain/store_models.dart';
import 'coin_packs_section.dart';
import 'coin_purchase_host.dart';
import 'widgets/picture_shelf.dart';

/// The Shop: everything for sale that the player does not own yet, by
/// category. "Coins" (first) sells coin packs for real money through
/// Google Play / the App Store; "Pictures" is the profile-picture shelf
/// (diamonds; filter pills, infinite scroll); every other category is a
/// cosmetic kind with fixed-price items (coins or diamonds) opened in the
/// Collection's item sheet. A bought item leaves the Shop and shows in the
/// Collection. The Shop always opens on Coins (a `?category=` deep link
/// wins).
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, this.initialCategory});

  /// `/shop?category=`; null opens Coins.
  final String? initialCategory;

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  static const double _maxWidth = 960;

  final ScrollController _scroll = ScrollController();
  late String _category = widget.initialCategory ?? kCoinsCategory;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    // Every visit starts on Coins (or the deep link's category).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _remember(_category);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _remember(String category) =>
      ref.read(shopCategoryProvider.notifier).select(category);

  void _select(String category) {
    setState(() => _category = category);
    _remember(category);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  bool get _onPictures => _category == kPictureCategory;

  void _maybeLoadMore() {
    if (!mounted || !_onPictures) return;
    maybeLoadMorePictures(ref, _scroll, storeProvider);
  }

  /// A page shorter than the screen never scrolls: check after layout.
  void _checkAfterLayout() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());

  Future<void> _refresh() async {
    try {
      if (_category == kCoinsCategory) {
        await ref.read(coinPacksProvider.notifier).refresh();
      } else if (_onPictures) {
        await ref.read(storeProvider.notifier).refresh();
      } else {
        await ref.read(collectionProvider.notifier).refresh();
      }
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
    final collection = ref.watch(collectionProvider);
    final pictures = ref.watch(storeProvider);
    ref.listen(storeProvider, (prev, next) {
      if (prev?.items.length != next.items.length ||
          prev?.loading != next.loading) {
        _checkAfterLayout();
      }
    });
    final categories = shopCategories(collection.value);
    // An unknown or (no longer) sold category falls back to Coins.
    final category = categories.contains(_category)
        ? _category
        : kCoinsCategory;

    final scaffold = MetaScaffold(
      title: l10n.storeTitle,
      controller: _scroll,
      onRefresh: _refresh,
      maxWidth: _maxWidth,
      actions: const [
        _CoinsChip(),
        SizedBox(width: AppSpacing.xs),
        _DiamondsChip(),
      ],
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
        SliverToBoxAdapter(
          child: MetaPillTabs<String>(
            key: const ValueKey('shop-categories'),
            selected: category,
            onSelected: _select,
            pills: [
              for (final k in categories)
                MetaPill(
                  value: k,
                  label: switch (k) {
                    kCoinsCategory => l10n.coinsCategory,
                    kPictureCategory => l10n.metaTabPictures,
                    _ => CollectionTexts.tab(l10n, k),
                  },
                  icon: switch (k) {
                    kCoinsCategory => Icons.monetization_on_rounded,
                    kPictureCategory => Icons.face_retouching_natural,
                    _ => CollectionTexts.icon(k),
                  },
                ),
            ],
          ),
        ),
        if (category == kCoinsCategory)
          const CoinPacksSliver()
        else if (category == kPictureCategory)
          ..._pictures(context, pictures)
        else
          ..._cosmetics(context, collection, category),
      ],
    );
    // Purchase results (coins added, pending, refused) while the Shop is
    // open; the app-wide host shows them elsewhere.
    return CoinPurchaseHost(child: scaffold);
  }

  List<Widget> _pictures(BuildContext context, StoreState state) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(sessionControllerProvider.select((s) => s.user));
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        sliver: SliverToBoxAdapter(
          child: _ShopHero(
            leading: PlayerAvatar(
              avatarIndex: user?.avatar ?? 0,
              picture: user?.picture,
              frameId: user?.loadout.frame ?? 'frame_none',
              size: 60,
            ),
            title: l10n.storeHeroTitle,
            subtitle: l10n.storeHeroSubtitle,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: MetaPillTabs<StoreFilter>(
          key: const ValueKey('store-filters'),
          dense: true,
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
          ],
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
      ...pictureShelfSlivers(
        context,
        state: state,
        shelf: storeProvider,
        maxWidth: _maxWidth,
        onRetry: _refresh,
        empty: MetaEmptySliver(
          title: l10n.storeEmptyTitle,
          message: l10n.storeEmptyMessage,
          action: _viewInCollection(l10n, kPictureCategory),
        ),
      ),
    ];
  }

  List<Widget> _cosmetics(
    BuildContext context,
    AsyncValue<CollectionData> collection,
    String kind,
  ) {
    final l10n = AppLocalizations.of(context);
    final hero = SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      sliver: SliverToBoxAdapter(
        child: _ShopHero(
          leading: _KindBadge(kind: kind),
          title: CollectionTexts.tab(l10n, kind),
          subtitle: l10n.storeCosmeticsHeroSubtitle,
        ),
      ),
    );
    switch (collection) {
      case AsyncValue(:final value?):
        final items = value.shopItems(kind);
        if (items.isEmpty) {
          return [
            hero,
            MetaEmptySliver(
              title: l10n.storeAllOwnedTitle,
              message: l10n.storeAllOwnedMessage,
              action: _viewInCollection(l10n, kind),
            ),
          ];
        }
        final width = MediaQuery.sizeOf(context).width.clamp(0.0, _maxWidth);
        final columns = width >= 760
            ? 5
            : (width >= 600 ? 4 : (width >= 420 ? 3 : 2));
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        return [
          hero,
          SliverPadding(
            padding: kMetaPagePadding,
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: textScale > 1.15 ? 0.66 : 0.74,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return CollectionItemCard(
                  key: ValueKey('shop-item-${item.id}'),
                  item: item,
                  onTap: () =>
                      showCollectionItemSheet(context, item.id, inShop: true),
                );
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: MetaNote(
                icon: Icons.verified_rounded,
                text: l10n.metaCollectionFairNote,
              ),
            ),
          ),
        ];
      case AsyncError(:final error):
        return [
          MetaErrorSliver(
            message: metaErrorMessage(l10n, error),
            onRetry: () => ref.invalidate(collectionProvider),
          ),
        ];
      default:
        return const [MetaLoadingSliver()];
    }
  }

  /// "View in Collection" (that category of the Collection Room).
  Widget _viewInCollection(AppLocalizations l10n, String kind) => PremiumButton(
    key: const ValueKey('shop-view-in-collection'),
    label: l10n.storeViewInCollection,
    icon: Icons.diamond_rounded,
    size: PremiumButtonSize.medium,
    variant: PremiumButtonVariant.secondary,
    expand: false,
    onPressed: () => context.push(MetaRoutes.collectionFor(kind: kind)),
  );
}

/// Header card of a Shop category: a visual, a title and what it sells.
class _ShopHero extends StatelessWidget {
  const _ShopHero({
    required this.leading,
    required this.title,
    required this.subtitle,
  });

  final Widget leading;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SurfaceCard(
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [c.surfaceRaised, Color.lerp(c.surface, c.goldSoft, 0.5)!],
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(subtitle, style: context.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gold badge with the icon of a cosmetic kind.
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: c.goldGradient,
          borderRadius: AppRadii.lgAll,
          boxShadow: [
            BoxShadow(
              color: c.goldStrong.withValues(alpha: c.isDark ? 0.4 : 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(CollectionTexts.icon(kind), size: 30, color: c.onGold),
      ),
    );
  }
}

class _CoinsChip extends ConsumerWidget {
  const _CoinsChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = ref.watch(walletControllerProvider.select((w) => w.coins));
    return BalanceChip(
      kind: BalanceKind.coins,
      value: coins,
      onTap: () => WalletSheet.show(context),
    );
  }
}

class _DiamondsChip extends ConsumerWidget {
  const _DiamondsChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diamonds = ref.watch(
      walletControllerProvider.select((w) => w.diamonds),
    );
    return BalanceChip(
      kind: BalanceKind.diamonds,
      value: diamonds,
      onTap: () => WalletSheet.show(context),
    );
  }
}
