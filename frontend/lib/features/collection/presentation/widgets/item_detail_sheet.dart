import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/audio_haptics/audio_service.dart';
import '../../../../core/audio_haptics/haptics_service.dart';
import '../../../../core/localization/number_format.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../meta_routes.dart';
import '../../../progression/application/meta_support.dart';
import '../../../progression/presentation/widgets/meta_scaffold.dart';
import '../../../wallet/wallet_controller.dart';
import '../../application/collection_controller.dart';
import '../../domain/collection_models.dart';
import '../../domain/collection_texts.dart';
import 'item_preview.dart';

/// Opens the item detail sheet (large preview, description, acquisition,
/// equip / purchase).
Future<void> showCollectionItemSheet(BuildContext context, String itemId) =>
    AppBottomSheet.show<void>(
      context,
      builder: (_) => CollectionItemSheet(itemId: itemId),
    );

class CollectionItemSheet extends ConsumerWidget {
  const CollectionItemSheet({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final item = ref.watch(
      collectionProvider.select((a) => a.value?.byId(itemId)),
    );
    if (item == null) {
      return const SizedBox(height: 200, child: LoadingState());
    }
    final rarity = CosmeticRarity.parse(item.rarity);
    final tint = rarity.color(c);
    final name = cosmeticName(l10n, item.id);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: AppRadii.lgAll,
            gradient: RadialGradient(
              radius: 0.9,
              colors: [
                tint.withValues(alpha: c.isDark ? 0.32 : 0.22),
                Color.lerp(c.surfaceSunken, tint, 0.06)!,
              ],
            ),
            border: Border.all(color: tint.withValues(alpha: 0.35)),
          ),
          child: Center(
            child: CosmeticItemPreview(
              id: item.id,
              kind: item.kind,
              size: 160,
              animate: true,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(name, style: context.textTheme.headlineSmall),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _RarityChip(label: rarityName(l10n, item.rarity), color: tint),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          cosmeticKindName(l10n, item.kind),
          style: context.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          CollectionTexts.description(l10n, item),
          style: context.textTheme.bodyMedium?.copyWith(color: c.textPrimary),
        ),
        if (!item.canPurchase) ...[
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            icon: item.owned ? Icons.check_circle_rounded : Icons.lock_rounded,
            color: item.owned ? c.success : c.textSecondary,
            text: item.owned
                ? (item.equipped ? l10n.metaEquipped : l10n.metaOwned)
                : CollectionTexts.acquisition(l10n, locale, item),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        ..._actions(context, ref, item),
      ],
    );
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    CollectionItem item,
  ) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final ctl = ref.read(collectionProvider.notifier);

    if (item.owned && item.equippable) {
      if (item.equipped) {
        return [
          PremiumButton(
            label: l10n.metaEquipped,
            icon: Icons.check_rounded,
            size: PremiumButtonSize.medium,
            variant: PremiumButtonVariant.secondary,
            onPressed: null,
          ),
          if (!item.isStarter) ...[
            const SizedBox(height: AppSpacing.sm),
            PremiumButton(
              key: const ValueKey('equip-default'),
              label: l10n.metaEquipDefault,
              icon: Icons.restart_alt_rounded,
              size: PremiumButtonSize.medium,
              variant: PremiumButtonVariant.ghost,
              onPressed: () => _run(
                context,
                () => ctl.equipDefault(item.kind),
                success: l10n.metaDefaultEquippedToast,
              ),
            ),
          ],
        ];
      }
      return [
        PremiumButton(
          key: const ValueKey('equip'),
          label: l10n.metaEquip,
          icon: Icons.checkroom_rounded,
          size: PremiumButtonSize.medium,
          onPressed: () => _run(
            context,
            () => ctl.equip(item),
            success: l10n.metaEquippedToast,
          ),
        ),
      ];
    }
    if (item.owned) {
      return [
        MetaNote(
          icon: Icons.info_rounded,
          text: item.kind == 'emote' ? l10n.metaEmoteHint : l10n.metaBadgeHint,
        ),
      ];
    }
    final price = item.acquisition.price;
    if (item.canPurchase && price != null) {
      return [
        PremiumButton(
          key: const ValueKey('buy'),
          label: l10n.metaBuyFor(CollectionTexts.price(l10n, locale, price)),
          leading: price.inDiamonds
              ? const DiamondIcon(size: 20)
              : const CoinIcon(size: 20),
          variant: PremiumButtonVariant.gold,
          size: PremiumButtonSize.medium,
          sound: null,
          onPressed: () => _purchase(context, ref, item),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.metaCosmeticOnlyNote,
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall,
        ),
      ];
    }
    if (item.acquisition.type == AcquisitionType.level) {
      return [
        MetaNote(
          icon: Icons.trending_up_rounded,
          text: l10n.metaUnlocksAtLevel(item.acquisition.level ?? 1),
        ),
        const SizedBox(height: AppSpacing.sm),
        PremiumButton(
          label: l10n.metaLevelRoadTitle,
          icon: Icons.route_rounded,
          size: PremiumButtonSize.medium,
          variant: PremiumButtonVariant.ghost,
          onPressed: () {
            Navigator.of(context).pop();
            GoRouter.maybeOf(context)?.push(MetaRoutes.progression);
          },
        ),
      ];
    }
    return [
      MetaNote(icon: Icons.flag_rounded, text: l10n.metaEarnFromMissionsHint),
      const SizedBox(height: AppSpacing.sm),
      PremiumButton(
        label: l10n.metaGoToMissions,
        icon: Icons.flag_rounded,
        size: PremiumButtonSize.medium,
        variant: PremiumButtonVariant.ghost,
        onPressed: () {
          Navigator.of(context).pop();
          // Missions is a bottom-navigation tab.
          GoRouter.maybeOf(context)?.go(AppRoutes.missions);
        },
      ),
    ];
  }

  Future<void> _run(
    BuildContext context,
    Future<CollectionOutcome> Function() action, {
    required String success,
  }) async {
    final outcome = await action();
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case CollectionSucceeded():
        // Server-confirmed (e.g. equipped).
        playUiSound(context, Sfx.uiConfirm);
        AppToast.show(context, success, kind: ToastKind.success);
      case CollectionIgnored():
        break;
      case CollectionFailed(:final error):
        AppToast.show(
          context,
          metaErrorMessage(l10n, error, context: MetaErrorContext.item),
          kind: ToastKind.error,
        );
    }
  }

  Future<void> _purchase(
    BuildContext context,
    WidgetRef ref,
    CollectionItem item,
  ) async {
    final wallet = ref.read(walletControllerProvider).wallet;
    final confirmed = await PurchaseConfirmDialog.show(context, item, wallet);
    if (confirmed != true || !context.mounted) return;
    final outcome = await ref.read(collectionProvider.notifier).purchase(item);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case CollectionSucceeded():
        ref.read(audioServiceProvider).play(Sfx.purchase);
        ref.read(hapticsServiceProvider).success();
        AppToast.show(
          context,
          l10n.metaPurchaseSuccess(cosmeticName(l10n, item.id)),
          kind: ToastKind.success,
          icon: Icons.auto_awesome_rounded,
        );
      case CollectionIgnored():
        break;
      case CollectionFailed(:final error):
        AppToast.show(
          context,
          purchaseErrorMessage(l10n, error, item),
          kind: ToastKind.error,
        );
    }
  }
}

