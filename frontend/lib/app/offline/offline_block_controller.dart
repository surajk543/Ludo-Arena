import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lifecycle/app_lifecycle.dart';
import '../../core/realtime/realtime_providers.dart';
import '../gate/app_gate_controller.dart';

/// Whether the app is blocked behind the "Connection lost" overlay
/// (`OfflineBlockingHost`).
///
/// Single source of truth: the realtime WebSocket status
/// ([realtimeStatusProvider]). The socket is open on every screen once the
/// gate is ready (signed in, policy OK), so "socket down" means the user can
/// neither play nor get fresh server state, wherever they are.
///
/// - Only past the gate ([GatePhase.ready]). Splash, login, maintenance,
///   update and "can't reach" screens have their own handling.
/// - Shown once the connection has been lost (`reconnecting` / `offline`) for
///   [showAfter] while the app is in the foreground, so brief blips never
///   flash it. The first connection after sign-in (`connecting`) is not a
///   loss; screens show their own "connecting" state.
/// - Stays up while the socket keeps retrying and clears as soon as it is
///   `connected` again, after at least [minVisible] on screen.
/// - Never for states that waiting cannot fix or that have their own UI:
///   `idle` (signed out / stopped), `replaced` (4409, the app shell offers
///   Reconnect) and a halt on a rejected handshake (400, a client bug).
/// - A 4503/426 halt that the policy re-check did not confirm (the gate stays
///   ready, e.g. a proxy answering 503 during a deploy) would never retry on
///   its own; while blocked it is retried every [haltedRetryInterval].
class OfflineBlockController extends Notifier<bool> {
  /// How long the connection must stay lost before the overlay appears.
  static const Duration showAfter = Duration(seconds: 1);

  /// Minimum time on screen once shown (no flash when it recovers at once).
  static const Duration minVisible = Duration(milliseconds: 400);

  /// Retry cadence for an unconfirmed policy halt while blocked.
  static const Duration haltedRetryInterval = Duration(seconds: 15);

  Timer? _grace;
  Timer? _minVisible;
  Timer? _haltedRetry;

  @override
  bool build() {
    ref.listen<RealtimeStatus>(realtimeStatusProvider, (_, _) => _evaluate());
    ref.listen<GatePhase>(
      appGateControllerProvider.select((s) => s.phase),
      (_, _) => _evaluate(),
    );
    final lifecycle = ref
        .read(appLifecycleProvider)
        .changes
        .listen((_) => _evaluate());
    ref.onDispose(() {
      lifecycle.cancel();
      _grace?.cancel();
      _minVisible?.cancel();
      _haltedRetry?.cancel();
    });
    scheduleMicrotask(_evaluate);
    return false;
  }

  /// "Try now": reconnects immediately (resets the backoff, clears a halt).
  void retryNow() => ref.read(realtimeConnectionProvider).reconnectNow();

  RealtimeConnection get _connection => ref.read(realtimeConnectionProvider);

  bool get _foreground => ref.read(appLifecycleProvider).isForeground;

  /// Past the gate and the socket is trying to (re)connect.
  bool get _down {
    if (ref.read(appGateControllerProvider).phase != GatePhase.ready) {
      return false;
    }
    if (_connection.haltReason == RealtimeHaltReason.badRequest) return false;
    return switch (ref.read(realtimeStatusProvider)) {
      RealtimeStatus.connecting ||
      RealtimeStatus.reconnecting ||
      RealtimeStatus.offline => true,
      RealtimeStatus.idle ||
      RealtimeStatus.connected ||
      RealtimeStatus.replaced => false,
    };
  }

  /// [_down] after a connection was lost (not the first attempt).
  bool get _lost =>
      _down && ref.read(realtimeStatusProvider) != RealtimeStatus.connecting;

  void _evaluate() {
    if (!ref.mounted) return;
    if (state) {
      if (_down) {
        _syncHaltedRetry();
      } else if (_minVisible == null) {
        _hide();
      }
      return;
    }
    if (_lost && _foreground) {
      _grace ??= Timer(showAfter, _onGraceElapsed);
    } else if (!_down || !_foreground) {
      _cancelGrace();
    }
  }

  void _onGraceElapsed() {
    _grace = null;
    if (!ref.mounted || state || !_down || !_foreground) return;
    state = true;
    _minVisible = Timer(minVisible, () {
      _minVisible = null;
      _evaluate();
    });
    _syncHaltedRetry();
  }

  void _hide() {
    _cancelGrace();
    _haltedRetry?.cancel();
    _haltedRetry = null;
    state = false;
  }

  void _cancelGrace() {
    _grace?.cancel();
    _grace = null;
  }

  void _syncHaltedRetry() {
    if (_connection.haltReason != RealtimeHaltReason.policy) {
      _haltedRetry?.cancel();
      _haltedRetry = null;
      return;
    }
    _haltedRetry ??= Timer(haltedRetryInterval, () {
      _haltedRetry = null;
      if (!ref.mounted || !state) return;
      if (_connection.haltReason == RealtimeHaltReason.policy) retryNow();
    });
  }
}

final offlineBlockProvider = NotifierProvider<OfflineBlockController, bool>(
  OfflineBlockController.new,
);
