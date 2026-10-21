import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/analytics/analytics_providers.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../../../core/audio_haptics/audio_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../authentication/application/session_controller.dart';
import '../../../profile/progression.dart';
import '../../../wallet/presentation/wallet_sheet.dart';
import '../../../wallet/wallet_controller.dart';

/// Home header: avatar + frame, name, level + title, XP, balances, Save
/// Progress (guests), theme shortcut, settings, connection status.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(sessionControllerProvider.select((s) => s.user));
    final progression = ref.watch(progressionSummaryProvider);
    final wallet = ref.watch(walletControllerProvider);
    if (user == null) return const SizedBox.shrink();

    final brightness = Theme.of(context).brightness;

    return GlassCard(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: l10n.homeProfileTooltip,
                child: GestureDetector(
                  onTap: () {
                    playUiSound(context, Sfx.uiTap);
                    context.push(AppRoutes.profile);
                  },
                  child: PlayerAvatar(
                    avatarIndex: user.avatar,
                    frameId: user.loadout.frame,
                    size: 58,
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
                      style: context.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        LevelBadge(
                          level: progression?.level ?? user.level,
                          size: 26,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: TitleChip(
                            titleId: progression?.title ?? user.title,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (user.needsSaveProgress) ...[
                IconCircleButton(
                  icon: Icons.cloud_upload_rounded,
                  tooltip: l10n.homeSaveProgressTooltip,
                  highlighted: true,
                  size: 40,
                  onPressed: () => context.push(AppRoutes.linkAccount),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              IconCircleButton(
                icon: Icons.settings_rounded,
                tooltip: l10n.homeSettingsTooltip,
                size: 40,
                onPressed: () => context.push(AppRoutes.settings),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (progression != null)
            XpProgressBar(
              current: progression.isMaxLevel
                  ? progression.nextLevelXp
                  : progression.xpIntoLevel,
              total: progression.nextLevelXp <= 0 ? 1 : progression.nextLevelXp,
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              // Chips keep their natural width and wrap on narrow phones.
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    BalanceChip(
                      kind: BalanceKind.coins,
                      value: wallet.coins,
                      onTap: () => WalletSheet.show(context),
                    ),
                    BalanceChip(
                      kind: BalanceKind.diamonds,
                      value: wallet.diamonds,
                      onTap: () => WalletSheet.show(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
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
              const SizedBox(width: AppSpacing.xs),
              ConnectionIndicator(
                compact: true,
                onReconnect: () =>
                    ref.read(realtimeConnectionProvider).reconnectNow(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
