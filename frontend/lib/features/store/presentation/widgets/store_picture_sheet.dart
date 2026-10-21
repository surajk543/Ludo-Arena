import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio_haptics/audio_service.dart';
import '../../../../core/audio_haptics/haptics_service.dart';
import '../../../../core/localization/number_format.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../authentication/application/session_controller.dart';
import '../../../progression/application/meta_support.dart';
import '../../../progression/presentation/widgets/meta_scaffold.dart';
import '../../../wallet/wallet_controller.dart';
import '../../application/store_controller.dart';
import '../../domain/store_models.dart';

/// Opens the picture sheet: large preview (in the player's frame), price
/// and balance, Buy → Apply, or Apply / back to the classic avatar.
Future<void> showStorePictureSheet(BuildContext context, ProfilePicture item) =>
    AppBottomSheet.show<void>(
      context,
      builder: (_) => StorePictureSheet(initial: item),
    );

class StorePictureSheet extends ConsumerWidget {
  const StorePictureSheet({super.key, required this.initial});

  /// The item as tapped; live updates come from the Store state.
  final ProfilePicture initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final item =
        ref.watch(storeProvider.select((s) => s.byId(initial.id))) ?? initial;
    final wallet = ref.watch(walletControllerProvider.select((w) => w.wallet));
    final user = ref.watch(sessionControllerProvider.select((s) => s.user));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 196,
          decoration: BoxDecoration(
            borderRadius: AppRadii.lgAll,
            gradient: RadialGradient(
              radius: 0.9,
              colors: [
                c.brand.withValues(alpha: c.isDark ? 0.30 : 0.18),
                Color.lerp(c.surfaceSunken, c.brand, 0.05)!,
              ],
            ),
            border: Border.all(color: c.brand.withValues(alpha: 0.25)),
          ),
          child: Center(
            child: PlayerAvatar(
              avatarIndex: user?.avatar ?? 0,
              picture: item.picture,
              frameId: user?.loadout.frame ?? 'frame_none',
              size: 156,
              semanticLabel: item.name,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(item.name, style: context.textTheme.headlineSmall),
        ),
        const SizedBox(height: 2),
        Text(
          item.isAnimated ? l10n.storeKindAnimated : l10n.storeKindStatic,
          style: context.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        if (item.owned)
          _InfoRow(
            icon: item.equipped
                ? Icons.check_circle_rounded
                : Icons.verified_rounded,
            color: item.equipped ? c.brand : c.success,
            text: item.equipped ? l10n.metaEquipped : l10n.metaOwned,
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
        ..._actions(context, ref, item, wallet),
      ],
    );
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    ProfilePicture item,
    Wallet? wallet,
  ) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    String diamonds(int n) =>
        l10n.metaPriceDiamonds(formatNumberFull(n, locale));

    if (!item.owned) {
      final affordable = item.affordableWith(wallet);
      return [
        PremiumButton(
          key: const ValueKey('store-buy'),
          label: l10n.metaBuyFor(diamonds(item.priceDiamonds)),
          leading: const DiamondIcon(size: 20),
          variant: PremiumButtonVariant.gold,
          size: PremiumButtonSize.medium,
          // The purchase cue plays once the server confirms.
          sound: null,
          onPressed: affordable ? () => _purchase(context, ref, item) : null,
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
            key: const ValueKey('store-need-more'),
            icon: Icons.info_rounded,
            text: l10n.metaNeedMore(diamonds(item.shortfall(wallet))),
          ),
      ];
    }
    if (!item.equipped) {
      return [
        PremiumButton(
          key: const ValueKey('store-apply'),
          label: l10n.storeApply,
          icon: Icons.face_retouching_natural,
          size: PremiumButtonSize.medium,
          onPressed: () => _apply(context, ref, item),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.storeNextMatchNote,
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall,
        ),
      ];
    }
    return [
      PremiumButton(
        label: l10n.metaEquipped,
        icon: Icons.check_rounded,
        size: PremiumButtonSize.medium,
        variant: PremiumButtonVariant.secondary,
        onPressed: null,
      ),
      const SizedBox(height: AppSpacing.sm),
      PremiumButton(
        key: const ValueKey('store-remove'),
        label: l10n.storeRemove,
        icon: Icons.restart_alt_rounded,
        size: PremiumButtonSize.medium,
        variant: PremiumButtonVariant.ghost,
        onPressed: () => _apply(context, ref, null),
      ),
    ];
  }

  Future<void> _purchase(
    BuildContext context,
    WidgetRef ref,
    ProfilePicture item,
  ) async {
    final outcome = await ref.read(storeProvider.notifier).purchase(item);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case StoreSucceeded():
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
        AppToast.show(
          context,
          storeErrorMessage(l10n, error),
          kind: ToastKind.error,
        );
    }
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    ProfilePicture? item,
  ) async {
    final outcome = await ref.read(storeProvider.notifier).apply(item);
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case StoreSucceeded():
        // Server-confirmed.
        playUiSound(context, Sfx.uiConfirm);
        AppToast.show(
          context,
          item == null ? l10n.storeRemovedToast : l10n.storeAppliedToast,
          kind: ToastKind.success,
        );
      case StoreIgnored():
        break;
      case StoreFailed(:final error):
        AppToast.show(
          context,
          storeErrorMessage(l10n, error),
          kind: ToastKind.error,
        );
    }
  }
}

/// User-facing text for a failed Store action.
String storeErrorMessage(AppLocalizations l10n, ApiException error) {
  switch (error.code) {
    case 'insufficient_funds':
      return l10n.metaNotEnoughDiamonds;
    case 'already_owned':
      return l10n.metaAlreadyOwned;
  }
  final msg = metaErrorMessage(l10n, error, context: MetaErrorContext.item);
  return isTransientFailure(error) ? l10n.metaRetryHint(msg) : msg;
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
