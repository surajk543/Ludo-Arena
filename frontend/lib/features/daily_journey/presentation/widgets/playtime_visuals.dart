import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/localization/number_format.dart';
import '../../../../core/protocol/protocol.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// "40 XP + 10,000 coins" (server amounts; empty parts are left out).
String playtimeRewardText(
  AppLocalizations l10n,
  Locale locale,
  PlaytimeReward r,
) {
  final parts = [
    if (r.xp > 0) l10n.journeyRewardXp(formatNumberFull(r.xp, locale)),
    if (r.coins > 0) l10n.journeyRewardCoins(formatCoins(r.coins, locale)),
    if (r.diamonds > 0)
      l10n.journeyRewardDiamonds(formatNumberFull(r.diamonds, locale)),
  ];
  if (parts.isEmpty) return '';
  return parts.reduce((a, b) => l10n.journeyRewardJoin(a, b));
}

/// Localized status line of one milestone.
String playtimeStatusText(
  AppLocalizations l10n,
  Locale locale,
  Playtime p,
  PlaytimeMilestone m,
) {
  final left = formatNumberFull(p.remainingMinutes(m), locale);
  return switch (m.status) {
    PlaytimeMilestoneStatus.completed => l10n.journeyStatusCompleted,
    _ when p.remainingMinutes(m) == 0 => l10n.journeyUnlocking,
    PlaytimeMilestoneStatus.inProgress => l10n.journeyStatusNext(left),
    PlaytimeMilestoneStatus.locked => l10n.journeyStatusLocked(left),
  };
}

/// The next-reward sentence: "12 more minutes to unlock 40 XP + 10,000
/// coins", "Unlocking your reward…" or the calm all-done line.
String playtimeNextRewardText(
  AppLocalizations l10n,
  Locale locale,
  Playtime p,
) {
  final next = p.next;
  if (next == null) return l10n.journeyAllDone;
  final left = p.remainingMinutes(next);
  if (left == 0) return l10n.journeyUnlocking;
  return l10n.journeyNextReward(
    left,
    formatNumberFull(left, locale),
    playtimeRewardText(l10n, locale, next.reward),
  );
}

/// Circular progress toward the day's last milestone, with today's minutes
/// in the middle. Animates between server values only (never ticks).
class PlaytimeRing extends StatelessWidget {
  const PlaytimeRing({super.key, required this.playtime, this.size = 64});

