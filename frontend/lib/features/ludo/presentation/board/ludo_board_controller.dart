import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../../shared/game_visuals/game_palette.dart';
import '../../../../shared/game_visuals/motion/board_motion.dart';
import 'ludo_geometry.dart';

/// Drives the Ludo token layer from server-confirmed state.
///
/// Typical sequencing on a game screen:
/// * full snapshot (`game.started`, `game.state`, `room.updated`) →
///   [setPositions] (snaps and cancels animations), [setTurnSeat],
///   [setInteraction] for `awaiting_move`, [setForfeitedSeats];
/// * `game.dice_result` → await the dice roll, then [setInteraction] with
///   the legal tokens when it is the local player's choice;
/// * `game.move_applied` → `setInteraction()` (clear) then
///   `await animateMove(...)` with `from`, `to`, `captures` and `home`;
/// * `game.turn_changed` → [setTurnSeat].
///
/// [positions] always reflects every command immediately; the board renders
/// a display state that catches up as queued animations play, so concurrent
/// [animateMove] calls run one after another.
///
/// Event hooks ([onStep], [onCapture], [onHome]) fire in sync with the
/// animation (in a microtask right after the frame) so the screen can play
/// sounds and haptics. They do not fire for snapped moves or when no board
/// is attached (moves are then applied instantly).
class LudoBoardController extends ChangeNotifier {
  LudoBoardController({
    required List<SeatColor> seatColors,
    required int tokensPerPlayer,
    required List<List<int>> positions,
    int quarterTurns = 0,
  }) : assert(tokensPerPlayer >= 1 && tokensPerPlayer <= 4),
       _seatColors = List<SeatColor>.unmodifiable(seatColors),
       _quarterTurns = quarterTurns % 4,
       _boardColors = List<SeatColor>.unmodifiable([
         for (final c in seatColors) c.rotated(quarterTurns),
       ]),
       _tokensPerPlayer = tokensPerPlayer.clamp(1, 4),
       _target = _normalize(
         positions,
         seatColors.length,
         tokensPerPlayer.clamp(1, 4),
       ),
       _display = _normalize(
         positions,
         seatColors.length,
         tokensPerPlayer.clamp(1, 4),
       ) {
    final n = seatColors.length * _tokensPerPlayer;
    _motion = List<TokenMotionState>.generate(n, (_) => TokenMotionState());
    _moveScale = Float64List(n)..fillRange(0, n, 1);
    _restX = Float64List(n);
    _restY = Float64List(n);
    _restScale = Float64List(n);
    _badge = Int32List(n);
    _engine = BoardMotionEngine(
      onFrame: _frames.ping,
      onStateChanged: _stateChanged,
    );
  }

  final List<SeatColor> _seatColors;
  final int _quarterTurns;

  /// Per seat, the color whose board geometry (corner, start square, home
  /// column) the seat is drawn with: [seatColors] turned by [quarterTurns].
  final List<SeatColor> _boardColors;
  final int _tokensPerPlayer;
  final List<List<int>> _target;
  final List<List<int>> _display;
  late final List<TokenMotionState> _motion;
  late final Float64List _moveScale;
  late final Float64List _restX;
  late final Float64List _restY;
  late final Float64List _restScale;
  late final Int32List _badge;
  bool _layoutDirty = true;

  final RepaintSignal _frames = RepaintSignal();
  late final BoardMotionEngine _engine;
  TickerProvider? _vsync;

  int? _interactiveSeat;
  Set<int> _legal = const <int>{};
  int? _turnSeat;
  Set<int> _forfeited = const <int>{};
  int _revision = 0;
  bool _disposed = false;

  /// Called when the moving token lands on each square (progress value).
  void Function(int seat, int token, int progress)? onStep;

  /// Called when the moving token captures [captured] tokens.
  void Function(int seat, int token, List<({int seat, int token})> captured)?
  onCapture;

  /// Called when the moving token reaches home (progress 56).
  void Function(int seat, int token)? onHome;

  static List<List<int>> _normalize(
    List<List<int>> positions,
    int seats,
    int tpp,
  ) => [
    for (var s = 0; s < seats; s++)
      [
        for (var t = 0; t < tpp; t++)
          s < positions.length && t < positions[s].length
              ? positions[s][t].clamp(
                  LudoGeometry.baseProgress,
                  LudoGeometry.homeProgress,
                )
              : LudoGeometry.baseProgress,
      ],
  ];

