import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Decorative 45° gold sash reading "No Ads", for the top-end corner of a
/// card whose corner radius is [cornerRadius] (top-right in LTR, top-left in
/// RTL, mirrored with the header layout).
///
/// The widget is a [reach] × [reach] square: place its top-end corner on the
/// card's top-end corner. The band is clipped to the card's rounded corner,
/// never takes pointer events, and is announced once as "No Ads" (no
/// action).
///
/// The label blinks on a loop (one gentle blink every [blinkPeriod], well
/// below the 3 flashes per second limit for flashing content); with reduced
/// motion (system or in-app setting) it stays still and fully visible.
class NoAdsRibbon extends StatefulWidget {
  const NoAdsRibbon({super.key, this.cornerRadius = AppRadii.xl});

  /// Corner radius of the card the ribbon sits on.
  final double cornerRadius;

  /// Where the band's inner edge meets the card's top and end edges,
  /// measured from the corner.
  static const double reach = 54;

  /// Width of the band, perpendicular to its 45° direction.
  static const double thickness = 18;

  /// Largest text scale applied to the label; the band does not grow, so the
  /// header controls stay clear at any text size.
  static const double maxTextScale = 1.2;

  static const double _fontSize = 10;

  /// One blink: the label holds, fades to [blinkMinOpacity], holds, and
  /// fades back.
  static const Duration blinkPeriod = Duration(milliseconds: 1400);

  /// Opacity of the label at the bottom of a blink.
  static const double blinkMinOpacity = 0.15;

  /// Label opacity over one [blinkPeriod].
  static final Animatable<double> _blink = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1), weight: 45),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: blinkMinOpacity,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 15,
    ),
    TweenSequenceItem(tween: ConstantTween(blinkMinOpacity), weight: 25),
    TweenSequenceItem(
      tween: Tween(
        begin: blinkMinOpacity,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 15,
    ),
  ]);

  /// Space kept between the label and the card edges.
  static const double _margin = 1.5;

  /// Perpendicular distance from the card corner to the band's inner edge.
  /// Anything farther than this from the corner is never covered.
  static double get innerEdge => reach / math.sqrt2;

  /// Perpendicular distance from the card corner to the band's centre line.
  static double get midline => innerEdge - thickness / 2;

  /// Font size and label box width for [text]: the text scale is capped at
  /// [maxTextScale], then long translations shrink until the label fits the
  /// visible part of the band. A w × h label centred on the midline touches
  /// the card edges when w + h = 2 × midline (the band's chord at the
  /// label's corner-side edge).
  static ({double fontSize, double width}) _fit(
    String text,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final size = scaler.clamp(maxScaleFactor: maxTextScale).scale(_fontSize);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      ),
      textDirection: direction,
      maxLines: 1,
    )..layout();
    final room = 2 * (midline - _margin);
    final shrink = math.min(1.0, room / (painter.width + painter.height));
    final width = room - painter.height * shrink;
    painter.dispose();
    return (fontSize: size * shrink, width: width);
  }

  @override
  State<NoAdsRibbon> createState() => _NoAdsRibbonState();
}

class _NoAdsRibbonState extends State<NoAdsRibbon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NoAdsRibbon.blinkPeriod,
  );
  late final Animation<double> _opacity = _controller.drive(NoAdsRibbon._blink);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller
        ..stop()
        ..value = 0; // fully visible
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cornerRadius = widget.cornerRadius;
    const reach = NoAdsRibbon.reach;
    const thickness = NoAdsRibbon.thickness;
    final innerEdge = NoAdsRibbon.innerEdge;
    final midline = NoAdsRibbon.midline;
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final direction = Directionality.of(context);
    final rtl = direction == TextDirection.rtl;
    final label = l10n.homeNoAdsRibbon;
    final style = (context.textTheme.labelSmall ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
      height: 1.1,
      letterSpacing: 0.3,
      color: c.onGold,
    );
    final fit = NoAdsRibbon._fit(
      label,
      style,
      MediaQuery.textScalerOf(context),
      direction,
    );

    // Band centre on the corner's diagonal; the band is longer than its
    // visible chord and clipped to the card corner.
    final offset = midline / math.sqrt2;
    final center = Offset(rtl ? offset : reach - offset, offset);
    final length = 2 * innerEdge + thickness;

    final band = DecoratedBox(
      decoration: BoxDecoration(
        gradient: c.goldGradient,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: c.isDark ? 0.4 : 0.65),
            width: 0.8,
          ),
          bottom: BorderSide(
            color: c.onGold.withValues(alpha: 0.28),
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: c.shadowColor.withValues(alpha: c.isDark ? 0.5 : 0.22),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: fit.width,
          // Safety net only: [fit] already sized the text to this box.
          child: FadeTransition(
            opacity: _opacity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                textScaler: TextScaler.noScaling, // capped in [_fit]
                style: style.copyWith(fontSize: fit.fontSize),
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: IgnorePointer(
        child: SizedBox.square(
          dimension: reach,
          child: ClipRRect(
            borderRadius: BorderRadiusDirectional.only(
              topEnd: Radius.circular(cornerRadius),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: center.dx - length / 2,
                  top: center.dy - thickness / 2,
                  width: length,
                  height: thickness,
                  child: Transform.rotate(
                    angle: rtl ? -math.pi / 4 : math.pi / 4,
                    child: band,
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
