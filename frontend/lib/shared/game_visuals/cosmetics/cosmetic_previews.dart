import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../features/ludo/presentation/board/mini_ludo_board.dart';
import '../../../features/snakes_ladders/presentation/board/mini_snakes_board.dart';
import '../dice/dice_controller.dart';
import '../dice/dice_view.dart';
import '../effects/victory_overlay.dart';
import '../game_palette.dart';
import '../motion/board_motion.dart';
import '../tokens/token_renderer.dart';
import '../trails/trail_renderer.dart';
import 'cosmetic_visuals.dart';

/// Preview of any renderable cosmetic id for the Collection Room.
///
/// Dispatches on the id's kind; unknown ids of a known kind show that
/// kind's starter look, and ids this library does not render (frames,
/// titles, badges, emotes) produce an empty box of [size].
class CosmeticPreview extends StatelessWidget {
  const CosmeticPreview(
    this.id, {
    super.key,
    this.color = SeatColor.red,
    this.animate = true,
    this.size = 96,
  });

  final String id;
  final SeatColor color;
  final bool animate;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (CosmeticVisuals.kindOf(id)) {
      case CosmeticVisualKind.dice:
        return DiceSkinPreview(id, animate: animate, size: size * 0.7);
      case CosmeticVisualKind.token:
        return TokenSkinPreview(id, color, size: size);
      case CosmeticVisualKind.ludoBoard:
      case CosmeticVisualKind.snakesBoard:
        return BoardThemePreview(id, size: size);
      case CosmeticVisualKind.trail:
        return TrailPreview(id, color: color, size: size, animate: animate);
      case CosmeticVisualKind.victory:
        return VictoryPreview(id, size: size, animate: animate);
      case null:
        return SizedBox.square(dimension: size);
    }
  }
}

/// A die in the given skin. With [animate] it rolls to a new face every
/// couple of seconds (purely decorative; values are local).
class DiceSkinPreview extends StatefulWidget {
  const DiceSkinPreview(
    this.id, {
    super.key,
    this.animate = false,
    this.size = 64,
    this.accent,
  });

  final String id;
  final bool animate;
  final double size;
  final Color? accent;

  @override
  State<DiceSkinPreview> createState() => _DiceSkinPreviewState();
}

class _DiceSkinPreviewState extends State<DiceSkinPreview> {
  final DiceController _controller = DiceController(initialValue: 5);
  final math.Random _random = math.Random();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(DiceSkinPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.animate) return;
    _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (!mounted ||
          !TickerMode.valuesOf(context).enabled ||
          _controller.rolling) {
        return;
      }
      var next = 1 + _random.nextInt(6);
      if (next == _controller.value) next = next % 6 + 1;
      _controller.roll(next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ExcludeSemantics(
      child: DiceView(
        controller: _controller,
        skin: CosmeticVisuals.dice(widget.id),
        size: widget.size,
        accent: widget.accent,
        reducedMotion: reduced,
      ),
    );
  }
}

/// A single token of skin [id] in [color].
class TokenSkinPreview extends StatelessWidget {
  const TokenSkinPreview(this.id, this.color, {super.key, this.size = 56});

  final String id;
  final SeatColor color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _TokenPreviewPainter(
            skin: CosmeticVisuals.token(id),
            color: color,
            palette: GamePalette.of(context),
          ),
        ),
      ),
    );
  }
}

class _TokenPreviewPainter extends CustomPainter {
  _TokenPreviewPainter({
    required this.skin,
    required this.color,
    required this.palette,
  });

  final String skin;
  final SeatColor color;
  final GamePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.4;
    final center = Offset(size.width / 2, size.height / 2 - r * 0.08);
    TokenRenderer.paintShadow(
      canvas,
      center: center,
      radius: r,
      palette: palette,
    );
    TokenRenderer.paintToken(
      canvas,
      center: center,
      radius: r,
      skin: skin,
      color: color,
      palette: palette,
    );
  }

  @override
  bool shouldRepaint(covariant _TokenPreviewPainter oldDelegate) =>
      oldDelegate.skin != skin ||
      oldDelegate.color != color ||
      oldDelegate.palette != palette;
}

