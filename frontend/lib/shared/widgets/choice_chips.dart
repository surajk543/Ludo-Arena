import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_haptics/haptics_service.dart';
import '../../core/audio_haptics/reduced_motion.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// One option of a [ChoiceChips] selector.
class ChoiceOption<T> {
  const ChoiceOption({
    required this.value,
    required this.label,
    this.caption,
    this.icon,
  });

  final T value;
  final String label;

  /// Small secondary line (e.g. "Entry 1,000").
  final String? caption;
  final IconData? icon;
}

/// Premium segmented selector (capacity / variant / bot count pickers).
/// Lays options out in one row when they fit, otherwise wraps.
class ChoiceChips<T> extends ConsumerWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<ChoiceOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void select(T v) {
      if (v == value) return;
      ref.read(hapticsServiceProvider).selection();
      onChanged(v);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final n = options.length;
        final perItem = n == 0 ? 0.0 : (constraints.maxWidth - (n - 1) * 8) / n;
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final row = perItem >= 84 * scale;
        final tiles = [
          for (final o in options)
            _ChoiceTile<T>(
              option: o,
              selected: o.value == value,
              onTap: () => select(o.value),
            ),
        ];
        if (row) {
          // Equal-height tiles even when only some have a caption.
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }
        final width = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - AppSpacing.sm) / 2
            : 140.0;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final fg = selected ? c.brandStrong : c.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: [option.label, ?option.caption].join(', '),
      hint: selected ? l10n.widgetsSelected : null,
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedContainer(
        duration: context.motion(AppDurations.fast),
        curve: AppCurves.standard,
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: selected ? c.brandSoft : c.surfaceSunken,
          borderRadius: AppRadii.mdAll,
          border: Border.all(
            color: selected ? c.brand : c.outline,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.brand.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadii.mdAll,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (option.icon != null) ...[
                        Icon(option.icon, size: 18, color: fg),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: context.textTheme.titleSmall?.copyWith(
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (option.caption != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      option.caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: selected ? c.brandStrong : c.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
