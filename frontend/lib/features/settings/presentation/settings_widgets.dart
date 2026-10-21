import 'package:flutter/material.dart';

import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/widgets.dart';

/// A titled group of settings rows on a surface card.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: context.textTheme.titleSmall?.copyWith(color: c.brand),
              ),
            ),
          ),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: AppSpacing.lg + 36 + AppSpacing.md,
                      endIndent: AppSpacing.lg,
                      color: c.divider,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.brand;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: c.isDark ? 0.2 : 0.12),
        borderRadius: AppRadii.smAll,
      ),
      child: Icon(icon, color: tint, size: 20),
    );
  }
}

/// Toggle row.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? color;

  void _toggle(BuildContext context, bool v) {
    onChanged!(v);
    // After the change: switching Sound on is confirmed audibly, switching
    // it off is silent.
    playUiSound(context, Sfx.uiToggle);
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListTile(
        leading: _TileIcon(icon: icon, color: color),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged == null ? null : (v) => _toggle(context, v),
        ),
        onTap: onChanged == null ? null : () => _toggle(context, !value),
        minVerticalPadding: AppSpacing.sm,
      ),
    );
  }
}

/// Slider row (0..1) with the value shown at the end, e.g. a volume.
class SettingsSliderTile extends StatelessWidget {
  const SettingsSliderTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.format,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions = 20,
    this.color,
  });

  final IconData icon;
  final String title;
  final double value;

  /// Display / screen-reader text for a value (e.g. a localized percentage).
  final String Function(double value) format;

  /// Null disables the slider.
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int divisions;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onChanged != null;
    final valueLabel = format(value);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          _TileIcon(icon: icon, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: enabled ? null : c.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ExcludeSemantics(
                      child: Text(
                        valueLabel,
                        style: context.textTheme.labelLarge?.copyWith(
                          color: enabled ? c.textSecondary : c.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: value.clamp(0.0, 1.0),
                  divisions: divisions,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                  semanticFormatterCallback: format,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Navigation / action row.
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      leading: _TileIcon(icon: icon, color: destructive ? c.danger : color),
      title: Text(
        title,
        style: destructive
            ? context.textTheme.titleMedium?.copyWith(color: c.danger)
            : null,
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(
                  Icons.chevron_right_rounded,
                  color: c.textMuted,
                  // Directional: mirrored in RTL by Icon (matchTextDirection).
                )),
      onTap: onTap == null
          ? null
          : () {
              playUiSound(context, Sfx.uiTap);
              onTap!();
            },
      minVerticalPadding: AppSpacing.sm,
    );
  }
}
