import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/protocol/protocol.dart';

/// Navigation between the play screens. Flow transitions use `go` so the
/// stack never grows across matchmaking → game → results → play again; the
/// game route is entered directly (no intermediate loading screens).
abstract final class PlayNav {
  static void toGame(BuildContext context, String roomId) =>
      GoRouter.of(context).go(AppRoutes.game(roomId));

  static void toLobby(BuildContext context, String roomId) =>
      GoRouter.of(context).go(AppRoutes.roomLobby(roomId));

  static void home(BuildContext context) =>
      GoRouter.of(context).go(AppRoutes.home);

  /// Opens the screen that fits [room]: the game while playing or finished,
  /// the lobby otherwise.
  static void toRoom(BuildContext context, RoomSnapshot room) {
    if (room.isPlaying || room.isFinished) {
      toGame(context, room.id);
    } else {
      toLobby(context, room.id);
    }
  }

  /// Back out of a play screen: pop when something is below, else home.
  static void exit(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.home);
    }
  }
}
