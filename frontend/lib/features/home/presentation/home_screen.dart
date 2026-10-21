import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../authentication/application/session_controller.dart';
import '../application/play_options.dart';
import 'widgets/game_card.dart';
import 'widgets/home_header.dart';
import 'widgets/home_tiles.dart';

/// The main hub after the gate is ready.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    try {
      await ref.read(sessionControllerProvider.notifier).refreshMe();
    } catch (_) {
      // Pull-to-refresh is best effort; balances stay server-confirmed.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    final tiles = [
      ExploreTileData(
        icon: Icons.flag_rounded,
        color: c.seats.red,
        title: l10n.homeMissions,
        subtitle: l10n.homeMissionsSubtitle,
        onTap: () => context.push(AppRoutes.missions),
      ),
      ExploreTileData(
        icon: Icons.diamond_rounded,
        color: c.brand,
        title: l10n.homeCollection,
        subtitle: l10n.homeCollectionSubtitle,
        onTap: () => context.push(AppRoutes.collection),
      ),
      ExploreTileData(
        icon: Icons.people_alt_rounded,
        color: c.seats.green,
        title: l10n.homeFriends,
        subtitle: l10n.homeFriendsSubtitle,
        onTap: () => context.push(AppRoutes.friends),
      ),
      ExploreTileData(
        icon: Icons.emoji_events_rounded,
        color: c.gold,
        title: l10n.homeEvents,
        subtitle: l10n.homeEventsSubtitle,
        onTap: () => context.push(AppRoutes.events),
      ),
    ];

    const ludo = GameCard(game: GameId.ludo);
    const snakes = GameCard(game: GameId.snakesLadders);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayeredBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: c.brand,
            onRefresh: () => _refresh(ref),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.huge,
                      ),
                      sliver: SliverList.list(
                        children: [
                          const HomeHeader(),
                          const SizedBox(height: AppSpacing.xl),
                          const QuickActions(),
                          const SizedBox(height: AppSpacing.xl),
                          SectionHeader(title: l10n.homeGamesHeader),
                          const SizedBox(height: AppSpacing.md),
                          if (wide)
                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: ludo),
                                SizedBox(width: AppSpacing.lg),
                                Expanded(child: snakes),
                              ],
                            )
                          else ...const [
                            ludo,
                            SizedBox(height: AppSpacing.lg),
                            snakes,
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          SectionHeader(title: l10n.homeExploreHeader),
                          const SizedBox(height: AppSpacing.md),
                          ExploreGrid(tiles: tiles),
                          SizedBox(
                            height: MediaQuery.paddingOf(context).bottom,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
