import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/server_clock.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../missions/presentation/widgets/reset_label.dart';
import '../../progression/application/meta_support.dart';
import '../../progression/presentation/widgets/meta_scaffold.dart';
import '../application/leaderboard_controller.dart';
import '../domain/leaderboard_models.dart';
import 'widgets/leaderboard_row.dart';

/// Weekly friends leaderboard: you and your friends ranked by XP earned
/// this ISO week. Calm by design (no streak pressure, ties share a rank).
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(friendsLeaderboardProvider);

    Future<void> refresh() async {
      try {
        await ref.read(friendsLeaderboardProvider.notifier).refresh();
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
        slivers = _content(context, ref, value);
      case AsyncError(:final error):
        slivers = [
          MetaErrorSliver(
            message: metaErrorMessage(l10n, error),
            onRetry: () => ref.invalidate(friendsLeaderboardProvider),
          ),
        ];
      default:
        slivers = const [MetaLoadingSliver()];
    }

    return MetaScaffold(
      title: l10n.metaLeaderboardTitle,
      onRefresh: refresh,
      slivers: slivers,
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    FriendsLeaderboard lb,
  ) {
    final l10n = AppLocalizations.of(context);
    final clock = ref.watch(serverClockProvider);
    final reset = nextWeeklyResetUtc(
      DateTime.fromMillisecondsSinceEpoch(clock.nowMs(), isUtc: true),
    );
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.metaLeaderboardSubtitle,
                style: context.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              PeriodResetLabel(resetsAtUtc: reset, kind: ResetKind.weekly),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: kMetaPagePadding,
        sliver: SliverList.separated(
          itemCount: lb.entries.length,
          itemBuilder: (_, i) => LeaderboardRow(
            key: ValueKey('lb-${lb.entries[i].uid}'),
            entry: lb.entries[i],
          ),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        ),
      ),
      if (lb.isAlone)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetaNote(
                  icon: Icons.people_alt_rounded,
                  text: l10n.metaLeaderboardAlone,
                ),
                const SizedBox(height: AppSpacing.md),
                PremiumButton(
                  label: l10n.metaAddFriend,
                  icon: Icons.person_add_alt_1_rounded,
                  size: PremiumButtonSize.medium,
                  variant: PremiumButtonVariant.secondary,
                  // Friends is a bottom-navigation tab.
                  onPressed: () => context.go(AppRoutes.friends),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}
