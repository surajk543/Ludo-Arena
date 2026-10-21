import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/protocol/protocol.dart';
import '../core/realtime/realtime_providers.dart';
import '../core/state/in_match_provider.dart';
import 'gate/app_gate_controller.dart';
import 'router.dart';
import 'routes.dart';

/// Where to reopen the room in [state] after a launch, or null when there
/// is nothing to resume (no room, finished or closed, or the local player
/// already forfeited).
String? resumeLocationFor(ActiveRoomState state) {
  final room = state.room;
  final self = state.selfPlayer;
  if (room == null || self == null || self.forfeited) return null;
  if (room.isPlaying) return AppRoutes.game(room.id);
  if (room.isLobby) {
    // Public lobbies are shown by the game route (as matchmaking does).
    return room.isPrivate || room.isPractice
        ? AppRoutes.roomLobby(room.id)
        : AppRoutes.game(room.id);
  }
  return null;
}

/// How long after `connection.ready` the announced room may still be
/// opened (its snapshot normally arrives within one round trip).
const Duration kMatchResumeWindow = Duration(seconds: 20);

/// Reopens the match the user was in when the app was closed (force-quit,
/// crash, OS kill). After the gate becomes `ready`, the first
/// `connection.ready` names the server's active room; when its snapshot
/// arrives the app goes straight to it, unless a match screen is already
/// open. Later reconnects never navigate.
///
/// Watched once by the app shell. Listening to [activeRoomControllerProvider]
/// here also builds it before the socket connects, so the launch
/// `connection.ready` and its `game.state` are not missed.
final matchResumeProvider = Provider<void>((ref) {
  var armed = false;
  String? pending;
  Timer? expiry;

  void disarm() {
    armed = false;
    pending = null;
    expiry?.cancel();
    expiry = null;
  }

  void tryOpen() {
    final id = pending;
    if (id == null) return;
    final state = ref.read(activeRoomControllerProvider);
    if (state.room?.id != id) return;
    disarm();
    final target = resumeLocationFor(state);
    if (target == null || ref.read(inMatchProvider)) return;
    final router = ref.read(appRouterProvider);
    if (router.routerDelegate.currentConfiguration.uri.path == target) return;
    router.go(target);
  }

  ref.listen<GatePhase>(appGateControllerProvider.select((s) => s.phase), (
    previous,
    phase,
  ) {
    if (phase != GatePhase.ready) {
      disarm();
    } else if (previous != GatePhase.ready) {
      armed = true;
    }
  }, fireImmediately: true);

  ref.listen<String?>(
    activeRoomControllerProvider.select((s) => s.room?.id),
    (_, _) => tryOpen(),
  );

  final sub = ref.read(realtimeConnectionProvider).events.listen((m) {
    final e = m.event;
    if (!armed || e is! ConnectionReadyEvent) return;
    armed = false;
    pending = e.activeRoomId;
    if (pending == null) return;
    expiry = Timer(kMatchResumeWindow, disarm);
    tryOpen();
  });
  ref.onDispose(() {
    sub.cancel();
    expiry?.cancel();
  });
});
