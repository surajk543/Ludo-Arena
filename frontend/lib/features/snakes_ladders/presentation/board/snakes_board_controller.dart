import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../../shared/game_visuals/game_palette.dart';
import '../../../../shared/game_visuals/motion/board_motion.dart';
import 'snakes_geometry.dart';

/// Drives the Snakes & Ladders token layer.
///
/// The game screen feeds it server-confirmed state only:
/// * [setPositions] on every full snapshot (`game.started`, `game.state`,
///   `room.updated`) — snaps, cancelling animations;
/// * [animateMove] for each `game.move_applied` (pass `landing` and
///   `transition` straight from the event) and await it before applying the
///   next event;
/// * [setTurnSeat] on `game.turn_changed`.
///
/// [positions] always reflects every command immediately (logical state);
/// the board renders a separate display state that catches up as queued
/// animations play. Concurrent [animateMove] calls run sequentially.
///
/// Event hooks ([onStep], [onLadder], [onSnake], [onFinish]) fire in sync
/// with the animation (in a microtask right after the frame) so the screen
/// can play sounds and haptics. They are not fired when no board is attached
/// (moves then apply instantly) or for snapped moves.
class SnakesBoardController extends ChangeNotifier {
  SnakesBoardController({
    required List<SeatColor> seatColors,
    required List<int> positions,
  }) : _seatColors = List<SeatColor>.unmodifiable(seatColors),
       _target = _normalize(positions, seatColors.length),
       _display = _normalize(positions, seatColors.length),
       _motion = List<TokenMotionState>.generate(
         seatColors.length,
         (_) => TokenMotionState(),
       ),
       _moveScale = List<double>.filled(seatColors.length, 1) {
    _engine = BoardMotionEngine(
      onFrame: _frames.ping,
      onStateChanged: _stateChanged,
    );
  }

  final List<SeatColor> _seatColors;
  final List<int> _target;
  final List<int> _display;
  final List<TokenMotionState> _motion;
  final List<double> _moveScale;
  final RepaintSignal _frames = RepaintSignal();
  late final BoardMotionEngine _engine;
  TickerProvider? _vsync;
  int? _turnSeat;
  int _revision = 0;
  bool _disposed = false;

  /// Called when a token lands on a square during a step-by-step move.
  void Function(int seat, int square)? onStep;

  /// Called when a token starts sliding down a snake (head → tail).
  void Function(int seat, int from, int to)? onSnake;

  /// Called when a token starts climbing a ladder (foot → top).
  void Function(int seat, int from, int to)? onLadder;

  /// Called when a token reaches square 100.
  void Function(int seat)? onFinish;

  static List<int> _normalize(List<int> positions, int seats) =>
      List<int>.generate(
        seats,
        (i) => i < positions.length ? positions[i].clamp(0, 100) : 0,
      );

  /// Seat colors, index = seat.
  List<SeatColor> get seatColors => _seatColors;

  int get seatCount => _seatColors.length;

  /// Logical positions (all commands applied), index = seat. 0 = off board.
  List<int> get positions => List<int>.unmodifiable(_target);

  int? get turnSeat => _turnSeat;

  /// Per-frame repaint signal for the token layer.
  Listenable get frames => _frames;

  /// Whether a move animation is playing or queued.
  bool get isAnimating => _engine.isAnimating;

  /// Increments on every logical/display change (used by painters).
  int get revision => _revision;

  /// Engine time and active effects (for the token painter).
  double get now => _engine.now;
  List<BoardEffect> get effects => _engine.effects;

  /// Attaches the board's ticker provider. Calling again with the same
  /// [vsync] only updates [reducedMotion].
  void attach(TickerProvider vsync, {bool reducedMotion = false}) {
    _engine.reducedMotion = reducedMotion;
    if (identical(_vsync, vsync) && _engine.attached) return;
    _vsync = vsync;
    _engine.attach(vsync);
  }

  /// Detaches from the board; running animations snap to their end.
  void detach() {
    _vsync = null;
    _engine.detach();
  }

  /// Snaps to [positions] (full snapshot); cancels animations and completes
  /// their futures.
  void setPositions(List<int> positions) {
    _engine.snapAll();
    final next = _normalize(positions, seatCount);
    for (var i = 0; i < seatCount; i++) {
      _target[i] = next[i];
      _display[i] = next[i];
      _motion[i].reset();
      _moveScale[i] = 1;
    }
    _stateChanged();
    _frames.ping();
  }

