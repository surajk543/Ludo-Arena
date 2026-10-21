import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/network/api_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/session_controller.dart';
import '../data/provider_credential.dart';
import '../identity/identity_providers.dart';
import 'widgets/provider_button.dart';

/// Save Progress: links Google / Facebook / Apple to the CURRENT account
/// (`POST /account/link/{provider}`). Coins, XP and collection stay exactly
/// as they are. Conflicts never merge anything.
class LinkAccountScreen extends ConsumerStatefulWidget {
  const LinkAccountScreen({super.key});

  @override
  ConsumerState<LinkAccountScreen> createState() => _LinkAccountScreenState();
}

class _LinkAccountScreenState extends ConsumerState<LinkAccountScreen> {
  bool _busy = false;
  bool _celebrate = false;

  String _label(AppLocalizations l10n, LinkedProvider p) => switch (p) {
    LinkedProvider.google => l10n.authSaveWithGoogle,
    LinkedProvider.facebook => l10n.authSaveWithFacebook,
    LinkedProvider.apple => l10n.authSaveWithApple,
    LinkedProvider.guest => l10n.authPlayAsGuest,
  };

  Future<void> _link(LinkedProvider provider) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionControllerProvider.notifier);
      final outcome = await session.link(provider);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      switch (outcome) {
        case LinkSucceeded():
          // Refresh the profile from the server (best effort).
          try {
            await session.refreshMe();
          } catch (_) {}
          if (!mounted) return;
          ref.read(audioServiceProvider).play(Sfx.levelUp);
          ref.read(hapticsServiceProvider).success();
          setState(() => _celebrate = true);
          AppToast.show(
            context,
            l10n.authLinkSuccessMessage(providerName(l10n, provider)),
            kind: ToastKind.success,
            icon: Icons.cloud_done_rounded,
          );
        case LinkCancelled():
          break;
        case LinkConflict(:final credential):
          await _handleConflict(credential);
        case LinkAlreadyLinked(:final provider):
          await AppDialog.show<void>(
            context,
            title: l10n.authAlreadyLinkedTitle,
            message: l10n.authAlreadyLinkedMessage(
              providerName(l10n, provider),
            ),
            actions: [
              AppDialogAction(
                label: l10n.commonOk,
                variant: PremiumButtonVariant.primary,
              ),
            ],
          );
        case LinkFailed(:final code):
          AppToast.show(
            context,
            localizedErrorMessage(l10n, code),
            kind: ToastKind.error,
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleConflict(ProviderCredential credential) async {
    final l10n = AppLocalizations.of(context);
    final name = providerName(l10n, credential.provider);
    final wasGuest = ref.read(sessionControllerProvider).isGuest;
    final signIn = await AppDialog.show<bool>(
      context,
      title: l10n.authConflictTitle(name),
      message: l10n.authConflictMessage(name),
      content: wasGuest
          ? Text(
              l10n.authConflictGuestNote,
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall,
            )
          : null,
      actions: [
        AppDialogAction(
          label: l10n.authConflictSignIn,
          variant: PremiumButtonVariant.primary,
          value: true,
        ),
        AppDialogAction(
          label: l10n.commonCancel,
          variant: PremiumButtonVariant.ghost,
          value: false,
        ),
      ],
    );
    if (signIn != true || !mounted) return;
    final outcome = await ref
        .read(sessionControllerProvider.notifier)
        .signInWithCredential(credential);
    if (!mounted) return;
    switch (outcome) {
      case AuthSucceeded(:final user):
        AppToast.show(
          context,
          l10n.authWelcomeBack(user.displayName),
          kind: ToastKind.success,
        );
        context.go(AppRoutes.home);
      case AuthFailed(:final code):
        AppToast.show(
          context,
          localizedErrorMessage(l10n, code),
          kind: ToastKind.error,
        );
      case AuthCancelled():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final user = ref.watch(sessionControllerProvider.select((s) => s.user));
    final available = ref.watch(availableSignInProvidersProvider);
    final linked = user?.linkedProviders ?? const <LinkedProvider>{};
    final saved = !(user?.needsSaveProgress ?? true);
    final remaining = available.where((p) => !linked.contains(p)).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      // The hero below carries the title; the bar only offers "back".
      appBar: AppBar(),
      extendBodyBehindAppBar: true,
      body: LayeredBackground(
        child: Stack(
          children: [
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.maxContentWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.lg,
                      AppSpacing.gutter,
                      AppSpacing.xxl,
                    ),
                    children: [
                      _Hero(saved: saved),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        saved
                            ? l10n.authAlreadySavedTitle
                            : l10n.authSaveProgressTitle,
                        textAlign: TextAlign.center,
                        style: context.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        saved
                            ? l10n.authAlreadySavedMessage
                            : l10n.authSaveProgressSubtitle,
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (saved)
                        _LinkedList(linked: linked)
                      else
                        SurfaceCard(
                          child: Column(
                            children: [
                              _Benefit(
                                icon: Icons.savings_rounded,
                                text: l10n.authSaveBenefitKeep,
                              ),
                              _Benefit(
                                icon: Icons.devices_rounded,
                                text: l10n.authSaveBenefitDevices,
                              ),
                              _Benefit(
                                icon: Icons.verified_user_rounded,
                                text: l10n.authSaveBenefitSame,
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xl),
                      if (available.isEmpty)
                        Text(
                          l10n.authSaveNoProviders,
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: c.textMuted,
                          ),
                        ),
                      for (final p in remaining) ...[
                        ProviderButton(
                          provider: p,
                          label: _label(l10n, p),
                          onPressed: _busy ? null : () => _link(p),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(child: ConfettiBurst(play: _celebrate)),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.saved});

  final bool saved;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: saved ? c.goldGradient : c.brandGradient,
          boxShadow: c.shadow(AppElevation.medium),
        ),
        child: Icon(
          saved ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
          size: 52,
          color: saved ? c.onGold : c.onBrand,
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: AppRadii.smAll,
            ),
            child: Icon(icon, color: c.brand, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: context.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _LinkedList extends StatelessWidget {
  const _LinkedList({required this.linked});

  final Set<LinkedProvider> linked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final shown = linked.where((p) => p != LinkedProvider.guest).toList();
    return SurfaceCard(
      child: Column(
        children: [
          for (final p in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  ProviderLogo(provider: p, color: c.textPrimary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      providerName(l10n, p),
                      style: context.textTheme.titleMedium,
                    ),
                  ),
                  Icon(Icons.check_circle_rounded, color: c.success),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
