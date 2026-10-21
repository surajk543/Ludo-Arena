import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_policy/policy_signal.dart';
import '../config/app_config.dart';
import '../config/app_info.dart';
import '../lifecycle/app_lifecycle.dart';
import '../network/api_client.dart';
import '../protocol/protocol.dart';
import '../telemetry/telemetry_reporter.dart';
import '../time/server_clock.dart';
import 'active_room_controller.dart';
import 'realtime_connection.dart';
import 'realtime_status.dart';

export 'active_room_controller.dart';
export 'realtime_connection.dart';
export 'realtime_status.dart';

/// The app's single WebSocket. Created lazily and NOT auto-started: the
/// session layer calls `start()` when the gate is ready and `stop()` on
/// sign-out.
final realtimeConnectionProvider = Provider<RealtimeConnection>((ref) {
  final config = ref.watch(appConfigProvider);
  final info = ref.watch(appInfoProvider);
  final tokens = ref.watch(tokenManagerProvider);
  final policy = ref.watch(policySignalBusProvider);
  final clock = ref.watch(serverClockProvider);
  final telemetry = ref.watch(telemetryReporterProvider);
  final statusNotifier = ref.read(realtimeStatusProvider.notifier);

  final connection = RealtimeConnection(
    uri: config.webSocketUri,
    appHeaders: info.headers,
    accessToken: () =>
        tokens.validAccessToken(minValidity: const Duration(seconds: 60)),
    refreshSession: () async => await tokens.refreshNow() != null,
    onStatus: (s) {
      try {
        statusNotifier.set(s);
      } catch (_) {
        // The status provider was disposed together with the container.
      }
    },
    onPolicySignal: policy.notify,
    onServerTime: (ms, rtt) => clock.sample(ms, roundTrip: rtt),
    onTelemetry: telemetry.record,
    lifecycle: ref.watch(appLifecycleProvider),
  );
  ref.onDispose(connection.dispose);
  return connection;
});

/// Current room, matchmaking state and room commands.
final activeRoomControllerProvider =
    NotifierProvider<ActiveRoomController, ActiveRoomState>(
      ActiveRoomController.new,
    );

/// `wallet.updated` events (for `ref.listen`).
final walletUpdatesProvider = StreamProvider<WalletUpdatedEvent>(
  (ref) => ref.watch(realtimeConnectionProvider).walletUpdates,
);

/// `progression.updated` events (for `ref.listen`).
final progressionUpdatesProvider = StreamProvider<ProgressionUpdatedEvent>(
  (ref) => ref.watch(realtimeConnectionProvider).progressionUpdates,
);

/// `social.invite` / `social.friend_request` events (for `ref.listen`).
final socialEventsProvider = StreamProvider<ServerEvent>(
  (ref) => ref.watch(realtimeConnectionProvider).socialEvents,
);