  /// Highlights [seat] as the player whose turn it is (null = none).
  void setTurnSeat(int? seat) {
    if (_turnSeat == seat) return;
    _turnSeat = seat;
    _stateChanged();
    _frames.ping();
  }

  /// Animates `game.move_applied`: hops from [from] to [landing] (defaults
  /// to [to], or to `transition.from`), then climbs/slides along the
  /// [transition] to [to]. Completes when the animation ends (immediately
  /// without an attached board).
  Future<void> animateMove({
    required int seat,
    required int from,
    required int to,
    int? landing,
    ({String kind, int from, int to})? transition,
  }) {
    if (seat < 0 || seat >= seatCount) return Future<void>.value();
    final f = from.clamp(0, 100);
    final t = to.clamp(0, 100);
    final land = (landing ?? transition?.from ?? t).clamp(0, 100);
    _target[seat] = t;
    var kind = _Transition.none;
    if (land != t) {
      final k = transition?.kind;
      if (k == 'ladder' || SnakesGeometry.ladders[land] == t) {
        kind = SnakesGeometry.ladders.containsKey(land)
            ? _Transition.ladder
            : _Transition.jump;
      } else if (k == 'snake' || SnakesGeometry.snakes[land] == t) {
        kind = SnakesGeometry.snakes.containsKey(land)
            ? _Transition.snake
            : _Transition.jump;
      } else {
        kind = _Transition.jump;
      }
    }
    return _engine.run(_SnakesMoveJob(this, seat, f, t, land, kind));
  }

  /// Jumps every token to its final (logical) position and completes all
  /// pending animation futures. Use when a full snapshot arrives.
  void cancelAndSnap() {
    _engine.snapAll();
    for (var i = 0; i < seatCount; i++) {
      _display[i] = _target[i];
      _motion[i].reset();
      _moveScale[i] = 1;
    }
    _stateChanged();
    _frames.ping();
  }

  // ---------------------------------------------------------------------------
  // Rendering accessors.

  /// Square currently displayed for [seat] (may lag [positions] while
  /// animations are queued).
  int displayedSquare(int seat) => _display[seat];

  /// Live motion override of [seat] (active while it animates).
  TokenMotionState motionOf(int seat) => _motion[seat];

  /// Where [seat]'s token rests (grid units), including fan-out when
  /// several tokens share a square.
  Offset restingCenter(int seat) =>
      _fanCenter(seat, _display[seat], includeSelf: true);

  /// Size factor of [seat]'s resting token (fan-out shrinks tokens).
  double restingScale(int seat) =>
      _fanScale(seat, _display[seat], includeSelf: true);

  /// The token's current visual center in grid units.
  Offset debugVisualCenter(int seat) {
    final m = _motion[seat];
    return m.active ? m.center : restingCenter(seat);
  }

  /// The token's current size factor.
  double visualScale(int seat) =>
      _motion[seat].active ? _moveScale[seat] : restingScale(seat);

  static const List<double> _fanX2 = [-0.21, 0.21];
  static const List<double> _fanX3 = [-0.21, 0.21, 0];
  static const List<double> _fanY3 = [-0.1, -0.1, 0.15];
  static const List<double> _fanX4 = [-0.21, 0.21, -0.21, 0.21];
  static const List<double> _fanY4 = [-0.14, -0.14, 0.16, 0.16];

  /// Group size and rank of [seat] among resting tokens on [square].
  (int, int) _group(int seat, int square, {required bool includeSelf}) {
    var n = 0;
    var rank = 0;
    for (var s = 0; s < seatCount; s++) {
      final member = s == seat
          ? includeSelf
          : (!_motion[s].active && _display[s] == square);
      if (!member) continue;
      if (s < seat) rank++;
      n++;
    }
    return (math.max(n, 1), rank);
  }

  Offset _fanCenter(int seat, int square, {required bool includeSelf}) {
    if (square <= 0) return SnakesGeometry.startSlot(seat);
    final c = SnakesGeometry.centerOf(square);
    final (n, rank) = _group(seat, square, includeSelf: includeSelf);
    switch (n) {
      case 1:
        return c;
      case 2:
        return c.translate(_fanX2[rank], 0);
      case 3:
        return c.translate(_fanX3[rank], _fanY3[rank]);
      default:
        final r = math.min(rank, 3);
        return c.translate(_fanX4[r], _fanY4[r]);
    }
  }

  double _fanScale(int seat, int square, {required bool includeSelf}) {
    if (square <= 0) return SnakesGeometry.startTokenScale;
    final (n, _) = _group(seat, square, includeSelf: includeSelf);
    switch (n) {
      case 1:
        return 1;
      case 2:
        return 0.78;
      case 3:
        return 0.7;
      default:
        return 0.62;
    }
  }

