import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_haptics/audio_service.dart';
import '../../core/audio_haptics/haptics_service.dart';
import '../../core/audio_haptics/reduced_motion.dart';
import '../../core/theme/app_theme.dart';

/// Visual style of a [PremiumButton].
enum PremiumButtonVariant { primary, secondary, ghost, danger, gold }

/// Height preset of a [PremiumButton]. Every size keeps a ≥ 48 dp touch
/// target.
enum PremiumButtonSize { small, medium, large }

/// The app's primary call-to-action button.
///
/// - Gradient surfaces with a top highlight and a soft colored shadow.
/// - Light haptic + click sound on tap (both honor Settings).
/// - When [onPressed] returns a `Future`, the button shows a spinner and
///   ignores further taps until it completes (prevents double submit).
/// - Disabled when [onPressed] is null.
class PremiumButton extends ConsumerStatefulWidget {
  const PremiumButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PremiumButtonVariant.primary,
    this.size = PremiumButtonSize.large,
    this.icon,
    this.leading,
    this.loading = false,
    this.expand = true,
    this.sound = Sfx.uiTap,
    this.semanticLabel,
  });

  final String label;
  final FutureOr<void> Function()? onPressed;
  final PremiumButtonVariant variant;
  final PremiumButtonSize size;
  final IconData? icon;

  /// Custom leading widget (e.g. a painted provider logo). Wins over [icon].
  final Widget? leading;

  /// External loading flag (in addition to the internal pending-future one).
  final bool loading;

  /// Fill the available width.
  final bool expand;

  /// Tap sound; null for silent.
  final Sfx? sound;
  final String? semanticLabel;

  @override
  ConsumerState<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends ConsumerState<PremiumButton> {
  bool _busy = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;
  bool get _showSpinner => widget.loading || _busy;

  Future<void> _handleTap() async {
    final cb = widget.onPressed;
    if (cb == null || _busy || widget.loading) return;
    ref.read(hapticsServiceProvider).light();
    final sfx = widget.sound;
    if (sfx != null) ref.read(audioServiceProvider).play(sfx);
    FutureOr<void> result;
    try {
      result = cb();
    } catch (e, s) {
      _report(e, s);
      return;
    }
    if (result is Future<void>) {
      setState(() => _busy = true);
      try {
        await result;
      } catch (e, s) {
        _report(e, s);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  void _report(Object e, StackTrace s) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: e,
      stack: s,
      library: 'PremiumButton',
      context: ErrorDescription('while handling a button tap'),
    ),
  );

  double get _height => switch (widget.size) {
    PremiumButtonSize.small => 40,
    PremiumButtonSize.medium => 48,
    PremiumButtonSize.large => 56,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = context.textTheme;
    final style = _ButtonStyleSpec.resolve(widget.variant, c);
    final radius = BorderRadius.circular(
      widget.size == PremiumButtonSize.small ? AppRadii.md : AppRadii.lg,
    );
    final textStyle =
        (widget.size == PremiumButtonSize.small
                ? text.labelMedium
                : text.labelLarge)
            ?.copyWith(
              color: style.foreground,
              fontSize: switch (widget.size) {
                PremiumButtonSize.small => 14,
                PremiumButtonSize.medium => 16,
                PremiumButtonSize.large => 17,
              },
            );
    final iconSize = widget.size == PremiumButtonSize.small ? 18.0 : 22.0;

    Widget? lead = widget.leading;
    if (lead == null && widget.icon != null) {
      lead = Icon(widget.icon, size: iconSize, color: style.foreground);
    }

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (lead != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: style.foreground, size: iconSize),
            child: lead,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.label,
              maxLines: 1,
              softWrap: false,
              style: textStyle,
            ),
          ),
        ),
      ],
    );

    final content = Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: _showSpinner ? 0 : 1,
          duration: AppDurations.fast,
          child: label,
        ),
        if (_showSpinner)
          SizedBox.square(
            dimension: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              valueColor: AlwaysStoppedAnimation(style.foreground),
            ),
          ),
      ],
    );

    final enabled = _enabled;
    final decoration = BoxDecoration(
      gradient: style.gradient,
      color: style.gradient == null ? style.fill : null,
      borderRadius: radius,
      border: style.border,
    );

    Widget button = Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? _handleTap : null,
          onHighlightChanged: (v) {
            if (_pressed != v) setState(() => _pressed = v);
          },
          splashColor: style.foreground.withValues(alpha: 0.14),
          highlightColor: style.foreground.withValues(alpha: 0.06),
          child: Stack(
            children: [
              if (style.highlight)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.white.withValues(alpha: 0.28),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Container(
                height: _height,
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: widget.size == PremiumButtonSize.small
                      ? AppSpacing.md
                      : AppSpacing.xl,
                ),
                alignment: Alignment.center,
                child: content,
              ),
            ],
          ),
        ),
      ),
    );

    // Shadows live outside the Material so they are never clipped by the
    // ink layer.
    button = AnimatedContainer(
      duration: AppDurations.fast,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: enabled && !_pressed ? style.shadows : const [],
      ),
      child: button,
    );

    button = AnimatedScale(
      scale: _pressed && !context.reduceMotion ? 0.965 : 1,
      duration: AppDurations.instant,
      curve: AppCurves.standard,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.45,
        duration: AppDurations.fast,
        child: button,
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled && !_showSpinner,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      onTap: enabled ? _handleTap : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fill = widget.expand && constraints.hasBoundedWidth;
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: fill
                  ? SizedBox(width: constraints.maxWidth, child: button)
                  : button,
            ),
          );
        },
      ),
    );
  }
}

