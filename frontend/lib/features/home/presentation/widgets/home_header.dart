import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/analytics/analytics_providers.dart';
import '../../../../core/audio_haptics/audio_service.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../core/network/api_models.dart';
import '../../../authentication/application/session_controller.dart';
import '../../../profile/progression.dart';
import '../../../wallet/presentation/wallet_sheet.dart';
import '../../../wallet/wallet_controller.dart';
import 'no_ads_ribbon.dart';

/// Compact lobby header: avatar + frame, name, level badge, title and a slim
/// XP bar, then coin / diamond balances, connection status and the theme
/// shortcut. Guests also get the Save Progress shortcut. A decorative
/// "No Ads" ribbon sits on the card's top-end corner, above the actions.
///
/// Balances are separate widgets that `select` their own value, so wallet
/// updates never rebuild the rest of the header.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final user = ref.watch(sessionControllerProvider.select((s) => s.user));
    if (user == null) return const SizedBox.shrink();
    final progression = ref.watch(progressionSummaryProvider);
    final level = progression?.level ?? user.level;
    final title = progression?.title ?? user.title;

    return SurfaceCard(
      padding: _padding,
      borderRadius: AppRadii.xlAll,
      elevation: c.isDark ? AppElevation.flat : AppElevation.low,
      border: Border.all(color: c.cardBorder),
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          // In the card's top-end corner, just inside its 1 dp border (the
          // card's Ink adds the border width to the padding). Painted and
          // read before the controls, so it can never sit on top of them.
          PositionedDirectional(
            top: -_padding.top,
            end: -_padding.end,
            child: const NoAdsRibbon(cornerRadius: AppRadii.xl - 1),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              // Narrow phone or large text: smaller avatar, more room for
              // text.
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final compact = constraints.maxWidth < 330 * scale;
              return _layout(
                context,
                l10n,
                user,
                progression,
                level,
                title,
                compact,
              );
            },
          ),
        ],
      ),
    );
  }

  static const _padding = EdgeInsetsDirectional.fromSTEB(
    AppSpacing.md,
    AppSpacing.md,
    AppSpacing.sm,
    AppSpacing.md,
  );

  /// Lowers Save Progress / Settings below the [NoAdsRibbon]: with at least
  /// this much space above their 48 dp boxes, the 40 dp circles stay ≥ 4 dp
  /// clear of the band whatever the row height (text scale, locale).
  static const double _actionsTopInset = 20;

  Widget _layout(
    BuildContext context,
    AppLocalizations l10n,
    User user,
    ProgressionSummary? progression,
    int level,
    String title,
    bool compact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: l10n.homeProfileTooltip,
              excludeSemantics: true,
              child: InkWell(
                customBorder: const CircleBorder(),
                // Profile is a bottom-navigation tab: switch to it.
                onTap: () {
                  playUiSound(context, Sfx.uiTap);
                  context.go(AppRoutes.profile);
                },
                child: PlayerAvatar(
                  avatarIndex: user.avatar,
                  picture: user.picture,
                  frameId: user.loadout.frame,
                  size: compact ? 44 : 54,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Wraps under the badge on narrow phones / large text
                  // instead of truncating the title.
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      LevelBadge(level: level, size: 24),
                      TitleChip(titleId: title),
                    ],
                  ),
                  if (progression != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    XpProgressBar(
                      current: progression.isMaxLevel
                          ? progression.nextLevelXp
                          : progression.xpIntoLevel,
                      total: progression.nextLevelXp <= 0
                          ? 1
                          : progression.nextLevelXp,
                      showLabel: false,
                      height: 6,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(top: _actionsTopInset),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (user.needsSaveProgress)
                    IconCircleButton(
                      icon: Icons.cloud_upload_rounded,
                      tooltip: l10n.homeSaveProgressTooltip,
                      highlighted: true,
                      size: 40,
                      onPressed: () => context.push(AppRoutes.linkAccount),
                    ),
                  IconCircleButton(
                    icon: Icons.settings_rounded,
                    tooltip: l10n.homeSettingsTooltip,
                    size: 40,
                    onPressed: () => context.push(AppRoutes.settings),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const _StatusRow(),
      ],
    );
  }
}

/// Balances (wrap on narrow phones), live connection status and the
/// light/dark shortcut.
class _StatusRow extends ConsumerWidget {
  const _StatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The status label needs ~90 dp; below that only the dot shows (the
        // label stays available as tooltip and to screen readers).
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final roomy = constraints.maxWidth >= 300 * scale;
        return Row(
          children: [
            const Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [_CoinsChip(), _DiamondsChip()],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            ConnectionIndicator(
              compact: !roomy,
              onReconnect: () =>
                  ref.read(realtimeConnectionProvider).reconnectNow(),
            ),
            IconCircleButton(
              icon: brightness == Brightness.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              tooltip: l10n.homeThemeTooltip,
              size: 36,
              onPressed: () {
                final next = brightness == Brightness.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
                ref.read(themeModeControllerProvider.notifier).setMode(next);
                ref.read(analyticsServiceProvider).themeChanged(next.name);
              },
            ),
          ],
        );
      },
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
