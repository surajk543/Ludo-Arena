import 'package:go_router/go_router.dart';

import '../routes.dart';

/// How a bottom-navigation tab location can be opened from the current
/// navigation stack.
enum TabOpenMode {
  /// No tab shell in the stack (a play-flow page entered with `go`, such as
  /// the private-room lobby): push the tab on top so back returns there.
  push,

  /// The shell is on top, or only meta pages (settings, collection, …) sit
  /// above it: switch tabs with `go`.
  go,

  /// A play-flow page (matchmaking, practice, private room) sits above the
  /// shell. Pushing a tab route would build the shell a second time and
  /// `go` would drop that page, so the screen must be shown as a plain
  /// (pageless) route instead.
  overlay,
}

/// Paths of play-flow pages that must survive opening a tab.
const Set<String> _playFlowPaths = {
  AppRoutes.matchmaking,
  AppRoutes.createRoom,
  AppRoutes.joinRoom,
  AppRoutes.roomLobbyPattern,
  AppRoutes.practice,
  AppRoutes.gamePattern,
};

/// Decides how to open a tab from [stack] (the router's current matches).
TabOpenMode tabOpenModeFor(RouteMatchList stack) {
  final matches = stack.matches;
  final shell = matches.lastIndexWhere((m) => m is ShellRouteMatch);
  if (shell < 0) return TabOpenMode.push;
  for (final m in matches.skip(shell + 1)) {
    final route = m.route;
    if (route is GoRoute && _playFlowPaths.contains(route.path)) {
      return TabOpenMode.overlay;
    }
  }
  return TabOpenMode.go;
}