  // ---------------------------------------------------------------------------
  // Public state.

  List<SeatColor> get seatColors => _seatColors;

  /// Clockwise quarter turns of the board view (0..3). All grid positions
  /// this controller reports are in the turned view.
  int get quarterTurns => _quarterTurns;
  int get seatCount => _seatColors.length;
  int get tokensPerPlayer => _tokensPerPlayer;

  /// Logical positions `[seat][token]` with every command applied.
  List<List<int>> get positions => List<List<int>>.unmodifiable([
    for (final s in _target) List<int>.unmodifiable(s),
  ]);

  /// Seat whose legal tokens are highlighted and tappable (null = none).
  int? get interactiveSeat => _interactiveSeat;

  /// Legal token indices of [interactiveSeat].
  Set<int> get legalTokens => _legal;

  /// Seat whose turn it is (emphasised), null = none.
  int? get turnSeat => _turnSeat;

  /// Seats whose tokens are removed from the board.
  Set<int> get forfeitedSeats => _forfeited;

  /// Whether a move animation is playing or queued.
  bool get isAnimating => _engine.isAnimating;

  /// Per-frame repaint signal for the token layer.
  Listenable get frames => _frames;

  /// Increments on every logical/display change.
  int get revision => _revision;

  /// Engine time (seconds) and active effects, for the token painter.
  double get now => _engine.now;
  List<BoardEffect> get effects => _engine.effects;

  /// Snaps to a full snapshot `[seat][token]`; cancels animations and
  /// completes their futures.
  void setPositions(List<List<int>> positions) {
    _engine.snapAll();
    final next = _normalize(positions, seatCount, _tokensPerPlayer);
    for (var s = 0; s < seatCount; s++) {
      for (var t = 0; t < _tokensPerPlayer; t++) {
        _target[s][t] = next[s][t];
        _display[s][t] = next[s][t];
      }
    }
    _resetMotion();
    _changed();
  }

  /// Marks the local player's movable tokens. Pass no arguments to clear.
  void setInteraction({int? seat, Set<int> legalTokens = const {}}) {
    final legal = seat == null
        ? const <int>{}
        : Set<int>.unmodifiable(legalTokens);
    if (seat == _interactiveSeat && setEquals(legal, _legal)) return;
    _interactiveSeat = seat;
    _legal = legal;
    _changed();
  }

  /// Emphasises [seat] as the current turn (null = none).
  void setTurnSeat(int? seat) {
    if (seat == _turnSeat) return;
    _turnSeat = seat;
    _changed();
  }

  /// Removes the tokens of forfeited [seats] from the board.
  void setForfeitedSeats(Set<int> seats) {
    if (setEquals(seats, _forfeited)) return;
    _forfeited = Set<int>.unmodifiable(seats);
    _layoutDirty = true;
    _changed();
  }

  /// Animates `game.move_applied`. Completes when the animation (including
  /// capture knock-backs and the home glow) ends; immediately without an
  /// attached board.
  Future<void> animateMove({
    required int seat,
    required int token,
    required int from,
    required int to,
    List<({int seat, int token})> captures = const [],
    bool reachedHome = false,
  }) {
    if (seat < 0 ||
        seat >= seatCount ||
        token < 0 ||
        token >= _tokensPerPlayer) {
      return Future<void>.value();
    }
    final f = from.clamp(LudoGeometry.baseProgress, LudoGeometry.homeProgress);
    final t = to.clamp(LudoGeometry.baseProgress, LudoGeometry.homeProgress);
    _target[seat][token] = t;
    final victims = <({int seat, int token})>[
      for (final c in captures)
        if (c.seat >= 0 &&
            c.seat < seatCount &&
            c.token >= 0 &&
            c.token < _tokensPerPlayer)
          c,
    ];
    for (final v in victims) {
      _target[v.seat][v.token] = LudoGeometry.baseProgress;
    }
    return _engine.run(
      _LudoMoveJob(
        this,
        seat: seat,
        token: token,
        from: f,
        to: t,
        victims: victims,
        home: reachedHome || t == LudoGeometry.homeProgress,
      ),
    );
  }

