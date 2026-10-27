import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../../../core/analytics/analytics_providers.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../missions/application/missions_controller.dart';
import '../../missions/domain/mission_texts.dart';
import '../../profile/progression.dart';
import '../application/next_goal.dart';
import '../application/playtime_controller.dart';
import 'widgets/playtime_visuals.dart';

/// One achievable next objective after a match ([pickNextGoal] over server
/// data: today's playtime, the missions board and the level). Renders
/// nothing when no goal applies. [onOpen] receives the location to open
/// (the Missions tab); the caller leaves the finished room first.
class NextGoalRow extends ConsumerStatefulWidget {
  const NextGoalRow({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  ConsumerState<NextGoalRow> createState() => _NextGoalRowState();
}

class _NextGoalRowState extends ConsumerState<NextGoalRow> {
  NextGoalKind? _logged;

  String _text(AppLocalizations l10n, Locale locale, NextGoal g) =>
      switch (g.kind) {
        NextGoalKind.playtime => l10n.journeyGoalPlaytime(
          g.remaining,
          formatNumberFull(g.remaining, locale),
          playtimeRewardText(l10n, locale, g.milestone!.reward),
        ),
        NextGoalKind.mission => l10n.journeyGoalMission(
          formatNumberFull(g.remaining, locale),
          MissionTexts.title(l10n, g.mission!),
        ),
        NextGoalKind.claim => l10n.journeyGoalClaim(
          MissionTexts.title(l10n, g.mission!),
        ),
        NextGoalKind.level => l10n.journeyGoalLevel(
          formatNumberFull(g.remaining, locale),
          formatNumberFull(g.level, locale),
        ),
      };

  @override
  Widget build(BuildContext context) {
    final goal = pickNextGoal(
      playtime: ref.watch(playtimeControllerProvider).playtime,
      board: ref.watch(missionsProvider).value,
      progression: ref.watch(progressionSummaryProvider),
    );
    if (goal == null) return const SizedBox.shrink();
    if (_logged != goal.kind) {
      _logged = goal.kind;
      ref.read(analyticsServiceProvider).nextGoalShown(goal.kind.param);
    }
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final text = _text(l10n, Localizations.localeOf(context), goal);
    final icon = switch (goal.kind) {
      NextGoalKind.playtime => Icons.timer_rounded,
      NextGoalKind.mission => Icons.flag_rounded,
      NextGoalKind.claim => Icons.redeem_rounded,
      NextGoalKind.level => Icons.trending_up_rounded,
    };
    return Semantics(
      container: true,
      label: '${l10n.journeyNextGoalTitle}: $text',
      child: Container(
        key: ValueKey('next-goal-${goal.kind.param}'),
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: c.brand.withValues(alpha: c.isDark ? 0.14 : 0.07),
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: c.brand.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(icon, size: 22, color: c.brand)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.journeyNextGoalTitle,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: c.brand,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('next-goal-open'),
              onPressed: () {
                ref
                    .read(analyticsServiceProvider)
                    .nextGoalTapped(goal.kind.param);
                widget.onOpen(AppRoutes.missions);
              },
              style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
              child: Text(l10n.metaView),
            ),
          ],
        ),
      ),
    );
  }
}
