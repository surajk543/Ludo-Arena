import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/gate/app_gate_controller.dart';
import '../../../core/audio_haptics/reduced_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';

/// Branded splash shown for every transient gate phase, so nothing behind
/// the gate (home, games) can flash before the policy and session are known.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final phase = ref.watch(appGateControllerProvider.select((s) => s.phase));
    final status = switch (phase) {
      GatePhase.restoringSession => l10n.gateStatusSigningIn,
      GatePhase.loadingWallet => l10n.gateStatusLoadingProfile,
      _ => l10n.gateStatusChecking,
    };
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayeredBackground(
        style: LayeredBackgroundStyle.hero,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandLogo(size: 132, showWordmark: true),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.gateSplashTagline,
                    textAlign: TextAlign.center,
                    style: context.textTheme.titleMedium?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.huge),
                  SizedBox(
                    width: 160,
                    child: ClipRRect(
                      borderRadius: AppRadii.pillAll,
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        color: c.gold,
                        backgroundColor: c.surfaceSunken,
                        // Static bar when motion is reduced.
                        value: context.reduceMotion ? 0.6 : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AnimatedSwitcher(
                    duration: context.motion(AppDurations.fast),
                    child: Text(
                      status,
                      key: ValueKey(status),
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodyMedium,
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
