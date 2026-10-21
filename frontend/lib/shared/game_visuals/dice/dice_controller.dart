import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../motion/board_motion.dart';

enum _DiceMode { idle, spin, settle, pop }

/// Drives a [DiceView]. Purely presentational: the value always comes from
/// the server.
///
/// Typical flow on a game screen:
/// 1. Player taps the dice → screen sends `game.roll_dice` and (optionally)
///    calls [beginRoll] so the die starts tumbling immediately.
/// 2. `game.dice_result` arrives → `await controller.roll(value)`; the die
///    settles exactly on `value` and the future completes.
/// 3. On a full snapshot use [show] to snap without animation.
///
/// The controller borrows a ticker from the attached view and only runs it
/// while tumbling. Without an attached view, [roll] applies the value
/// immediately.
class DiceController extends ChangeNotifier {
  DiceController({int initialValue = 1}) : _value = _clampValue(initialValue) {
    _setPose(_value);
  }

  /// Rotation applied after the body rotation (x tilt, y tilt) so the
  /// resting pose shows the front face plus the top and right faces.
  static const double tiltX = 22 * math.pi / 180;
  static const double tiltY = -28 * math.pi / 180;

  /// Seconds a [beginRoll] spin waits for [roll] before giving up.
  static const double spinTimeout = 4.0;

  static const double _settleDuration = 1.0;
  static const double _settleFromSpinDuration = 0.85;
  static const double _popDuration = 0.25;

  int _value;
  int _previousValue = 1;
  bool _rolling = false;

  /// Called when a roll animation settles, with the settled value.
  ValueChanged<int>? onSettle;

  /// Called when the die starts tumbling (sync sounds/haptics here).
  VoidCallback? onTumbleStart;

  /// Set by the attached view; rolls become a short pop when true.
  bool reducedMotion = false;

  final RepaintSignal _frames = RepaintSignal();

  /// Fires once per animation frame (painters repaint on it).
  Listenable get frames => _frames;

  /// Current server value (the target while settling).
  int get value => _value;

  /// True from [beginRoll]/[roll] until the die settled.
  bool get rolling => _rolling;

  // --- Render state (read by the painter). ---------------------------------
  double _ax = 0, _ay = 0, _az = 0;
  double _hop = 0;
  double _squash = 0;
  double _popScale = 1;
  double _opacity = 1;

  /// Euler angles (radians) of the body rotation `Rz·Ry·Rx`.
  double get angleX => _ax;
  double get angleY => _ay;
  double get angleZ => _az;

  /// Height above the ground, 0..~0.4 (fraction of the die size).
  double get hop => _hop;

  /// Impact squash 0..1.
  double get squash => _squash;

  /// Scale used by the reduced-motion pop.
  double get popScale => _popScale;

  /// Opacity used by the reduced-motion pop.
  double get opacity => _opacity;

  // --- Animation state. -----------------------------------------------------
  Ticker? _ticker;
  double _clock = 0;
  double _clockBase = 0;
  _DiceMode _mode = _DiceMode.idle;
  Completer<void>? _pending;
  final math.Random _random = math.Random();

  // Spin.
  double _spinStart = 0;
  double _sx0 = 0, _sy0 = 0, _sz0 = 0;
  double _wx = 0, _wy = 0, _wz = 0;
  double _hoverFrom = 0;

  // Settle (cubic Hermite per axis).
  double _settleStart = 0;
  double _settleDuration0 = _settleDuration;
  double _p0x = 0, _p0y = 0, _p0z = 0;
  double _m0x = 0, _m0y = 0, _m0z = 0;
  double _p1x = 0, _p1y = 0, _p1z = 0;
  double _h0 = 0;
  bool _launch = true;
  int _target = 1;

  // Pop.
  double _popStart = 0;
  bool _popSwapped = false;

  static int _clampValue(int v) => v.clamp(1, 6);

  /// Base Euler angles (x, y) bringing face [v] to the front.
  static double baseAngleX(int v) {
    switch (v) {
      case 2:
        return math.pi / 2;
      case 5:
        return -math.pi / 2;
      default:
        return 0;
    }
  }

  static double baseAngleY(int v) {
    switch (v) {
      case 6:
        return math.pi;
      case 3:
        return -math.pi / 2;
      case 4:
        return math.pi / 2;
      default:
        return 0;
    }
  }

