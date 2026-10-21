import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../profile/progression.dart' show LevelMath;
import '../application/meta_support.dart';
import '../application/progression_controller.dart';
import '../domain/progression_models.dart';
import 'level_up_celebration_host.dart';
import 'widgets/level_header_card.dart';
import 'widgets/meta_scaffold.dart';
import 'widgets/reward_widgets.dart';

/// The level road: current level/XP, how XP is earned, and every level
/// milestone with its rewards and reached state (`GET /progression`).
class ProgressionScreen extends ConsumerWidget {
  const ProgressionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(progressionViewProvider);

    Future<void> refresh() async {
      try {
        await ref.read(progressionViewProvider.notifier).refresh();
      } catch (e) {
        if (context.mounted) {
          AppToast.show(
            context,
            metaErrorMessage(l10n, e),
            kind: ToastKind.error,
          );
        }
      }
    }

    final List<Widget> slivers;
    switch (async) {
      case AsyncValue(:final value?):
        slivers = _content(context, value);
      case AsyncError(:final error):
        slivers = [
          MetaErrorSliver(
            message: metaErrorMessage(l10n, error),
            onRetry: () => ref.invalidate(progressionViewProvider),
          ),
        ];
      default:
        slivers = const [MetaLoadingSliver()];
    }

    return LevelUpCelebrationHost(
      child: MetaScaffold(
        title: l10n.metaLevelRoadTitle,
        onRefresh: refresh,
        slivers: slivers,
      ),
    );
  }

  List<Widget> _content(BuildContext context, ProgressionView p) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final next = p.nextMilestone;
    Widget pad(Widget child, {double bottom = AppSpacing.md}) => SliverPadding(
      padding: kMetaPagePadding.copyWith(bottom: bottom),
      sliver: SliverToBoxAdapter(child: child),
    );
    return [
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
      pad(
        LevelHeaderCard(
          level: p.level,
          xp: p.xp,
          levelXp: p.levelXp,
          nextLevelXp: p.nextLevelXp,
          maxLevel: p.maxLevel,
          large: true,
        ),
      ),
      pad(
        Text(
          l10n.metaTotalXp(formatNumberFull(p.xp, locale)),
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall,
        ),
      ),
      pad(const _HowToEarnCard()),
      pad(SectionHeader(title: l10n.metaMilestonesTitle), bottom: 0),
      if (p.milestones.isEmpty)
        pad(MetaNote(text: l10n.metaNoMilestones, icon: Icons.info_rounded))
      else
        SliverPadding(
          padding: kMetaPagePadding,
          sliver: SliverList.builder(
            itemCount: p.milestones.length,
            itemBuilder: (context, i) {
              final m = p.milestones[i];
              return _MilestoneTile(
                milestone: m,
                isNext: identical(m, next),
                xpToGo: m.reached
                    ? 0
                    : math.max(0, LevelMath.levelStart(m.level) - p.xp),
                isFirst: i == 0,
                isLast: i == p.milestones.length - 1,
              );
            },
          ),
        ),
    ];
  }
}

class _HowToEarnCard extends StatelessWidget {
  const _HowToEarnCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final rows = [
      (Icons.check_circle_rounded, l10n.metaXpForMatch(20)),
      (Icons.emoji_events_rounded, l10n.metaXpForWin(15)),
      (Icons.people_alt_rounded, l10n.metaXpForFriend(5)),
      (Icons.flag_rounded, l10n.metaXpForMissions),
    ];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.metaHowToEarnXp, style: context.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final (icon, text) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: c.brand),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(text, style: context.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.metaXpFairPlayNote,
            style: context.textTheme.bodySmall?.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

/// One stop of the road: node + rewards card.
class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.milestone,
    required this.isNext,
    required this.xpToGo,
    required this.isFirst,
    required this.isLast,
  });

  final Milestone milestone;
  final bool isNext;
  final int xpToGo;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final reached = milestone.reached;
    final status = reached
        ? l10n.metaMilestoneUnlocked
        : isNext
        ? l10n.metaMilestoneNext(formatNumberFull(xpToGo, locale))
        : l10n.metaMilestoneLocked(formatNumberFull(xpToGo, locale));
    final lineColor = reached ? c.gold : c.outline;

    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: reached
            ? Color.lerp(c.surface, c.goldSoft, c.isDark ? 0.08 : 0.35)
            : c.surface,
        borderRadius: AppRadii.mdAll,
        border: Border.all(
          color: isNext
              ? c.brand
              : reached
              ? c.gold.withValues(alpha: 0.55)
              : c.outline.withValues(alpha: c.isDark ? 0.3 : 0.8),
          width: isNext ? 1.5 : 1,
        ),
        boxShadow: isNext ? c.shadow(AppElevation.low) : const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.commonLevel(milestone.level),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleMedium,
                ),
              ),
              Icon(
                reached
                    ? Icons.check_circle_rounded
                    : isNext
                    ? Icons.trending_up_rounded
                    : Icons.lock_rounded,
                size: 18,
                color: reached
                    ? c.success
                    : isNext
                    ? c.brand
                    : c.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            status,
            style: context.textTheme.bodySmall?.copyWith(
              color: isNext ? c.brand : null,
            ),
          ),
          if (milestone.rewards.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            RewardChips(items: milestone.rewards, muted: !reached && !isNext),
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      label: '${l10n.commonLevel(milestone.level)}, $status',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: 3,
                      color: isFirst ? Colors.transparent : lineColor,
                    ),
                  ),
                  Opacity(
                    opacity: reached || isNext ? 1 : 0.55,
                    child: LevelBadge(level: milestone.level, size: 34),
                  ),
                  Expanded(
                    child: Container(
                      width: 3,
                      color: isLast ? Colors.transparent : lineColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: card,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
