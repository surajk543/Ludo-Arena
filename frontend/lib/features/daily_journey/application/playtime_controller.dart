import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lifecycle/app_lifecycle.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/time/server_clock.dart';
import '../../authentication/application/session_controller.dart';
import '../data/playtime_api.dart';

/// Today's playtime as last confirmed by the server.
@immutable
class PlaytimeState {
  const PlaytimeState({
    this.playtime,
    this.loading = false,
    this.failed = false,
    this.disabled = false,
  });

  /// Null until the first server value (or while disabled / signed out).
  final Playtime? playtime;

  /// A fetch is in flight.
  final bool loading;

  /// The last fetch failed: [playtime], if any, may be out of date.
  final bool failed;

  /// The server has daily playtime switched off (`GET /playtime` → 404).
  final bool disabled;

  PlaytimeState copyWith({
    Playtime? playtime,
    bool? loading,
    bool? failed,
    bool? disabled,
  }) => PlaytimeState(
    playtime: playtime ?? this.playtime,
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    disabled: disabled ?? this.disabled,
  );
}

/// Today's server-counted playtime for the signed-in account.
///
/// Seeded by `GET /playtime` once the session is ready, then kept current
/// by `playtime.updated` pushes and `GET /missions` (which embeds the same
/// object). Refetches after a reconnect and when the app returns to the
/// foreground; widgets showing the reset time call [refresh] when the day
/// rolls over (`resetsAtUtc`, server clock). Values are merged with [Playtime.merge]: within a day `seconds` never
/// decreases, so out-of-order pushes cannot move the progress backwards.
class PlaytimeController extends Notifier<PlaytimeState> {
  /// Fetches closer together than this are coalesced (start-up fires the
  /// session seed and the first `connected` almost at once).
  static const minRefetchGap = Duration(seconds: 2);

  Future<void>? _inFlight;
  DateTime? _lastFetch;
  String? _userId;

  @override
  PlaytimeState build() {
    ref.listen<AsyncValue<PlaytimeUpdatedEvent>>(playtimeUpdatesProvider, (
      _,
      next,
    ) {
      final e = next.value;
      if (e != null) applyServer(e.playtime);
    });
    ref.listen<RealtimeStatus>(realtimeStatusProvider, (prev, next) {
      // Pushes sent while the socket was down were missed: catch up.
      if (next == RealtimeStatus.connected && prev != next) {
        unawaited(refresh(force: false));
      }
    });
    final sub = ref
        .watch(appLifecycleProvider)
        .resumed
        .listen((_) => unawaited(refresh(force: false)));
    ref.onDispose(sub.cancel);

    _userId = ref.watch(
      sessionControllerProvider.select((s) => s.isSignedIn ? s.user?.id : null),
    );
    _inFlight = null;
    _lastFetch = null;
    if (_userId == null) return const PlaytimeState();
    Future.microtask(() {
      if (ref.mounted) unawaited(refresh());
    });
    return const PlaytimeState(loading: true);
  }

  /// `GET /playtime`. Never throws: a failure keeps the previous value and
  /// marks it [PlaytimeState.failed]. [force] = false skips a fetch right
  /// after another one.
  Future<void> refresh({bool force = true}) {
    if (_userId == null) return Future.value();
    final pending = _inFlight;
    if (pending != null) return pending;
    final now = ref.read(clockProvider)();
    final last = _lastFetch;
    if (!force && last != null && now.difference(last) < minRefetchGap) {
      return Future.value();
    }
    _lastFetch = now;
    final user = _userId;
    final future = _fetch(user);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _fetch(String? user) async {
    if (state.playtime == null && !state.loading) {
      state = state.copyWith(loading: true);
    }
    try {
      final p = await ref.read(playtimeApiProvider).fetch();
      if (!ref.mounted || user != _userId) return;
      if (p == null) {
        state = const PlaytimeState(disabled: true);
        return;
      }
      _set(p);
    } catch (_) {
      if (!ref.mounted || user != _userId) return;
      state = state.copyWith(loading: false, failed: true);
    }
  }

  /// Applies a server value (push, `GET /missions` or a fetch).
  void applyServer(Playtime p) {
    if (_userId == null || p.periodKey.isEmpty) return;
    _set(p);
  }

  void _set(Playtime p) {
    final current = state.playtime;
    final merged = current == null ? p : current.merge(p);
    state = PlaytimeState(playtime: merged);
  }
}

final playtimeControllerProvider =
    NotifierProvider<PlaytimeController, PlaytimeState>(PlaytimeController.new);