  void _setPose(int v) {
    _ax = baseAngleX(v);
    _ay = baseAngleY(v);
    _az = 0;
    _hop = 0;
    _squash = 0;
    _popScale = 1;
    _opacity = 1;
  }

  /// Connects the controller to a view's ticker provider.
  void attach(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
    if (_mode != _DiceMode.idle) _ensureTicker();
  }

  /// Disconnects from the view, snapping to the current value.
  void detach() {
    if (_ticker == null) return;
    if (_mode != _DiceMode.idle || _rolling) _snap(_value, notify: false);
    _ticker?.dispose();
    _ticker = null;
  }

  /// Starts tumbling immediately (before the server answered). A later
  /// [roll] continues from this spin. Gives up after [spinTimeout] seconds
  /// and returns to the previous value.
  void beginRoll() {
    if (_mode == _DiceMode.spin) return;
    _previousValue = _value;
    _rolling = true;
    if (_ticker == null || reducedMotion) {
      notifyListeners();
      return;
    }
    _ensureTicker();
    _startSpin();
    onTumbleStart?.call();
    notifyListeners();
  }

  /// Animates to [serverValue] (1..6). Completes when settled.
  Future<void> roll(int serverValue) {
    assert(serverValue >= 1 && serverValue <= 6, 'dice value out of range');
    final v = _clampValue(serverValue);
    final previous = _pending;
    final completer = Completer<void>();
    _pending = completer;
    previous?.complete();
    _value = v;
    _target = v;

    if (_ticker == null) {
      _setPose(v);
      _mode = _DiceMode.idle;
      _rolling = false;
      _pending = null;
      notifyListeners();
      _frames.ping();
      onSettle?.call(v);
      completer.complete();
      return completer.future;
    }

    _rolling = true;
    _ensureTicker();
    if (reducedMotion) {
      _popStart = _clock;
      _popSwapped = false;
      _mode = _DiceMode.pop;
    } else {
      final fromSpin = _mode == _DiceMode.spin;
      if (!fromSpin && _mode == _DiceMode.idle) onTumbleStart?.call();
      _startSettle(v, fromSpin: fromSpin);
    }
    notifyListeners();
    return completer.future;
  }

  /// Snaps to [value] without animation (e.g. on a full snapshot).
  void show(int value) {
    _value = _clampValue(value);
    _snap(_value);
  }

  /// Stops any tumble and returns to the current value.
  void cancel() => _snap(_value);

  void _snap(int v, {bool notify = true}) {
    _ticker?.stop();
    _clockBase = _clock;
    _mode = _DiceMode.idle;
    _setPose(v);
    _rolling = false;
    final pending = _pending;
    _pending = null;
    pending?.complete();
    if (notify) notifyListeners();
    _frames.ping();
  }

  void _ensureTicker() {
    final ticker = _ticker;
    if (ticker == null || ticker.isActive) return;
    _clockBase = _clock;
    ticker.start();
  }

  void _startSpin() {
    _mode = _DiceMode.spin;
    _spinStart = _clock;
    _sx0 = _ax;
    _sy0 = _ay;
    _sz0 = _az;
    _hoverFrom = _hop;
    double sign() => _random.nextBool() ? 1.0 : -1.0;
    _wx = sign() * (9 + _random.nextDouble() * 4);
    _wy = sign() * (7 + _random.nextDouble() * 4);
    _wz = sign() * (2 + _random.nextDouble() * 2);
  }

  /// Picks the end angle `base + 2πk` for one axis so that a cubic Hermite
  /// with start tangent [m0] (and zero end tangent) stays monotonic and
  /// decelerates naturally.
  static double _pickEnd(double p0, double m0, double base) {
    const twoPi = 2 * math.pi;
    if (m0.abs() < 0.5) {
      final k = ((p0 - base) / twoPi).roundToDouble();
      return base + k * twoPi;
    }
    final want = p0 + 0.45 * m0;
    if (m0 > 0) {
      final k = ((want - base) / twoPi).ceilToDouble();
      return base + k * twoPi;
    } else {
      final k = ((want - base) / twoPi).floorToDouble();
      return base + k * twoPi;
    }
  }

