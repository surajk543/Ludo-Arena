import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/audio_haptics/audio_service.dart';
import '../../core/theme/app_theme.dart';

/// Solid elevated surface with soft shadow and a hairline highlight. The
/// building block for panels, list groups and game cards.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.elevation = AppElevation.low,
    this.borderRadius,
    this.gradient,
    this.color,
    this.border,
    this.sound = Sfx.uiTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Tap sound (only when [onTap] is set); null for silent.
  final Sfx? sound;
  final AppElevation elevation;
  final BorderRadius? borderRadius;
  final Gradient? gradient;
  final Color? color;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = borderRadius ?? AppRadii.lgAll;
    final decoration = BoxDecoration(
      color: gradient == null ? (color ?? c.surface) : null,
      gradient: gradient,
      borderRadius: radius,
      border:
          border ??
          Border.all(
            color: c.isDark
                ? Colors.white.withValues(alpha: 0.06)
                : c.outline.withValues(alpha: 0.7),
          ),
    );
    // Shadow outside the Material so the ink layer never clips it.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: c.shadow(elevation),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            onTap: _tapHandler(context, onTap, sound),
            borderRadius: radius,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// [onTap] with its UI sound (null stays null: disabled cards are silent).
VoidCallback? _tapHandler(BuildContext context, VoidCallback? onTap, Sfx? s) {
  if (onTap == null) return null;
  if (s == null) return onTap;
  return () {
    playUiSound(context, s);
    onTap();
  };
}

/// Frosted translucent card for content layered over rich backgrounds
/// (headers, overlays, hero sections).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.borderRadius,
    this.sound = Sfx.uiTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  /// Tap sound (only when [onTap] is set); null for silent.
  final Sfx? sound;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = borderRadius ?? AppRadii.lgAll;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.glassFill,
                  Color.lerp(c.glassFill, c.brandSoft, 0.35)!,
                ],
              ),
              border: Border.all(color: c.glassBorder),
            ),
            child: InkWell(
              onTap: _tapHandler(context, onTap, sound),
              borderRadius: radius,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slim ornamental divider with a gold diamond in the middle.
class RoyalDivider extends StatelessWidget {
  const RoyalDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget line(bool start) => Expanded(
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: start
                ? [c.divider.withValues(alpha: 0), c.divider]
                : [c.divider, c.divider.withValues(alpha: 0)],
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: indent,
        vertical: AppSpacing.sm,
      ),
      child: ExcludeSemantics(
        child: Row(
          children: [
            line(true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    gradient: c.goldGradient,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            ),
            line(false),
          ],
        ),
      ),
    );
  }
}