  /// Jumps every token to its final position and completes all pending
  /// animation futures. Use when a full snapshot arrives mid-animation.
  void cancelAndSnap() {
    _engine.snapAll();
    for (var s = 0; s < seatCount; s++) {
      for (var t = 0; t < _tokensPerPlayer; t++) {
        _display[s][t] = _target[s][t];
      }
    }
    _resetMotion();
    _changed();
  }

  /// Called by [LudoBoard]: borrows its ticker. Calling again with the same
  /// [vsync] only updates [reducedMotion].
  void attach(TickerProvider vsync, {bool reducedMotion = false}) {
    _engine.reducedMotion = reducedMotion;
    if (identical(_vsync, vsync) && _engine.attached) return;
    _vsync = vsync;
    _engine.attach(vsync);
  }

  /// Called by [LudoBoard] on dispose; running animations snap to the end.
  void detach() {
    _vsync = null;
    _engine.detach();
  }

  // ---------------------------------------------------------------------------
  // Rendering accessors (read by the token painter every frame).

  int _index(int seat, int token) => seat * _tokensPerPlayer + token;

  /// Progress currently displayed (lags [positions] while animations queue).
  int displayedProgress(int seat, int token) => _display[seat][token];

  /// Whether [seat]'s tokens are drawn.
  bool isSeatVisible(int seat) => !_forfeited.contains(seat);

  /// Live motion override of a token (active while it animates).
  TokenMotionState motionOf(int seat, int token) =>
      _motion[_index(seat, token)];

  /// Where a token rests (grid units), with fan-out for shared squares.
  Offset restingCenter(int seat, int token) {
    _ensureLayout();
    final i = _index(seat, token);
    return Offset(_restX[i], _restY[i]);
  }

  /// Size factor of a resting token (stacks shrink tokens).
  double restingScale(int seat, int token) {
    _ensureLayout();
    return _restScale[_index(seat, token)];
  }

  /// Stack count badge drawn next to this token (0 = none).
  int restingBadge(int seat, int token) {
    _ensureLayout();
    return _badge[_index(seat, token)];
  }

  /// Current visual center (grid units), including animation.
  Offset visualCenter(int seat, int token) {
    final m = _motion[_index(seat, token)];
    return m.active ? m.center : restingCenter(seat, token);
  }

  /// Current visual size factor, including animation.
  double visualScale(int seat, int token) {
    final i = _index(seat, token);
    return _motion[i].active ? _moveScale[i] : restingScale(seat, token);
  }

  /// The token of [interactiveSeat] that a tap at [grid] (grid units)
  /// selects, mapped to a legal token index; null when nothing legal is hit.
  int? hitTest(Offset grid) {
    final seat = _interactiveSeat;
    if (seat == null ||
        _legal.isEmpty ||
        seat >= seatCount ||
        !isSeatVisible(seat)) {
      return null;
    }
    int? best;
    var bestDistance = double.infinity;
    for (var t = 0; t < _tokensPerPlayer; t++) {
      final legal = _legalFor(seat, t);
      if (legal == null) continue;
      final c = visualCenter(seat, t);
      final scale = visualScale(seat, t);
      // Tokens stand above their cell center; bias the hit point upward.
      final d = (grid - c.translate(0, -0.12 * scale)).distance;
      final reach = math.max(0.5, 0.62 * scale);
      if (d <= reach && d < bestDistance) {
        bestDistance = d;
        best = legal;
      }
    }
    return best;
  }

  /// Legal token index represented by token [t] (itself, or the legal token
  /// with identical progress), else null.
  int? _legalFor(int seat, int t) {
    if (_legal.contains(t)) return t;
    final progress = _display[seat][t];
    for (final l in _legal) {
      if (l >= 0 && l < _tokensPerPlayer && _display[seat][l] == progress) {
        return l;
      }
    }
    return null;
  }

  /// Whether token [t] of [seat] gets the legal-move highlight.
  bool isLegalHighlighted(int seat, int t) =>
      seat == _interactiveSeat && _legal.contains(t);

  // ---------------------------------------------------------------------------
  // Stacking layout.

