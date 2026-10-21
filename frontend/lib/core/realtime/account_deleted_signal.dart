import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Decoupled channel from the realtime connection to the session layer: the
/// server closed the WebSocket with `4401` + reason `account deleted`
/// (websocket-protocol.md §1), so the account no longer exists. Keeps
/// `core/realtime` independent of the authentication feature.
class AccountDeletedSignal {
  final _controller = StreamController<void>.broadcast();

  Stream<void> get events => _controller.stream;

  void notify() {
    if (!_controller.isClosed) _controller.add(null);
  }

  void dispose() => _controller.close();
}

final accountDeletedSignalProvider = Provider<AccountDeletedSignal>((ref) {
  final signal = AccountDeletedSignal();
  ref.onDispose(signal.dispose);
  return signal;
});
