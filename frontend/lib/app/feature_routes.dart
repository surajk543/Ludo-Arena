import 'package:go_router/go_router.dart';

import '../features/meta_routes.dart';
import '../features/play_routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FEATURE ROUTES — the single file feature engineers edit to add screens.
//
// Add one GoRoute per screen, using the path constants in `routes.dart`
// (never hard-coded strings). The router includes this list as top-level
// routes, so every entry is automatically protected by the app gate: it is
// unreachable before the gate is `ready` (deep links are remembered and
// resumed once ready). Example:
//
//   import 'package:ludo_royale/app/routes.dart';
//   import 'package:ludo_royale/features/matchmaking/matchmaking_screen.dart';
//
//   final List<RouteBase> featureRoutes = [
//     GoRoute(
//       path: AppRoutes.matchmaking,
//       builder: (context, state) => MatchmakingScreen(
//         game: state.uri.queryParameters[AppRoutes.qGame] ?? 'ludo',
//         variant: state.uri.queryParameters[AppRoutes.qVariant] ?? 'classic',
//         capacity: int.tryParse(
//               state.uri.queryParameters[AppRoutes.qCapacity] ?? '') ?? 4,
//       ),
//     ),
//     GoRoute(
//       path: AppRoutes.gamePattern,
//       builder: (context, state) =>
//           GameScreen(roomId: state.pathParameters['roomId']!),
//     ),
//   ];
//
// Paths waiting for an implementation (Home already links to them):
//   AppRoutes.matchmaking, createRoom, joinRoom, roomLobbyPattern, practice,
//   gamePattern, missions, collection, friends, events.
// Until a path is registered, navigating to it shows the app's "not
// available yet" page with a way back home.
// ─────────────────────────────────────────────────────────────────────────────

final List<RouteBase> featureRoutes = [...playRoutes, ...metaRoutes];
