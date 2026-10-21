import 'package:flutter/material.dart';

import '../../../../core/protocol/protocol.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';

/// Header row used by the play setup screens (back + title + connection).
class PlayHeader extends StatelessWidget {
  const PlayHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
    this.closeIcon = false,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;
  final bool closeIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 4),
      child: Row(
        children: [
          IconCircleButton(
            icon: closeIcon ? Icons.close_rounded : Icons.arrow_back_rounded,
            tooltip: l10n.commonBack,
            onPressed: onBack,
            size: 40,
            mirrorInRtl: !closeIcon,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleLarge,
              ),
            ),
          ),
          ?trailing,
          const SizedBox(width: AppSpacing.xs),
          const ConnectionIndicator(compact: true),
        ],
      ),
    );
  }
}

/// Section label inside the setup forms.
class PlayFieldLabel extends StatelessWidget {
  const PlayFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
    child: Text(text, style: context.textTheme.titleSmall),
  );
}

/// Ludo / Snakes & Ladders picker.
class PlayGamePicker extends StatelessWidget {
  const PlayGamePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayFieldLabel(l10n.playGameLabel),
        ChoiceChips<String>(
          value: value,
          onChanged: onChanged,
          options: [
            ChoiceOption(
              value: GameIds.ludo,
              label: l10n.commonGameLudo,
              icon: Icons.grid_view_rounded,
            ),
            ChoiceOption(
              value: GameIds.snakesLadders,
              label: l10n.commonGameSnakesLadders,
              icon: Icons.stairs_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

/// Classic / Quick Ludo picker.
class PlayVariantPicker extends StatelessWidget {
  const PlayVariantPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayFieldLabel(l10n.playModeLabel),
        ChoiceChips<String>(
          value: value,
          onChanged: onChanged,
          options: [
            ChoiceOption(
              value: GameVariants.classic,
              label: l10n.commonVariantClassic,
              caption: l10n.playVariantClassicCaption,
            ),
            ChoiceOption(
              value: GameVariants.quick,
              label: l10n.commonVariantQuick,
              caption: l10n.playVariantQuickCaption,
            ),
          ],
        ),
      ],
    );
  }
}

/// Tinted note card (entry fee, warnings, errors).
class PlayNote extends StatelessWidget {
  const PlayNote({
    super.key,
    required this.text,
    this.icon,
    this.leading,
    this.color,
  });

  final String text;
  final IconData? icon;
  final Widget? leading;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.brand;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: c.isDark ? 0.16 : 0.08),
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          leading ?? Icon(icon ?? Icons.info_rounded, color: tint, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: context.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
