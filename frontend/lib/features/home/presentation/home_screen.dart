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
import 'widgets/quick_play_card.dart';
import 'widgets/shop_bar.dart';

/// The lobby (Home tab): the Shop button pinned on top, then one vertical
/// scroll with the compact profile header, Quick Play, private room
/// actions, the game cards and the More to Explore grid. Everything shown
/// comes from state that is already loaded (no network in build).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// The lobby is scrolled away from the top (the Shop bar shows its edge).
  final ValueNotifier<bool> _scrolled = ValueNotifier(false);

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await ref.read(sessionControllerProvider.notifier).refreshMe();
    } catch (_) {
      // Pull-to-refresh is best effort; balances stay server-confirmed.
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      _scrolled.value = n.metrics.pixels > 0.5;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    final tiles = [
      ExploreTileData(
        icon: Icons.flag_rounded,
        color: c.accentCoral,
        title: l10n.homeMissions,
        subtitle: l10n.homeMissionsSubtitle,
        // Missions and Friends are bottom-navigation tabs: switch to them.
        onTap: () => context.go(AppRoutes.missions),
      ),
      ExploreTileData(
        icon: Icons.diamond_rounded,
        color: c.accentViolet,
        title: l10n.homeCollection,
        subtitle: l10n.homeCollectionSubtitle,
        onTap: () => context.push(AppRoutes.collection),
      ),
      ExploreTileData(
        icon: Icons.people_alt_rounded,
        color: c.accentMint,
        title: l10n.homeFriends,
        subtitle: l10n.homeFriendsSubtitle,
        onTap: () => context.go(AppRoutes.friends),
      ),
      ExploreTileData(
        icon: Icons.emoji_events_rounded,
        color: c.accentAmber,
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                children: [
                  // Outside the scroll view: always visible.
                  LobbyShopBar(scrolled: _scrolled),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: RefreshIndicator(
                        color: c.brand,
                        onRefresh: _refresh,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                AppSpacing.xs,
                                AppSpacing.lg,
                                AppSpacing.xxl +
                                    MediaQuery.paddingOf(context).bottom,
                              ),
                              sliver: SliverList.list(
                                children: [
                                  const HomeHeader(),
                                  const SizedBox(height: AppSpacing.lg),
                                  const QuickPlayCard(),
                                  const SizedBox(height: AppSpacing.lg),
                                  const RoomActions(),
                                  const SizedBox(height: AppSpacing.lg),
                                  SectionHeader(title: l10n.homeGamesHeader),
                                  const SizedBox(height: AppSpacing.xs),
                                  if (wide)
                                    const Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                  const SizedBox(height: AppSpacing.lg),
                                  SectionHeader(title: l10n.homeExploreHeader),
                                  const SizedBox(height: AppSpacing.xs),
                                  ExploreGrid(tiles: tiles),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
