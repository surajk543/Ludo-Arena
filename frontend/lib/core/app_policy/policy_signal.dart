import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why the app policy should be fetched again.
enum PolicySignalReason {
  /// A REST call answered 426 `update_required`.
  restUpdateRequired,

  /// A REST call answered 503 `maintenance`.
  restMaintenance,

  /// The WebSocket closed with 4426.
  wsUpdateRequired,

  /// The WebSocket closed with 4503.
  wsMaintenance,

  /// The WebSocket handshake failed (any status); throttled re-check.
  wsHandshakeFailed,
}

/// Decoupled channel from the network layers (ApiClient, RealtimeConnection)
/// to the AppGateController, so neither depends on the other.
class PolicySignalBus {
  final _controller = StreamController<PolicySignalReason>.broadcast();

  Stream<PolicySignalReason> get signals => _controller.stream;

  void notify(PolicySignalReason reason) {
    if (!_controller.isClosed) _controller.add(reason);
  }

  void dispose() => _controller.close();
}

final policySignalBusProvider = Provider<PolicySignalBus>((ref) {
  final bus = PolicySignalBus();
  ref.onDispose(bus.dispose);
  return bus;
});
