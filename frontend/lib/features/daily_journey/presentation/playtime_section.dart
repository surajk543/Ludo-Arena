import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../missions/presentation/widgets/reset_label.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../../progression/presentation/widgets/reward_widgets.dart';
import '../application/playtime_controller.dart';
import 'widgets/playtime_visuals.dart';

/// "Today's playtime" on the Missions screen: progress, the reset time and
/// every milestone with its reward, status and remaining minutes. Renders
/// nothing while daily playtime is disabled or before the first value.
class PlaytimeSection extends ConsumerStatefulWidget {
  const PlaytimeSection({super.key});

  @override
  ConsumerState<PlaytimeSection> createState() => _PlaytimeSectionState();
}

class _PlaytimeSectionState extends ConsumerState<PlaytimeSection> {
  bool _viewLogged = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playtimeControllerProvider);
    final p = state.playtime;
    if (state.disabled || p == null || p.milestones.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!_viewLogged) {
      _viewLogged = true;
      ref.read(analyticsServiceProvider).playtimeProgressViewed('missions');
    }
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final c = context.colors;
    final minutes = formatNumberFull(p.minutes, locale);
    final goal = formatNumberFull(p.goalMinutes, locale);
    return Column(
      key: const ValueKey('playtime-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.journeyTodayPlaytime,
          trailing: state.failed
              ? Tooltip(
                  message: l10n.journeyStale,
                  child: Icon(
                    Icons.cloud_off_rounded,
                    size: 18,
                    color: c.textMuted,
                  ),
                )
              : null,
        ),
        if (p.resetsAtUtc != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: PeriodResetLabel(
              resetsAtUtc: p.resetsAtUtc!,
              kind: ResetKind.daily,
              onElapsed: () => unawaited(
                ref.read(playtimeControllerProvider.notifier).refresh(),
              ),
            ),
          ),
        SurfaceCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          border: p.allCompleted
              ? Border.all(color: c.gold.withValues(alpha: 0.7), width: 1.2)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                label: l10n.journeySemantics(minutes, goal),
                excludeSemantics: true,
                child: Row(
                  children: [
                    PlaytimeRing(playtime: p, size: 76),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.journeyMinutesOfGoal(minutes, goal),
                            style: context.textTheme.headlineSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            playtimeNextRewardText(l10n, locale, p),
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final m in p.milestones)
                _MilestoneRow(
                  key: ValueKey('playtime-milestone-${m.id}'),
                  playtime: p,
                  milestone: m,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        MetaNote(text: l10n.journeyRulesNote, icon: Icons.timer_rounded),
      ],
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    super.key,
    required this.playtime,
    required this.milestone,
  });

  final Playtime playtime;
  final PlaytimeMilestone milestone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final m = milestone;
    final status = playtimeStatusText(l10n, locale, playtime, m);
    final minutes = formatNumberFull(m.minutes, locale);
    final reward = playtimeRewardText(l10n, locale, m.reward);
    final done = m.completed;
    final current = m.status == PlaytimeMilestoneStatus.inProgress;
    return Semantics(
      container: true,
      label: l10n.journeyMilestoneSemantics(minutes, status, reward),
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: AppRadii.mdAll,
          color: current
              ? c.brand.withValues(alpha: c.isDark ? 0.14 : 0.07)
              : done
              ? c.gold.withValues(alpha: c.isDark ? 0.12 : 0.08)
              : c.surfaceSunken.withValues(alpha: 0.6),
          border: Border.all(
            color: current
                ? c.brand.withValues(alpha: 0.45)
                : done
                ? c.gold.withValues(alpha: 0.45)
                : c.outline.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            PlaytimeMilestoneMarker(status: m.status, size: 32),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.journeyMinutes(minutes),
                        style: context.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.labelMedium?.copyWith(
                            color: done
                                ? c.success
                                : current
                                ? c.brand
                                : c.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  RewardChips(
                    coins: m.reward.coins,
                    diamonds: m.reward.diamonds,
                    xp: m.reward.xp,
                    muted: done,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