  static const List<double> _fan2X = [-0.2, 0.2];
  static const List<double> _fan3X = [-0.2, 0.2, 0];
  static const List<double> _fan3Y = [-0.1, -0.1, 0.14];
  static const List<double> _fan4X = [-0.2, 0.2, -0.2, 0.2];
  static const List<double> _fan4Y = [-0.13, -0.13, 0.15, 0.15];

  void _ensureLayout() {
    if (!_layoutDirty) return;
    _layoutDirty = false;
    final n = seatCount * _tokensPerPlayer;
    final keys = Int32List(n);
    for (var s = 0; s < seatCount; s++) {
      for (var t = 0; t < _tokensPerPlayer; t++) {
        final i = _index(s, t);
        _badge[i] = 0;
        if (!isSeatVisible(s)) {
          keys[i] = -1;
          final spot = _spotOf(s, t);
          _restX[i] = spot.center.dx;
          _restY[i] = spot.center.dy;
          _restScale[i] = 1;
          continue;
        }
        keys[i] = _spotOf(s, t).stackKey;
      }
    }
    for (var s = 0; s < seatCount; s++) {
      for (var t = 0; t < _tokensPerPlayer; t++) {
        final i = _index(s, t);
        if (keys[i] < 0) continue;
        final spot = _spotOf(s, t);
        var count = 0;
        var rank = 0;
        var sameSeat = true;
        for (var j = 0; j < n; j++) {
          if (keys[j] != keys[i]) continue;
          if (j < i) rank++;
          if (j ~/ _tokensPerPlayer != s) sameSeat = false;
          count++;
        }
        var x = spot.center.dx;
        var y = spot.center.dy;
        var scale = 1.0;
        switch (spot.kind) {
          case LudoSpotKind.base:
            scale = 1.12;
          case LudoSpotKind.home:
            final spread = LudoGeometry.homeSpread(spot.color);
            final spacing = count > 2 ? 0.44 : 0.52;
            final o = (rank - (count - 1) / 2) * spacing;
            x += spread.dx * o;
            y += spread.dy * o;
            scale = 0.56;
          case LudoSpotKind.track:
          case LudoSpotKind.homeColumn:
            switch (count) {
              case 1:
                break;
              case 2:
                x += _fan2X[rank];
                scale = 0.74;
              case 3:
                x += _fan3X[rank];
                y += _fan3Y[rank];
                scale = 0.66;
              default:
                final r = rank % 4;
                x += _fan4X[r];
                y += _fan4Y[r] - 0.06 * (rank ~/ 4);
                scale = 0.6;
            }
            // One badge per stack: on the last token of the group.
            if (count >= 3 || (count == 2 && sameSeat)) {
              if (rank == count - 1) _badge[i] = count;
            }
        }
        _restX[i] = x;
        _restY[i] = y;
        _restScale[i] = scale;
      }
    }
  }

  LudoSpot _spotOf(int seat, int token) => LudoGeometry.cellFor(
    _boardColors[seat],
    _display[seat][token],
    tokenIndex: token,
    tokensPerPlayer: _tokensPerPlayer,
  );

  // ---------------------------------------------------------------------------

  void _resetMotion() {
    for (var i = 0; i < _motion.length; i++) {
      _motion[i].reset();
      _moveScale[i] = 1;
    }
    _layoutDirty = true;
  }

  void _changed() {
    _stateChanged();
    _frames.ping();
  }

  void _stateChanged() {
    if (_disposed) return;
    _layoutDirty = true;
    _revision++;
    notifyListeners();
  }

  void _emit(VoidCallback callback) {
    scheduleMicrotask(() {
      if (!_disposed) callback();
    });
  }

  Color _fallbackColor(int seat) => GamePalette.light.seat(_seatColors[seat]);

  @override
  void dispose() {
    _disposed = true;
    _engine.detach();
    _frames.dispose();
    super.dispose();
  }
}

/// One `move_applied` animation: hops → landing (+ capture knock-backs,
/// home glow) → settle.
class _LudoMoveJob extends MotionJob {
  _LudoMoveJob(
    this.c, {
    required this.seat,
    required this.token,
    required this.from,
    required this.to,
    required this.victims,
    required this.home,
  });

  final LudoBoardController c;
  final int seat;
  final int token;
  final int from;
  final int to;
  final List<({int seat, int token})> victims;
  final bool home;

