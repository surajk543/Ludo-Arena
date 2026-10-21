import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../seat_color.dart';

/// A tiny listenable fired once per animation frame. Painters pass it as
/// their `repaint` so frames repaint without rebuilding widgets.
class RepaintSignal extends ChangeNotifier {
  bool _disposed = false;

  /// Notifies listeners; a no-op after [dispose] (a board may detach after
  /// its controller was disposed).
  void ping() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Fixed-capacity ring buffer of recent token positions (grid units) used to
/// draw trails without per-frame allocations.
class TrailHistory {
  static const int capacity = 28;

  final Float32List _x = Float32List(capacity);
  final Float32List _y = Float32List(capacity);
  final Float32List _t = Float32List(capacity);
  int _start = 0;
  int _length = 0;

  int get length => _length;

  void clear() {
    _start = 0;
    _length = 0;
  }

  void add(double x, double y, double time) {
    if (_length > 0) {
      final last = (_start + _length - 1) % capacity;
      final dx = _x[last] - x;
      final dy = _y[last] - y;
      // Skip near-duplicate samples (resting token).
      if (dx * dx + dy * dy < 0.0004 && time - _t[last] < 0.05) return;
    }
    final index = (_start + _length) % capacity;
    _x[index] = x;
    _y[index] = y;
    _t[index] = time;
    if (_length < capacity) {
      _length++;
    } else {
      _start = (_start + 1) % capacity;
    }
  }

  /// Sample [i], 0 = oldest.
  double xAt(int i) => _x[(_start + i) % capacity];
  double yAt(int i) => _y[(_start + i) % capacity];
  double timeAt(int i) => _t[(_start + i) % capacity];
}

/// Mutable visual override for a token while it animates. Positions are in
/// grid units; [lift] raises the token above its ground point (grid units).
class TokenMotionState {
  bool active = false;
  double x = 0;
  double y = 0;
  double lift = 0;

  /// Lift normalised 0..1 (used to shrink the shadow).
  double liftFraction = 0;
  double scaleX = 1;
  double scaleY = 1;
  double opacity = 1;
  double glow = 0;
  double rotation = 0;

  /// Draw this token above resting ones.
  bool onTop = false;
  bool trailEnabled = false;
  final TrailHistory trail = TrailHistory();

  Offset get center => Offset(x, y);

  void set(double nx, double ny) {
    x = nx;
    y = ny;
  }

  void reset() {
    active = false;
    lift = 0;
    liftFraction = 0;
    scaleX = 1;
    scaleY = 1;
    opacity = 1;
    glow = 0;
    rotation = 0;
    onTop = false;
    trailEnabled = false;
    trail.clear();
  }
}

/// Visual one-shot effects drawn on the token layer.
enum BoardEffectKind {
  /// Restrained burst where a token was captured.
  captureBurst,

  /// Glow + sparkle when a token enters home.
  homeSparkle,

  /// Golden highlight burst (Snakes square 100).
  finishBurst,

  /// Subtle dust ring on landing.
  landingRing,

  /// Quick shimmer at a snake head / ladder foot.
  transitionFlash,
}

/// A scheduled effect. [center] is in grid units, times in engine seconds.
class BoardEffect {
  BoardEffect({
    required this.kind,
    required this.center,
    required this.color,
    required this.start,
    required this.duration,
    this.seed = 0,
    this.scale = 1,
    this.seatColor,
  });

  final BoardEffectKind kind;
  final Offset center;

  /// Fallback color; when [seatColor] is set painters use the active
  /// palette's tone for that seat instead.
  final Color color;
  final SeatColor? seatColor;
  final double start;
  final double duration;
  final int seed;
  final double scale;

  double progress(double now) =>
      duration <= 0 ? 1 : ((now - start) / duration).clamp(0.0, 1.0);
  bool isDone(double now) => now - start >= duration;
}

/// One queued animation. Implementations write [TokenMotionState]s and add
/// effects; [finish] must leave the final state (it is also used to snap).
abstract class MotionJob {
  final Completer<void> _completer = Completer<void>();

  /// Completes when the job finished or was snapped.
  Future<void> get done => _completer.future;

  /// Total duration in seconds (known after [begin]).
  double get duration;

  /// Called when the job starts (apply logical state, activate overrides).
  void begin(BoardMotionEngine engine);

  /// Called every frame with seconds since start, 0..[duration].
  void update(BoardMotionEngine engine, double t);

  /// Final state; clear overrides. Called exactly once.
  void finish(BoardMotionEngine engine);

