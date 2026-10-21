import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/analytics/analytics_providers.dart';
import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/app_info.dart';
import '../../../core/links/external_link_launcher.dart';
import '../../../core/localization/language_controller.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../authentication/application/session_controller.dart';
import '../../authentication/presentation/account_actions.dart';
import 'language_picker.dart';
import 'settings_widgets.dart';

/// Settings: appearance, language, sound/haptics/motion, quick chat, privacy
/// (analytics consent), account (Save Progress, switch back to guest, sign
/// out, delete account) and about (version, legal notices).
///
/// Changing theme or language never touches the session, socket or a match.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static String _settingName(SettingKey k) => switch (k) {
    SettingKey.sound => 'sound',
    SettingKey.haptics => 'haptics',
    SettingKey.reducedMotion => 'reduced_motion',
    SettingKey.quickChatMute => 'quick_chat_mute',
  };

  /// Open-source notices live on a web page (sungamestudio.com/ludo-royale/
  /// legal/ by default, `LEGAL_NOTICES_URL` to override) opened in the
  /// browser.
  static Future<void> _openLegalNotices(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final url = ref.read(appConfigProvider).legalNoticesUrl;
    final ok = await ref.read(externalLinkLauncherProvider).open(url);
    if (!ok && context.mounted) {
      AppToast.show(
        context,
        l10n.settingsLegalNoticesOpenFailed,
        kind: ToastKind.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final settings = ref.watch(settingsControllerProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    final locale = ref.watch(languageControllerProvider);
    final consent = ref.watch(analyticsConsentProvider);
    final analyticsAvailable = ref.watch(analyticsBackendProvider) != null;
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final info = ref.watch(appInfoProvider);
    final systemReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final uiLocale = Localizations.localeOf(context);
    String percent(double v) =>
        AppNumberFormat.percent((v * 100).round(), uiLocale);
    void volume(VolumeKey key, double v, {bool persist = false}) => ref
        .read(settingsControllerProvider.notifier)
        .setVolume(key, v, persist: persist);

    void toggle(SettingKey key, bool value) {
      ref.read(settingsControllerProvider.notifier).set(key, value);
      ref
          .read(analyticsServiceProvider)
          .settingsChanged(_settingName(key), value);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: LayeredBackground(
        style: LayeredBackgroundStyle.calm,
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
                  SettingsSection(
                    title: l10n.settingsAppearance,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.settingsTheme,
                              style: context.textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            ChoiceChips<ThemeMode>(
                              value: themeMode,
                              onChanged: (mode) {
                                ref
                                    .read(themeModeControllerProvider.notifier)
                                    .setMode(mode);
                                ref
                                    .read(analyticsServiceProvider)
                                    .themeChanged(mode.name);
                              },
                              options: [
                                ChoiceOption(
                                  value: ThemeMode.light,
                                  label: l10n.settingsThemeLight,
                                  icon: Icons.light_mode_rounded,
                                ),
                                ChoiceOption(
                                  value: ThemeMode.dark,
                                  label: l10n.settingsThemeDark,
                                  icon: Icons.dark_mode_rounded,
                                ),
                                ChoiceOption(
                                  value: ThemeMode.system,
                                  label: l10n.settingsThemeSystem,
                                  icon: Icons.brightness_auto_rounded,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SettingsNavTile(
                        icon: Icons.translate_rounded,
                        title: l10n.settingsLanguage,
                        subtitle: nativeLanguageName(locale),
                        onTap: () => LanguageSheet.show(context),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: l10n.settingsSoundAndHaptics,
                    children: [
                      SettingsSwitchTile(
                        icon: Icons.volume_up_rounded,
                        title: l10n.settingsSound,
                        subtitle: l10n.settingsSoundSubtitle,
                        value: settings.soundEnabled,
                        onChanged: (v) => toggle(SettingKey.sound, v),
                      ),
                      SettingsSliderTile(
                        icon: Icons.graphic_eq_rounded,
                        title: l10n.settingsSfxVolume,
                        value: settings.sfxVolume,
                        format: percent,
                        onChanged: settings.soundEnabled
                            ? (v) {
                                volume(VolumeKey.sfx, v);
                                // Preview at the new level (throttled by the
                                // audio service's gesture window).
                                ref.read(audioServiceProvider).play(Sfx.uiTick);
                              }
                            : null,
                        onChangeEnd: settings.soundEnabled
                            ? (v) => volume(VolumeKey.sfx, v, persist: true)
                            : null,
                      ),
                      SettingsSliderTile(
                        icon: Icons.music_note_rounded,
                        title: l10n.settingsMusicVolume,
                        value: settings.musicVolume,
                        format: percent,
                        // The lobby music itself is the preview (live).
                        onChanged: settings.soundEnabled
                            ? (v) => volume(VolumeKey.music, v)
                            : null,
                        onChangeEnd: settings.soundEnabled
                            ? (v) => volume(VolumeKey.music, v, persist: true)
                            : null,
                      ),
                      SettingsSwitchTile(
                        icon: Icons.vibration_rounded,
                        title: l10n.settingsHaptics,
                        value: settings.hapticsEnabled,
                        onChanged: (v) => toggle(SettingKey.haptics, v),
                      ),
                      SettingsSwitchTile(
                        icon: Icons.animation_rounded,
                        title: l10n.settingsReducedMotion,
                        subtitle: systemReduced
                            ? l10n.settingsReducedMotionSystemOn
                            : l10n.settingsReducedMotionSubtitle,
                        value: settings.reducedMotion,
                        onChanged: (v) => toggle(SettingKey.reducedMotion, v),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: l10n.settingsGameplay,
                    children: [
                      SettingsSwitchTile(
                        icon: Icons.speaker_notes_off_rounded,
                        title: l10n.settingsQuickChatMute,
                        subtitle: l10n.settingsQuickChatMuteSubtitle,
                        value: settings.quickChatMuted,
                        onChanged: (v) => toggle(SettingKey.quickChatMute, v),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: l10n.settingsPrivacy,
                    children: [
                      SettingsSwitchTile(
                        icon: Icons.insights_rounded,
                        title: l10n.settingsAnalytics,
                        subtitle: analyticsAvailable
                            ? l10n.settingsAnalyticsSubtitle
                            : l10n.settingsAnalyticsNotConfigured,
                        value: consent == AnalyticsConsent.granted,
                        onChanged: analyticsAvailable
                            ? (v) {
                                final ctl = ref.read(
                                  analyticsConsentProvider.notifier,
                                );
                                v ? ctl.grant() : ctl.deny();
                              }
                            : null,
                      ),
                    ],
                  ),
                  if (user != null)
                    SettingsSection(
                      title: l10n.settingsAccount,
                      children: [
                        ListTile(
                          leading: PlayerAvatar(
                            avatarIndex: user.avatar,
                            frameId: user.loadout.frame,
                            size: 40,
                          ),
                          title: Text(
                            l10n.settingsSignedInAs(user.displayName),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            user.needsSaveProgress
                                ? l10n.commonGuest
                                : l10n.profileAccountLinked,
                          ),
                          onTap: () => context.push(AppRoutes.profile),
                        ),
                        if (user.needsSaveProgress)
                          SettingsNavTile(
                            icon: Icons.cloud_upload_rounded,
                            color: c.gold,
                            title: l10n.settingsSaveProgress,
                            subtitle: l10n.settingsSaveProgressSubtitle,
                            onTap: () => context.push(AppRoutes.linkAccount),
                          ),
                        if (session.canSwitchBackToGuest)
                          SettingsNavTile(
                            icon: Icons.switch_account_rounded,
                            title: l10n.settingsSwitchToGuest,
                            subtitle: l10n.settingsSwitchToGuestSubtitle,
                            onTap: () => AccountActions.confirmSwitchToGuest(
                              context,
                              ref,
                            ),
                          ),
                        SettingsNavTile(
                          icon: Icons.logout_rounded,
                          title: l10n.settingsSignOut,
                          destructive: true,
                          onTap: () =>
                              AccountActions.confirmSignOut(context, ref),
                        ),
                        SettingsNavTile(
                          icon: Icons.delete_forever_rounded,
                          title: l10n.settingsDeleteAccount,
                          subtitle: l10n.settingsDeleteAccountSubtitle,
                          destructive: true,
                          onTap: () =>
                              AccountActions.confirmDeleteAccount(context, ref),
                        ),
                      ],
                    ),
                  SettingsSection(
                    title: l10n.settingsAbout,
                    children: [
                      SettingsNavTile(
                        icon: Icons.info_outline_rounded,
                        title: l10n.settingsVersion,
                        trailing: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            info.display,
                            style: context.textTheme.labelLarge?.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      SettingsNavTile(
                        icon: Icons.gavel_rounded,
                        title: l10n.settingsLegalNotices,
                        subtitle: l10n.settingsLegalNoticesSubtitle,
                        trailing: Icon(
                          Icons.open_in_new_rounded,
                          size: 20,
                          color: c.textMuted,
                        ),
                        onTap: () => _openLegalNotices(context, ref),
                      ),
                    ],
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
