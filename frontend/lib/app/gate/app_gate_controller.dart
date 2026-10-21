import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_providers.dart';
import '../../core/app_policy/app_policy_repository.dart';
import '../../core/app_policy/policy_signal.dart';
import '../../core/lifecycle/app_lifecycle.dart';
import '../../core/localization/language_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/state/in_match_provider.dart';
import '../../core/storage/preferences_store.dart';
import '../../core/time/server_clock.dart';
import '../../features/authentication/application/session_controller.dart';

/// Startup / access state machine (docs/app-version-policy.md):
///
/// ```
/// initializing → checkingPolicy → maintenance | forceUpdate | unreachable
///                               | (optionalUpdatePrompt →) restoringSession
/// restoringSession → loadingWallet → ready      (or → signedOut → login)
/// ```
///
/// No home/game route is reachable before [GatePhase.ready].
enum GatePhase {
  initializing,
  checkingPolicy,
  maintenance,
  forceUpdate,
  unreachable,
  optionalUpdatePrompt,
  restoringSession,
  signedOut,
  loadingWallet,
  ready;

  /// Full-screen blocking states.
  bool get isBlocking =>
      this == maintenance || this == forceUpdate || this == unreachable;

  /// Splash is shown for these.
  bool get isTransient =>
      this == initializing ||
      this == checkingPolicy ||
      this == optionalUpdatePrompt ||
      this == restoringSession ||
      this == loadingWallet;

  /// The policy allowed access for this launch.
  bool get isPastPolicy =>
      this == restoringSession ||
      this == signedOut ||
      this == loadingWallet ||
      this == ready;
}

@immutable
class GateState {
  const GateState({
    this.phase = GatePhase.initializing,
    this.policy,
    this.cachedPolicy,
    this.rechecking = false,
    this.lastCheckedAt,
    this.optionalPromptPending = false,
  });

  final GatePhase phase;

  /// Policy fetched during this launch.
  final AppPolicy? policy;

  /// Last policy cached from a previous launch — display context only.
  final AppPolicy? cachedPolicy;

  /// A background re-check is running (blocking screens show progress).
  final bool rechecking;
  final DateTime? lastCheckedAt;

  /// An optional-update dialog should be shown over the current screen
  /// (post-startup; never while in a match).
  final bool optionalPromptPending;

  GateState copyWith({
    GatePhase? phase,
    AppPolicy? policy,
    AppPolicy? cachedPolicy,
    bool? rechecking,
    DateTime? lastCheckedAt,
    bool? optionalPromptPending,
  }) => GateState(
    phase: phase ?? this.phase,
    policy: policy ?? this.policy,
    cachedPolicy: cachedPolicy ?? this.cachedPolicy,
    rechecking: rechecking ?? this.rechecking,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    optionalPromptPending: optionalPromptPending ?? this.optionalPromptPending,
  );
}

class AppGateController extends Notifier<GateState> {
  /// Resume re-checks are throttled to one per this interval (except on
  /// blocking screens and after visiting the store).
  static const Duration resumeThrottle = Duration(seconds: 30);

  /// Automatic re-check cadence on the maintenance screen.
  static const Duration maintenanceRecheck = Duration(seconds: 30);

  bool _started = false;
  Future<void>? _inflight;
  bool _queued = false;
  DateTime? _lastCheckStarted;
  bool _returningFromStore = false;
  bool _optionalShownThisLaunch = false;
  bool _forcePromptLogged = false;
  Timer? _maintenanceTimer;

  NowFn get _now => ref.read(clockProvider);