/// User-facing purchase failure text.
String purchaseErrorMessage(
  AppLocalizations l10n,
  ApiException error,
  CollectionItem item,
) {
  switch (error.code) {
    case 'insufficient_funds':
      final inDiamonds = item.acquisition.price?.inDiamonds ?? false;
      return inDiamonds ? l10n.metaNotEnoughDiamonds : l10n.metaNotEnoughCoins;
    case 'already_owned':
      return l10n.metaAlreadyOwned;
    case 'item_locked':
      return l10n.metaItemNotForSale;
  }
  final msg = metaErrorMessage(l10n, error, context: MetaErrorContext.item);
  return isTransientFailure(error) ? l10n.metaRetryHint(msg) : msg;
}

/// Purchase confirmation: price, current balance and balance after —
/// cosmetic only, fixed price, no randomness.
abstract final class PurchaseConfirmDialog {
  static Future<bool?> show(
    BuildContext context,
    CollectionItem item,
    Wallet? wallet,
  ) {
    final l10n = AppLocalizations.of(context);
    final price = item.acquisition.price ?? const Price();
    final affordable = price.affordableWith(wallet);
    return AppDialog.show<bool>(
      context,
      title: l10n.metaPurchaseTitle(cosmeticName(l10n, item.id)),
      content: _PurchaseSummary(item: item, price: price, wallet: wallet),
      actions: affordable
          ? [
              AppDialogAction(
                label: l10n.metaBuy,
                variant: PremiumButtonVariant.gold,
                value: true,
              ),
              AppDialogAction(
                label: l10n.commonCancel,
                variant: PremiumButtonVariant.ghost,
                value: false,
              ),
            ]
          : [
              AppDialogAction(
                label: l10n.commonOk,
                variant: PremiumButtonVariant.secondary,
                value: false,
              ),
            ],
    );
  }
}

class _PurchaseSummary extends StatelessWidget {
  const _PurchaseSummary({
    required this.item,
    required this.price,
    required this.wallet,
  });

  final CollectionItem item;
  final Price price;
  final Wallet? wallet;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    String amount(int v) => price.inDiamonds
        ? l10n.metaPriceDiamonds(formatNumberFull(v, locale))
        : l10n.metaPriceCoins(formatCoins(v, locale));
    final have = price.inDiamonds ? wallet?.diamonds : wallet?.coins;
    final affordable = price.affordableWith(wallet);

    Widget row(String label, String value, {Color? color, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: context.textTheme.bodyMedium)),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style:
                      (bold
                              ? context.textTheme.titleSmall
                              : context.textTheme.bodyMedium)
                          ?.copyWith(color: color ?? c.textPrimary),
                ),
              ),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: CosmeticItemPreview(id: item.id, kind: item.kind, size: 88),
        ),
        const SizedBox(height: AppSpacing.md),
        row(l10n.metaPrice, amount(price.amount), bold: true),
        if (have != null) ...[
          row(l10n.metaYourBalance, amount(have)),
          if (affordable)
            row(l10n.metaBalanceAfter, amount(have - price.amount)),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (!affordable)
          MetaNote(
            icon: Icons.info_rounded,
            text: l10n.metaNeedMore(amount(price.shortfall(wallet))),
          )
        else
          MetaNote(
            icon: Icons.verified_rounded,
            text: l10n.metaCosmeticOnlyNote,
          ),
      ],
    );
  }
}

class _RarityChip extends StatelessWidget {
  const _RarityChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: AppRadii.pillAll,
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Text(
      label,
      style: context.textTheme.labelMedium?.copyWith(color: color),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          text,
          style: context.textTheme.labelLarge?.copyWith(color: color),
        ),
      ),
    ],
  );
}
