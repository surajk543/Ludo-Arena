import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../../progression/presentation/widgets/pill_tabs.dart';
import '../application/collection_controller.dart';
import '../domain/collection_models.dart';
import '../domain/collection_texts.dart';
import 'widgets/item_card.dart';
import 'widgets/item_detail_sheet.dart';
import 'widgets/loadout_summary.dart';

/// The Collection Room: equipped look, kind tabs, owned/locked filter and a
/// grid of every cosmetic with live previews. Everything is cosmetic only.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, this.initialKind, this.initialItemId});

  final String? initialKind;
  final String? initialItemId;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  late String _kind = kCollectionKinds.contains(widget.initialKind)
      ? widget.initialKind!
      : kCollectionKinds.first;
  CollectionFilter _filter = CollectionFilter.all;
  bool _viewedLogged = false;
  bool _openedInitial = false;
  Set<String> _unseen = const {};
  bool _unseenComputed = false;
  late final CollectionSeenStore _seen = ref.read(collectionSeenStoreProvider);

  @override
  void dispose() {
    // Leaving the room marks new items as seen.
    if (_unseen.isNotEmpty) _seen.markSeen(_unseen);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await ref.read(collectionProvider.notifier).refresh();
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

    final List<Widget> slivers;
    switch (async) {
      case AsyncValue(:final value?):
        _onData(value);
        slivers = _content(context, value);
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
      onRefresh: _refresh,
      maxWidth: 720,
      slivers: slivers,
    );
  }

  List<Widget> _content(BuildContext context, CollectionData data) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final items = data.filtered(_kind, _filter);
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 720.0);
    final columns = width >= 600 ? 4 : (width >= 420 ? 3 : 2);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        sliver: SliverToBoxAdapter(
          child: LoadoutSummaryCard(
            data: data,
            onOpenKind: (k) => setState(() => _kind = k),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: MetaPillTabs<String>(
          key: const ValueKey('collection-kinds'),
          selected: _kind,
          onSelected: (k) => setState(() => _kind = k),
          pills: [
            for (final k in kCollectionKinds)
              MetaPill(
                value: k,
                label: CollectionTexts.tab(l10n, k),
                icon: CollectionTexts.icon(k),
                trailing:
                    '${formatNumberFull(data.ownedOf(k), locale)}/'
                    '${formatNumberFull(data.totalOf(k), locale)}',
              ),
          ],
        ),
      ),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Text(
                _filter == CollectionFilter.locked
                    ? l10n.metaAllOwnedInKind
                    : l10n.metaNothingOwnedInKind,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium,
              ),
            ),
          ),
        )
      else
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
}
