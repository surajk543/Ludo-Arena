import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/analytics/analytics_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../missions/application/missions_controller.dart';
import '../../missions/domain/mission_models.dart';
import '../../missions/presentation/widgets/mission_card.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/level_up_celebration_host.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import 'widgets/event_card.dart';

/// Running events: window, rules and their missions (claimable here).
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(missionsProvider);
    if (!_viewedLogged && async.hasValue) {
      _viewedLogged = true;
      ref.read(analyticsServiceProvider).missionViewed();
    }

    final List<Widget> slivers;
    switch (async) {
      case AsyncValue(:final value?):
        slivers = _content(context, value.events);
      case AsyncError(:final error):
        slivers = [
          MetaErrorSliver(
            message: metaErrorMessage(l10n, error),
            onRetry: () => ref.invalidate(missionsProvider),
          ),
        ];
      default:
        slivers = const [MetaLoadingSliver()];
    }

    return LevelUpCelebrationHost(
      child: MetaScaffold(
        title: l10n.metaEventsTitle,
        onRefresh: _refresh,
        slivers: slivers,
      ),
    );
  }

  List<Widget> _content(BuildContext context, List<EventSet> events) {
    final l10n = AppLocalizations.of(context);
    if (events.isEmpty) {
      return [
        MetaEmptySliver(
          title: l10n.metaNoEventsTitle,
          message: l10n.metaNoEventsMessage,
          illustration: const EventEmptyIllustration(),
          action: PremiumButton(
            label: l10n.metaGoToMissions,
            icon: Icons.flag_rounded,
            expand: false,
            size: PremiumButtonSize.medium,
            variant: PremiumButtonVariant.secondary,
            onPressed: () => context.pushReplacement(AppRoutes.missions),
          ),
        ),
      ];
    }
    Widget pad(Widget child, {double bottom = AppSpacing.md}) => SliverPadding(
      padding: kMetaPagePadding.copyWith(bottom: bottom),
      sliver: SliverToBoxAdapter(child: child),
    );
    return [
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
      for (final e in events) ...[
        pad(EventHeroCard(event: e)),
        pad(const EventRulesCard()),
        pad(SectionHeader(title: l10n.metaEventMissionsTitle), bottom: 0),
        for (final m in e.missions)
          pad(
            MissionCard(
              key: ValueKey('event-${e.periodKey}-${m.id}'),
              periodKey: e.periodKey,
              mission: m,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ],
    ];
  }
}
