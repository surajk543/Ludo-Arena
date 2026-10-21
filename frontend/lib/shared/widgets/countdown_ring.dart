import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/time/server_clock.dart';
import '../../l10n/generated/app_localizations.dart';

/// Turn timer ring driven by a server-clock deadline (unix ms). Uses the
/// [ServerClock] offset so devices with skewed clocks stay accurate.
///
/// Color shifts from [color] (default brand) to warning below 50 % and danger
/// below 25 %. Stops ticking when the deadline passes.
class CountdownRing extends ConsumerStatefulWidget {
  const CountdownRing({
    super.key,
    required this.deadlineMs,
    required this.totalMs,
    this.size = 48,
    this.strokeWidth = 4,
    this.color,
    this.child,
    this.showSeconds = true,
  });

  /// Server unix-ms deadline (`turn.deadline`).
  final int deadlineMs;

  /// Full turn duration in ms (for the ring fraction).
  final int totalMs;
  final double size;
  final double strokeWidth;
  final Color? color;

  /// Content inside the ring (e.g. an avatar). When null and [showSeconds],
  /// the remaining seconds are shown.
  final Widget? child;
  final bool showSeconds;

  @override
  ConsumerState<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends ConsumerState<CountdownRing>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = _compute();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant CountdownRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadlineMs != widget.deadlineMs ||
        oldWidget.totalMs != widget.totalMs) {
      _remaining = _compute();
      _syncTicker();
    }
  }

  Duration _compute() =>
      ref.read(serverClockProvider).remainingUntil(widget.deadlineMs);

  void _syncTicker() {
    final active = _remaining > Duration.zero;
    if (active && !_ticker.isActive) _ticker.start();
    if (!active && _ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration _) {
    final next = _compute();
    if (next != _remaining) setState(() => _remaining = next);
    if (next == Duration.zero) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final total = math.max(1, widget.totalMs);
    final fraction = (_remaining.inMilliseconds / total).clamp(0.0, 1.0);
    final base = widget.color ?? c.brand;
    final color = fraction < 0.25
        ? c.danger
        : fraction < 0.5
        ? c.warning
        : base;
    final seconds = (_remaining.inMilliseconds / 1000).ceil();

    Widget? inner = widget.child;
    if (inner == null && widget.showSeconds) {
      inner = Padding(
        padding: EdgeInsets.all(widget.strokeWidth + 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            l10n.commonSecondsShort(seconds),
            maxLines: 1,
            style: context.textTheme.labelLarge?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: l10n.widgetsSecondsLeft(seconds),
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _RingPainter(
            fraction: fraction,
            color: color,
            track: c.surfaceSunken.withValues(alpha: 0.8),
            strokeWidth: widget.strokeWidth,
            rtl: Directionality.of(context) == TextDirection.rtl,
          ),
          child: inner == null
              ? null
              : ExcludeSemantics(child: Center(child: inner)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.strokeWidth,
    required this.rtl,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double strokeWidth;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = track,
    );
    if (fraction <= 0) return;
    final sweep = math.pi * 2 * fraction;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      rtl ? -sweep : sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.strokeWidth != strokeWidth ||
      old.rtl != rtl;
}