  static const double _hop = 0.16;
  static const double _lastHop = 0.19;
  static const double _baseHop = 0.32;
  static const double _settle = 0.16;
  static const double _knock = 0.52;
  static const double _knockStagger = 0.07;
  static const double _homeGlow = 0.75;

  bool _reduced = false;
  double _duration = 0;
  double _land = 0;
  List<Offset> _points = const [];
  List<int> _progress = const [];
  List<double> _hopStart = const [];
  List<double> _hopLen = const [];
  List<double> _arc = const [];
  Offset _end = Offset.zero;
  double _scaleFrom = 1;
  double _scaleTo = 1;
  List<Offset> _victimFrom = const [];
  List<Offset> _victimTo = const [];
  List<double> _victimScale = const [];
  int _stepsFired = 0;
  bool _landed = false;

  @override
  double get duration => _duration;

  int _i(int s, int t) => c._index(s, t);

  @override
  void begin(BoardMotionEngine engine) {
    _reduced = engine.reducedMotion;
    final mi = _i(seat, token);
    final m = c._motion[mi];
    final wasResting = c._display[seat][token] == from && !m.active;
    final color = c._boardColors[seat];
    final start = wasResting
        ? c.restingCenter(seat, token)
        : LudoGeometry.cellFor(
            color,
            from,
            tokenIndex: token,
            tokensPerPlayer: c._tokensPerPlayer,
          ).center;
    _scaleFrom = wasResting ? c.restingScale(seat, token) : 1;

    final landingCell = to >= 0
        ? LudoGeometry.cellFor(
            color,
            to,
            tokenIndex: token,
            tokensPerPlayer: c._tokensPerPlayer,
          ).center
        : start;
    _victimFrom = [
      for (final v in victims)
        c._display[v.seat][v.token] != LudoGeometry.baseProgress &&
                !c._motion[_i(v.seat, v.token)].active
            ? c.restingCenter(v.seat, v.token)
            : landingCell,
    ];
    _victimScale = [
      for (final v in victims)
        c._display[v.seat][v.token] != LudoGeometry.baseProgress
            ? c.restingScale(v.seat, v.token)
            : 1.0,
    ];

    // Apply the move to the display state.
    c._display[seat][token] = to;
    for (final v in victims) {
      c._display[v.seat][v.token] = LudoGeometry.baseProgress;
    }
    c._layoutDirty = true;
    _end = c.restingCenter(seat, token);
    _scaleTo = c.restingScale(seat, token);
    _victimTo = [for (final v in victims) c.restingCenter(v.seat, v.token)];

    m.reset();
    m
      ..active = true
      ..onTop = true
      ..trailEnabled = !_reduced
      ..set(start.dx, start.dy);
    c._moveScale[mi] = _scaleFrom;
    for (var k = 0; k < victims.length; k++) {
      final vi = _i(victims[k].seat, victims[k].token);
      c._motion[vi]
        ..reset()
        ..active = true
        ..set(_victimFrom[k].dx, _victimFrom[k].dy);
      c._moveScale[vi] = _victimScale[k];
    }

    final spots = to > from
        ? LudoGeometry.pathCells(color, from, to)
        : const <LudoSpot>[];
    _progress = [for (var p = from + 1; p <= to && spots.isNotEmpty; p++) p];
    _points = [
      start,
      for (var k = 0; k < spots.length; k++)
        k == spots.length - 1 ? _end : spots[k].center,
      if (spots.isEmpty) _end,
    ];

    if (_reduced) {
      _land = 0.11;
      _duration = victims.isEmpty ? 0.24 : 0.36;
      if (home) _duration = math.max(_duration, 0.3);
      return;
    }

    final hops = _points.length - 1;
    _hopStart = List<double>.filled(hops, 0);
    _hopLen = List<double>.filled(hops, 0);
    _arc = List<double>.filled(hops, 0);
    var t = 0.0;
    for (var k = 0; k < hops; k++) {
      final fromBase = k == 0 && from == LudoGeometry.baseProgress;
      final len = fromBase ? _baseHop : (k == hops - 1 ? _lastHop : _hop);
      _hopStart[k] = t;
      _hopLen[k] = len;
      final dist = (_points[k + 1] - _points[k]).distance;
      _arc[k] = fromBase ? 0.95 : (0.32 + 0.1 * dist).clamp(0.3, 0.7);
      t += len;
    }
    _land = t;
    var end = _land + _settle;
    if (victims.isNotEmpty) {
      end = math.max(
        end,
        _land + 0.04 + _knockStagger * (victims.length - 1) + _knock + 0.1,
      );
    }
    if (home) end = math.max(end, _land + _homeGlow);
    _duration = end;
  }

