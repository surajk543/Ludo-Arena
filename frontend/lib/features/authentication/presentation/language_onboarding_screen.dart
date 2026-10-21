import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/localization/language_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../settings/presentation/language_picker.dart';

/// First-launch language choice, shown after the launch intro on every
/// launch until the player confirms a language — signed in (guest restored)
/// or not. Tapping a language applies it immediately (the preview card
/// updates live); Continue confirms it, then the app goes on to the lobby,
/// the login screen or the loading splash, wherever the gate is.
class LanguageOnboardingScreen extends ConsumerWidget {
  const LanguageOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayeredBackground(
        style: LayeredBackgroundStyle.hero,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.maxContentWidth,
              ),
              // Scrollable list with a pinned call to action (no intrinsic
              // sizing, so it works at any text scale / screen height).
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.gutter,
                        AppSpacing.xxl,
                        AppSpacing.gutter,
                        AppSpacing.lg,
                      ),
                      children: [
                        const Center(child: BrandLogo(size: 88)),
                        const SizedBox(height: AppSpacing.lg),
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.onboardingLanguageTitle,
                            textAlign: TextAlign.center,
                            style: context.textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.onboardingLanguageSubtitle,
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        const LanguagePreviewCard(),
                        const SizedBox(height: AppSpacing.lg),
                        const LanguagePickerList(confirmOnSelect: false),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.sm,
                      AppSpacing.gutter,
                      AppSpacing.lg,
                    ),
                    child: PremiumButton(
                      label: l10n.commonContinue,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () async {
                        await ref
                            .read(languageControllerProvider.notifier)
                            .confirmCurrent();
                        if (context.mounted) context.go(AppRoutes.login);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
