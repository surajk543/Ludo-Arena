import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio_haptics/haptics_service.dart';
import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/theme/app_theme.dart';

/// One pill of [MetaPillTabs].
class MetaPill<T> {
  const MetaPill({
    required this.value,
    required this.label,
    this.icon,
    this.trailing,
    this.badge = 0,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Small secondary text (e.g. `2/4`), rendered LTR.
  final String? trailing;

  /// Attention dot count (e.g. pending requests); 0 hides it.
  final int badge;
}

/// Horizontally scrollable pill selector (tabs / filters). RTL-aware;
/// every pill keeps a ≥ 40 dp height and a selected semantics flag. The
/// selected pill is scrolled into view (also when opened by a deep link), so
/// a pill past the screen edge is never selected out of sight.
class MetaPillTabs<T> extends ConsumerStatefulWidget {
  const MetaPillTabs({
    super.key,
    required this.pills,
    required this.selected,
    required this.onSelected,
    this.dense = false,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  final List<MetaPill<T>> pills;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool dense;
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<MetaPillTabs<T>> createState() => _MetaPillTabsState<T>();
}

class _MetaPillTabsState<T> extends ConsumerState<MetaPillTabs<T>> {
  final _scroll = ScrollController();
  final _keys = <Object?, GlobalKey>{};

  /// The user scrolled the row by hand since the last reveal: content
  /// updates (e.g. a count appearing) then keep their scroll position.
  bool _userScrolled = false;

  static const double _revealMargin = AppSpacing.lg;

  @override
  void initState() {
    super.initState();
    _revealSelected(animate: false);
  }

  @override
  void didUpdateWidget(MetaPillTabs<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _userScrolled = false;
      _revealSelected(animate: true);
    } else if (!_userScrolled) {
      // Pills can change width (counts load later): keep the selection in view.
      _revealSelected(animate: false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls this row only (never the page) just enough to show the selected
  /// pill fully, with a small margin; a fully visible pill doesn't move.
  void _revealSelected({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final box = _keys[widget.selected]?.currentContext?.findRenderObject();
      if (box == null || !box.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final pos = _scroll.position;
      // Offsets that put the pill at the row's leading / trailing edge.
      final leading = viewport.getOffsetToReveal(box, 0).offset - _revealMargin;
      final trailing =
          viewport.getOffsetToReveal(box, 1).offset + _revealMargin;
      final double target;
      if (pos.pixels > leading) {
        target = leading;
      } else if (pos.pixels < trailing) {
        target = trailing;
      } else {
        return;
      }
      final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((clamped - pos.pixels).abs() < 1) return;
      final duration = context.motion(AppDurations.medium);
      if (!animate || duration == Duration.zero) {
        _scroll.jumpTo(clamped);
      } else {
        _scroll.animateTo(
          clamped,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pills = widget.pills;
    final c = context.colors;
    final height = widget.dense ? 36.0 : 42.0;
    return SizedBox(
      height: height + 8,
      child: NotificationListener<UserScrollNotification>(
        onNotification: (n) {
          if (n.direction != ScrollDirection.idle) _userScrolled = true;
          return false;
        },
        // All pills are built (there are only a few) so the selected one can
        // always be measured and revealed.
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          child: Row(
            children: [
              for (var i = 0; i < pills.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                _pill(context, pills[i], c, height),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context,
    MetaPill<T> p,
    AppColors c,
    double height,
  ) {
    final dense = widget.dense;
    final isSel = p.value == widget.selected;
    final fg = isSel ? c.onBrand : c.textPrimary;
    return Center(
      key: _keys.putIfAbsent(p.value, GlobalKey.new),
      child: Semantics(
        button: true,
        selected: isSel,
        label: p.badge > 0 ? '${p.label} (${p.badge})' : p.label,
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: context.motion(AppDurations.fast),
          height: height,
          decoration: BoxDecoration(
            gradient: isSel ? c.brandGradient : null,
            color: isSel ? null : c.surface,
            borderRadius: AppRadii.pillAll,
            border: Border.all(
              color: isSel
                  ? Colors.transparent
                  : c.outline.withValues(alpha: c.isDark ? 0.4 : 0.9),
            ),
            boxShadow: isSel ? c.shadow(AppElevation.low) : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: AppRadii.pillAll,
              onTap: () {
                if (isSel) return;
                ref.read(hapticsServiceProvider).selection();
                widget.onSelected(p.value);
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? AppSpacing.md : AppSpacing.lg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (p.icon != null) ...[
                      Icon(p.icon, size: dense ? 16 : 18, color: fg),
                      const SizedBox(width: AppSpacing.xs + 2),
                    ],
                    Text(
                      p.label,
                      maxLines: 1,
                      style:
                          (dense
                                  ? context.textTheme.labelMedium
                                  : context.textTheme.labelLarge)
                              ?.copyWith(color: fg),
                    ),
                    if (p.trailing != null) ...[
                      const SizedBox(width: AppSpacing.xs + 2),
                      Text(
                        p.trailing!,
                        textDirection: TextDirection.ltr,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: fg.withValues(alpha: 0.75),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (p.badge > 0) ...[
                      const SizedBox(width: AppSpacing.xs + 2),
                      Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSel ? c.onBrand : c.danger,
                          borderRadius: AppRadii.pillAll,
                        ),
                        child: Text(
                          '${p.badge}',
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: context.textTheme.labelSmall?.copyWith(
                            color: isSel ? c.brand : c.onDanger,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