class _ButtonStyleSpec {
  const _ButtonStyleSpec({
    required this.foreground,
    this.gradient,
    this.fill,
    this.border,
    this.shadows = const [],
    this.highlight = false,
  });

  final Color foreground;
  final Gradient? gradient;
  final Color? fill;
  final BoxBorder? border;
  final List<BoxShadow> shadows;
  final bool highlight;

  static List<BoxShadow> _glow(Color color, bool dark) => [
    BoxShadow(
      color: color.withValues(alpha: dark ? 0.45 : 0.32),
      blurRadius: 18,
      offset: const Offset(0, 7),
    ),
    BoxShadow(
      color: color.withValues(alpha: 0.18),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  static _ButtonStyleSpec resolve(PremiumButtonVariant v, AppColors c) {
    switch (v) {
      case PremiumButtonVariant.primary:
        return _ButtonStyleSpec(
          foreground: c.onBrand,
          gradient: c.brandGradient,
          shadows: _glow(c.brand, c.isDark),
          highlight: true,
        );
      case PremiumButtonVariant.gold:
        return _ButtonStyleSpec(
          foreground: c.onGold,
          gradient: c.goldGradient,
          shadows: _glow(c.goldStrong, c.isDark),
          highlight: true,
        );
      case PremiumButtonVariant.danger:
        return _ButtonStyleSpec(
          foreground: c.isDark ? c.onDanger : Colors.white,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(c.danger, Colors.white, 0.12)!,
              Color.lerp(c.danger, Colors.black, 0.12)!,
            ],
          ),
          shadows: _glow(c.danger, c.isDark),
          highlight: true,
        );
      case PremiumButtonVariant.secondary:
        return _ButtonStyleSpec(
          foreground: c.isDark ? c.textPrimary : c.brandStrong,
          fill: c.surfaceRaised,
          border: Border.all(color: c.outline, width: 1.2),
          shadows: c.shadow(AppElevation.low),
        );
      case PremiumButtonVariant.ghost:
        return _ButtonStyleSpec(
          foreground: c.isDark ? c.brandStrong : c.brand,
          fill: Colors.transparent,
        );
    }
  }
}
