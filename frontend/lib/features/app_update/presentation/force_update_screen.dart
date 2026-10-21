import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/gate/app_gate_controller.dart';
import '../../../core/config/app_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/store_launcher.dart';
import 'gate_illustrations.dart';
import 'gate_layout.dart';

/// Blocking "update required" screen. Cannot be dismissed (back is
/// disabled); the only ways out are updating or the server lowering the
/// minimum version (re-checked on resume / Check again).
class ForceUpdateScreen extends ConsumerWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gate = ref.watch(appGateControllerProvider);
    final info = ref.watch(appInfoProvider);
    final policy = gate.policy;
    final c = context.colors;

    final required = policy == null || policy.minimumSupportedVersion.isEmpty
        ? null
        : (policy.minimumSupportedBuild > 0
              ? '${policy.minimumSupportedVersion} (${policy.minimumSupportedBuild})'
              : policy.minimumSupportedVersion);
    final storeReady = policy?.canOpenStore ?? false;

    Future<void> openStore() async {
      final url = policy?.storeUrl ?? '';
      ref.read(appGateControllerProvider.notifier).markVisitingStore();
      final ok = await ref.read(storeLauncherProvider).open(url);
      if (!ok && context.mounted) {
        AppToast.show(
          context,
          l10n.gateStoreNotReadyTitle,
          kind: ToastKind.warning,
        );
      }
    }

    return PopScope(
      canPop: false,
      child: GateLayout(
        art: GateArt.update,
        title: (policy?.title.isNotEmpty ?? false)
            ? policy!.title
            : l10n.gateForceUpdateTitle,
        message: (policy?.message.isNotEmpty ?? false)
            ? policy!.message
            : l10n.gateForceUpdateMessage,
        details: [
          SurfaceCard(
            child: Column(
              children: [
                GateInfoRow(
                  label: l10n.gateInstalledVersion,
                  value: info.display,
                ),
                if (required != null) ...[
                  const RoyalDivider(),
                  GateInfoRow(
                    label: l10n.gateRequiredVersion,
                    value: required,
                    emphasize: true,
                  ),
                ],
              ],
            ),
          ),
          if (!storeReady) ...[
            const SizedBox(height: AppSpacing.lg),
            SurfaceCard(
              color: c.goldSoft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.hourglass_top_rounded, color: c.goldStrong),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.gateStoreNotReadyTitle,
                          style: context.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.gateStoreNotReadyMessage,
                          style: context.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        actions: [
          if (storeReady)
            PremiumButton(
              label: l10n.gateUpdateNow,
              icon: Icons.system_update_alt_rounded,
              variant: PremiumButtonVariant.gold,
              onPressed: openStore,
            ),
          PremiumButton(
            label: storeReady ? l10n.gateCheckAgain : l10n.commonRetry,
            icon: Icons.refresh_rounded,
            variant: storeReady
                ? PremiumButtonVariant.ghost
                : PremiumButtonVariant.primary,
            loading: gate.rechecking,
            onPressed: () =>
                ref.read(appGateControllerProvider.notifier).retry(),
          ),
        ],
      ),
    );
  }
}
