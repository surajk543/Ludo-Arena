import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/analytics/analytics_providers.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/server_clock.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../missions/application/missions_controller.dart';
import '../application/playtime_controller.dart';
import 'widgets/playtime_visuals.dart';

/// The lobby's Daily Play Journey: today's server-counted playtime with its
/// three milestones, the next reward, and the daily missions count. Taps
/// open the Missions tab (full progress). Hidden while daily playtime is
/// disabled on the server or nobody is signed in.
class DailyJourneyCard extends ConsumerStatefulWidget {
  const DailyJourneyCard({super.key});

  @override
  ConsumerState<DailyJourneyCard> createState() => _DailyJourneyCardState();
}

class _DailyJourneyCardState extends ConsumerState<DailyJourneyCard> {
  bool _viewLogged = false;
  bool _visible = true;
  Timer? _rollover;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A tab switch back to Home counts as a new visit.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) _viewLogged = false;
    _visible = visible;
  }

  @override
  void initState() {
    super.initState();
    // Calm day-rollover check (no per-second rebuilds).
    _rollover = Timer.periodic(const Duration(seconds: 30), (_) {
      final p = ref.read(playtimeControllerProvider).playtime;
      final reset = p?.resetsAtUtc;
      if (reset == null) return;
      final clock = ref.read(serverClockProvider);
      if (clock.nowMs() >= reset.millisecondsSinceEpoch) {
        unawaited(ref.read(playtimeControllerProvider.notifier).refresh());
      }
    });
  }

  @override
  void dispose() {
    _rollover?.cancel();
    super.dispose();
  }

  void _open() => context.go(AppRoutes.missions);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playtimeControllerProvider);
    final p = state.playtime;
    if (state.disabled) return const SizedBox.shrink();
    if (p == null) {
      if (state.loading) return const _JourneySkeleton();
      if (state.failed) {
        return _JourneyFailed(
          onRetry: () => unawaited(
            ref.read(playtimeControllerProvider.notifier).refresh(),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    if (p.milestones.isEmpty) return const SizedBox.shrink();
    if (!_viewLogged && _visible) {
      _viewLogged = true;
      ref.read(analyticsServiceProvider).playtimeProgressViewed('home');
    }
    // The daily missions count rides along when the board is loaded.
    final board = ref.watch(missionsProvider).value;
    return _JourneyContent(
      playtime: p,
      stale: state.failed,
      missionsDone: board?.dailyCompletedCount,
      missionsTotal: board?.daily.missions.length ?? 0,
      onTap: _open,
    );
  }
}

class _JourneyContent extends StatelessWidget {
  const _JourneyContent({
    required this.playtime,
    required this.stale,
    required this.missionsDone,
    required this.missionsTotal,
    required this.onTap,
  });

  final Playtime playtime;
  final bool stale;
  final int? missionsDone;
  final int missionsTotal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final p = playtime;
    final minutes = formatNumberFull(p.minutes, locale);
    final goal = formatNumberFull(p.goalMinutes, locale);
    final nextText = playtimeNextRewardText(l10n, locale, p);
    final done = p.allCompleted;
    return Semantics(
      container: true,
      button: true,
      label:
          '${l10n.journeyCardTitle}. ${l10n.journeySemantics(minutes, goal)} '
          '$nextText',
      excludeSemantics: true,
      child: SurfaceCard(
        key: const ValueKey('daily-journey-card'),
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        border: done
            ? Border.all(color: c.gold.withValues(alpha: 0.7), width: 1.2)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                PlaytimeRing(playtime: p, size: 60),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.journeyCardTitle.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.labelMedium?.copyWith(
                                color: c.goldStrong,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (stale)
                            Tooltip(
                              message: l10n.journeyStale,
                              child: Icon(
                                Icons.cloud_off_rounded,
                                size: 16,
                                color: c.textMuted,
                              ),
                            ),
                          Icon(
                            Directionality.of(context) == TextDirection.rtl
                                ? Icons.chevron_left_rounded
                                : Icons.chevron_right_rounded,
                            color: c.textMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${l10n.journeyTodayPlaytime}  '),
                            TextSpan(
                              text: l10n.journeyMinutesOfGoal(minutes, goal),
                              style: TextStyle(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            PlaytimeMilestoneTrack(playtime: p),
            const SizedBox(height: AppSpacing.xs),
            _InfoLine(
              icon: done ? Icons.emoji_events_rounded : Icons.redeem_rounded,
              color: done ? c.goldStrong : c.brand,
              text: nextText,
              strong: true,
            ),
            if (missionsDone != null && missionsTotal > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              _InfoLine(
                icon: Icons.flag_rounded,
                color: c.accentCoral,
                text: l10n.journeyMissionsCount(
                  formatNumberFull(missionsDone!, locale),
                  formatNumberFull(missionsTotal, locale),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.color,
    required this.text,
    this.strong = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.xs + 2),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                (strong
                        ? context.textTheme.labelLarge
                        : context.textTheme.bodySmall)
                    ?.copyWith(color: strong ? c.textPrimary : c.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Compact placeholder while the first value loads (no layout jump: about
/// the card's height).
class _JourneySkeleton extends StatelessWidget {
  const _JourneySkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: AppRadii.pillAll,
      ),
    );
    return ExcludeSemantics(
      child: SurfaceCard(
        key: const ValueKey('daily-journey-loading'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.surfaceSunken,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(120, 10),
                  const SizedBox(height: AppSpacing.sm),
                  bar(double.infinity, 8),
                  const SizedBox(height: AppSpacing.sm),
                  bar(160, 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyFailed extends StatelessWidget {
  const _JourneyFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return SurfaceCard(
      key: const ValueKey('daily-journey-failed'),
      onTap: onRetry,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: c.textMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              l10n.journeyLoadFailed,
              style: context.textTheme.bodySmall,
            ),
          ),
          Icon(Icons.refresh_rounded, color: c.textMuted),
        ],
      ),
    );
  }
}
