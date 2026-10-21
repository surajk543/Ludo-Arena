import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/routes.dart';
import 'game/application/play_config.dart';
import 'game/presentation/game_route_screen.dart';
import 'matchmaking/presentation/matchmaking_screen.dart';
import 'practice/presentation/practice_screen.dart';
import 'private_rooms/presentation/create_room_screen.dart';
import 'private_rooms/presentation/join_room_screen.dart';
import 'private_rooms/presentation/room_lobby_screen.dart';

/// Routes of the PLAY experience (matchmaking, private rooms, practice and
/// the game screens). Spread into `featureRoutes` by the app shell:
///
/// ```dart
/// final List<RouteBase> featureRoutes = [...playRoutes, ...];
/// ```
final List<RouteBase> playRoutes = [
  GoRoute(
    path: AppRoutes.matchmaking,
    pageBuilder: (context, state) => _fade(
      state,
      MatchmakingScreen(
        request: PlayRequest.fromQuery(state.uri.queryParameters),
      ),
    ),
  ),
  GoRoute(
    path: AppRoutes.createRoom,
    builder: (context, state) => CreateRoomScreen(
      request: PlayRequest.fromQuery(state.uri.queryParameters),
    ),
  ),
  GoRoute(
    path: AppRoutes.joinRoom,
    builder: (context, state) =>
        JoinRoomScreen(initialCode: state.uri.queryParameters[AppRoutes.qCode]),
  ),
  GoRoute(
    path: AppRoutes.roomLobbyPattern,
    pageBuilder: (context, state) =>
        _fade(state, RoomLobbyScreen(roomId: state.pathParameters['id']!)),
  ),
  GoRoute(
    path: AppRoutes.practice,
    pageBuilder: (context, state) => _fade(
      state,
      PracticeScreen(request: PlayRequest.fromQuery(state.uri.queryParameters)),
    ),
  ),
  GoRoute(
    path: AppRoutes.gamePattern,
    pageBuilder: (context, state) =>
        _fade(state, GameRouteScreen(roomId: state.pathParameters['roomId']!)),
  ),
];

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
