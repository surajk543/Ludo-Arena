/// Every route path in the app. Navigate ONLY through these constants and
/// builders (`context.go(AppRoutes.home)`, `context.push(AppRoutes.game(id))`).
///
/// Gate routes are controlled by `AppGateController`; feature engineers add
/// their `GoRoute`s in `lib/app/feature_routes.dart` using these paths.
abstract final class AppRoutes {
  // ---------------------------------------------------------- gate (owned by app)
  static const String splash = '/splash';
  static const String maintenance = '/maintenance';
  static const String updateRequired = '/update-required';
  static const String unreachable = '/unreachable';

  // ---------------------------------------------------------- pre-auth
  static const String languageOnboarding = '/welcome/language';
  static const String login = '/login';

  // ---------------------------------------------------------- core screens
  // Bottom-navigation tabs (one StatefulShellRoute, see app/shell/): home,
  // games, missions, friends, profile. Reach a tab with `context.go(...)`;
  // pushing a tab route over a page that sits above the shell would build
  // the shell twice.
  static const String home = '/home';
  static const String games = '/games';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String linkAccount = '/link-account';

  // ---------------------------------------------------------- feature screens
  // (implemented by later engineers in feature_routes.dart)

  /// `/matchmaking?game=ludo&variant=classic&capacity=4`
  static const String matchmaking = '/matchmaking';

  /// `/rooms/create?game=ludo&variant=classic&capacity=4`
  static const String createRoom = '/rooms/create';

  /// `/rooms/join` or `/rooms/join?code=K7Q2MX`
  static const String joinRoom = '/rooms/join';

  /// `/rooms/:id/lobby`
  static const String roomLobbyPattern = '/rooms/:id/lobby';

  /// `/practice?game=ludo&variant=classic&bots=3`
  static const String practice = '/practice';

  /// `/game/:roomId`
  static const String gamePattern = '/game/:roomId';

  static const String missions = '/missions';
  static const String collection = '/collection';
  static const String friends = '/friends';
  static const String events = '/events';

  /// Store (profile pictures for diamonds). Full screen above the tabs:
  /// `context.push(AppRoutes.store)`.
  static const String store = '/store';

  // ---------------------------------------------------------- query keys
  static const String qGame = 'game';
  static const String qVariant = 'variant';
  static const String qCapacity = 'capacity';
  static const String qBots = 'bots';
  static const String qCode = 'code';

  // ---------------------------------------------------------- builders

  /// [game]: `ludo` | `snakes_ladders`; [variant]: `classic` | `quick`
  /// (Ludo only; Snakes & Ladders always `classic`); [capacity]: 2..4.
  static String matchmakingFor({
    required String game,
    String variant = 'classic',
    required int capacity,
  }) => Uri(
    path: matchmaking,
    queryParameters: {qGame: game, qVariant: variant, qCapacity: '$capacity'},
  ).toString();

  static String createRoomFor({
    required String game,
    String variant = 'classic',
    required int capacity,
  }) => Uri(
    path: createRoom,
    queryParameters: {qGame: game, qVariant: variant, qCapacity: '$capacity'},
  ).toString();

  /// [code] is an optional pre-filled 6-character room code.
  static String joinRoomFor({String? code}) => code == null || code.isEmpty
      ? joinRoom
      : Uri(path: joinRoom, queryParameters: {qCode: code}).toString();

  static String roomLobby(String roomId) =>
      '/rooms/${Uri.encodeComponent(roomId)}/lobby';

  /// [bots]: 1..3 (caller + bots ≤ 4).
  static String practiceFor({
    required String game,
    String variant = 'classic',
    int bots = 3,
  }) => Uri(
    path: practice,
    queryParameters: {qGame: game, qVariant: variant, qBots: '$bots'},
  ).toString();

  static String game(String roomId) => '/game/${Uri.encodeComponent(roomId)}';

  /// Full-screen gate routes (only reachable when the gate is in that phase).
  static const Set<String> gateRoutes = {
    splash,
    maintenance,
    updateRequired,
    unreachable,
  };

  /// Roots of the bottom-navigation tabs, in bar order.
  static const List<String> tabs = [home, games, missions, friends, profile];

  /// Routes available while signed out.
  static const Set<String> preAuthRoutes = {languageOnboarding, login};
}
