import 'package:go_router/go_router.dart';

import '../app/routes.dart';
import 'collection/presentation/collection_screen.dart';
import 'events/presentation/events_screen.dart';
import 'leaderboard/presentation/leaderboard_screen.dart';
import 'progression/presentation/progression_screen.dart';
import 'store/presentation/shop_screen.dart';

/// Meta paths not (yet) in `AppRoutes`.
abstract final class MetaRoutes {
  /// Level road (milestones).
  static const String progression = '/progression';

  /// Weekly friends leaderboard.
  static const String leaderboard = '/leaderboard';

  /// Query keys.
  static const String qTab = 'tab';
  static const String qKind = 'kind';
  static const String qItem = 'item';

  /// `/friends?tab=friends|requests|recent|reported`.
  static String friendsTab(String tab) =>
      Uri(path: AppRoutes.friends, queryParameters: {qTab: tab}).toString();

  /// `/collection?kind=dice&item=dice_neon`.
  static String collectionFor({String? kind, String? item}) {
    final query = {qKind: ?kind, qItem: ?item};
    return Uri(
      path: AppRoutes.collection,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }
}

/// Routes of the meta experience shown above the tab shell (events,
/// collection, shop, leaderboard, level road). Spread into `featureRoutes`
/// by the app. Missions (`/missions`) and Friends (`/friends?tab=`) are
/// bottom-navigation tabs mounted by `app/shell/main_shell.dart`.
final List<RouteBase> metaRoutes = [
  GoRoute(
    path: AppRoutes.shop,
    builder: (context, state) => ShopScreen(
      initialCategory: state.uri.queryParameters[AppRoutes.qCategory],
    ),
  ),
  // The Shop's former path (old deep links and notifications).
  GoRoute(
    path: AppRoutes.store,
    redirect: (context, state) => Uri(
      path: AppRoutes.shop,
      queryParameters: state.uri.queryParameters.isEmpty
          ? null
          : state.uri.queryParameters,
    ).toString(),
  ),
  GoRoute(
    path: AppRoutes.events,
    builder: (context, state) => const EventsScreen(),
  ),
  GoRoute(
    path: AppRoutes.collection,
    builder: (context, state) => CollectionScreen(
      initialKind: state.uri.queryParameters[MetaRoutes.qKind],
      initialItemId: state.uri.queryParameters[MetaRoutes.qItem],
    ),
  ),
  GoRoute(
    path: MetaRoutes.leaderboard,
    builder: (context, state) => const LeaderboardScreen(),
  ),
  GoRoute(
    path: MetaRoutes.progression,
    builder: (context, state) => const ProgressionScreen(),
  ),
];
