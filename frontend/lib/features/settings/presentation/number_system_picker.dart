import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';

/// The number system amounts are shown in right now: the user's choice, or
/// the language default until they pick one. Watches the setting (call it
/// from `build`).
NumberSystem effectiveNumberSystem(WidgetRef ref, Locale locale) =>
    ref.watch(settingsControllerProvider).numberSystem ??
    AppNumberFormat.defaultSystemFor(locale);

String numberSystemName(AppLocalizations l10n, NumberSystem system) =>
    switch (system) {
      NumberSystem.indian => l10n.settingsNumberSystemIndian,
      NumberSystem.international => l10n.settingsNumberSystemInternational,
    };

/// Live example in [locale]: one lakh in full and ten lakh as a coin amount,
/// e.g. `1,00,000 · 10 Lakh` (Indian) or `100,000 · 1M` (international).
String numberSystemExample(
  AppLocalizations l10n,
  Locale locale,
  NumberSystem system,
) => l10n.settingsNumberSystemExample(
  formatNumberFull(AppNumberFormat.lakh, locale, system: system),
  formatCoins(10 * AppNumberFormat.lakh, locale, system: system),
);

/// Applies [system] immediately (every visible amount reformats) and
/// reports `settings_changed` when the shown format actually changes.
Future<void> applyNumberSystem(
  WidgetRef ref,
  Locale locale,
  NumberSystem system,
) async {
  final before =
      ref.read(settingsControllerProvider).numberSystem ??
      AppNumberFormat.defaultSystemFor(locale);
  await ref.read(settingsControllerProvider.notifier).setNumberSystem(system);
  if (before != system) {
    ref
        .read(analyticsServiceProvider)
        .settingsChanged(
          'international_numbers',
          system == NumberSystem.international,
        );
  }
}

/// Bottom sheet with the two number systems, each with a live example.
abstract final class NumberSystemSheet {
  static Future<void> show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBottomSheet.show<void>(
      context,
      title: l10n.settingsNumberSystem,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: NumberSystemPickerList(
          onSelected: (_) => Navigator.of(sheetContext).maybePop(),
        ),
      ),
    );
  }
}

/// Selectable list of the number systems; the current one is highlighted.
class NumberSystemPickerList extends ConsumerWidget {
  const NumberSystemPickerList({super.key, this.onSelected});

  final ValueChanged<NumberSystem>? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final current = effectiveNumberSystem(ref, locale);
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsNumberSystemHint,
          style: context.textTheme.bodyMedium?.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final system in NumberSystem.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _NumberSystemTile(
              key: ValueKey('numberSystem.${system.name}'),
              title: numberSystemName(l10n, system),
              example: numberSystemExample(l10n, locale, system),
              selected: system == current,
              onTap: () async {
                ref.read(hapticsServiceProvider).selection();
                ref.read(audioServiceProvider).play(Sfx.uiTab);
                await applyNumberSystem(ref, locale, system);
                onSelected?.call(system);
              },
            ),
          ),
      ],
    );
  }
}

class _NumberSystemTile extends StatelessWidget {
  const _NumberSystemTile({
    super.key,
    required this.title,
    required this.example,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String example;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      label: '$title, $example',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? c.brandSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mdAll,
          side: BorderSide(
            color: selected ? c.brand : c.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: AppRadii.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: selected ? c.brandGradient : null,
                    color: selected ? null : c.surfaceSunken,
                  ),
                  child: Icon(
                    Icons.numbers_rounded,
                    size: 20,
                    color: selected ? c.onBrand : c.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        example,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: AppDurations.fast,
                  child: Icon(Icons.check_circle_rounded, color: c.brand),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
