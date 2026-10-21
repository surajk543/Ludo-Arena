import 'package:flutter/material.dart';
import 'package:ludo_royale/features/meta_routes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/routes.dart';
import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/network/api_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../authentication/application/session_controller.dart';
import '../../authentication/identity/identity_providers.dart';
import '../../authentication/presentation/widgets/provider_button.dart';
import '../progression.dart';
import 'display_name_sheet.dart';
import 'profile_picture_sheet.dart';

/// Profile: avatar + frame, title, level/XP, public friend code (copy /
/// share), account type, linked sign-in methods and Save Progress.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final c = context.colors;
    final user = ref.watch(sessionControllerProvider.select((s) => s.user));
    final progression = ref.watch(progressionSummaryProvider);
    final available = ref.watch(availableSignInProvidersProvider);
    if (user == null || progression == null) {
      return const Scaffold(body: LoadingState());
    }

    final shownProviders = {
      ...available,
      ...user.linkedProviders.where((p) => p != LinkedProvider.guest),
    }.toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        // Profile is a bottom-navigation tab: keep Settings one tap away.
        actions: [
          IconButton(
            tooltip: l10n.homeSettingsTooltip,
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: LayeredBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.maxContentWidth,
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: [
                  SurfaceCard(
                    elevation: AppElevation.medium,
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        _AvatarButton(user: user),
                        const SizedBox(height: AppSpacing.md),
                        _NameRow(name: user.displayName),
                        const SizedBox(height: AppSpacing.sm),
                        TitleChip(titleId: progression.title),
                        const SizedBox(height: AppSpacing.lg),
                        // Opens the level road (milestones and rewards).
                        InkWell(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          onTap: () {
                            playUiSound(context, Sfx.uiTap);
                            context.push(MetaRoutes.progression);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            child: Row(
                              children: [
                                LevelBadge(level: progression.level, size: 40),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.commonLevel(progression.level),
                                        style: context.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      XpProgressBar(
                                        current: progression.isMaxLevel
                                            ? progression.nextLevelXp
                                            : progression.xpIntoLevel,
                                        total: progression.nextLevelXp <= 0
                                            ? 1
                                            : progression.nextLevelXp,
                                        showLabel: false,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        progression.isMaxLevel
                                            ? l10n.profileMaxLevel
                                            : l10n.profileLevelProgress(
                                                formatNumberFull(
                                                  progression.xpRemaining,
                                                  locale,
                                                ),
                                                progression.level + 1,
                                              ),
                                        style: context.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _FriendCodeCard(uid: user.uid),
                  const SizedBox(height: AppSpacing.lg),
                  SectionHeader(title: l10n.profileAccountSection),
                  const SizedBox(height: AppSpacing.sm),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Row(
                          label: l10n.profileAccountType,
                          value: user.needsSaveProgress
                              ? l10n.profileAccountGuest
                              : l10n.profileAccountLinked,
                          valueColor: user.needsSaveProgress
                              ? c.warning
                              : c.success,
                        ),
                        _Row(
                          label: l10n.profileTotalXp,
                          value: formatNumberFull(progression.xp, locale),
                        ),
                        if (shownProviders.isNotEmpty) ...[
                          const RoyalDivider(),
                          Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.sm,
                              bottom: AppSpacing.xs,
                            ),
                            child: Text(
                              l10n.profileLinkedAccounts,
                              style: context.textTheme.titleSmall,
                            ),
                          ),
                          for (final p in shownProviders)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xs,
                              ),
                              child: Row(
                                children: [
                                  ProviderLogo(
                                    provider: p,
                                    color: c.textPrimary,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Text(
                                      providerName(l10n, p),
                                      style: context.textTheme.bodyLarge,
                                    ),
                                  ),
                                  Text(
                                    user.linkedProviders.contains(p)
                                        ? l10n.profileLinked
                                        : l10n.profileNotLinked,
                                    style: context.textTheme.labelMedium
                                        ?.copyWith(
                                          color:
                                              user.linkedProviders.contains(p)
                                              ? c.success
                                              : c.textMuted,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (user.needsSaveProgress) ...[
                          const SizedBox(height: AppSpacing.md),
                          PremiumButton(
                            label: l10n.profileSaveProgressCta,
                            icon: Icons.cloud_upload_rounded,
                            variant: PremiumButtonVariant.gold,
                            size: PremiumButtonSize.medium,
                            // Don't await the route: the button would stay
                            // busy until the pushed screen pops.
                            onPressed: () {
                              context.push(AppRoutes.linkAccount);
                            },
                          ),
                        ],
                      ],
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

/// The player's avatar (Store picture or built-in) with an edit badge; a
/// tap opens [ProfilePictureSheet] (owned pictures or the classic avatar).
class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.user});

  final User user;

  static const double _size = 104;

  Future<void> _edit(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    playUiSound(context, Sfx.uiTap);
    final updated = await ProfilePictureSheet.show(context);
    if (updated == null || !context.mounted) return;
    // Server-confirmed.
    playUiSound(context, Sfx.uiConfirm);
    AppToast.show(
      context,
      updated.picture == null ? l10n.storeRemovedToast : l10n.storeAppliedToast,
      kind: ToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.profileChangePicture,
      excludeSemantics: true,
      child: Tooltip(
        message: l10n.profileChangePicture,
        child: InkWell(
          key: const ValueKey('profile-change-picture'),
          customBorder: const CircleBorder(),
          onTap: () => _edit(context),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PlayerAvatar(
                avatarIndex: user.avatar,
                picture: user.picture,
                frameId: user.loadout.frame,
                size: _size,
              ),
              PositionedDirectional(
                end: 2,
                bottom: 2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.brand,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surface, width: 2),
                  ),
                  child: Icon(Icons.edit_rounded, size: 16, color: c.onBrand),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The player's name with a pencil button that opens [DisplayNameSheet].
/// A balancing gap on the other side keeps the name centered.
class _NameRow extends StatelessWidget {
  const _NameRow({required this.name});

  final String name;

  static const double _buttonSize = 36;
  static const double _slot = 48; // IconCircleButton's min touch target

  Future<void> _edit(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final user = await DisplayNameSheet.show(context);
    if (user == null || !context.mounted) return;
    AppToast.show(
      context,
      l10n.profileNameSaved(user.displayName),
      kind: ToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        const SizedBox(width: _slot),
        Expanded(
          child: Text(
            name,
            key: const ValueKey('profile-display-name'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.headlineSmall,
          ),
        ),
        IconCircleButton(
          key: const ValueKey('profile-edit-name'),
          icon: Icons.edit_rounded,
          tooltip: l10n.profileEditNameTooltip,
          size: _buttonSize,
          onPressed: () => _edit(context),
        ),
      ],
    );
  }
}

class _FriendCodeCard extends StatelessWidget {
  const _FriendCodeCard({required this.uid});

  final String uid;

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.profileFriendCode,
                  style: context.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xxs),
                // Public id: always rendered LTR for readability.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(
                    uid,
                    style: context.textTheme.titleLarge?.copyWith(
                      color: c.brand,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.profileFriendCodeHint,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconCircleButton(
            icon: Icons.copy_rounded,
            tooltip: l10n.commonCopy,
            size: 44,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: uid));
              if (context.mounted) {
                AppToast.show(
                  context,
                  l10n.commonCopied,
                  kind: ToastKind.success,
                );
              }
            },
          ),
          const SizedBox(width: AppSpacing.sm),
          IconCircleButton(
            icon: Icons.share_rounded,
            tooltip: l10n.commonShare,
            size: 44,
            onPressed: () {
              final box = context.findRenderObject() as RenderBox?;
              SharePlus.instance.share(
                ShareParams(
                  text: l10n.profileShareFriendCode(uid),
                  sharePositionOrigin: box == null
                      ? null
                      : box.localToGlobal(Offset.zero) & box.size,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.textTheme.bodyMedium)),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: context.textTheme.titleSmall?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