  void _complete() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Drives [MotionJob]s sequentially on a single [Ticker] borrowed from the
/// attached board, plus short-lived [BoardEffect]s. The ticker only runs
/// while something animates.
class BoardMotionEngine {
  BoardMotionEngine({required this.onFrame, required this.onStateChanged});

  /// Called after every animation frame (repaint only).
  final VoidCallback onFrame;

  /// Called when logical state changes (rebuild token layer / semantics).
  final VoidCallback onStateChanged;

  Ticker? _ticker;
  final Queue<MotionJob> _queue = Queue<MotionJob>();
  MotionJob? _current;
  double _currentStart = 0;
  double _clock = 0;
  double _clockBase = 0;

  /// When true jobs should use their reduced-motion variants.
  bool reducedMotion = false;

  /// Active effects (read by painters).
  final List<BoardEffect> effects = <BoardEffect>[];

  /// Engine time in seconds (monotonic while attached).
  double get now => _clock;

  bool get attached => _ticker != null;

  bool get isAnimating => _current != null || _queue.isNotEmpty;

  /// Whether anything (job or effect) needs frames.
  bool get isActive => isAnimating || effects.isNotEmpty;

  void attach(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_tick);
    if (isActive) _ensureRunning();
  }

  /// Detaching snaps everything to its final state.
  void detach() {
    snapAll();
    _ticker?.dispose();
    _ticker = null;
  }

  /// Runs [job] after the queued ones. Without an attached board the job is
  /// applied instantly.
  Future<void> run(MotionJob job) {
    if (_ticker == null) {
      job.begin(this);
      job.finish(this);
      job._complete();
      onStateChanged();
      onFrame();
      return job.done;
    }
    _queue.add(job);
    _pump();
    return job.done;
  }

  void addEffect(BoardEffect effect) {
    if (_ticker == null) return;
    // Keep effects bounded.
    if (effects.length >= 12) effects.removeAt(0);
    effects.add(effect);
    _ensureRunning();
  }

  /// Completes all jobs at their final state and clears effects.
  void snapAll() {
    _ticker?.stop();
    _clockBase = _clock;
    final current = _current;
    _current = null;
    if (current != null) {
      current.finish(this);
      current._complete();
    }
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      job.begin(this);
      job.finish(this);
      job._complete();
    }
    effects.clear();
    onStateChanged();
    onFrame();
  }

  void _pump() {
    if (_current != null || _queue.isEmpty) return;
    final job = _queue.removeFirst();
    _current = job;
    _currentStart = _clock;
    job.begin(this);
    job.update(this, 0);
    onStateChanged();
    _ensureRunning();
  }

  void _ensureRunning() {
    final ticker = _ticker;
    if (ticker == null || ticker.isActive) return;
    _clockBase = _clock;
    ticker.start();
  }

  void _tick(Duration elapsed) {
    _clock = _clockBase + elapsed.inMicroseconds / 1e6;
    var guard = 0;
    while (_current != null && guard++ < 8) {
      final job = _current!;
      final t = _clock - _currentStart;
      if (t >= job.duration) {
        job.update(this, job.duration);
        job.finish(this);
        _current = null;
        job._complete();
        onStateChanged();
        if (_queue.isNotEmpty) {
          _pump();
          continue;
        }
      } else {
        job.update(this, t);
      }
      break;
    }
    for (var i = effects.length - 1; i >= 0; i--) {
      if (effects[i].isDone(_clock)) effects.removeAt(i);
    }
    if (!isActive) {
      _ticker?.stop();
      _clockBase = _clock;
    }
    onFrame();
  }
}

/// Easing helpers shared by the boards (allocation free).
abstract final class MotionCurves {
  static double easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  static double easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();

  static double easeIn(double t) => t * t * t;

  static double easeOutBack(double t, [double s = 1.4]) {
    final u = t - 1;
    return 1 + (s + 1) * u * u * u + s * u * u;
  }

  /// Parabolic hop height 0..1..0.
  static double hop(double t) => 4 * t * (1 - t);

  /// Squash amount 0..1: peaks at take-off and landing.
  static double squash(double t) {
    if (t < 0.12) return 1 - t / 0.12;
    if (t > 0.86) return (t - 0.86) / 0.14;
    return 0;
  }

  /// Cheap deterministic hash in 0..1.
  static double hash(int a, int b) {
    var h = a * 374761393 + b * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    h = h ^ (h >> 16);
    return (h & 0xFFFF) / 0xFFFF;
  }
}
