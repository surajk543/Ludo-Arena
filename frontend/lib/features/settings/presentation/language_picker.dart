import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';
import '../../../core/localization/language_controller.dart';
import '../../../core/localization/supported_locales.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';

/// Native language name (`English`, `हिन्दी`, `اردو`, `العربية`,
/// `Bahasa Indonesia`), read from that language's own ARB.
String nativeLanguageName(Locale locale) =>
    lookupAppLocalizations(locale).languageNameNative;

/// Applies [locale] immediately (no sign-out, no session/wallet/match
/// changes) and reports `language_changed`. [confirm]: see
/// `LanguageController.setLocale`.
Future<void> applyLanguage(
  WidgetRef ref,
  Locale locale, {
  bool confirm = true,
}) async {
  final current = ref.read(languageControllerProvider);
  await ref
      .read(languageControllerProvider.notifier)
      .setLocale(locale, confirm: confirm);
  if (current.languageCode != locale.languageCode) {
    ref.read(analyticsServiceProvider).languageChanged(locale.languageCode);
  }
}

/// Selectable list of the supported languages with native names; the
/// current one is highlighted.
class LanguagePickerList extends ConsumerWidget {
  const LanguagePickerList({
    super.key,
    this.onSelected,
    this.confirmOnSelect = true,
  });

  final ValueChanged<Locale>? onSelected;

  /// Whether a tap is the user's final choice (Settings). The first-launch
  /// screen previews taps and confirms with its Continue button.
  final bool confirmOnSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageControllerProvider);
    final c = context.colors;
    return Column(
      children: [
        for (final locale in SupportedLocales.all)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _LanguageTile(
              locale: locale,
              selected: locale.languageCode == current.languageCode,
              colors: c,
              onTap: () async {
                ref.read(hapticsServiceProvider).selection();
                ref.read(audioServiceProvider).play(Sfx.uiTab);
                await applyLanguage(ref, locale, confirm: confirmOnSelect);
                onSelected?.call(locale);
              },
            ),
          ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.locale,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final Locale locale;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = nativeLanguageName(locale);
    final rtl = SupportedLocales.isRtl(locale);
    return Semantics(
      selected: selected,
      button: true,
      label: name,
      child: Material(
        color: selected ? colors.brandSoft : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mdAll,
          side: BorderSide(
            color: selected ? colors.brand : colors.outline,
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
                    gradient: selected ? colors.brandGradient : null,
                    color: selected ? null : colors.surfaceSunken,
                  ),
                  child: Text(
                    locale.languageCode.toUpperCase(),
                    style: context.textTheme.labelSmall?.copyWith(
                      color: selected ? colors.onBrand : colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  // Each name keeps its own script direction but all names
                  // line up at the start edge of the current UI direction.
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      name,
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      style: context.textTheme.titleMedium,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: AppDurations.fast,
                  child: Icon(Icons.check_circle_rounded, color: colors.brand),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Live preview of the current language (headline, body, numbers).
class LanguagePreviewCard extends StatelessWidget {
  const LanguagePreviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return SurfaceCard(
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [c.surfaceRaised, c.brandSoft],
      ),
      child: Row(
        children: [
          const BrandLogo(size: 52),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.onboardingPreviewLabel,
                  style: context.textTheme.labelSmall?.copyWith(color: c.brand),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.onboardingPreviewTitle,
                  style: context.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.onboardingPreviewBody,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet with the language list + preview (login screen, settings).
abstract final class LanguageSheet {
  static Future<void> show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBottomSheet.show<void>(
      context,
      title: l10n.settingsLanguage,
      builder: (_) => const Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LanguagePreviewCard(),
            SizedBox(height: AppSpacing.lg),
            LanguagePickerList(),
          ],
        ),
      ),
    );
  }
}