  @override
  void update(BoardMotionEngine engine, double t) {
    if (_reduced) {
      _updateReduced(engine, t);
      return;
    }
    final mi = _i(seat, token);
    final m = c._motion[mi];
    m
      ..lift = 0
      ..liftFraction = 0
      ..scaleX = 1
      ..scaleY = 1
      ..rotation = 0
      ..opacity = 1;

    if (t < _land) {
      var k = 0;
      while (k < _hopLen.length - 1 && t >= _hopStart[k] + _hopLen[k]) {
        k++;
      }
      _fireSteps(k);
      final u = ((t - _hopStart[k]) / _hopLen[k]).clamp(0.0, 1.0);
      final a = _points[k];
      final b = _points[k + 1];
      final e = MotionCurves.easeInOut(u);
      m.set(a.dx + (b.dx - a.dx) * e, a.dy + (b.dy - a.dy) * e);
      final h = MotionCurves.hop(u);
      // Keep the arc inside the board near the top edge.
      m.lift = math.min(h * _arc[k], math.max(0.2, m.y - 0.3));
      m.liftFraction = h;
      final sq = MotionCurves.squash(u);
      final flight = math.sin(math.pi * u) * (1 - sq);
      m.scaleY = 1 - 0.16 * sq + 0.07 * flight;
      m.scaleX = 1 + 0.12 * sq - 0.035 * flight;
      final overall = _land <= 0 ? 1.0 : t / _land;
      c._moveScale[mi] = _scaleFrom + (_scaleTo - _scaleFrom) * overall;
    } else {
      _fireSteps(_progress.length);
      _onLanded(engine);
      m.set(_end.dx, _end.dy);
      c._moveScale[mi] = _scaleTo;
      final p = ((t - _land) / _settle).clamp(0.0, 1.0);
      final s = math.sin(math.pi * p) * (1 - p);
      m.scaleY = 1 - 0.14 * s;
      m.scaleX = 1 + 0.1 * s;
      if (home) {
        final g = ((t - _land) / _homeGlow).clamp(0.0, 1.0);
        m.glow = math.sin(math.pi * g);
      }
    }
    if (m.trailEnabled) m.trail.add(m.x, m.y - m.lift, engine.now);

    // Victims: wait on the square, flinch at impact, then fly home.
    for (var k = 0; k < victims.length; k++) {
      final vi = _i(victims[k].seat, victims[k].token);
      final vm = c._motion[vi];
      vm
        ..lift = 0
        ..liftFraction = 0
        ..scaleX = 1
        ..scaleY = 1
        ..rotation = 0
        ..opacity = 1;
      final ks = _land + 0.04 + _knockStagger * k;
      final a = _victimFrom[k];
      final b = _victimTo[k];
      if (t < ks) {
        vm.set(a.dx, a.dy);
        c._moveScale[vi] = _victimScale[k];
        if (t >= _land) {
          vm.scaleY = 0.86;
          vm.scaleX = 1.1;
        }
        continue;
      }
      final u = ((t - ks) / _knock).clamp(0.0, 1.0);
      final e = MotionCurves.easeInOut(u);
      vm.set(a.dx + (b.dx - a.dx) * e, a.dy + (b.dy - a.dy) * e);
      final dist = (b - a).distance;
      final h = MotionCurves.hop(u);
      vm.lift = math.min(
        h * (0.9 + 0.12 * dist).clamp(0.9, 2.2),
        math.max(0.2, vm.y - 0.3),
      );
      vm.liftFraction = h;
      vm.rotation = math.sin(u * math.pi * 3) * 0.45 * (1 - u);
      c._moveScale[vi] = _victimScale[k] + (1 - _victimScale[k]) * e;
      if (u >= 1) {
        final p = ((t - ks - _knock) / 0.1).clamp(0.0, 1.0);
        final s = math.sin(math.pi * p);
        vm.scaleY = 1 - 0.12 * s;
        vm.scaleX = 1 + 0.08 * s;
      }
    }
  }

