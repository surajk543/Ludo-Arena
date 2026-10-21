import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio_haptics/haptics_service.dart';
import '../../core/audio_haptics/reduced_motion.dart';
import '../../core/theme/app_theme.dart';
import '../../features/home/presentation/games_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/meta_routes.dart';
import '../../features/missions/presentation/missions_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/social/presentation/friends_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../routes.dart';

/// The bottom-navigation tabs: one `StatefulShellRoute.indexedStack` whose
/// branches keep their own navigator and state (scroll position, selected
/// friends tab, …) while the user switches tabs.
///
/// Everything else (settings, collection, events, matchmaking, private
/// rooms, practice, the game) stays a top-level route on the root navigator,
/// so it covers the bar; play-flow routes are entered with `go` and replace
/// the shell entirely. Built per router (branch navigator keys are owned by
/// one router at a time).
StatefulShellRoute buildMainTabsRoute() => StatefulShellRoute.indexedStack(
  pageBuilder: (context, state, shell) => CustomTransitionPage<void>(
    key: state.pageKey,
    child: MainShell(navigationShell: shell),
    transitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
  ),
  branches: [
    _branch(AppRoutes.home, (_) => const HomeScreen(), backToHome: false),
    _branch(AppRoutes.games, (_) => const GamesScreen()),
    _branch(AppRoutes.missions, (_) => const MissionsScreen()),
    _branch(
      AppRoutes.friends,
      (state) =>
          FriendsScreen(initialTab: state.uri.queryParameters[MetaRoutes.qTab]),
    ),
    _branch(AppRoutes.profile, (_) => const ProfileScreen()),
  ],
);

StatefulShellBranch _branch(
  String path,
  Widget Function(GoRouterState state) screen, {
  bool backToHome = true,
}) => StatefulShellBranch(
  routes: [
    GoRoute(
      path: path,
      pageBuilder: (_, state) => NoTransitionPage(
        key: state.pageKey,
        child: backToHome
            ? _BackToHomeScope(child: screen(state))
            : screen(state),
      ),
    ),
  ],
);

/// System back on a tab root other than Home switches to Home.
///
/// Lives inside the branch's own page: the branch navigator then reports
/// that the app handles back (Android predictive back asks the innermost
/// navigator), which a scope above the branch navigators cannot do.
class _BackToHomeScope extends StatelessWidget {
  const _BackToHomeScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) StatefulNavigationShell.maybeOf(context)?.goBranch(0);
    },
    child: child,
  );
}

/// Scaffold of the tab shell: the active branch above [AppBottomNav].
/// System back on any tab but Home returns to Home first (see
/// [_BackToHomeScope]; the scope here keeps the root navigator reporting it
/// after pages pushed above the shell close).
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _select(int index) => navigationShell.goBranch(
    index,
    // Re-tapping the active tab returns to its root.
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(0);
      },
      child: Scaffold(
        backgroundColor: context.colors.backgroundBottom,
        body: navigationShell,
        bottomNavigationBar: AppBottomNav(
          currentIndex: index,
          onSelect: _select,
        ),
      ),
    );
  }
}

/// One destination of [AppBottomNav].
class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Bottom navigation bar: Home, Games, Missions, Friends, Profile. The
/// active item sits on a soft brand pill. Extends under the system gesture
/// area; every item is a ≥ 48 dp target.
class AppBottomNav extends ConsumerWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static List<AppNavDestination> destinations(AppLocalizations l10n) => [
    AppNavDestination(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: l10n.homeNavHome,
    ),
    AppNavDestination(
      icon: Icons.sports_esports_outlined,
      activeIcon: Icons.sports_esports_rounded,
      label: l10n.homeNavGames,
    ),
    AppNavDestination(
      icon: Icons.flag_outlined,
      activeIcon: Icons.flag_rounded,
      label: l10n.homeNavMissions,
    ),
    AppNavDestination(
      icon: Icons.people_alt_outlined,
      activeIcon: Icons.people_alt_rounded,
      label: l10n.homeNavFriends,
    ),
    AppNavDestination(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: l10n.homeNavProfile,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final items = destinations(l10n);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.xl),
        ),
        border: Border(top: BorderSide(color: c.cardBorder)),
        boxShadow: c.isDark
            ? const []
            : [
                BoxShadow(
                  color: c.shadowColor.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, -4),
                ),
              ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          // Items stay phone-sized on tablets instead of stretching.
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _NavItem(
                        destination: items[i],
                        selected: i == currentIndex,
                        onTap: () {
                          ref.read(hapticsServiceProvider).selection();
                          onSelect(i);
                        },
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? (c.isDark ? c.onBrand : c.brand) : c.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.lgAll,
            child: AnimatedContainer(
              duration: context.motion(AppDurations.fast),
              curve: AppCurves.standard,
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxs,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? (c.isDark ? c.brand.withValues(alpha: 0.85) : c.brandSoft)
                    : Colors.transparent,
                borderRadius: AppRadii.lgAll,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? destination.activeIcon : destination.icon,
                    size: 26,
                    color: fg,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      style: context.textTheme.labelMedium?.copyWith(
                        color: fg,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
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
