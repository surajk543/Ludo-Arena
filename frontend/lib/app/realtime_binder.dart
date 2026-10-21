import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime/realtime_providers.dart';
import '../features/authentication/application/session_controller.dart';
import 'gate/app_gate_controller.dart';

/// Starts the realtime WebSocket only when the gate is `ready` (signed in,
/// policy OK) and stops it when signed out or blocked. When the signed-in
/// account changes (e.g. after "Sign in to that account"), the socket is
/// re-established with the new session and room state is reset.
///
/// Watched once by the app shell.
final realtimeBinderProvider = Provider<void>((ref) {
  void restartForNewUser() {
    final connection = ref.read(realtimeConnectionProvider);
    connection.stop();
    ref.invalidate(activeRoomControllerProvider);
    if (ref.read(appGateControllerProvider).phase == GatePhase.ready) {
      connection.start();
    }
  }

  ref.listen<GatePhase>(appGateControllerProvider.select((s) => s.phase), (
    previous,
    phase,
  ) {
    final connection = ref.read(realtimeConnectionProvider);
    if (phase == GatePhase.ready) {
      connection.start();
    } else if (phase == GatePhase.signedOut) {
      connection.stop();
      ref.invalidate(activeRoomControllerProvider);
    } else if (phase == GatePhase.maintenance ||
        phase == GatePhase.forceUpdate) {
      // The server pauses matches during maintenance; room state is kept and
      // re-synced (game.state) after reconnecting.
      connection.stop();
    }
  }, fireImmediately: true);

  ref.listen<String?>(sessionControllerProvider.select((s) => s.user?.id), (
    previous,
    next,
  ) {
    if (previous != null && next != null && previous != next) {
      restartForNewUser();
    }
  });
});