  void _startSettle(int v, {required bool fromSpin}) {
    double wx, wy, wz;
    if (fromSpin) {
      wx = _wx;
      wy = _wy;
      wz = _wz;
    } else {
      double sign() => _random.nextBool() ? 1.0 : -1.0;
      wx = sign() * (10 + _random.nextDouble() * 5);
      wy = sign() * (8 + _random.nextDouble() * 5);
      wz = sign() * (2 + _random.nextDouble() * 3);
    }
    final d = fromSpin ? _settleFromSpinDuration : _settleDuration;
    _settleDuration0 = d;
    _p0x = _ax;
    _p0y = _ay;
    _p0z = _az;
    _m0x = wx * d;
    _m0y = wy * d;
    _m0z = wz * d;
    _p1x = _pickEnd(_p0x, _m0x, baseAngleX(v));
    _p1y = _pickEnd(_p0y, _m0y, baseAngleY(v));
    _p1z = _pickEnd(_p0z, _m0z, 0);
    _h0 = _hop;
    _launch = !fromSpin;
    _settleStart = _clock;
    _mode = _DiceMode.settle;
  }

  static double _hermite(double p0, double m0, double p1, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * p0 +
        (t3 - 2 * t2 + t) * m0 +
        (-2 * t3 + 3 * t2) * p1;
  }

  // Bounce schedule as fractions of the settle duration.
  static const double _e1 = 0.42;
  static const double _e2 = 0.66;
  static const double _e3 = 0.8;

  double _heightAt(double u) {
    if (u < _e1) {
      final s = u / _e1;
      return _launch ? 0.36 * 4 * s * (1 - s) : _h0 * (1 - s * s);
    }
    if (u < _e2) {
      final s = (u - _e1) / (_e2 - _e1);
      return 0.12 * 4 * s * (1 - s);
    }
    if (u < _e3) {
      final s = (u - _e2) / (_e3 - _e2);
      return 0.04 * 4 * s * (1 - s);
    }
    return 0;
  }

  double _squashAt(double u) {
    double env(double e, double strength) {
      if (u < e) return 0;
      final k = 1 - (u - e) / 0.08;
      return k > 0 ? strength * k : 0;
    }

    return math.max(env(_e1, 1), math.max(env(_e2, 0.5), env(_e3, 0.2)));
  }

  void _onTick(Duration elapsed) {
    _clock = _clockBase + elapsed.inMicroseconds / 1e6;
    switch (_mode) {
      case _DiceMode.idle:
        _ticker?.stop();
        _clockBase = _clock;
      case _DiceMode.spin:
        final t = _clock - _spinStart;
        _ax = _sx0 + _wx * t;
        _ay = _sy0 + _wy * t;
        _az = _sz0 + _wz * t;
        final rise = t < 0.25 ? MotionCurves.easeOut(t / 0.25) : 1.0;
        _hop = _hoverFrom + (0.22 - _hoverFrom) * rise + 0.03 * math.sin(t * 7);
        _squash = 0;
        if (t > spinTimeout) {
          // No server value arrived: settle back to the previous value.
          _value = _previousValue;
          _target = _previousValue;
          _startSettle(_previousValue, fromSpin: true);
        }
      case _DiceMode.settle:
        final u = ((_clock - _settleStart) / _settleDuration0).clamp(0.0, 1.0);
        _ax = _hermite(_p0x, _m0x, _p1x, u);
        _ay = _hermite(_p0y, _m0y, _p1y, u);
        _az = _hermite(_p0z, _m0z, _p1z, u);
        _hop = _heightAt(u);
        _squash = _squashAt(u);
        if (u >= 1) _finishSettle();
      case _DiceMode.pop:
        final u = ((_clock - _popStart) / _popDuration).clamp(0.0, 1.0);
        if (u >= 0.5 && !_popSwapped) {
          _popSwapped = true;
          _ax = baseAngleX(_target);
          _ay = baseAngleY(_target);
          _az = 0;
        }
        _hop = 0;
        _squash = 0;
        _popScale = 1 - 0.16 * math.sin(math.pi * u);
        _opacity = 0.55 + 0.45 * (math.cos(math.pi * u)).abs();
        if (u >= 1) _finishSettle();
    }
    _frames.ping();
  }

  void _finishSettle() {
    final v = _target;
    _setPose(v);
    _mode = _DiceMode.idle;
    _ticker?.stop();
    _clockBase = _clock;
    final wasRolling = _rolling;
    _rolling = false;
    final pending = _pending;
    _pending = null;
    notifyListeners();
    _frames.ping();
    if (wasRolling && pending != null) onSettle?.call(v);
    pending?.complete();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    final pending = _pending;
    _pending = null;
    pending?.complete();
    _frames.dispose();
    super.dispose();
  }
}