  @override
  GateState build() {
    final subs = <StreamSubscription<dynamic>>[
      ref.read(policySignalBusProvider).signals.listen(_onPolicySignal),
      ref.read(appLifecycleProvider).resumed.listen((_) => _onResume()),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      _maintenanceTimer?.cancel();
    });
    ref.listen<SessionState>(sessionControllerProvider, _onSessionChanged);
    ref.listen<bool>(inMatchProvider, (_, inMatch) {
      if (!inMatch) _maybeQueueOptionalPrompt();
    });
    return GateState(cachedPolicy: ref.read(policyCacheProvider).read());
  }

  // ------------------------------------------------------------ public API

  /// Starts the machine (called once by the app shell after first frame).
  Future<void> start() {
    if (_started) return _inflight ?? Future.value();
    _started = true;
    return _check(startup: true);
  }

  /// Retry button on blocking screens.
  Future<void> retry() => _check();

  /// Call right before opening the store so the next resume re-checks
  /// immediately (bypassing the throttle).
  void markVisitingStore() => _returningFromStore = true;

  /// The optional-update dialog was answered. [later] stores the reminder
  /// deferral for `optionalUpdateReminderHours`, keyed by `latestVersion`.
  Future<void> resolveOptionalUpdate({required bool later}) async {
    _optionalShownThisLaunch = true;
    final policy = state.policy;
    if (later && policy != null) {
      final prefs = ref.read(preferencesStoreProvider);
      final until = _now().add(
        Duration(hours: policy.optionalUpdateReminderHours.clamp(1, 24 * 30)),
      );
      await prefs.setString(
        PrefKeys.optionalUpdateDeferredVersion,
        policy.latestVersion,
      );
      await prefs.setInt(
        PrefKeys.optionalUpdateDeferredUntil,
        until.millisecondsSinceEpoch,
      );
    }
    if (!ref.mounted) return;
    final wasPrompt = state.phase == GatePhase.optionalUpdatePrompt;
    _set(state.copyWith(optionalPromptPending: false));
    if (wasPrompt) await _proceedToSession();
  }

  // ------------------------------------------------------------ triggers

  void _onResume() {
    if (!_started) return;
    final blocking = state.phase.isBlocking;
    final last = _lastCheckStarted;
    final due = last == null || _now().difference(last) >= resumeThrottle;
    if (blocking || _returningFromStore || due) {
      _returningFromStore = false;
      unawaited(_check());
    }
  }

  void _onPolicySignal(PolicySignalReason reason) {
    if (!_started) return;
    if (reason == PolicySignalReason.wsHandshakeFailed) {
      final last = _lastCheckStarted;
      if (last != null && _now().difference(last) < resumeThrottle) return;
    }
    unawaited(_check());
  }

  void _onSessionChanged(SessionState? previous, SessionState next) {
    if (!_started) return;
    final phase = state.phase;
    if (next.isSignedIn && phase == GatePhase.signedOut) {
      unawaited(_loadAccount());
    } else if (next.status == SessionStatus.signedOut &&
        (phase == GatePhase.ready || phase == GatePhase.loadingWallet)) {
      _set(state.copyWith(phase: GatePhase.signedOut));
    }
  }

  // ------------------------------------------------------------ policy

  /// Coalesces concurrent checks; a check requested while one runs is
  /// queued once so the newest server state always wins.
  Future<void> _check({bool startup = false}) async {
    if (_inflight != null) {
      _queued = true;
      return _inflight;
    }
    final future = _runChecks(startup);
    _inflight = future;
    try {
      await future;
    } finally {
      if (identical(_inflight, future)) _inflight = null;
    }
  }

  Future<void> _runChecks(bool startup) async {
    var first = true;
    do {
      _queued = false;
      await _checkOnce(startup: startup && first);
      first = false;
    } while (_queued && ref.mounted);
  }

  Future<void> _checkOnce({required bool startup}) async {
    if (!ref.mounted) return;
    _lastCheckStarted = _now();
    final phase = state.phase;
    if (startup || phase == GatePhase.initializing) {
      _set(state.copyWith(phase: GatePhase.checkingPolicy));
    } else {
      _set(state.copyWith(rechecking: true));
    }

    final AppPolicy policy;
    try {
      policy = await ref
          .read(appPolicyRepositoryProvider)
          .fetch(locale: ref.read(languageControllerProvider).languageCode);
    } on ApiException {
      _onPolicyUnavailable();
      return;
    } catch (e) {
      debugPrint('gate: policy fetch failed ($e)');
      _onPolicyUnavailable();
      return;
    }
    if (!ref.mounted) return;

    unawaited(ref.read(policyCacheProvider).write(policy));
    if (policy.serverTime > 0) {
      ref.read(serverClockProvider).sample(policy.serverTime);
    }
    _set(
      state.copyWith(policy: policy, rechecking: false, lastCheckedAt: _now()),
    );

    switch (policy.mode) {
      case PolicyMode.maintenance:
        _enterBlocking(GatePhase.maintenance);
      case PolicyMode.forceUpdate:
        _enterBlocking(GatePhase.forceUpdate);
        if (!_forcePromptLogged) {
          _forcePromptLogged = true;
          ref
              .read(analyticsServiceProvider)
              .appUpdatePromptShown('force_update');
        }
      case PolicyMode.optionalUpdate:
        if (!state.phase.isPastPolicy && _shouldPromptOptional(policy)) {
          _stopMaintenanceTimer();
          _set(state.copyWith(phase: GatePhase.optionalUpdatePrompt));
          ref
              .read(analyticsServiceProvider)
              .appUpdatePromptShown('optional_update');
          return;
        }
        await _leaveBlocking();
        _maybeQueueOptionalPrompt();
      case PolicyMode.normal:
        await _leaveBlocking();
    }
  }

  void _onPolicyUnavailable() {
    if (!ref.mounted) return;
    final phase = state.phase;
    // Once access was granted for this launch, a failed background re-check
    // does not kick the user out (the realtime indicator shows offline).
    if (phase.isPastPolicy ||
        phase == GatePhase.maintenance ||
        phase == GatePhase.forceUpdate) {
      _set(state.copyWith(rechecking: false, lastCheckedAt: _now()));
      return;
    }
    _set(
      state.copyWith(
        phase: GatePhase.unreachable,
        rechecking: false,
        lastCheckedAt: _now(),
      ),
    );
  }

  bool _shouldPromptOptional(AppPolicy policy) {
    if (_optionalShownThisLaunch) return false;
    final prefs = ref.read(preferencesStoreProvider);
    final deferredVersion = prefs.getString(
      PrefKeys.optionalUpdateDeferredVersion,
    );
    final until = prefs.getInt(PrefKeys.optionalUpdateDeferredUntil) ?? 0;
    if (deferredVersion == policy.latestVersion &&
        _now().millisecondsSinceEpoch < until) {
      return false;
    }
    return true;
  }

  /// Post-startup optional update: show a dialog over the current screen
  /// unless the user is in a match (re-evaluated when the match ends).
  void _maybeQueueOptionalPrompt() {
    final policy = state.policy;
    if (policy == null ||
        policy.mode != PolicyMode.optionalUpdate ||
        state.phase != GatePhase.ready ||
        state.optionalPromptPending ||
        ref.read(inMatchProvider) ||
        !_shouldPromptOptional(policy)) {
      return;
    }
    _set(state.copyWith(optionalPromptPending: true));
    ref.read(analyticsServiceProvider).appUpdatePromptShown('optional_update');
  }

  void _enterBlocking(GatePhase phase) {
    _set(state.copyWith(phase: phase, optionalPromptPending: false));
    if (phase == GatePhase.maintenance) {
      _maintenanceTimer ??= Timer.periodic(maintenanceRecheck, (_) {
        if (state.phase == GatePhase.maintenance) unawaited(_check());
      });
    } else {
      _stopMaintenanceTimer();
    }
  }

  void _stopMaintenanceTimer() {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
  }

  Future<void> _leaveBlocking() async {
    _stopMaintenanceTimer();
    if (state.phase.isPastPolicy) return;
    await _proceedToSession();
  }

  // ------------------------------------------------------------ session

  Future<void> _proceedToSession() async {
    if (!ref.mounted) return;
    final session = ref.read(sessionControllerProvider);
    if (session.isSignedIn) {
      await _loadAccount();
      return;
    }
    _set(state.copyWith(phase: GatePhase.restoringSession));
    final outcome = await ref
        .read(sessionControllerProvider.notifier)
        .restore();
    if (!ref.mounted) return;
    switch (outcome) {
      case RestoreOutcome.restored:
        await _loadAccount();
      case RestoreOutcome.signedOut:
        _set(state.copyWith(phase: GatePhase.signedOut));
      case RestoreOutcome.networkError:
        _set(state.copyWith(phase: GatePhase.unreachable));
      case RestoreOutcome.policyBlocked:
        _set(state.copyWith(phase: GatePhase.checkingPolicy));
        _queued = true;
    }
  }

  Future<void> _loadAccount() async {
    if (!ref.mounted) return;
    _set(state.copyWith(phase: GatePhase.loadingWallet));
    try {
      await ref.read(sessionControllerProvider.notifier).refreshMe();
      if (!ref.mounted) return;
      if (!ref.read(sessionControllerProvider).isSignedIn) {
        _set(state.copyWith(phase: GatePhase.signedOut));
        return;
      }
      _set(state.copyWith(phase: GatePhase.ready));
      _maybeQueueOptionalPrompt();
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      if (e.isPolicyBlock) {
        // The ApiClient already signalled; make sure a check follows.
        _set(state.copyWith(phase: GatePhase.checkingPolicy));
        if (_inflight != null) {
          _queued = true;
        } else {
          unawaited(_check());
        }
      } else if (e.isUnauthorized) {
        _set(state.copyWith(phase: GatePhase.signedOut));
      } else {
        _set(state.copyWith(phase: GatePhase.unreachable));
      }
    }
  }

  void _set(GateState s) {
    if (ref.mounted) state = s;
  }
}

final appGateControllerProvider =
    NotifierProvider<AppGateController, GateState>(AppGateController.new);
