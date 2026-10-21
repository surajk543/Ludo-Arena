import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/audio_haptics/reduced_motion.dart';
import '../../core/localization/number_format.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'cosmetic_names.dart';

/// Hexagonal level badge (violet gem with a gold rim).
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level, this.size = 32});

  final int level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = '$level';
    return Semantics(
      label: l10n.commonLevel(level),
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size * 1.08,
        child: CustomPaint(
          painter: const _HexBadgePainter(),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(size * 0.16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  textDirection: TextDirection.ltr,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontSize: size * 0.42,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    shadows: const [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexBadgePainter extends CustomPainter {
  const _HexBadgePainter();

  Path _hex(Size size, double inset) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final ang = -math.pi / 2 + i * math.pi / 3;
      final pt = Offset(
        w / 2 + math.cos(ang) * (w / 2 - inset),
        h / 2 + math.sin(ang) * (h / 2 - inset),
      );
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outer = _hex(size, 0);
    final inner = _hex(size, size.width * 0.09);
    canvas.drawShadow(outer, Colors.black, 2, false);
    canvas.drawPath(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BrandPalette.gold300, BrandPalette.gold600],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      inner,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandPalette.royal400, BrandPalette.royal700],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipPath(inner);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.45),
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HexBadgePainter oldDelegate) => false;
}

/// XP progress within the current level. [current] = xp − levelXp,
/// [total] = nextLevelXp. Animates the fill and plays a one-shot gold
/// shimmer when progress changes (skipped under reduced motion).
class XpProgressBar extends StatefulWidget {
  const XpProgressBar({
    super.key,
    required this.current,
    required this.total,
    this.showLabel = true,
    this.height = 10,
  });

  final int current;
  final int total;
  final bool showLabel;
  final double height;

  @override
  State<XpProgressBar> createState() => _XpProgressBarState();
}

class _XpProgressBarState extends State<XpProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  double get _fraction =>
      widget.total <= 0 ? 0 : (widget.current / widget.total).clamp(0.0, 1.0);

  @override
  void didUpdateWidget(covariant XpProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.current != widget.current ||
            oldWidget.total != widget.total) &&
        !ReducedMotion.of(context)) {
      _shimmer.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final cur = formatNumberFull(math.max(0, widget.current), locale);
    final tot = formatNumberFull(math.max(0, widget.total), locale);
    final reduce = context.reduceMotion;

    final bar = TweenAnimationBuilder<double>(
      tween: Tween(end: _fraction),
      duration: reduce ? Duration.zero : AppDurations.slow,
      curve: AppCurves.standard,
      builder: (context, value, _) => AnimatedBuilder(
        animation: _shimmer,
        builder: (context, _) => CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _XpBarPainter(
            fraction: value,
            track: c.surfaceSunken,
            trackBorder: c.outline.withValues(alpha: 0.6),
            shimmer: _shimmer.isAnimating ? _shimmer.value : -1,
            rtl: Directionality.of(context) == TextDirection.rtl,
          ),
        ),
      ),
    );

    return Semantics(
      label: l10n.widgetsXpLabel(cur, tot),
      value: '${(_fraction * 100).round()}%',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: widget.height, child: bar),
          if (widget.showLabel) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                l10n.commonXpProgress(cur, tot),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _XpBarPainter extends CustomPainter {
  _XpBarPainter({
    required this.fraction,
    required this.track,
    required this.trackBorder,
    required this.shimmer,
    required this.rtl,
  });

  final double fraction;
  final Color track;
  final Color trackBorder;
  final double shimmer;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final full = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(full, Paint()..color = track);
    canvas.drawRRect(
      full,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = trackBorder,
    );
    if (fraction <= 0) return;
    final w = math.max(size.height, size.width * fraction);
    final left = rtl ? size.width - w : 0.0;
    final fillRect = Rect.fromLTWH(left, 0, w, size.height);
    final fill = RRect.fromRectAndRadius(fillRect, r);
    canvas.drawRRect(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
          end: rtl ? Alignment.centerLeft : Alignment.centerRight,
          colors: const [
            BrandPalette.gold600,
            BrandPalette.gold400,
            BrandPalette.gold300,
          ],
        ).createShader(fillRect),
    );
    canvas.save();
    canvas.clipRRect(fill);
    canvas.drawRect(
      Rect.fromLTWH(left, 0, w, size.height * 0.45),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    if (shimmer >= 0) {
      final x = rtl
          ? size.width - (size.width + 60) * shimmer + 30
          : (size.width + 60) * shimmer - 30;
      canvas.drawRect(
        Rect.fromLTWH(x - 24, 0, 48, size.height),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.7),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(x - 24, 0, 48, size.height)),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_XpBarPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.trackBorder != trackBorder ||
      old.shimmer != shimmer ||
      old.rtl != rtl;
}

/// Player title chip (`title_*` id), tinted by rarity.
class TitleChip extends StatelessWidget {
  const TitleChip({super.key, required this.titleId});

  final String titleId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final rarity = cosmeticRarity(titleId);
    final tint = rarity.color(c);
    final name = cosmeticName(l10n, titleId);
    final fancy =
        rarity == CosmeticRarity.epic || rarity == CosmeticRarity.legendary;
    return Semantics(
      label: l10n.widgetsTitleLabel(name),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 10, 3),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: c.isDark ? 0.18 : 0.12),
          borderRadius: AppRadii.pillAll,
          border: Border.all(color: tint.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              fancy
                  ? Icons.workspace_premium_rounded
                  : Icons.military_tech_rounded,
              size: 14,
              color: tint,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelMedium?.copyWith(color: tint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
