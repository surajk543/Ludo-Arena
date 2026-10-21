import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/protocol/models.dart' show PlayerPicture;
import '../../../core/theme/app_theme.dart';
import '../../../core/time/server_clock.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../progression/application/meta_support.dart';
import '../application/friends_controller.dart';
import '../application/reports_controller.dart';
import '../domain/report_models.dart';
import '../domain/social_models.dart';
import 'report_text.dart';

/// The player a [PlayerActionsSheet] is about, taken from the live room
/// snapshot (`players[]`).
@immutable
class PlayerSheetTarget {
  const PlayerSheetTarget({
    required this.uid,
    required this.name,
    this.avatar = 0,
    this.picture,
    this.level = 1,
    this.frameId = 'frame_none',
    this.seatColor,
    this.bot = false,
  });

  final String uid;

  /// Display name (already resolved for empty names).
  final String name;
  final int avatar;

  /// Store profile picture (null: the built-in [avatar]).
  final PlayerPicture? picture;
  final int level;
  final String frameId;
  final SeatColor? seatColor;

  /// Server-flagged bot: shown like anyone else, but without actions.
  final bool bot;
}

/// Opponent options during (or right after) a match: profile header, Add
/// friend (state from `GET /friends`) and Report (reason → confirm →
/// `POST /reports`).
abstract final class PlayerActionsSheet {
  /// Opens the sheet over the match. [canAct] is false for spectators (no
  /// seat): only the profile is shown. A successful report closes the sheet
  /// and confirms with a toast on [context].
  static Future<void> show(
    BuildContext context, {
    required PlayerSheetTarget player,
    required String roomId,
    required bool canAct,
  }) async {
    final l10n = AppLocalizations.of(context);
    final result = await withOverlaySounds(
      context,
      showModalBottomSheet<ReportSubmitted>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Lighter than other sheets: the board and the turn timer stay
        // readable behind it.
        barrierColor: Colors.black.withValues(alpha: 0.3),
        builder: (_) => AppBottomSheetFrame(
          child: PlayerActionsPanel(
            player: player,
            roomId: roomId,
            canAct: canAct,
          ),
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    AppToast.show(
      context,
      l10n.socialReportSent(result.limit.remaining, result.limit.perDay),
      kind: ToastKind.success,
    );
  }
}

/// Body of [PlayerActionsSheet] (public for tests).
class PlayerActionsPanel extends ConsumerStatefulWidget {
  const PlayerActionsPanel({
    super.key,
    required this.player,
    required this.roomId,
    required this.canAct,
  });

  final PlayerSheetTarget player;
  final String roomId;
  final bool canAct;

  @override
  ConsumerState<PlayerActionsPanel> createState() => _PlayerActionsPanelState();
}

class _PlayerActionsPanelState extends ConsumerState<PlayerActionsPanel> {
  bool _reporting = false;
  ReportReason? _reason;
  bool _sending = false;
  bool _friendBusy = false;
  String? _friendError;
  String? _reportError;

  PlayerSheetTarget get _p => widget.player;
  bool get _actions => widget.canAct && !_p.bot;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  // ------------------------------------------------------------- friends

  Future<void> _friendAction(FriendStatus status) async {
    if (_friendBusy) return;
    setState(() {
      _friendBusy = true;
      _friendError = null;
    });
    final notifier = ref.read(friendsProvider.notifier);
    final outcome = status == FriendStatus.incoming
        ? await notifier.accept(_p.uid)
        : await notifier.sendRequest(_p.uid);
    if (!mounted) return;
    setState(() => _friendBusy = false);
    final l10n = _l10n;
    switch (outcome) {
      case FriendActionSucceeded(:final friend?):
        if (status != FriendStatus.incoming) {
          ref.read(analyticsServiceProvider).friendRequestSent('match');
        }
        AppToast.show(
          context,
          friend.status == FriendStatus.friend
              ? l10n.metaNowFriends(_p.name)
              : l10n.metaRequestSent(_p.name),
          kind: ToastKind.success,
        );
      case FriendActionFailed(:final error):
        // `already_friends`: the controller refreshes the lists.
        if (error.code == 'already_friends') return;
        setState(
          () => _friendError = metaErrorMessage(
            l10n,
            error,
            maxFriends: ref.read(friendsProvider).value?.maxFriends,
          ),
        );
      default:
        break;
    }
  }

  // ------------------------------------------------------------- reports

  Future<void> _sendReport() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() {
      _sending = true;
      _reportError = null;
    });
    final outcome = await ref
        .read(reportsProvider.notifier)
        .submit(uid: _p.uid, roomId: widget.roomId, reason: reason);
    if (!mounted) return;
    setState(() => _sending = false);
    switch (outcome) {
      case ReportSubmitted():
        Navigator.of(context).pop(outcome);
      case ReportAlreadyReported() || ReportLimitReached():
        // The state (blocked player / no reports left) explains it.
        setState(() => _reporting = false);
      case ReportFailed(:final error):
        setState(() => _reportError = ReportText.error(_l10n, error));
      case ReportIgnored():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_actions) {
      // Keep both lists alive for the whole sheet (they auto-dispose), also
      // while the reason picker is shown.
      ref
        ..watch(friendsProvider)
        ..watch(reportsProvider);
    }
    return Semantics(
      key: const ValueKey('player-sheet'),
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(player: _p),
          if (_actions) ...[
            const SizedBox(height: AppSpacing.lg),
            if (_reporting) _reportStep(context) else _mainStep(context),
          ],
        ],
      ),
    );
  }

  Widget _mainStep(BuildContext context) {
    final l10n = _l10n;
    final c = context.colors;
    final locale = Localizations.localeOf(context);
    final clock = ref.watch(serverClockProvider);
    final friends = ref.watch(friendsProvider);
    final reports = ref.watch(reportsProvider);
    final lists = friends.value;
    final status = lists?.statusOf(_p.uid) ?? FriendStatus.none;
    final atLimit =
        (lists?.atFriendLimit ?? false) &&
        (status == FriendStatus.none || status == FriendStatus.incoming);

    final reportState = reports.value;
    final limit = reportState?.limit;
    final reported =
        reportState?.reportedRecently(_p.uid, clock.nowMs()) ?? false;
    final exhausted = !reported && (limit?.exhausted ?? false);

    final String? reportNote = reported
        ? l10n.socialAlreadyReported
        : exhausted
        ? ReportText.limitReached(l10n, locale, clock, limit!)
        : limit == null
        ? null
        : l10n.socialReportsLeft(limit.remaining, limit.perDay);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _friendButton(
          status,
          loading: lists == null && friends.isLoading,
          atLimit: atLimit,
        ),
        if (atLimit) ...[
          const SizedBox(height: AppSpacing.xs),
          _Note(
            key: const ValueKey('sheet-friend-limit'),
            text: l10n.socialFriendLimitNote(lists!.maxFriends),
            icon: Icons.group_rounded,
          ),
        ],
        if (_friendError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _Note(
            key: const ValueKey('sheet-friend-error'),
            text: _friendError!,
            icon: Icons.error_outline_rounded,
            color: c.danger,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        PremiumButton(
          key: const ValueKey('sheet-report'),
          label: reported ? l10n.socialReported : l10n.socialReportPlayer,
          icon: reported ? Icons.check_rounded : Icons.flag_rounded,
          variant: PremiumButtonVariant.ghost,
          size: PremiumButtonSize.medium,
          onPressed: reported || exhausted
              ? null
              : () => setState(() {
                  _reporting = true;
                  _reportError = null;
                }),
        ),
        if (reportNote != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _Note(
            key: const ValueKey('sheet-report-note'),
            text: reportNote,
            icon: reported || exhausted
                ? Icons.info_outline_rounded
                : Icons.flag_outlined,
            color: exhausted ? c.warning : null,
          ),
        ],
      ],
    );
  }

  Widget _friendButton(
    FriendStatus status, {
    required bool loading,
    required bool atLimit,
  }) {
    final l10n = _l10n;
    const key = ValueKey('sheet-friend-action');
    if (loading) {
      return PremiumButton(
        key: key,
        label: l10n.metaAddFriend,
        icon: Icons.person_add_alt_1_rounded,
        size: PremiumButtonSize.medium,
        loading: true,
        onPressed: null,
      );
    }
    return switch (status) {
      FriendStatus.friend => PremiumButton(
        key: key,
        label: l10n.metaFriendsLabel,
        icon: Icons.check_circle_rounded,
        variant: PremiumButtonVariant.secondary,
        size: PremiumButtonSize.medium,
        onPressed: null,
      ),
      FriendStatus.outgoing => PremiumButton(
        key: key,
        label: l10n.socialRequestSent,
        icon: Icons.schedule_rounded,
        variant: PremiumButtonVariant.secondary,
        size: PremiumButtonSize.medium,
        onPressed: null,
      ),
      FriendStatus.incoming => PremiumButton(
        key: key,
        label: l10n.socialAcceptRequest,
        icon: Icons.how_to_reg_rounded,
        size: PremiumButtonSize.medium,
        loading: _friendBusy,
        onPressed: atLimit ? null : () => _friendAction(status),
      ),
      FriendStatus.none => PremiumButton(
        key: key,
        label: l10n.metaAddFriend,
        icon: Icons.person_add_alt_1_rounded,
        size: PremiumButtonSize.medium,
        loading: _friendBusy,
        onPressed: atLimit ? null : () => _friendAction(status),
      ),
    };
  }

  Widget _reportStep(BuildContext context) {
    final l10n = _l10n;
    final c = context.colors;
    return Column(
      key: const ValueKey('report-step'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.socialReportTitle(_p.name),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.socialReportWhy, style: context.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xs),
        RadioGroup<ReportReason>(
          groupValue: _reason,
          onChanged: (r) {
            if (_sending) return;
            setState(() {
              _reason = r;
              _reportError = null;
            });
          },
          // The list tiles paint their ink on this (the sheet is decorated).
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final r in ReportReason.values)
                  RadioListTile<ReportReason>(
                    key: ValueKey('report-reason-${r.wire}'),
                    value: r,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(ReportText.reason(l10n, r)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.socialReportReviewNote,
          style: context.textTheme.bodySmall?.copyWith(color: c.textSecondary),
        ),
        if (_reportError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _Note(
            key: const ValueKey('sheet-report-error'),
            text: _reportError!,
            icon: Icons.error_outline_rounded,
            color: c.danger,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        PremiumButton(
          key: const ValueKey('send-report'),
          label: l10n.socialSendReport,
          icon: Icons.flag_rounded,
          variant: PremiumButtonVariant.danger,
          size: PremiumButtonSize.medium,
          loading: _sending,
          onPressed: _reason == null ? null : _sendReport,
        ),
        const SizedBox(height: AppSpacing.sm),
        PremiumButton(
          key: const ValueKey('report-back'),
          label: l10n.commonBack,
          variant: PremiumButtonVariant.ghost,
          size: PremiumButtonSize.medium,
          onPressed: _sending
              ? null
              : () => setState(() {
                  _reporting = false;
                  _reportError = null;
                }),
        ),
      ],
    );
  }
}

/// Avatar, name and level.
class _Header extends StatelessWidget {
  const _Header({required this.player});

  final PlayerSheetTarget player;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: '${player.name}, ${l10n.commonLevel(player.level)}',
      excludeSemantics: true,
      child: Row(
        children: [
          PlayerAvatar(
            avatarIndex: player.avatar,
            picture: player.picture,
            frameId: player.frameId,
            seatColor: player.seatColor,
            size: 64,
            semanticLabel: player.name,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    LevelBadge(level: player.level, size: 22),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Flexible(
                      child: Text(
                        l10n.commonLevel(player.level),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short inline explanation under an action.
class _Note extends StatelessWidget {
  const _Note({super.key, required this.text, required this.icon, this.color});

  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.textSecondary;
    return Semantics(
      // Errors and limits are announced when they appear.
      liveRegion: color != null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: tint),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodySmall?.copyWith(color: tint),
            ),
          ),
        ],
      ),
    );
  }
}
