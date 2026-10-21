import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_providers.dart';
import '../../core/audio_haptics/audio_service.dart';
import '../../core/localization/language_controller.dart';
import '../../core/localization/number_format.dart';
import '../../core/protocol/protocol.dart';
import '../../core/realtime/realtime_providers.dart';
import '../../core/state/in_match_provider.dart';
import '../../features/app_update/application/store_launcher.dart';
import '../../features/app_update/presentation/optional_update_dialog.dart';
import '../../features/settings/presentation/analytics_consent_sheet.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../gate/app_gate_controller.dart';
import '../launch_intro.dart';
import '../router.dart';

/// App-wide, route-independent UI reactions, mounted once above the router:
///
/// - the optional-update dialog (startup prompt and post-startup, never in a
///   match, never over the launch intro or the first-launch language screen);
/// - the first-run analytics consent sheet (after sign-in, opt-in, after the
///   launch intro and the language choice);
/// - "signed in on another device" (WebSocket 4409) with Reconnect;
/// - level-up and coin-gain celebrations outside matches (game screens
///   handle their own in-match feedback).
class AppShellHost extends ConsumerStatefulWidget {
  const AppShellHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShellHost> createState() => _AppShellHostState();
}

class _AppShellHostState extends ConsumerState<AppShellHost> {
  bool _optionalShowing = false;
  bool _consentShowing = false;
  bool _consentHandledThisLaunch = false;
  bool _replacedShowing = false;

  BuildContext? get _navContext => rootNavigatorKey.currentContext;

  /// Startup dialogs wait for the launch intro and, on first launch, for the
  /// language choice (they would cover either screen).
  bool get _firstLaunchDone =>
      !ref.read(launchIntroPlayingProvider) &&
      ref.read(languageControllerProvider.notifier).hasExplicitChoice;

  void _recheckStartupDialogs() {
    if (!_firstLaunchDone) return;
    final gate = ref.read(appGateControllerProvider);
    _maybeShowOptionalUpdate(gate);
    if (gate.phase == GatePhase.ready) _maybeAskConsent();
  }

  void _afterFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  // ---------------------------------------------------------------- update

  void _maybeShowOptionalUpdate(GateState gate) {
    final wants =
        gate.phase == GatePhase.optionalUpdatePrompt ||
        (gate.optionalPromptPending && gate.phase == GatePhase.ready);
    final policy = gate.policy;
    if (!wants || _optionalShowing || policy == null) return;
    if (!_firstLaunchDone) return;
    _optionalShowing = true;
    _afterFrame(() async {
      final ctx = _navContext;
      if (ctx == null) {
        _optionalShowing = false;
        return;
      }
      final choice = await OptionalUpdateDialog.show(ctx, policy);
      final gateCtl = ref.read(appGateControllerProvider.notifier);
      if (choice == OptionalUpdateChoice.updateNow) {
        gateCtl.markVisitingStore();
        unawaited(ref.read(storeLauncherProvider).open(policy.storeUrl));
      }
      await gateCtl.resolveOptionalUpdate(
        later: choice == OptionalUpdateChoice.later,
      );
      _optionalShowing = false;
    });
  }

  // ---------------------------------------------------------------- consent

  void _maybeAskConsent() {
    if (_consentHandledThisLaunch || _consentShowing) return;
    if (!_firstLaunchDone) return;
    final gate = ref.read(appGateControllerProvider);
    if (gate.phase != GatePhase.ready || gate.optionalPromptPending) return;
    if (ref.read(analyticsConsentProvider) != AnalyticsConsent.unknown) return;
    if (ref.read(analyticsBackendProvider) == null) return;
    if (ref.read(inMatchProvider)) return;
    _consentShowing = true;
    Future<void>.delayed(const Duration(milliseconds: 700), () async {
      final ctx = _navContext;
      if (!mounted || ctx == null || !ctx.mounted) {
        _consentShowing = false;
        return;
      }
      _consentHandledThisLaunch = true;
      await AnalyticsConsentSheet.show(ctx);
      _consentShowing = false;
    });
  }

  // ---------------------------------------------------------------- 4409

  void _onRealtimeStatus(RealtimeStatus status) {
    if (status != RealtimeStatus.replaced || _replacedShowing) return;
    _replacedShowing = true;
    _afterFrame(() async {
      final ctx = _navContext;
      if (ctx == null) {
        _replacedShowing = false;
        return;
      }
      final l10n = AppLocalizations.of(ctx);
      final reconnect = await AppDialog.show<bool>(
        ctx,
        title: l10n.commonConnectionReplaced,
        content: const Center(
          child: Padding(
            padding: EdgeInsets.only(top: 4),
            child: ConnectionIndicator(status: RealtimeStatus.replaced),
          ),
        ),
        actions: [
          AppDialogAction(
            label: l10n.commonReconnect,
            variant: PremiumButtonVariant.primary,
            value: true,
          ),
          AppDialogAction(
            label: l10n.commonClose,
            variant: PremiumButtonVariant.ghost,
            value: false,
          ),
        ],
      );
      if (reconnect == true) {
        ref.read(realtimeConnectionProvider).reconnectNow();
      }
      _replacedShowing = false;
    });
  }

  // ---------------------------------------------------------------- rewards

  // Level-ups are celebrated by MetaShellHost (mounted in app.dart), which
  // defers the celebration while a match is on screen. Nothing to do here.
  void _onProgression(ProgressionUpdatedEvent e) {}

  void _onWallet(WalletUpdatedEvent e) {
    // A coin pack ("purchase" with coins added) has its own celebration
    // (CoinPurchaseHost); a refund ("refund", negative) only updates the
    // balance chips.
    if (e.deltaCoins <= 0 || e.reason == 'purchase') return;
    if (ref.read(inMatchProvider)) return;
    final ctx = _navContext;
    if (ctx == null) return;
    ref.read(audioServiceProvider).play(Sfx.coin);
    AppToast.show(
      ctx,
      AppLocalizations.of(ctx).homeCoinsGainedToast(
        formatCoins(e.deltaCoins, Localizations.localeOf(ctx)),
      ),
      kind: ToastKind.success,
      icon: Icons.paid_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GateState>(appGateControllerProvider, (_, next) {
      _maybeShowOptionalUpdate(next);
      if (next.phase == GatePhase.ready) _maybeAskConsent();
    });
    ref.listen<bool>(inMatchProvider, (_, inMatch) {
      if (!inMatch) _maybeAskConsent();
    });
    ref.listen<bool>(
      launchIntroPlayingProvider,
      (_, _) => _recheckStartupDialogs(),
    );
    ref.listen<Locale>(
      languageControllerProvider,
      (_, _) => _recheckStartupDialogs(),
    );
    ref.listen<RealtimeStatus>(realtimeStatusProvider, (_, s) {
      _onRealtimeStatus(s);
    });
    ref.listen<AsyncValue<ProgressionUpdatedEvent>>(
      progressionUpdatesProvider,
      (_, next) {
        final e = next.value;
        if (e != null) _onProgression(e);
      },
    );
    ref.listen<AsyncValue<WalletUpdatedEvent>>(walletUpdatesProvider, (
      _,
      next,
    ) {
      final e = next.value;
      if (e != null) _onWallet(e);
    });
    return widget.child;
  }
}