/// A mini board of theme [id] (Ludo or Snakes & Ladders, by prefix).
class BoardThemePreview extends StatelessWidget {
  const BoardThemePreview(
    this.id, {
    super.key,
    this.size,
    this.showTokens = true,
  });

  final String id;

  /// Width of the preview; null = fill the incoming constraints.
  final double? size;
  final bool showTokens;

  @override
  Widget build(BuildContext context) {
    final Widget board =
        CosmeticVisuals.kindOf(id) == CosmeticVisualKind.snakesBoard
        ? MiniSnakesBoard(
            boardTheme: CosmeticVisuals.snakesBoard(id),
            showTokens: showTokens,
          )
        : MiniLudoBoard(
            boardTheme: CosmeticVisuals.ludoBoard(id),
            showTokens: showTokens,
          );
    if (size == null) return board;
    return SizedBox(width: size, child: board);
  }
}

/// A token hopping along a short strip, leaving trail [id].
class TrailPreview extends StatefulWidget {
  const TrailPreview(
    this.id, {
    super.key,
    this.color = SeatColor.red,
    this.size = 96,
    this.animate = true,
    this.tokenSkin = TokenSkins.classic,
  });

  final String id;
  final SeatColor color;
  final double size;
  final bool animate;
  final String tokenSkin;

  @override
  State<TrailPreview> createState() => _TrailPreviewState();
}

class _TrailPreviewState extends State<TrailPreview>
    with SingleTickerProviderStateMixin {
  static const double _cycle = 1.9;
  static const double _hopTime = 0.36;
  static const int _hops = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_cycle * 1000).round()),
  )..addListener(_tick);
  final TrailHistory _history = TrailHistory();
  final _TrailFrame _frame = _TrailFrame();
  double _lastValue = 0;
  int _cycles = 0;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(TrailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncAnimation();
  }

  bool get _shouldAnimate =>
      widget.animate &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _syncAnimation() {
    if (_shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _prefill();
    }
  }

  /// Static frame: the token mid-strip with its trail behind it.
  void _prefill() {
    _version++;
    _history.clear();
    const end = 0.92;
    for (var t = 0.4; t <= end; t += 1 / 60) {
      _place(t);
      _history.add(_frame.x, _frame.y - _frame.lift, t);
    }
    _place(end);
    _frame.now = end;
  }

  /// Token position at [t] seconds into the cycle (grid units of a 4 × 2
  /// strip).
  void _place(double t) {
    final hopsEnd = _hopTime * _hops;
    if (t >= hopsEnd) {
      _frame
        ..x = 0.5 + _hops
        ..y = 1.1
        ..lift = 0
        ..scaleX = 1
        ..scaleY = 1;
      return;
    }
    final k = (t / _hopTime).floor().clamp(0, _hops - 1);
    final u = ((t - k * _hopTime) / _hopTime).clamp(0.0, 1.0);
    final e = MotionCurves.easeInOut(u);
    final sq = MotionCurves.squash(u);
    _frame
      ..x = 0.5 + k + e
      ..y = 1.1
      ..lift = MotionCurves.hop(u) * 0.55
      ..scaleY = 1 - 0.14 * sq + 0.05 * math.sin(math.pi * u)
      ..scaleX = 1 + 0.1 * sq;
  }

  void _tick() {
    final v = _controller.value;
    if (v < _lastValue) {
      _cycles++;
      _history.clear();
    }
    _lastValue = v;
    final t = v * _cycle;
    _place(t);
    final now = _cycles * _cycle + t;
    _frame.now = now;
    _history.add(_frame.x, _frame.y - _frame.lift, now);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(widget.size, widget.size * 0.62),
          painter: _TrailPreviewPainter(
            repaint: _controller,
            history: _history,
            frame: _frame,
            version: _version,
            trailId: CosmeticVisuals.trail(widget.id),
            color: widget.color,
            skin: CosmeticVisuals.token(widget.tokenSkin),
            palette: GamePalette.of(context),
          ),
        ),
      ),
    );
  }
}

