import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Decorative mini Ludo board for the Home game card: four colored bases
/// with token pieces, the cross-shaped track and the home triangles.
class MiniLudoBoard extends StatelessWidget {
  const MiniLudoBoard({super.key, this.size = 112});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: MiniLudoBoardPainter(colors: context.colors),
      ),
    ),
  );
}

class MiniLudoBoardPainter extends CustomPainter {
  const MiniLudoBoardPainter({required this.colors});

  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cell = s / 15;
    final board = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(s * 0.08),
    );
    canvas.drawRRect(
      board.shift(Offset(0, s * 0.02)),
      Paint()
        ..color = colors.shadowColor.withValues(
          alpha: colors.isDark ? 0.5 : 0.18,
        ),
    );
    canvas.drawRRect(
      board,
      Paint()..color = colors.isDark ? const Color(0xFF2A2150) : Colors.white,
    );
    canvas.save();
    canvas.clipRRect(board);

    final seats = colors.seats;
    // Bases: red TL, green TR, yellow BR, blue BL (game-rules.md geometry).
    final bases = <(Color, Offset)>[
      (seats.red, Offset.zero),
      (seats.green, Offset(9 * cell, 0)),
      (seats.yellow, Offset(9 * cell, 9 * cell)),
      (seats.blue, Offset(0, 9 * cell)),
    ];
    for (final (color, origin) in bases) {
      final r = Rect.fromLTWH(origin.dx, origin.dy, 6 * cell, 6 * cell);
      canvas.drawRect(r, Paint()..color = color);
      final inner = RRect.fromRectAndRadius(
        r.deflate(cell * 0.9),
        Radius.circular(cell * 0.8),
      );
      canvas.drawRRect(
        inner,
        Paint()..color = colors.isDark ? const Color(0xFF1B1538) : Colors.white,
      );
      // Four token pieces.
      for (var i = 0; i < 4; i++) {
        final cx = inner.left + inner.width * (i.isEven ? 0.3 : 0.7);
        final cy = inner.top + inner.height * (i < 2 ? 0.3 : 0.7);
        _token(canvas, Offset(cx, cy), cell * 0.78, color);
      }
    }

    // Track grid lines.
    final grid = Paint()
      ..color = colors.isDark
          ? const Color(0x33FFFFFF)
          : const Color(0x22000000)
      ..strokeWidth = math.max(0.5, s * 0.004);
    for (var i = 6; i <= 9; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, 6 * cell), grid);
      canvas.drawLine(Offset(i * cell, 9 * cell), Offset(i * cell, s), grid);
      canvas.drawLine(Offset(0, i * cell), Offset(6 * cell, i * cell), grid);
      canvas.drawLine(Offset(9 * cell, i * cell), Offset(s, i * cell), grid);
    }
    for (var i = 1; i < 6; i++) {
      canvas.drawLine(
        Offset(6 * cell, i * cell),
        Offset(9 * cell, i * cell),
        grid,
      );
      canvas.drawLine(
        Offset(6 * cell, (9 + i) * cell),
        Offset(9 * cell, (9 + i) * cell),
        grid,
      );
      canvas.drawLine(
        Offset(i * cell, 6 * cell),
        Offset(i * cell, 9 * cell),
        grid,
      );
      canvas.drawLine(
        Offset((9 + i) * cell, 6 * cell),
        Offset((9 + i) * cell, 9 * cell),
        grid,
      );
    }
    // Home columns.
    void col(Rect r, Color c) => canvas.drawRect(r, Paint()..color = c);
    col(Rect.fromLTWH(cell, 7 * cell, 5 * cell, cell), seats.red);
    col(Rect.fromLTWH(7 * cell, cell, cell, 5 * cell), seats.green);
    col(Rect.fromLTWH(9 * cell, 7 * cell, 5 * cell, cell), seats.yellow);
    col(Rect.fromLTWH(7 * cell, 9 * cell, cell, 5 * cell), seats.blue);

    // Center home triangles.
    final c = Offset(7.5 * cell, 7.5 * cell);
    final tl = Offset(6 * cell, 6 * cell);
    final tr = Offset(9 * cell, 6 * cell);
    final br = Offset(9 * cell, 9 * cell);
    final bl = Offset(6 * cell, 9 * cell);
    void tri(Offset a, Offset b, Color color) => canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..close(),
      Paint()..color = color,
    );
    tri(tl, bl, seats.red);
    tri(tl, tr, seats.green);
    tri(tr, br, seats.yellow);
    tri(bl, br, seats.blue);
    // A few tokens on the track for life.
    _token(canvas, Offset(2.5 * cell, 6.5 * cell), cell * 0.8, seats.red);
    _token(canvas, Offset(8.5 * cell, 2.5 * cell), cell * 0.8, seats.green);
    _token(canvas, Offset(12.5 * cell, 8.5 * cell), cell * 0.8, seats.yellow);
    canvas.restore();
    canvas.drawRRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02
        ..color = colors.gold.withValues(alpha: 0.85),
    );
  }

  void _token(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(
      c + Offset(0, r * 0.12),
      r * 0.62,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
    canvas.drawCircle(
      c,
      r * 0.6,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(color, Colors.white, 0.45)!, color],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.6)),
    );
    canvas.drawCircle(
      c,
      r * 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(MiniLudoBoardPainter old) => old.colors != colors;
}

