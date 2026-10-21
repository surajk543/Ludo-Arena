import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../application/coin_packs_controller.dart';
import '../application/coin_purchase_controller.dart';
import '../domain/coin_pack_models.dart';
import 'widgets/coin_pack_card.dart';

/// The Shop's Coins category (slivers): a header, the coin packs and a
/// note that coins and diamonds have no cash value.
class CoinPacksSliver extends ConsumerWidget {
  const CoinPacksSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(coinPacksProvider);
    final busy = ref.watch(
      coinPurchaseControllerProvider.select((s) => s.busy),
    );
    const hero = SliverPadding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      sliver: SliverToBoxAdapter(child: _CoinsHero()),
    );

    if (state.catalog == null) {
      final error = state.error;
      return SliverMainAxisGroup(
        slivers: [
          hero,
          if (error != null)
            MetaErrorSliver(
              message: metaErrorMessage(l10n, error),
              onRetry: () => _retry(context, ref),
            )
          else if (state.loading)
            const MetaLoadingSliver(),
        ],
      );
    }

    final packs = state.packs;
    return SliverMainAxisGroup(
      slivers: [
        hero,
        SliverPadding(
          padding: kMetaPagePadding,
          sliver: SliverList.separated(
            itemCount: packs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) {
              final pack = packs[i];
              return CoinPackCard(
                pack: pack,
                product: state.productFor(pack),
                busy: busy.contains(pack.productId),
                onBuy: () => _buy(context, ref, pack),
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
              icon: Icons.info_outline_rounded,
              text: l10n.coinsNote,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(coinPacksProvider.notifier).refresh();
    } catch (e) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        metaErrorMessage(AppLocalizations.of(context), e),
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _buy(BuildContext context, WidgetRef ref, CoinPack pack) async {
    final result = await ref
        .read(coinPurchaseControllerProvider.notifier)
        .buy(pack);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (result) {
      case CoinBuyResult.unavailable:
        AppToast.show(
          context,
          l10n.coinsErrorUnavailable,
          icon: Icons.hourglass_top_rounded,
        );
      case CoinBuyResult.failed:
        AppToast.show(context, l10n.coinsBuyFailed, kind: ToastKind.error);
      case CoinBuyResult.started:
      case CoinBuyResult.busy:
        break;
    }
  }
}

/// Header card of the Coins category.
class _CoinsHero extends StatelessWidget {
  const _CoinsHero();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return SurfaceCard(
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [c.surfaceRaised, Color.lerp(c.surface, c.goldSoft, 0.5)!],
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
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
              child: const CoinIcon(size: 34),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.coinsHeroTitle, style: context.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.coinsHeroSubtitle,
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
