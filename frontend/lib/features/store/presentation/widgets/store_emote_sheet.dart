import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/audio_haptics/audio_service.dart';
import '../../../../core/audio_haptics/haptics_service.dart';
import '../../../../core/localization/number_format.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../meta_routes.dart';
import '../../../progression/presentation/widgets/meta_scaffold.dart';
import '../../../wallet/wallet_controller.dart';
import '../../application/emote_shelf_controller.dart';
import '../../application/shop_category.dart';
import '../../application/store_controller.dart';
import '../../domain/store_models.dart';
import 'store_emote_tile.dart';
import 'store_picture_sheet.dart' show storeErrorMessage;

/// Opens the emote sheet: large animated preview, price and balance, Buy
/// (Shop) or Owned with how to send it in a match. [shelf] is the shelf the
/// emote was tapped on (default: the Shop).
Future<void> showStoreEmoteSheet(
  BuildContext context,
  ShopEmote item, {
  EmoteShelfProvider? shelf,
}) => AppBottomSheet.show<void>(
  context,
  builder: (_) => StoreEmoteSheet(initial: item, shelf: shelf),
);

class StoreEmoteSheet extends ConsumerStatefulWidget {
  const StoreEmoteSheet({super.key, required this.initial, this.shelf});

  /// The emote as tapped; live updates come from [shelf].
  final ShopEmote initial;

  /// Default: the Shop ([shopEmotesProvider]).
  final EmoteShelfProvider? shelf;

  @override
  ConsumerState<StoreEmoteSheet> createState() => _StoreEmoteSheetState();
}

class _StoreEmoteSheetState extends ConsumerState<StoreEmoteSheet> {
  /// Bought (or found already owned) in this sheet. It has left the Shop's
  /// shelf, so the sheet keeps showing it: View in Collection.
  ShopEmote? _bought;

  EmoteShelfProvider get _shelf => widget.shelf ?? shopEmotesProvider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(_shelf.select((s) => s.byId(widget.initial.id)));
    final item = _bought ?? live ?? widget.initial;
    final wallet = ref.watch(walletControllerProvider.select((w) => w.wallet));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 176,
          decoration: BoxDecoration(
            borderRadius: AppRadii.lgAll,
            gradient: RadialGradient(
              radius: 0.9,
              colors: [
                c.gold.withValues(alpha: c.isDark ? 0.26 : 0.18),
                Color.lerp(c.surfaceSunken, c.gold, 0.05)!,
              ],
            ),
            border: Border.all(color: c.gold.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Semantics(
              image: true,
              label: l10n.widgetsEmoteLabel(item.name),
              child: StoreEmotePreview(item: item, size: 140),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(item.name, style: context.textTheme.headlineSmall),
        ),
        const SizedBox(height: 2),
        Text(l10n.storeEmoteKind, style: context.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        if (item.owned)
          _InfoRow(
            icon: Icons.verified_rounded,
            color: c.success,
            text: l10n.metaOwned,
          )
        else ...[
          _ValueRow(
            label: l10n.metaPrice,
            diamonds: item.priceDiamonds,
            bold: true,
          ),
          if (wallet != null)
            _ValueRow(label: l10n.metaYourBalance, diamonds: wallet.diamonds),
        ],
        const SizedBox(height: AppSpacing.xl),
        ..._actions(context, item, wallet),
      ],
    );
  }

  List<Widget> _actions(BuildContext context, ShopEmote item, Wallet? wallet) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    String diamonds(int n) =>
        l10n.metaPriceDiamonds(formatNumberFull(n, locale));

    if (!item.owned) {
      final affordable = item.affordableWith(wallet);
      return [
        PremiumButton(
          key: const ValueKey('store-emote-buy'),
          label: l10n.metaBuyFor(diamonds(item.priceDiamonds)),
          leading: const DiamondIcon(size: 20),
          variant: PremiumButtonVariant.gold,
          size: PremiumButtonSize.medium,
          // The purchase cue plays once the server confirms.
          sound: null,
          onPressed: affordable ? () => _purchase(item) : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (affordable)
          Text(
            l10n.metaCosmeticOnlyNote,
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall,
          )
        else
          MetaNote(
            key: const ValueKey('store-emote-need-more'),
            icon: Icons.info_rounded,
            text: l10n.metaNeedMore(diamonds(item.shortfall(wallet))),
          ),
      ];
    }
    return [
      MetaNote(
        key: const ValueKey('store-emote-use-note'),
        icon: Icons.chat_bubble_rounded,
        text: l10n.storeEmoteUseInMatchNote,
      ),
      // Just bought in the Shop: it now lives in the Collection.
      if (_bought != null) ...[
        const SizedBox(height: AppSpacing.md),
        PremiumButton(
          key: const ValueKey('store-emote-view-in-collection'),
          label: l10n.storeViewInCollection,
          icon: Icons.diamond_rounded,
          size: PremiumButtonSize.medium,
          variant: PremiumButtonVariant.secondary,
          onPressed: _openCollection,
        ),
      ],
    ];
  }

  /// Closes the sheet and opens the Collection's Emotes tab.
  void _openCollection() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    router?.push(MetaRoutes.collectionFor(kind: kShopEmoteCategory));
  }

  Future<void> _purchase(ShopEmote item) async {
    final outcome = await ref.read(_shelf.notifier).purchase(item);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case StoreSucceeded():
        setState(() => _bought = item.copyWith(owned: true));
        ref.read(audioServiceProvider).play(Sfx.purchase);
        ref.read(hapticsServiceProvider).success();
        AppToast.show(
          context,
          l10n.storePurchasedToast(item.name),
          kind: ToastKind.success,
          icon: Icons.auto_awesome_rounded,
        );
      case StoreIgnored():
        break;
      case StoreFailed(:final error):
        if (error.code == 'already_owned') {
          setState(() => _bought = item.copyWith(owned: true));
        }
        AppToast.show(
          context,
          storeErrorMessage(l10n, error),
          kind: ToastKind.error,
        );
    }
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.diamonds,
    this.bold = false,
  });

  final String label;
  final int diamonds;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.textTheme.bodyMedium)),
          const SizedBox(width: AppSpacing.sm),
          const DiamondIcon(size: 16),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              l10n.metaPriceDiamonds(formatNumberFull(diamonds, locale)),
              textAlign: TextAlign.end,
              style:
                  (bold
                          ? context.textTheme.titleSmall
                          : context.textTheme.bodyMedium)
                      ?.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
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
