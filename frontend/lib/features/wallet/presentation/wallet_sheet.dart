import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../wallet_controller.dart';

/// Balance details: server-confirmed coins and diamonds, what they're for,
/// and the "virtual, non-redeemable" notice.
abstract final class WalletSheet {
  static Future<void> show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBottomSheet.show<void>(
      context,
      title: l10n.walletTitle,
      builder: (_) => const _WalletBody(),
    );
  }
}

class _WalletBody extends ConsumerWidget {
  const _WalletBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final c = context.colors;
    final wallet = ref.watch(walletControllerProvider);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BalanceRow(
            icon: const CoinIcon(size: 40),
            title: l10n.commonCoins,
            value: formatCoins(wallet.coins, locale),
            exact: l10n.walletExactBalance(
              formatNumberFull(wallet.coins, locale),
            ),
            caption: l10n.walletCoinsCaption,
            tint: c.gold,
          ),
          const SizedBox(height: AppSpacing.md),
          _BalanceRow(
            icon: const DiamondIcon(size: 40),
            title: l10n.commonDiamonds,
            value: formatCoins(wallet.diamonds, locale),
            exact: l10n.walletExactBalance(
              formatNumberFull(wallet.diamonds, locale),
            ),
            caption: l10n.walletDiamondsCaption,
            tint: c.diamond,
          ),
          const SizedBox(height: AppSpacing.lg),
          SurfaceCard(
            color: c.surfaceSunken,
            elevation: AppElevation.flat,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_rounded, color: c.brand, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.walletVirtualTitle,
                        style: context.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.walletVirtualNotice,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.walletEarnTitle, style: context.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _Tip(icon: Icons.emoji_events_rounded, text: l10n.walletEarnWins),
          _Tip(icon: Icons.flag_rounded, text: l10n.walletEarnMissions),
          _Tip(icon: Icons.military_tech_rounded, text: l10n.walletEarnLevels),
          const SizedBox(height: AppSpacing.lg),
          PremiumButton(
            label: l10n.walletRefresh,
            icon: Icons.refresh_rounded,
            variant: PremiumButtonVariant.secondary,
            onPressed: () async {
              try {
                await ref.read(walletControllerProvider.notifier).refresh();
              } on ApiException catch (e) {
                if (context.mounted) {
                  AppToast.show(
                    context,
                    localizedErrorMessage(l10n, e.code),
                    kind: ToastKind.error,
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.exact,
    required this.caption,
    required this.tint,
  });

  final Widget icon;
  final String title;
  final String value;
  final String exact;
  final String caption;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SurfaceCard(
      border: Border.all(color: tint.withValues(alpha: 0.35)),
      child: Row(
        children: [
          icon,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.textTheme.labelMedium?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
                Text(value, style: context.textTheme.headlineSmall),
                Text(exact, style: context.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  caption,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.gold),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: context.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
