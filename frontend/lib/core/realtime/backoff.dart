import 'dart:math';

/// Bounded exponential backoff with full jitter
/// (websocket-protocol.md §1 "Reconnect strategy"):
///
/// `delay = random(0, min(cap, base × 2^attempt))`
///
/// The owner calls [reset] once a connection has stayed up for
/// [stableAfter] (30 s), and on app resume.
class ReconnectBackoff {
  ReconnectBackoff({
    Random? random,
    this.base = const Duration(milliseconds: 500),
    this.cap = const Duration(seconds: 30),
    this.stableAfter = const Duration(seconds: 30),
  }) : _random = random ?? Random();

  final Random _random;
  final Duration base;
  final Duration cap;

  /// How long a connection must stay up before [attempt] is reset.
  final Duration stableAfter;

  int _attempt = 0;

  /// Number of delays handed out since the last [reset].
  int get attempt => _attempt;

  /// Upper bound of the jitter window for [attempt].
  Duration ceilingFor(int attempt) {
    final exp = attempt.clamp(0, 30);
    final ms = base.inMilliseconds * (1 << exp);
    return Duration(milliseconds: min(ms, cap.inMilliseconds));
  }

  /// Next delay in `[0, ceilingFor(attempt)]`; increments [attempt].
  Duration next() {
    final ceiling = ceilingFor(_attempt).inMilliseconds;
    _attempt++;
    return Duration(milliseconds: _random.nextInt(ceiling + 1));
  }

  void reset() => _attempt = 0;
}
