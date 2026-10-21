import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_haptics/haptics_service.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Glassy round icon button for headers and toolbars.
class IconCircleButton extends ConsumerWidget {
  const IconCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.highlighted = false,
    this.badgeCount,
    this.size = 44,
    this.mirrorInRtl = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Tooltip and screen-reader label.
  final String tooltip;

  /// Gold accent ring (e.g. "Save Progress" for guests).
  final bool highlighted;

  /// Small count badge at the top-end corner (hidden when null or 0).
  final int? badgeCount;
  final double size;

  /// Flip the icon horizontally in RTL (only for directional glyphs).
  final bool mirrorInRtl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final count = badgeCount ?? 0;
    final enabled = onPressed != null;

    Widget glyph = Icon(
      icon,
      size: size * 0.5,
      color: highlighted ? c.goldStrong : c.textPrimary,
    );
    if (mirrorInRtl && rtl) {
      glyph = Transform.flip(flipX: true, child: glyph);
    }

    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.glassFill, Color.lerp(c.glassFill, c.brandSoft, 0.5)!],
        ),
        border: Border.all(
          color: highlighted ? c.gold : c.glassBorder,
          width: highlighted ? 1.6 : 1,
        ),
        boxShadow: [
          ...c.shadow(AppElevation.low),
          if (highlighted)
            BoxShadow(color: c.gold.withValues(alpha: 0.35), blurRadius: 12),
        ],
      ),
      alignment: Alignment.center,
      child: glyph,
    );

    final label = count > 0
        ? '$tooltip, ${l10n.widgetsNewItems(count)}'
        : tooltip;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: SizedBox(
            width: size < 48 ? 48 : size,
            height: size < 48 ? 48 : size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: enabled
                        ? () {
                            ref.read(hapticsServiceProvider).selection();
                            onPressed!();
                          }
                        : null,
                    child: circle,
                  ),
                ),
                if (count > 0)
                  PositionedDirectional(
                    top: (size < 48 ? (48 - size) / 2 : 0) - 2,
                    end: (size < 48 ? (48 - size) / 2 : 0) - 2,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: c.danger,
                        borderRadius: AppRadii.pillAll,
                        border: Border.all(color: c.surface, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: context.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          height: 1,
                        ),
                      ),
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
