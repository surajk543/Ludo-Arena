import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/analytics/analytics_providers.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../../progression/presentation/widgets/pill_tabs.dart';
import '../../store/application/emote_shelf_controller.dart';
import '../../store/application/shop_category.dart';
import '../../store/application/store_controller.dart';
import '../../store/presentation/widgets/emote_shelf.dart';
import '../../store/presentation/widgets/picture_shelf.dart';
import '../application/collection_controller.dart';
import '../domain/collection_models.dart';
import '../domain/collection_texts.dart';
import 'widgets/item_card.dart';
import 'widgets/item_detail_sheet.dart';
import 'widgets/loadout_summary.dart';

/// Collection Room tabs: the cosmetic kinds with the owned profile pictures
/// next to the other looks of the avatar (before frames).
final List<String> kCollectionTabs = [
  for (final k in kCollectionKinds) ...[if (k == 'frame') kPictureCategory, k],
];

/// The Collection Room: equipped look, kind tabs, owned/locked filter and a
/// grid of everything the player owns (starter, bought, earned) plus what
/// can still be earned by playing, shown locked with how to earn it. Items
/// for sale live in the Shop until bought. The Pictures tab lists the owned
/// profile pictures; the Emotes tab also lists the animated emotes bought in
/// the Shop (page by page). Everything is cosmetic only.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, this.initialKind, this.initialItemId});

  final String? initialKind;
  final String? initialItemId;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  late String _kind = kCollectionTabs.contains(widget.initialKind)
      ? widget.initialKind!
      : kCollectionTabs.first;
  CollectionFilter _filter = CollectionFilter.all;
  bool _viewedLogged = false;
  bool _openedInitial = false;
  Set<String> _unseen = const {};
  bool _unseenComputed = false;
  late final CollectionSeenStore _seen = ref.read(collectionSeenStoreProvider);
  final ScrollController _scroll = ScrollController();

  bool get _onPictures => _kind == kPictureCategory;
  bool get _onEmotes => _kind == kShopEmoteCategory;

  /// Whether the Emotes tab shows the bought Store emotes (not under the
  /// "to unlock" filter: they are all owned).
  bool get _showsStoreEmotes => _onEmotes && _filter != CollectionFilter.locked;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    // Leaving the room marks new items as seen.
    if (_unseen.isNotEmpty) _seen.markSeen(_unseen);
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!mounted) return;
    if (_onPictures) {
      maybeLoadMorePictures(ref, _scroll, ownedPicturesProvider);
    } else if (_showsStoreEmotes) {
      maybeLoadMoreEmotes(ref, _scroll, ownedStoreEmotesProvider);
    }
  }

  void _select(String kind) {
    setState(() => _kind = kind);
    if (kind == kPictureCategory || kind == kShopEmoteCategory) {
      // A first page shorter than the screen never scrolls.
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    }
  }

  Future<void> _refresh() async {
    try {
      if (_onPictures) {
        await ref.read(ownedPicturesProvider.notifier).refresh();
      } else if (_onEmotes) {
        await Future.wait([
          ref.read(collectionProvider.notifier).refresh(),
          ref.read(ownedStoreEmotesProvider.notifier).refresh(),
        ]);
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

  void _open(CollectionItem item) {
    if (_unseen.contains(item.id)) {
      _seen.markSeen([item.id]);
      setState(() => _unseen = {..._unseen}..remove(item.id));
    }
    showCollectionItemSheet(context, item.id);
  }

  void _openShop(String category) =>
      context.push(AppRoutes.shopFor(category: category));

  void _onData(CollectionData data) {
    if (!_viewedLogged) {
      _viewedLogged = true;
      ref.read(analyticsServiceProvider).collectionViewed();
    }
    if (!_unseenComputed) {
      _unseenComputed = true;
      _unseen = _seen.unseenOwned(data);
    }
    if (!_openedInitial && widget.initialItemId != null) {
      _openedInitial = true;
      final item = data.byId(widget.initialItemId!);
      if (item != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _kind = item.kind);
            _open(item);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(collectionProvider);
    final pictures = ref.watch(ownedPicturesProvider);
    final emotes = ref.watch(ownedStoreEmotesProvider);
    void checkAfterLayout(
      int? prevLength,
      bool? prevLoading,
      int length,
      bool loading,
    ) {
      if (prevLength != length || prevLoading != loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
      }
    }

    ref.listen(
      ownedPicturesProvider,
      (prev, next) => checkAfterLayout(
        prev?.items.length,
        prev?.loading,
        next.items.length,
        next.loading,
      ),
    );
    ref.listen(
      ownedStoreEmotesProvider,
      (prev, next) => checkAfterLayout(
        prev?.items.length,
        prev?.loading,
        next.items.length,
        next.loading,
      ),
    );

    final List<Widget> slivers;
    switch (async) {
      case AsyncValue(:final value?):
        _onData(value);
        slivers = _content(context, value, pictures, emotes);
      case AsyncError(:final error):
        slivers = [
          MetaErrorSliver(
            message: metaErrorMessage(l10n, error),
            onRetry: () => ref.invalidate(collectionProvider),
          ),
        ];
      default:
        slivers = const [MetaLoadingSliver()];
    }

    return MetaScaffold(
      title: l10n.metaCollectionTitle,
      controller: _scroll,
      onRefresh: _refresh,
      maxWidth: 720,
      slivers: slivers,
    );
  }

  List<Widget> _content(
    BuildContext context,
    CollectionData data,
    StoreState pictures,
    EmoteShelfState emotes,
  ) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final picturesLoaded = !pictures.loading && pictures.error == null;
    // Bought Store emotes count in the Emotes tab once their total is known.
    int extra(String kind) =>
        kind == kShopEmoteCategory && emotes.loaded ? emotes.total : 0;

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        sliver: SliverToBoxAdapter(
          child: LoadoutSummaryCard(data: data, onOpenKind: _select),
        ),
      ),
      SliverToBoxAdapter(
        child: MetaPillTabs<String>(
          key: const ValueKey('collection-kinds'),
          selected: _kind,
          onSelected: _select,
          pills: [
            for (final k in kCollectionTabs)
              if (k == kPictureCategory)
                MetaPill(
                  value: k,
                  label: l10n.metaTabPictures,
                  icon: Icons.face_retouching_natural,
                  trailing: picturesLoaded
                      ? formatNumberFull(pictures.total, locale)
                      : null,
                )
              else
                MetaPill(
                  value: k,
                  label: CollectionTexts.tab(l10n, k),
                  icon: CollectionTexts.icon(k),
                  trailing:
                      '${formatNumberFull(data.ownedOf(k) + extra(k), locale)}/'
                      '${formatNumberFull(data.totalOf(k) + extra(k), locale)}',
                ),
          ],
        ),
      ),
      if (_onPictures)
        ..._pictures(context, pictures)
      else
        ..._items(context, data, emotes),
    ];
  }

  List<Widget> _pictures(BuildContext context, StoreState state) {
    final l10n = AppLocalizations.of(context);
    return [
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
      ...pictureShelfSlivers(
        context,
        state: state,
        shelf: ownedPicturesProvider,
        maxWidth: 720,
        onRetry: () => ref.read(ownedPicturesProvider.notifier).refresh(),
        empty: MetaEmptySliver(
          title: l10n.storeEmptyOwnedTitle,
          message: l10n.profilePictureEmptyMessage,
          action: _GoToShopButton(onPressed: () => _openShop(kPictureCategory)),
        ),
      ),
      if (state.items.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _MoreInShop(onPressed: () => _openShop(kPictureCategory)),
          ),
        ),
    ];
  }

  List<Widget> _items(
    BuildContext context,
    CollectionData data,
    EmoteShelfState emotes,
  ) {
    final l10n = AppLocalizations.of(context);
    final items = data.filtered(_kind, _filter);
    // The Shop always sells emotes (its animated Store emotes).
    final forSale = data.shopItems(_kind).isNotEmpty || _onEmotes;
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 720.0);
    final columns = width >= 600 ? 4 : (width >= 420 ? 3 : 2);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return [
      SliverToBoxAdapter(
        child: MetaPillTabs<CollectionFilter>(
          key: const ValueKey('collection-filter'),
          dense: true,
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
          pills: [
            MetaPill(value: CollectionFilter.all, label: l10n.metaFilterAll),
            MetaPill(
              value: CollectionFilter.owned,
              label: l10n.metaFilterOwned,
            ),
            MetaPill(
              value: CollectionFilter.locked,
              label: l10n.metaFilterLocked,
            ),
          ],
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
      if (items.isEmpty)
        SliverPadding(
          padding: kMetaPagePadding,
          sliver: SliverToBoxAdapter(
            child: _EmptyKind(
              key: const ValueKey('collection-empty'),
              message: data.totalOf(_kind) == 0
                  ? l10n.metaKindEmptyMessage
                  : _filter == CollectionFilter.locked
                  ? l10n.metaAllOwnedInKind
                  : l10n.metaNothingOwnedInKind,
              // An empty category always points to the Shop.
              onGoToShop: forSale || data.totalOf(_kind) == 0
                  ? () => _openShop(forSale ? _kind : kPictureCategory)
                  : null,
            ),
          ),
        )
      else ...[
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
                key: ValueKey('item-${item.id}'),
                item: item,
                isNew: _unseen.contains(item.id),
                onTap: () => _open(item),
              );
            },
          ),
        ),
      ],
      if (_showsStoreEmotes) ..._storeEmotes(context, emotes),
      if (items.isNotEmpty || _showsStoreEmotes) ...[
        if (forSale)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _MoreInShop(onPressed: () => _openShop(_kind)),
            ),
          ),
      ],
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
  }

  /// The Emotes tab's animated emotes bought in the Shop (`filter=owned`),
  /// page by page under a section title; tap shows the owned sheet.
  List<Widget> _storeEmotes(BuildContext context, EmoteShelfState emotes) {
    final l10n = AppLocalizations.of(context);
    return [
      SliverToBoxAdapter(
        child: EmoteSectionTitle(
          key: const ValueKey('collection-store-emotes'),
          title: l10n.storeEmotesHeroTitle,
        ),
      ),
      ...emoteShelfSlivers(
        context,
        state: emotes,
        shelf: ownedStoreEmotesProvider,
        maxWidth: 720,
        inline: true,
        onRetry: () => ref.read(ownedStoreEmotesProvider.notifier).refresh(),
        empty: SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: SliverToBoxAdapter(
            child: Text(
              l10n.storeEmotesOwnedEmpty,
              key: const ValueKey('collection-store-emotes-empty'),
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    ];
  }
}

/// Nothing to show in a tab: a friendly line and, when the Shop sells
/// something of it, a way there.
class _EmptyKind extends StatelessWidget {
  const _EmptyKind({super.key, required this.message, this.onGoToShop});

  final String message;
  final VoidCallback? onGoToShop;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium,
        ),
        if (onGoToShop != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _GoToShopButton(onPressed: onGoToShop!),
        ],
      ],
    ),
  );
}

class _GoToShopButton extends StatelessWidget {
  const _GoToShopButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PremiumButton(
    key: const ValueKey('collection-go-to-shop'),
    label: AppLocalizations.of(context).metaGoToShop,
    icon: Icons.storefront_rounded,
    variant: PremiumButtonVariant.gold,
    size: PremiumButtonSize.medium,
    expand: false,
    onPressed: onPressed,
  );
}

/// Below a tab's grid: more of it is for sale in the Shop.
class _MoreInShop extends StatelessWidget {
  const _MoreInShop({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: PremiumButton(
      key: const ValueKey('collection-more-in-shop'),
      label: AppLocalizations.of(context).metaFindMoreInShop,
      icon: Icons.storefront_rounded,
      variant: PremiumButtonVariant.secondary,
      size: PremiumButtonSize.small,
      expand: false,
      onPressed: onPressed,
    ),
  );
}
