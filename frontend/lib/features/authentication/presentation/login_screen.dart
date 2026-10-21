import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/localization/language_controller.dart';
import '../../../core/network/api_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../settings/presentation/language_picker.dart';
import '../application/session_controller.dart';
import '../identity/identity_providers.dart';
import 'widgets/provider_button.dart';

/// Welcome / sign-in. Provider buttons appear only when configured for this
/// platform/build; "Play as guest" is always available. On success the app
/// gate moves on to home automatically.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// One sign-in at a time across all buttons.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final reason = ref.read(sessionControllerProvider).signOutReason;
    if (reason == SignOutReason.replaced) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_explainReplaced());
      });
    }
  }

  /// Signed out because the account signed in on another device.
  Future<void> _explainReplaced() {
    final l10n = AppLocalizations.of(context);
    return AppDialog.show<void>(
      context,
      title: l10n.authSignedInElsewhereTitle,
      message: l10n.authSignedInElsewhereMessage,
      illustration: const Icon(Icons.devices_other_rounded, size: 48),
      actions: [
        AppDialogAction(
          label: l10n.commonOk,
          variant: PremiumButtonVariant.primary,
        ),
      ],
    );
  }

  Future<void> _run(Future<AuthOutcome> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await action();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      switch (outcome) {
        case AuthSucceeded(:final user):
          AppToast.show(
            context,
            l10n.authWelcomeBack(user.displayName),
            kind: ToastKind.success,
          );
        case AuthCancelled():
          break; // Silent by design.
        case AuthFailed(:final code):
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

  String _label(AppLocalizations l10n, LinkedProvider p) => switch (p) {
    LinkedProvider.google => l10n.authContinueWithGoogle,
    LinkedProvider.facebook => l10n.authContinueWithFacebook,
    LinkedProvider.apple => l10n.authContinueWithApple,
    LinkedProvider.guest => l10n.authPlayAsGuest,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final providers = ref.watch(availableSignInProvidersProvider);
    final reason = ref.watch(
      sessionControllerProvider.select((s) => s.signOutReason),
    );
    final banner = switch (reason) {
      SignOutReason.expired => l10n.authSessionExpiredBanner,
      SignOutReason.replaced => l10n.authSignedInElsewhereBanner,
      _ => null,
    };
    final locale = ref.watch(languageControllerProvider);
    final session = ref.read(sessionControllerProvider.notifier);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _LanguageChip(
            label: nativeLanguageName(locale),
            tooltip: l10n.authChangeLanguage,
            onTap: () => LanguageSheet.show(context),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Center(child: BrandLogo(size: 112, showWordmark: true)),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          header: true,
          child: Text(
            l10n.authWelcomeTitle,
            textAlign: TextAlign.center,
            style: context.textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.authWelcomeSubtitle,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyLarge?.copyWith(color: c.textSecondary),
        ),
        if (banner != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _Banner(text: banner),
        ],
      ],
    );

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in providers) ...[
          ProviderButton(
            provider: p,
            label: _label(l10n, p),
            onPressed: _busy ? null : () => _run(() => session.signIn(p)),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (providers.isNotEmpty) ...[
          _OrDivider(label: l10n.authOrDivider),
          const SizedBox(height: AppSpacing.md),
        ],
        PremiumButton(
          label: l10n.authPlayAsGuest,
          icon: Icons.sports_esports_rounded,
          variant: PremiumButtonVariant.gold,
          onPressed: _busy ? null : () => _run(session.continueAsGuest),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.authGuestHint,
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.authFairPlayNote,
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall?.copyWith(color: c.textMuted),
        ),
      ],
    );

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
              // Content fills the screen when it fits and scrolls when it
              // doesn't (small phones, large text) — no intrinsic sizing.
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                    vertical: AppSpacing.md,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - AppSpacing.md * 2,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        const SizedBox(height: AppSpacing.xxl),
                        actions,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.glassFill,
        shape: StadiumBorder(side: BorderSide(color: c.glassBorder)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.translate_rounded, size: 18, color: c.brand),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelMedium,
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, size: 18, color: c.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(child: Divider(color: c.outline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            label,
            style: context.textTheme.labelMedium?.copyWith(color: c.textMuted),
          ),
        ),
        Expanded(child: Divider(color: c.outline)),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.goldSoft,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: c.gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_rounded, color: c.goldStrong),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: context.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