  void _updateReduced(BoardMotionEngine engine, double t) {
    final mi = _i(seat, token);
    final m = c._motion[mi];
    m
      ..lift = 0
      ..liftFraction = 0
      ..scaleX = 1
      ..scaleY = 1
      ..rotation = 0;
    if (t < _land) {
      final a = _points.first;
      m
        ..set(a.dx, a.dy)
        ..opacity = 1 - t / _land;
      c._moveScale[mi] = _scaleFrom;
    } else {
      if (!_landed) {
        _stepsFired = _progress.length;
        if (_progress.isNotEmpty) {
          final p = _progress.last;
          c._emit(() => c.onStep?.call(seat, token, p));
        }
      }
      _onLanded(engine);
      m
        ..set(_end.dx, _end.dy)
        ..opacity = ((t - _land) / 0.12).clamp(0.0, 1.0);
      c._moveScale[mi] = _scaleTo;
      if (home) {
        m.glow = math.sin(
          math.pi * ((t - _land) / (_duration - _land)).clamp(0.0, 1.0),
        );
      }
    }
    for (var k = 0; k < victims.length; k++) {
      final vi = _i(victims[k].seat, victims[k].token);
      final vm = c._motion[vi];
      if (t < _land + 0.12) {
        vm
          ..set(_victimFrom[k].dx, _victimFrom[k].dy)
          ..opacity = t < _land ? 1 : 1 - (t - _land) / 0.12;
        c._moveScale[vi] = _victimScale[k];
      } else {
        vm
          ..set(_victimTo[k].dx, _victimTo[k].dy)
          ..opacity = ((t - _land - 0.12) / 0.12).clamp(0.0, 1.0);
        c._moveScale[vi] = 1;
      }
    }
  }

  void _fireSteps(int completed) {
    while (_stepsFired < completed && _stepsFired < _progress.length) {
      final p = _progress[_stepsFired];
      _stepsFired++;
      c._emit(() => c.onStep?.call(seat, token, p));
    }
  }

  void _onLanded(BoardMotionEngine engine) {
    if (_landed) return;
    _landed = true;
    final color = c._seatColors[seat];
    final landingSpot = _end;
    if (victims.isNotEmpty) {
      final victimSeat = victims.first.seat;
      engine.addEffect(
        BoardEffect(
          kind: BoardEffectKind.captureBurst,
          center: landingSpot,
          color: c._fallbackColor(victimSeat),
          seatColor: c._seatColors[victimSeat],
          start: engine.now,
          duration: _reduced ? 0.35 : 0.55,
          seed: seat * 7 + token,
        ),
      );
      final captured = List<({int seat, int token})>.unmodifiable(victims);
      c._emit(() => c.onCapture?.call(seat, token, captured));
    } else if (!home && !_reduced && _progress.isNotEmpty) {
      engine.addEffect(
        BoardEffect(
          kind: BoardEffectKind.landingRing,
          center: landingSpot,
          color: c._fallbackColor(seat),
          seatColor: color,
          start: engine.now,
          duration: 0.32,
        ),
      );
    }
    if (home) {
      engine.addEffect(
        BoardEffect(
          kind: BoardEffectKind.homeSparkle,
          center: LudoGeometry.homeCenter(c._boardColors[seat]),
          color: c._fallbackColor(seat),
          seatColor: color,
          start: engine.now,
          duration: _reduced ? 0.6 : 0.95,
          seed: seat * 5 + token,
        ),
      );
      c._emit(() => c.onHome?.call(seat, token));
    }
  }

  @override
  void finish(BoardMotionEngine engine) {
    final mi = _i(seat, token);
    c._motion[mi].reset();
    c._moveScale[mi] = 1;
    c._display[seat][token] = to;
    for (final v in victims) {
      final vi = _i(v.seat, v.token);
      c._motion[vi].reset();
      c._moveScale[vi] = 1;
      c._display[v.seat][v.token] = LudoGeometry.baseProgress;
    }
    c._layoutDirty = true;
  }
}