/// Decorative mini Snakes & Ladders board: a colorful numbered 6×6 grid
/// (boustrophedon) with a painted ladder and snake.
class MiniSnakesBoard extends StatelessWidget {
  const MiniSnakesBoard({super.key, this.size = 112});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: MiniSnakesBoardPainter(
          colors: context.colors,
          textDirection: TextDirection.ltr,
        ),
      ),
    ),
  );
}

class MiniSnakesBoardPainter extends CustomPainter {
  const MiniSnakesBoardPainter({
    required this.colors,
    required this.textDirection,
  });

  final AppColors colors;
  final TextDirection textDirection;

  static const int n = 6;

  Offset _center(int square, double cell) {
    final row = (square - 1) ~/ n;
    final inRow = (square - 1) % n;
    final col = row.isEven ? inRow : n - 1 - inRow;
    return Offset((col + 0.5) * cell, (n - 1 - row + 0.5) * cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cell = s / n;
    final board = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(s * 0.08),
    );
    canvas.drawRRect(
      board.shift(Offset(0, s * 0.02)),
      Paint()
        ..color = colors.shadowColor.withValues(
          alpha: colors.isDark ? 0.5 : 0.18,
        ),
    );
    canvas.save();
    canvas.clipRRect(board);
    final palette = [
      colors.seats.red,
      colors.seats.yellow,
      colors.seats.green,
      colors.seats.blue,
    ];
    for (var sq = 1; sq <= n * n; sq++) {
      final c = _center(sq, cell);
      final rect = Rect.fromCenter(center: c, width: cell, height: cell);
      final base = palette[sq % palette.length];
      final light = sq.isEven;
      canvas.drawRect(
        rect,
        Paint()
          ..color = Color.lerp(
            base,
            colors.isDark ? const Color(0xFF1B1538) : Colors.white,
            light ? 0.55 : 0.3,
          )!,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '$sq',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: cell * 0.32,
            fontWeight: FontWeight.w700,
            color: colors.isDark
                ? Colors.white.withValues(alpha: 0.85)
                : const Color(0xFF2A1F4A).withValues(alpha: 0.75),
          ),
        ),
        textDirection: textDirection,
      )..layout();
      tp.paint(canvas, rect.topLeft + Offset(cell * 0.1, cell * 0.06));
    }
    _ladder(canvas, _center(4, cell), _center(22, cell), cell);
    _snake(canvas, _center(33, cell), _center(14, cell), cell);
    canvas.restore();
    canvas.drawRRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02
        ..color = colors.gold.withValues(alpha: 0.85),
    );
  }

  void _ladder(Canvas canvas, Offset from, Offset to, double cell) {
    final dir = to - from;
    final len = dir.distance;
    final unit = dir / len;
    final normal = Offset(-unit.dy, unit.dx) * (cell * 0.22);
    final rail = Paint()
      ..strokeWidth = cell * 0.1
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF9A5B2A);
    final rung = Paint()
      ..strokeWidth = cell * 0.07
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFC98A4B);
    final steps = (len / (cell * 0.45)).floor();
    for (var i = 1; i < steps; i++) {
      final p = from + unit * (i * cell * 0.45);
      canvas.drawLine(p - normal, p + normal, rung);
    }
    canvas.drawLine(from - normal, to - normal, rail);
    canvas.drawLine(from + normal, to + normal, rail);
  }

  void _snake(Canvas canvas, Offset head, Offset tail, double cell) {
    final mid = Offset.lerp(head, tail, 0.5)!;
    final dir = tail - head;
    final normal = Offset(-dir.dy, dir.dx) / dir.distance * cell * 0.9;
    final path = Path()
      ..moveTo(head.dx, head.dy)
      ..cubicTo(
        Offset.lerp(head, mid, 0.5)!.dx + normal.dx,
        Offset.lerp(head, mid, 0.5)!.dy + normal.dy,
        Offset.lerp(mid, tail, 0.5)!.dx - normal.dx,
        Offset.lerp(mid, tail, 0.5)!.dy - normal.dy,
        tail.dx,
        tail.dy,
      );
    final body = colors.seats.green;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = cell * 0.36
        ..color = Color.lerp(body, Colors.black, 0.25)!,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = cell * 0.26
        ..color = body,
    );
    // Belly stripes.
    final metric = path.computeMetrics().first;
    final stripe = Paint()
      ..strokeWidth = cell * 0.06
      ..strokeCap = StrokeCap.round
      ..color = colors.seats.yellow;
    for (var d = cell * 0.5; d < metric.length - cell * 0.3; d += cell * 0.42) {
      final t = metric.getTangentForOffset(d)!;
      final nrm = Offset(-t.vector.dy, t.vector.dx) * (cell * 0.1);
      canvas.drawLine(t.position - nrm, t.position + nrm, stripe);
    }
    // Head with eyes.
    canvas.drawCircle(head, cell * 0.24, Paint()..color = body);
    final eye = Paint()..color = Colors.white;
    final pupil = Paint()..color = Colors.black;
    for (final dx in [-0.09, 0.09]) {
      final e = head + Offset(cell * dx, -cell * 0.05);
      canvas.drawCircle(e, cell * 0.06, eye);
      canvas.drawCircle(e, cell * 0.03, pupil);
    }
    canvas.drawLine(
      head + Offset(0, cell * 0.2),
      head + Offset(0, cell * 0.34),
      Paint()
        ..strokeWidth = cell * 0.04
        ..color = colors.seats.red,
    );
  }

  @override
  bool shouldRepaint(MiniSnakesBoardPainter old) =>
      old.colors != colors || old.textDirection != textDirection;
}
