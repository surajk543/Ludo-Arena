import 'package:flutter/material.dart';
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
/// every pill keeps a ≥ 40 dp height and a selected semantics flag.
class MetaPillTabs<T> extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final height = dense ? 36.0 : 42.0;
    return SizedBox(
      height: height + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: pills.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final p = pills[i];
          final isSel = p.value == selected;
          final fg = isSel ? c.onBrand : c.textPrimary;
          return Center(
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
                      onSelected(p.value);
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
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
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
        },
      ),
    );
  }
}
