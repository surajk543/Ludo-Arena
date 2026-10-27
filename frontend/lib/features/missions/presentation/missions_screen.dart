import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/analytics/analytics_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../daily_journey/presentation/playtime_section.dart';
import '../../meta_routes.dart';
import '../../profile/progression.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/level_up_celebration_host.dart';
import '../../progression/presentation/widgets/level_header_card.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../application/missions_controller.dart';
import '../domain/mission_models.dart';
import '../domain/mission_texts.dart';
import 'widgets/mission_card.dart';
import 'widgets/reset_label.dart';

/// Daily missions, the weekly challenge and running events.
class MissionsScreen extends ConsumerStatefulWidget {
  const MissionsScreen({super.key});

  @override
  ConsumerState<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends ConsumerState<MissionsScreen> {
  bool _viewedLogged = false;

  Future<void> _refresh() async {
    try {
      await ref.read(missionsProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        metaErrorMessage(AppLocalizations.of(context), e),
        kind: ToastKind.error,
      );
    }
  }

  void _reloadAfterReset() => unawaited(_refresh().catchError((Object _) {}));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(missionsProvider);
    if (!_viewedLogged && async.hasValue) {
      // Logged once per visit, only after the server answered.
      _viewedLogged = true;
      ref.read(analyticsServiceProvider).missionViewed();
    }
    final summary = ref.watch(progressionSummaryProvider);

    final slivers = <Widget>[];
    if (summary != null) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: LevelHeaderCard(
              level: summary.level,
              xp: summary.xp,
              levelXp: summary.levelXp,
              nextLevelXp: summary.nextLevelXp,
              onTap: () => context.push(MetaRoutes.progression),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: context.colors.textMuted,
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ),
      );
    }

    // Today's playtime (renders nothing while disabled or loading).
    slivers.add(
      const SliverPadding(
        padding: kMetaPagePadding,
        sliver: SliverToBoxAdapter(child: PlaytimeSection()),
      ),
    );

    switch (async) {
      case AsyncValue(:final value?):
        slivers.addAll(_board(context, value));
      case AsyncError(:final error):
        slivers.add(
          MetaErrorSliver(
            message: metaErrorMessage(l10n, error),
            onRetry: () => ref.invalidate(missionsProvider),
          ),
        );
      default:
        slivers.add(const MetaLoadingSliver());
    }

    return LevelUpCelebrationHost(
      child: MetaScaffold(
        title: l10n.metaMissionsTitle,
        onRefresh: _refresh,
        actions: [
          IconButton(
            tooltip: l10n.metaLevelRoadTitle,
            icon: const Icon(Icons.route_rounded),
            onPressed: () => context.push(MetaRoutes.progression),
          ),
        ],
        slivers: slivers,
      ),
    );
  }

  List<Widget> _board(BuildContext context, MissionsBoard board) {
    final l10n = AppLocalizations.of(context);
    if (board.isEmpty) {
      return [
        MetaEmptySliver(
          title: l10n.metaMissionsEmptyTitle,
          message: l10n.metaMissionsEmptyMessage,
        ),
      ];
    }
    Widget pad(Widget child) => SliverPadding(
      padding: kMetaPagePadding,
      sliver: SliverToBoxAdapter(child: child),
    );
    List<Widget> cards(String periodKey, List<Mission> list) => [
      for (final m in list)
        pad(
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: MissionCard(
              key: ValueKey('mission-$periodKey-${m.id}'),
              periodKey: periodKey,
              mission: m,
            ),
          ),
        ),
    ];

    return [
      if (board.daily.missions.isNotEmpty) ...[
        pad(SectionHeader(title: l10n.metaDailyTitle)),
        if (board.daily.resetsAtUtc != null)
          pad(
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: PeriodResetLabel(
                resetsAtUtc: board.daily.resetsAtUtc!,
                kind: ResetKind.daily,
                onElapsed: _reloadAfterReset,
              ),
            ),
          ),
        ...cards(board.daily.periodKey, board.daily.missions),
      ],
      if (board.weekly.missions.isNotEmpty) ...[
        pad(SectionHeader(title: l10n.metaWeeklyTitle)),
        if (board.weekly.resetsAtUtc != null)
          pad(
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: PeriodResetLabel(
                resetsAtUtc: board.weekly.resetsAtUtc!,
                kind: ResetKind.weekly,
                onElapsed: _reloadAfterReset,
              ),
            ),
          ),
        ...cards(board.weekly.periodKey, board.weekly.missions),
      ],
      for (final e in board.events) ...[
        pad(
          SectionHeader(
            title: MissionTexts.eventTitle(l10n, e),
            actionLabel: l10n.metaEventDetails,
            onAction: () => context.push(AppRoutes.events),
          ),
        ),
        if (e.endsAtUtc != null)
          pad(
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: PeriodResetLabel(
                resetsAtUtc: e.endsAtUtc!,
                kind: ResetKind.event,
                onElapsed: _reloadAfterReset,
              ),
            ),
          ),
        ...cards(e.periodKey, e.missions),
      ],
      pad(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: MetaNote(text: l10n.metaNoPenaltyNote),
        ),
      ),
    ];
  }
}
