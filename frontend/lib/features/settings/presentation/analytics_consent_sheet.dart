import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';

/// First-run, opt-in analytics consent. Shown once after sign-in when
/// Firebase Analytics is configured and no choice was made yet. Both answers
/// are persisted; the Settings toggle changes it later.
abstract final class AnalyticsConsentSheet {
  static Future<void> show(BuildContext context) => AppBottomSheet.show<void>(
    context,
    isDismissible: false,
    builder: (_) => const _ConsentBody(),
  );
}

class _ConsentBody extends ConsumerWidget {
  const _ConsentBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: c.goldGradient,
                boxShadow: c.shadow(AppElevation.low),
              ),
              child: Icon(Icons.insights_rounded, color: c.onGold, size: 36),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.settingsConsentTitle,
            textAlign: TextAlign.center,
            style: context.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.settingsConsentMessage,
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          PremiumButton(
            label: l10n.settingsConsentAllow,
            icon: Icons.check_rounded,
            onPressed: () async {
              await ref.read(analyticsConsentProvider.notifier).grant();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          PremiumButton(
            label: l10n.settingsConsentDeny,
            variant: PremiumButtonVariant.ghost,
            onPressed: () async {
              await ref.read(analyticsConsentProvider.notifier).deny();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