class _TrailFrame {
  double x = 0.5;
  double y = 1.1;
  double lift = 0;
  double scaleX = 1;
  double scaleY = 1;
  double now = 0;
}

class _TrailPreviewPainter extends CustomPainter {
  _TrailPreviewPainter({
    required Listenable repaint,
    required this.history,
    required this.frame,
    required this.version,
    required this.trailId,
    required this.color,
    required this.skin,
    required this.palette,
  }) : super(repaint: repaint);

  final TrailHistory history;
  final _TrailFrame frame;
  final int version;
  final String trailId;
  final SeatColor color;
  final String skin;
  final GamePalette palette;
  static final Paint _paint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = math.min(size.width / 4.2, size.height / 1.7);
    final origin = Offset(
      (size.width - cell * 4) / 2,
      size.height - cell * 1.62,
    );
    // Strip of cells.
    for (var i = 0; i < 4; i++) {
      final rect = Rect.fromLTWH(
        origin.dx + i * cell,
        origin.dy + 0.6 * cell,
        cell,
        cell,
      ).deflate(cell * 0.04);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.14));
      _paint.color = palette.gridLine;
      canvas.drawRRect(rrect.shift(Offset(0, cell * 0.045)), _paint);
      _paint.color = i == 3 ? palette.shades(color).tint : palette.trackCell;
      canvas.drawRRect(rrect, _paint);
    }
    final shades = palette.shades(color);
    TrailRenderer.paint(
      canvas,
      history,
      trailId: trailId,
      now: frame.now,
      cell: cell,
      origin: origin,
      color: shades.base,
    );
    final r = cell * 0.43;
    final center = Offset(
      origin.dx + frame.x * cell,
      origin.dy + frame.y * cell,
    );
    TokenRenderer.paintShadow(
      canvas,
      center: center,
      radius: r,
      palette: palette,
      liftFraction: (frame.lift / 0.55).clamp(0.0, 1.0),
    );
    TokenRenderer.paintToken(
      canvas,
      center: center,
      radius: r,
      skin: skin,
      color: color,
      palette: palette,
      lift: frame.lift * cell,
      scaleX: frame.scaleX,
      scaleY: frame.scaleY,
    );
  }

  @override
  bool shouldRepaint(covariant _TrailPreviewPainter oldDelegate) =>
      oldDelegate.trailId != trailId ||
      oldDelegate.color != color ||
      oldDelegate.skin != skin ||
      oldDelegate.palette != palette ||
      oldDelegate.version != version ||
      !identical(oldDelegate.frame, frame);
}

/// A looping, contained version of victory effect [id].
class VictoryPreview extends StatefulWidget {
  const VictoryPreview(
    this.id, {
    super.key,
    this.color,
    this.size = 120,
    this.animate = true,
  });

  final String id;

  /// Winner color; defaults to the red seat color.
  final Color? color;
  final double size;
  final bool animate;

  @override
  State<VictoryPreview> createState() => _VictoryPreviewState();
}

class _VictoryPreviewState extends State<VictoryPreview>
    with SingleTickerProviderStateMixin {
  static const int _pauseMs = 700;
  late final int _effectMs = VictoryEffectPainter.durationFor().inMilliseconds;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _effectMs + _pauseMs),
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(0, _effectMs / (_effectMs + _pauseMs)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(VictoryPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _sync();
  }

  void _sync() {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animate && !reduced) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      // A representative still frame.
      _controller.value = 0.3;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of(context);
    final color = widget.color ?? palette.seat(SeatColor.red);
    final background = palette.isDark
        ? Color.lerp(palette.boardSurface, color, 0.12)!
        : Color.lerp(const Color(0xFF1E2230), color, 0.18)!;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size * 0.12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Color.lerp(background, Colors.white, 0.08)!,
                  background,
                ],
              ),
            ),
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: VictoryEffectPainter(
                victoryId: CosmeticVisuals.victory(widget.id),
                color: color,
                progress: _progress,
                palette: palette,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
