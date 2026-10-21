import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable wall clock (overridden in tests).
typedef NowFn = DateTime Function();

final clockProvider = Provider<NowFn>((ref) => DateTime.now);

/// Estimates the server clock from `serverTime` samples (app config,
/// `connection.ready`, `pong.ts`). Turn deadlines are server unix ms, so
/// countdowns must use [nowMs], never the raw device clock.
class ServerClock {
  ServerClock([NowFn? now]) : _now = now ?? DateTime.now;

  final NowFn _now;
  int _offsetMs = 0;
  bool _hasSample = false;

  /// server − device, in milliseconds.
  int get offsetMs => _offsetMs;
  bool get hasSample => _hasSample;

  /// Records a server timestamp. [roundTrip] (if known) halves the latency
  /// error. Smooths subsequent samples to avoid countdown jitter.
  void sample(int serverMs, {Duration roundTrip = Duration.zero}) {
    if (serverMs <= 0) return;
    final local = _now().millisecondsSinceEpoch;
    final measured = serverMs + roundTrip.inMilliseconds ~/ 2 - local;
    if (!_hasSample || (measured - _offsetMs).abs() > 2000) {
      _offsetMs = measured;
    } else {
      _offsetMs = (_offsetMs * 0.7 + measured * 0.3).round();
    }
    _hasSample = true;
  }

  /// Estimated current server time (unix ms).
  int nowMs() => _now().millisecondsSinceEpoch + _offsetMs;

  /// Time remaining until a server-clock [deadlineMs] (never negative).
  Duration remainingUntil(int deadlineMs) {
    final ms = deadlineMs - nowMs();
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  /// Converts a server unix-ms instant to local device time.
  DateTime toLocal(int serverMs) =>
      DateTime.fromMillisecondsSinceEpoch(serverMs - _offsetMs);
}

final serverClockProvider = Provider<ServerClock>(
  (ref) => ServerClock(ref.watch(clockProvider)),
);