  /// Seat accent used for effects.
  Color _seatColorFor(int seat) => GamePalette.light.seat(_seatColors[seat]);

  void _stateChanged() {
    if (_disposed) return;
    _revision++;
    notifyListeners();
  }

  void _emit(VoidCallback callback) {
    scheduleMicrotask(() {
      if (!_disposed) callback();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _engine.detach();
    _frames.dispose();
    super.dispose();
  }
}

enum _Transition { none, ladder, snake, jump }

/// One `move_applied` animation: hops → (ladder climb | snake slide |
/// jump) → settle.
class _SnakesMoveJob extends MotionJob {
  _SnakesMoveJob(
    this.c,
    this.seat,
    this.from,
    this.to,
    this.landing,
    this.kind,
  );

  final SnakesBoardController c;
  final int seat;
  final int from;
  final int to;
  final int landing;
  final _Transition kind;

  static const double _hop = 0.17;
  static const double _firstHopFromStart = 0.26;
  static const double _pause = 0.08;
  static const double _settle = 0.14;

  bool _reduced = false;
  List<int> _squares = const [];
  List<Offset> _points = const [];
  double _firstHop = _hop;
  double _hopsEnd = 0;
  double _transStart = 0;
  double _transDur = 0;
  double _duration = 0;
  Offset _start = Offset.zero;
  Offset _land = Offset.zero;
  Offset _end = Offset.zero;
  Offset _transEndPoint = Offset.zero;
  double _scaleFrom = 1;
  double _scaleTo = 1;
  SnakeBody? _snake;
  LadderRails? _ladder;
  List<double> _stops = const [];
  int _stepsFired = 0;
  bool _landed = false;
  bool _transFired = false;
  bool _finishFired = false;

  @override
  double get duration => _duration;

  TokenMotionState get _m => c._motion[seat];

  @override
  void begin(BoardMotionEngine engine) {
    _reduced = engine.reducedMotion;
    final wasResting = c._display[seat] == from && !_m.active;
    _start = wasResting
        ? c.restingCenter(seat)
        : SnakesGeometry.positionCenter(from, seat: seat);
    _scaleFrom = wasResting ? c.restingScale(seat) : 1;

    c._display[seat] = to;
    final m = _m..reset();
    m.active = true;
    m.onTop = true;
    m.trailEnabled = !_reduced;
    m.set(_start.dx, _start.dy);

    _end = c._fanCenter(seat, to, includeSelf: true);
    _scaleTo = c._fanScale(seat, to, includeSelf: true);
    _squares = SnakesGeometry.stepPath(from, landing);
    _land = landing <= 0
        ? _start
        : (kind == _Transition.none ? _end : SnakesGeometry.centerOf(landing));
    _points = [
      _start,
      for (var i = 0; i < _squares.length; i++)
        i == _squares.length - 1 ? _land : SnakesGeometry.centerOf(_squares[i]),
    ];
    if (_squares.isEmpty) _land = _start;
    _transEndPoint = _land;

    if (kind == _Transition.ladder) {
      _ladder = SnakesGeometry.ladderRails(landing);
      _stops = [0, ..._ladder!.rungTs, 1];
      _transEndPoint = _ladder!.head;
    } else if (kind == _Transition.snake) {
      _snake = SnakesGeometry.snakeBody(landing);
      _transEndPoint = _snake!.pointAt(1);
    } else if (kind == _Transition.jump) {
      _transEndPoint = SnakesGeometry.positionCenter(to, seat: seat);
    }

    if (_reduced) {
      _hopsEnd = 0.22;
      _transStart = _hopsEnd + 0.1;
      _transDur = kind == _Transition.none ? 0 : 0.2;
      _duration = kind == _Transition.none ? _hopsEnd : _transStart + _transDur;
      return;
    }
    _firstHop = from <= 0 ? _firstHopFromStart : _hop;
    _hopsEnd = _squares.isEmpty ? 0 : _firstHop + (_squares.length - 1) * _hop;
    switch (kind) {
      case _Transition.none:
        _transStart = _hopsEnd;
        _transDur = 0;
      case _Transition.ladder:
        _transStart = _hopsEnd + _pause;
        _transDur = ((_stops.length - 1) * 0.11).clamp(0.45, 1.5);
      case _Transition.snake:
        _transStart = _hopsEnd + _pause;
        _transDur = (0.35 + 0.16 * _snake!.length).clamp(0.9, 1.6);
      case _Transition.jump:
        _transStart = _hopsEnd + _pause;
        _transDur = 0.38;
    }
    _duration = _transStart + _transDur + _settle;
  }

  @override
  void update(BoardMotionEngine engine, double t) {
    if (_reduced) {
      _updateReduced(engine, t);
      return;
    }
    final m = _m;
    m.rotation = 0;
    m.lift = 0;
    m.liftFraction = 0;
    m.scaleX = 1;
    m.scaleY = 1;
    m.opacity = 1;
    final overall = _duration <= 0 ? 1.0 : (t / _duration).clamp(0.0, 1.0);
    c._moveScale[seat] = _scaleFrom + (_scaleTo - _scaleFrom) * overall;

    if (t < _hopsEnd) {
      final int i;
      final double u;
      if (t < _firstHop) {
        i = 0;
        u = t / _firstHop;
      } else {
        final k = ((t - _firstHop) / _hop).floor();
        i = math.min(1 + k, _squares.length - 1);
        u = ((t - _firstHop - k * _hop) / _hop).clamp(0.0, 1.0);
      }
      _fireSteps(i);
      final a = _points[i];
      final b = _points[i + 1];
      final e = MotionCurves.easeInOut(u);
      m.set(a.dx + (b.dx - a.dx) * e, a.dy + (b.dy - a.dy) * e);
      final arc = (i == 0 && from <= 0) ? 0.55 : 0.32;
      final h = MotionCurves.hop(u);
      m.lift = h * arc;
      m.liftFraction = h;
      final sq = MotionCurves.squash(u);
      final flight = math.sin(math.pi * u) * (1 - sq);
      m.scaleY = 1 - 0.16 * sq + 0.06 * flight;
      m.scaleX = 1 + 0.12 * sq - 0.03 * flight;
    } else {
      _fireSteps(_squares.length);
      if (!_landed) {
        _landed = true;
        if (_squares.isNotEmpty) {
          engine.addEffect(
            BoardEffect(
              kind: BoardEffectKind.landingRing,
              center: _land,
              color: c._seatColorFor(seat),
              seatColor: c._seatColors[seat],
              start: engine.now,
              duration: 0.35,
            ),
          );
        }
        if (kind == _Transition.none) _maybeFinish(engine, _end);
      }
      final tt = t - _transStart;
      if (tt < 0) {
        // Anticipation before the transition.
        final p = ((t - _hopsEnd) / _pause).clamp(0.0, 1.0);
        m.set(_land.dx, _land.dy);
        final s = math.sin(math.pi * p);
        m.scaleY = 1 - 0.12 * s;
        m.scaleX = 1 + 0.08 * s;
      } else if (tt < _transDur) {
        _fireTransition(engine);
        _transition(tt / _transDur);
      } else {
        _fireTransition(engine);
        if (kind != _Transition.none) _maybeFinish(engine, _transEndPoint);
        final p = _settle <= 0
            ? 1.0
            : ((tt - _transDur) / _settle).clamp(0.0, 1.0);
        final e = MotionCurves.easeOut(p);
        m.set(
          _transEndPoint.dx + (_end.dx - _transEndPoint.dx) * e,
          _transEndPoint.dy + (_end.dy - _transEndPoint.dy) * e,
        );
        final s = math.sin(math.pi * p);
        m.scaleY = 1 - 0.12 * s;
        m.scaleX = 1 + 0.08 * s;
      }
    }
    if (m.trailEnabled) m.trail.add(m.x, m.y - m.lift, engine.now);
  }

  void _transition(double v) {
    final m = _m;
    switch (kind) {
      case _Transition.none:
        break;
      case _Transition.ladder:
        final ladder = _ladder!;
        final segs = _stops.length - 1;
        final f = v * segs;
        final j = math.min(f.floor(), segs - 1);
        final w = (f - j).clamp(0.0, 1.0);
        final e = MotionCurves.easeInOut(w);
        final frac = _stops[j] + (_stops[j + 1] - _stops[j]) * e;
        final p = ladder.pointAt(frac);
        final d = ladder.direction;
        final lateral = math.sin((j + e) * math.pi) * 0.07;
        m.set(p.dx - d.dy * lateral, p.dy + d.dx * lateral);
        final h = MotionCurves.hop(w);
        m.lift = 0.07 * h;
        m.liftFraction = 0.3 * h;
        m.scaleY = 1 + 0.06 * math.sin(math.pi * w);
        m.scaleX = 1 - 0.04 * math.sin(math.pi * w);
      case _Transition.snake:
        final body = _snake!;
        final e = 0.5 - 0.5 * math.cos(math.pi * v);
        final p = body.pointAt(e);
        final tan = body.tangentAt(e);
        final wave = math.sin(e * math.pi * 7) * (1 - e);
        m.set(p.dx - tan.dy * wave * 0.1, p.dy + tan.dx * wave * 0.1);
        m.rotation = 0.2 * wave;
        m.scaleX = 1.04;
        m.scaleY = 0.94;
      case _Transition.jump:
        final e = MotionCurves.easeInOut(v);
        m.set(
          _land.dx + (_transEndPoint.dx - _land.dx) * e,
          _land.dy + (_transEndPoint.dy - _land.dy) * e,
        );
        final h = MotionCurves.hop(v);
        m.lift = 0.6 * h;
        m.liftFraction = h;
    }
  }

  void _updateReduced(BoardMotionEngine engine, double t) {
    final m = _m;
    m.lift = 0;
    m.liftFraction = 0;
    m.scaleX = 1;
    m.scaleY = 1;
    m.rotation = 0;
    const fade = 0.11;
    final mid = kind == _Transition.none ? _end : _land;
    if (t < fade) {
      m.set(_start.dx, _start.dy);
      m.opacity = 1 - t / fade;
      c._moveScale[seat] = _scaleFrom;
    } else if (t < _hopsEnd) {
      m.set(mid.dx, mid.dy);
      m.opacity = ((t - fade) / fade).clamp(0.0, 1.0);
      c._moveScale[seat] = kind == _Transition.none ? _scaleTo : 1;
      if (!_landed) {
        _landed = true;
        if (_squares.isNotEmpty) {
          _stepsFired = _squares.length;
          final square = _squares.last;
          c._emit(() => c.onStep?.call(seat, square));
          engine.addEffect(
            BoardEffect(
              kind: BoardEffectKind.landingRing,
              center: mid,
              color: c._seatColorFor(seat),
              seatColor: c._seatColors[seat],
              start: engine.now,
              duration: 0.3,
            ),
          );
        }
      }
    } else {
      m.opacity = 1;
      if (kind == _Transition.none) {
        m.set(_end.dx, _end.dy);
        _maybeFinish(engine, _end);
        return;
      }
      final tt = t - _transStart;
      if (tt < 0) {
        m.set(mid.dx, mid.dy);
      } else {
        _fireTransition(engine);
        final half = _transDur / 2;
        if (tt < half) {
          m.set(mid.dx, mid.dy);
          m.opacity = 1 - tt / half;
        } else {
          m.set(_end.dx, _end.dy);
          m.opacity = ((tt - half) / half).clamp(0.0, 1.0);
          c._moveScale[seat] = _scaleTo;
          if (tt >= _transDur - 1e-6) _maybeFinish(engine, _end);
        }
      }
    }
  }

  void _fireSteps(int completed) {
    while (_stepsFired < completed && _stepsFired < _squares.length) {
      final square = _squares[_stepsFired];
      _stepsFired++;
      c._emit(() => c.onStep?.call(seat, square));
    }
  }

  void _fireTransition(BoardMotionEngine engine) {
    if (_transFired || kind == _Transition.none) return;
    _transFired = true;
    final color = kind == _Transition.snake
        ? const Color(0xFFE5484D)
        : const Color(0xFFFFD45C);
    engine.addEffect(
      BoardEffect(
        kind: BoardEffectKind.transitionFlash,
        center: SnakesGeometry.positionCenter(landing, seat: seat),
        color: color,
        start: engine.now,
        duration: 0.4,
      ),
    );
    if (kind == _Transition.ladder) {
      c._emit(() => c.onLadder?.call(seat, landing, to));
    } else if (kind == _Transition.snake) {
      c._emit(() => c.onSnake?.call(seat, landing, to));
    }
  }

  void _maybeFinish(BoardMotionEngine engine, Offset at) {
    if (_finishFired || to != 100) return;
    _finishFired = true;
    engine.addEffect(
      BoardEffect(
        kind: BoardEffectKind.finishBurst,
        center: SnakesGeometry.centerOf(100),
        color: c._seatColorFor(seat),
        seatColor: c._seatColors[seat],
        start: engine.now,
        duration: _reduced ? 0.8 : 1.4,
        seed: seat + 1,
      ),
    );
    c._emit(() => c.onFinish?.call(seat));
  }

  @override
  void finish(BoardMotionEngine engine) {
    _m.reset();
    c._moveScale[seat] = 1;
    c._display[seat] = to;
  }
}
