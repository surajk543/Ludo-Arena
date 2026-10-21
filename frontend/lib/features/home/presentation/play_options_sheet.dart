import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../wallet/wallet_controller.dart';
import '../application/play_options.dart';
import 'join_code_sheet.dart';

/// Localized game name.
String gameName(AppLocalizations l10n, String game) =>
    game == GameId.snakesLadders
    ? l10n.commonGameSnakesLadders
    : l10n.commonGameLudo;

/// Localized variant name.
String variantName(AppLocalizations l10n, String variant) =>
    variant == 'quick' ? l10n.commonVariantQuick : l10n.commonVariantClassic;

/// Options sheet for Play Online / Play with Friends / Practice vs Bots and
/// Quick Play setup. Choosing navigates to the feature route
/// (`/matchmaking`, `/rooms/create`, `/practice`).
abstract final class PlayOptionsSheet {
  /// [game] null → the sheet also offers the game choice.
  /// [quickPlay] → the choice is remembered as the Quick Play default.
  static Future<void> show(
    BuildContext context, {
    required PlayMode mode,
    String? game,
    bool quickPlay = false,
  }) {
    final l10n = AppLocalizations.of(context);
    final title = quickPlay
        ? l10n.homeQuickPlay
        : game == null
        ? l10n.homeOptionsPrivateRoomTitle
        : switch (mode) {
            PlayMode.online => l10n.homeOptionsOnlineTitle(
              gameName(l10n, game),
            ),
            PlayMode.friends => l10n.homeOptionsFriendsTitle(
              gameName(l10n, game),
            ),
            PlayMode.practice => l10n.homeOptionsPracticeTitle(
              gameName(l10n, game),
            ),
          };
    return AppBottomSheet.show<void>(
      context,
      title: title,
      builder: (_) =>
          _PlayOptionsBody(mode: mode, game: game, quickPlay: quickPlay),
    );
  }
}

class _PlayOptionsBody extends ConsumerStatefulWidget {
  const _PlayOptionsBody({
    required this.mode,
    required this.game,
    required this.quickPlay,
  });

  final PlayMode mode;
  final String? game;
  final bool quickPlay;

  @override
  ConsumerState<_PlayOptionsBody> createState() => _PlayOptionsBodyState();
}

class _PlayOptionsBodyState extends ConsumerState<_PlayOptionsBody> {
  late PlayConfig _config;

  @override
  void initState() {
    super.initState();
    final remembered = ref.read(quickPlayProvider);
    _config = widget.quickPlay
        ? remembered
        : remembered.copyWith(game: widget.game ?? remembered.game);
  }

  Future<void> _go() async {
    if (widget.quickPlay) {
      await ref.read(quickPlayProvider.notifier).remember(_config);
    }
    if (!mounted) return;
    final router = GoRouter.of(context);
    final route = _config.routeFor(widget.mode);
    Navigator.of(context).pop();
    router.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final c = context.colors;
    final isLudo = _config.game == GameId.ludo;
    final fee = ref.watch(entryFeeProvider(_config.game));
    final coins = ref.watch(walletControllerProvider.select((w) => w.coins));
    final walletLoaded = ref.watch(
      walletControllerProvider.select((w) => w.isLoaded),
    );
    final practice = widget.mode == PlayMode.practice;
    final short = !practice && walletLoaded && coins < fee;

    final action = switch (widget.mode) {
      PlayMode.online => l10n.homeFindMatch,
      PlayMode.friends => l10n.homeCreateRoom,
      PlayMode.practice => l10n.homeStartPractice,
    };

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Text(text, style: context.textTheme.titleSmall),
    );

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.game == null) ...[
            label(l10n.homeGameLabel),
            ChoiceChips<String>(
              value: _config.game,
              onChanged: (g) =>
                  setState(() => _config = _config.copyWith(game: g)),
              options: [
                ChoiceOption(
                  value: GameId.ludo,
                  label: l10n.commonGameLudo,
                  icon: Icons.grid_view_rounded,
                ),
                ChoiceOption(
                  value: GameId.snakesLadders,
                  label: l10n.commonGameSnakesLadders,
                  icon: Icons.stairs_rounded,
                ),
              ],
            ),
          ],
          if (!practice) ...[
            label(l10n.homePlayersLabel),
            ChoiceChips<int>(
              value: _config.capacity,
              onChanged: (v) =>
                  setState(() => _config = _config.copyWith(capacity: v)),
              options: [
                for (final n in const [2, 3, 4])
                  ChoiceOption(value: n, label: l10n.commonPlayerCount(n)),
              ],
            ),
          ] else ...[
            label(l10n.homeBotsLabel),
            ChoiceChips<int>(
              value: _config.bots,
              onChanged: (v) =>
                  setState(() => _config = _config.copyWith(bots: v)),
              options: [
                for (final n in const [1, 2, 3])
                  ChoiceOption(value: n, label: l10n.homeBotCount(n)),
              ],
            ),
          ],
          if (isLudo) ...[
            label(l10n.homeModeLabel),
            ChoiceChips<String>(
              value: _config.variant,
              onChanged: (v) =>
                  setState(() => _config = _config.copyWith(variant: v)),
              options: [
                ChoiceOption(
                  value: 'classic',
                  label: l10n.commonVariantClassic,
                  caption: l10n.homeModeClassicCaption,
                ),
                ChoiceOption(
                  value: 'quick',
                  label: l10n.commonVariantQuick,
                  caption: l10n.homeModeQuickCaption,
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _NoteCard(
            icon: practice ? Icons.school_rounded : null,
            leading: practice ? null : const CoinIcon(size: 22),
            text: practice
                ? l10n.homePracticeNote
                : l10n.homeEntryFeeNote(formatCoins(fee, locale)),
          ),
          if (short) ...[
            const SizedBox(height: AppSpacing.sm),
            _NoteCard(
              icon: Icons.warning_amber_rounded,
              color: c.danger,
              text: l10n.homeNotEnoughCoins(formatCoins(fee, locale)),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PremiumButton(
            label: action,
            icon: switch (widget.mode) {
              PlayMode.online => Icons.public_rounded,
              PlayMode.friends => Icons.meeting_room_rounded,
              PlayMode.practice => Icons.smart_toy_rounded,
            },
            variant: widget.mode == PlayMode.online
                ? PremiumButtonVariant.gold
                : PremiumButtonVariant.primary,
            sound: Sfx.lobbyPlay,
            onPressed: short ? null : _go,
          ),
          if (widget.mode == PlayMode.friends) ...[
            const SizedBox(height: AppSpacing.sm),
            PremiumButton(
              label: l10n.homeHaveACode,
              icon: Icons.vpn_key_rounded,
              variant: PremiumButtonVariant.ghost,
              onPressed: () {
                final nav = Navigator.of(context);
                final rootCtx = nav.context;
                nav.pop();
                JoinCodeSheet.show(rootCtx);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text, this.icon, this.leading, this.color});

  final String text;
  final IconData? icon;
  final Widget? leading;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.brand;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: c.isDark ? 0.16 : 0.08),
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          leading ?? Icon(icon ?? Icons.info_rounded, color: tint, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: context.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