  final Playtime playtime;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = Localizations.localeOf(context);
    final l10n = AppLocalizations.of(context);
    final done = playtime.allCompleted;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: playtime.fraction),
          duration: context.motion(AppDurations.slow),
          curve: AppCurves.standard,
          builder: (context, v, child) => CustomPaint(
            painter: _RingPainter(
              fraction: v,
              track: c.surfaceSunken,
              outline: c.outline.withValues(alpha: 0.6),
              colors: done
                  ? [BrandPalette.gold300, c.goldStrong]
                  : [c.brand, c.gold],
              stroke: size * 0.11,
            ),
            child: child,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatNumberFull(playtime.minutes, locale),
                  maxLines: 1,
                  style:
                      (size >= 72
                              ? context.textTheme.titleLarge
                              : context.textTheme.titleMedium)
                          ?.copyWith(
                            height: 1.05,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: done ? c.goldStrong : c.textPrimary,
                          ),
                ),
                Text(
                  l10n.journeyMinutesUnit,
                  maxLines: 1,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: c.textSecondary,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.track,
    required this.outline,
    required this.colors,
    required this.stroke,
  });

  final double fraction;
  final Color track;
  final Color outline;
  final List<Color> colors;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2 + 1);
    canvas.drawCircle(
      rect.center,
      arc.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    canvas.drawCircle(
      rect.center,
      arc.width / 2 + stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline,
    );
    final f = fraction.clamp(0.0, 1.0);
    if (f <= 0) return;
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * math.max(f, 0.02);
    canvas.drawArc(
      arc,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + 2 * math.pi,
          colors: colors,
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(arc),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.outline != outline ||
      old.stroke != stroke ||
      old.colors.first != colors.first ||
      old.colors.last != colors.last;
}

/// One milestone dot: gold check (completed), highlighted timer (in
/// progress) or a muted lock (locked).
class PlaytimeMilestoneMarker extends StatelessWidget {
  const PlaytimeMilestoneMarker({
    super.key,
    required this.status,
    this.size = 24,
  });

  final PlaytimeMilestoneStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (decoration, icon, color) = switch (status) {
      PlaytimeMilestoneStatus.completed => (
        BoxDecoration(
          shape: BoxShape.circle,
          gradient: c.goldGradient,
          boxShadow: [
            BoxShadow(
              color: c.gold.withValues(alpha: 0.45),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        Icons.check_rounded,
        c.onGold,
      ),
      PlaytimeMilestoneStatus.inProgress => (
        BoxDecoration(
          shape: BoxShape.circle,
          color: c.surface,
          border: Border.all(color: c.brand, width: 2.5),
          boxShadow: [
            BoxShadow(color: c.brand.withValues(alpha: 0.3), blurRadius: 8),
          ],
        ),
        Icons.timer_rounded,
        c.brand,
      ),
      PlaytimeMilestoneStatus.locked => (
        BoxDecoration(
          shape: BoxShape.circle,
          color: c.surfaceSunken,
          border: Border.all(color: c.outline),
        ),
        Icons.lock_rounded,
        c.textMuted,
      ),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: decoration,
        child: Icon(icon, size: size * 0.6, color: color),
      ),
    );
  }
}

/// Evenly spaced milestone markers on a track. The fill is piecewise: each
/// segment covers the minutes between two thresholds, so "18 of 60" sits
/// between the 10- and 30-minute markers. Follows the text direction.
class PlaytimeMilestoneTrack extends StatelessWidget {
  const PlaytimeMilestoneTrack({
    super.key,
    required this.playtime,
    this.markerSize = 24,
  });

  final Playtime playtime;
  final double markerSize;

  /// Track fill 0..1 for [p] (piecewise between thresholds).
  static double fillFor(Playtime p) {
    final ms = p.milestones;
    if (ms.isEmpty) return 0;
    final n = ms.length;
    var prev = 0;
    for (var i = 0; i < n; i++) {
      final t = ms[i].thresholdSeconds;
      if (p.seconds < t && !ms[i].completed) {
        final span = t - prev;
        final part = span <= 0 ? 0.0 : (p.seconds - prev) / span;
        return (i + part.clamp(0.0, 1.0)) / n;
      }
      prev = t;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final ms = playtime.milestones;
    final fill = fillFor(playtime);
    const labelWidth = 64.0;
    final r = markerSize / 2;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final span = math.max(0.0, w - 2 * r);
          double centerOf(int i) => r + span * (i + 1) / ms.length;
          return SizedBox(
            height: markerSize + 20,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PositionedDirectional(
                  start: r,
                  end: r,
                  top: r - 4,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surfaceSunken,
                      borderRadius: AppRadii.pillAll,
                      border: Border.all(
                        color: c.outline.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: r,
                  top: r - 4,
                  height: 8,
                  width: span,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: fill),
                      duration: context.motion(AppDurations.slow),
                      curve: AppCurves.standard,
                      builder: (context, v, _) => FractionallySizedBox(
                        widthFactor: v.clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: AppRadii.pillAll,
                            gradient: playtime.allCompleted
                                ? c.goldGradient
                                : c.brandGradient,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < ms.length; i++) ...[
                  PositionedDirectional(
                    start: centerOf(i) - r,
                    top: 0,
                    child: PlaytimeMilestoneMarker(
                      key: ValueKey('playtime-marker-${ms[i].id}'),
                      status: ms[i].status,
                      size: markerSize,
                    ),
                  ),
                  PositionedDirectional(
                    start: (centerOf(i) - labelWidth / 2).clamp(
                      0.0,
                      math.max(0.0, w - labelWidth),
                    ),
                    top: markerSize + 2,
                    width: labelWidth,
                    child: Text(
                      l10n.journeyMinutes(
                        formatNumberFull(ms[i].minutes, locale),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: i == ms.length - 1 && w > labelWidth
                          ? TextAlign.end
                          : TextAlign.center,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: ms[i].completed
                            ? c.goldStrong
                            : ms[i].status == PlaytimeMilestoneStatus.inProgress
                            ? c.textPrimary
                            : c.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
