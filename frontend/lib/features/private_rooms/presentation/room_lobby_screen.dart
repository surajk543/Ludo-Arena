import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/game_visuals/game_visuals.dart';
import '../../../shared/widgets/widgets.dart';
import '../../game/presentation/play_nav.dart';
import '../../game/presentation/play_text.dart';
import '../../game/presentation/widgets/play_form.dart';
import '../application/lobby_rules.dart';
import '../application/room_share.dart';
import 'invite_friends_sheet.dart';

/// `/rooms/:id/lobby` — private room lobby: big shareable code, seats with
/// avatar / frame / level / BOT badge / connection / host crown, host
/// controls (start, allow bots, add / remove bot, invite friends) and leave.
/// Goes straight to the game on `game.started`.
class RoomLobbyScreen extends ConsumerStatefulWidget {
  const RoomLobbyScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends ConsumerState<RoomLobbyScreen> {
  StreamSubscription<RoomEvent>? _sub;
  bool _leaving = false;
  bool _navigated = false;
  bool _timedOut = false;
  Timer? _syncTimer;

  /// Bots the host asked for that are not seated yet.
  int _targetBots = 0;
  Timer? _pendingTimer;

  @override
  void initState() {
    super.initState();
    _sub = ref
        .read(activeRoomControllerProvider.notifier)
        .events
        .listen(_onEvent);
    final room = ref.read(activeRoomControllerProvider).room;
    if (room?.id != widget.roomId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(activeRoomControllerProvider.notifier)
            .requestSync(roomId: widget.roomId);
      });
      _syncTimer = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _timedOut = true);
      });
    } else {
      _targetBots = _botsIn(room!);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _syncTimer?.cancel();
    _pendingTimer?.cancel();
    super.dispose();
  }

  static int _botsIn(RoomSnapshot room) =>
      room.players.where((p) => p.bot).length;

  int _pendingBots(RoomSnapshot room) =>
      math.max(0, _targetBots - _botsIn(room));

  void _onEvent(RoomEvent e) {
    if (!mounted || _navigated) return;
    switch (e) {
      case RoomSnapshotApplied(:final room):
        if (room.id != widget.roomId) return;
        if (room.isPlaying) {
          _navigated = true;
          PlayNav.toGame(context, room.id);
          return;
        }
        if (_pendingBots(room) == 0) _pendingTimer?.cancel();
        if (!room.allowBots) _targetBots = _botsIn(room);
      case RoomErrorReceived(:final error):
        if (error.code == 'bots_unavailable' ||
            error.code == 'bots_not_allowed') {
          final room = ref.read(activeRoomControllerProvider).room;
          setState(() => _targetBots = room == null ? 0 : _botsIn(room));
          AppToast.show(
            context,
            localizedErrorMessage(AppLocalizations.of(context), error.code),
            kind: ToastKind.warning,
          );
        }
      case RoomCleared(:final reason):
        if (_leaving) return;
        _navigated = true;
        final l10n = AppLocalizations.of(context);
        AppToast.show(
          context,
          reason == RoomClearReason.closed
              ? l10n.playRoomClosed
              : l10n.playRemovedFromRoom,
          kind: ToastKind.warning,
        );
        PlayNav.home(context);
      default:
        break;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context);
    try {
      await action();
    } on RealtimeCommandException catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        localizedErrorMessage(l10n, e.code),
        kind: ToastKind.warning,
      );
    }
  }

  Future<void> _addBot(RoomSnapshot room) => _run(() async {
    await ref.read(activeRoomControllerProvider.notifier).addBot();
    if (!mounted) return;
    setState(() => _targetBots = _botsIn(room) + _pendingBots(room) + 1);
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 25), () {
      // practice.start / add_bot close after ~20 s without a bot.
      final live = ref.read(activeRoomControllerProvider).room;
      if (mounted && live != null) setState(() => _targetBots = _botsIn(live));
    });
  });

  Future<void> _removeBot(RoomSnapshot room, int seat) => _run(() async {
    await ref.read(activeRoomControllerProvider.notifier).removeBot(seat);
    if (mounted) {
      setState(() => _targetBots = math.max(0, _botsIn(room) - 1));
    }
  });

  Future<void> _start() =>
      _run(() => ref.read(activeRoomControllerProvider.notifier).startGame());

  Future<void> _allowBots(bool allow) => _run(
    () => ref.read(activeRoomControllerProvider.notifier).allowBots(allow),
  );

  Future<void> _leave(RoomSnapshot? room) async {
    if (room != null) {
      final l10n = AppLocalizations.of(context);
      final isHost =
          ref.read(activeRoomControllerProvider).isHost &&
          room.players.length > 1;
      final ok = await AppDialog.show<bool>(
        context,
        title: l10n.playLeaveRoomTitle,
        message: isHost
            ? l10n.playLeaveRoomHostMessage
            : l10n.playLeaveRoomMessage,
        actions: [
          AppDialogAction(
            label: l10n.playStay,
            variant: PremiumButtonVariant.secondary,
            value: false,
          ),
          AppDialogAction(
            label: l10n.playLeaveRoom,
            variant: PremiumButtonVariant.danger,
            value: true,
          ),
        ],
      );
      if (ok != true || !mounted) return;
    }
    _leaving = true;
    try {
      await ref
          .read(activeRoomControllerProvider.notifier)
          .leaveRoom()
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
    if (mounted) PlayNav.home(context);
  }

  Future<void> _copy(String code) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      AppToast.show(context, l10n.playCodeCopied, kind: ToastKind.success);
    }
  }

  Future<void> _share(RoomSnapshot room, Rect? origin) async {
    final code = room.code;
    if (code == null) return;
    final l10n = AppLocalizations.of(context);
    await ref.read(roomShareProvider)(
      l10n.playInviteShareText(PlayText.game(l10n, room.game), code),
      subject: l10n.playInviteShareSubject,
      origin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(activeRoomControllerProvider);
    final room = live.room?.id == widget.roomId ? live.room : null;

    if (room != null && room.isPlaying && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) PlayNav.toGame(context, room.id);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(room);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayeredBackground(
          child: SafeArea(
            child: Column(
              children: [
                PlayHeader(
                  title: l10n.playLobbyTitle,
                  onBack: () => _leave(room),
                ),
                Expanded(
                  child: room == null
                      ? (_timedOut
                            ? EmptyState(
                                title: l10n.playRoomUnavailable,
                                action: PremiumButton(
                                  label: l10n.playBackHome,
                                  icon: Icons.home_rounded,
                                  expand: false,
                                  size: PremiumButtonSize.medium,
                                  onPressed: () => PlayNav.home(context),
                                ),
                              )
                            : LoadingState(message: l10n.playLoadingRoom))
                      : _LobbyBody(
                          room: room,
                          selfUid: live.selfUid,
                          permissions: LobbyPermissions.of(
                            room,
                            selfSeat: live.selfSeat,
                            pendingBots: _pendingBots(room),
                          ),
                          pendingBots: _pendingBots(room),
                          onCopy: _copy,
                          onShare: _share,
                          onStart: _start,
                          onAllowBots: _allowBots,
                          onAddBot: () => _addBot(room),
                          onRemoveBot: (seat) => _removeBot(room, seat),
                          onInvite: () => InviteFriendsSheet.show(context),
                          onLeave: () => _leave(room),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LobbyBody extends StatelessWidget {
  const _LobbyBody({
    required this.room,
    required this.selfUid,
    required this.permissions,
    required this.pendingBots,
    required this.onCopy,
    required this.onShare,
    required this.onStart,
    required this.onAllowBots,
    required this.onAddBot,
    required this.onRemoveBot,
    required this.onInvite,
    required this.onLeave,
  });

  final RoomSnapshot room;
  final String? selfUid;
  final LobbyPermissions permissions;
  final int pendingBots;
  final Future<void> Function(String code) onCopy;
  final Future<void> Function(RoomSnapshot room, Rect? origin) onShare;
  final Future<void> Function() onStart;
  final Future<void> Function(bool allow) onAllowBots;
  final Future<void> Function() onAddBot;
  final Future<void> Function(int seat) onRemoveBot;
  final VoidCallback onInvite;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final locale = Localizations.localeOf(context);
    final players = [...room.players]..sort((a, b) => a.seat - b.seat);
    final p = permissions;

    final startHint = switch (p.startBlocker) {
      StartBlocker.needPlayers => l10n.playStartBlockedNeedPlayers,
      StartBlocker.waitingForConnections => l10n.playStartBlockedConnections,
      StartBlocker.botsJoining => l10n.playStartBlockedBots,
      _ => null,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            _CodeCard(room: room, onCopy: onCopy, onShare: onShare),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _InfoPill(
                  icon: room.isLudo
                      ? Icons.grid_view_rounded
                      : Icons.stairs_rounded,
                  text: PlayText.gameTitle(l10n, room.game, room.variant),
                ),
                _InfoPill(
                  leading: const CoinIcon(size: 16),
                  text: room.hasBots
                      ? l10n.commonFree
                      : l10n.playEntryFee(formatCoins(room.entryFee, locale)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              title: l10n.playLobbyPlayers(players.length, room.capacity),
            ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final w = (constraints.maxWidth - AppSpacing.sm) / 2;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (var i = 0; i < room.capacity; i++)
                      SizedBox(
                        width: w,
                        child: i < players.length
                            ? _SeatTile(
                                player: players[i],
                                isSelf: players[i].uid == selfUid,
                                isHost: players[i].seat == room.hostSeat,
                                onRemove: p.canRemoveBots && players[i].bot
                                    ? () => onRemoveBot(players[i].seat)
                                    : null,
                              )
                            : _EmptySeatTile(
                                joining: i - players.length < pendingBots,
                                onAddBot: p.canAddBot ? onAddBot : null,
                              ),
                      ),
                  ],
                );
              },
            ),
            if (room.hasBots) ...[
              const SizedBox(height: AppSpacing.md),
              PlayNote(
                icon: Icons.smart_toy_rounded,
                text: l10n.playBotsFreeNote,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (p.isHost) ...[
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: room.allowBots,
                  onChanged: p.canToggleBots ? onAllowBots : null,
                  title: Text(
                    l10n.playAllowBots,
                    style: context.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    l10n.playAllowBotsHint,
                    style: context.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (p.canInvite)
              PremiumButton(
                label: l10n.playInviteFriends,
                icon: Icons.person_add_alt_1_rounded,
                variant: PremiumButtonVariant.secondary,
                size: PremiumButtonSize.medium,
                onPressed: onInvite,
              ),
            const SizedBox(height: AppSpacing.lg),
            if (p.isHost) ...[
              PremiumButton(
                label: l10n.playLobbyStart,
                icon: Icons.play_arrow_rounded,
                variant: PremiumButtonVariant.gold,
                onPressed: p.canStart ? onStart : null,
              ),
              if (startHint != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  startHint,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ] else
              _WaitingForHost(
                hostName: room.playerAtSeat(room.hostSeat) == null
                    ? null
                    : PlayText.playerName(
                        l10n,
                        room.playerAtSeat(room.hostSeat)!,
                      ),
              ),
            const SizedBox(height: AppSpacing.sm),
            PremiumButton(
              label: l10n.playLeaveRoom,
              icon: Icons.logout_rounded,
              variant: PremiumButtonVariant.ghost,
              size: PremiumButtonSize.medium,
              onPressed: onLeave,
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.room,
    required this.onCopy,
    required this.onShare,
  });

  final RoomSnapshot room;
  final Future<void> Function(String code) onCopy;
  final Future<void> Function(RoomSnapshot room, Rect? origin) onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final code = room.code ?? '------';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: c.brandGradient,
        borderRadius: AppRadii.xlAll,
        boxShadow: c.shadow(AppElevation.medium),
      ),
      child: Column(
        children: [
          Text(
            l10n.playRoomCodeLabel,
            style: context.textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Codes are Latin identifiers: always LTR, even in ar / ur.
          Semantics(
            label: l10n.playRoomCodeA11y(code.split('').join(' ')),
            excludeSemantics: true,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  code,
                  maxLines: 1,
                  style: context.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: PremiumButton(
                  label: l10n.playCopyCode,
                  icon: Icons.copy_rounded,
                  variant: PremiumButtonVariant.secondary,
                  size: PremiumButtonSize.small,
                  onPressed: room.code == null ? null : () => onCopy(code),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Builder(
                  builder: (context) => PremiumButton(
                    label: l10n.playShareInvite,
                    icon: Icons.ios_share_rounded,
                    variant: PremiumButtonVariant.gold,
                    size: PremiumButtonSize.small,
                    onPressed: room.code == null
                        ? null
                        : () {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            final origin = box == null || !box.hasSize
                                ? null
                                : box.localToGlobal(Offset.zero) & box.size;
                            return onShare(room, origin);
                          },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.player,
    required this.isSelf,
    required this.isHost,
    this.onRemove,
  });

  final RoomPlayer player;
  final bool isSelf;
  final bool isHost;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final name = PlayText.playerName(l10n, player);
    final seat = SeatColor.tryFromName(player.color);
    final palette = GamePalette.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      border: Border.all(
        color: isSelf
            ? c.brand
            : (seat == null
                  ? c.outline
                  : palette.seat(seat).withValues(alpha: 0.5)),
        width: isSelf ? 2 : 1,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              const SizedBox(height: 4),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  PlayerAvatar(
                    avatarIndex: player.avatar,
                    frameId: player.cosmetics.frame,
                    size: 56,
                    seatColor: seat,
                    dimmed: !player.connected,
                    semanticLabel: name,
                  ),
                  PositionedDirectional(
                    top: -2,
                    end: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: player.connected ? c.success : c.warning,
                        border: Border.all(color: c.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isHost) ...[
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 16,
                      color: c.gold,
                      semanticLabel: l10n.playHostBadge,
                    ),
                    const SizedBox(width: 2),
                  ],
                  Flexible(
                    child: Text(
                      isSelf ? l10n.playNameYou(name) : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                player.connected
                    ? l10n.commonLevelShort(player.level)
                    : l10n.playPlayerDisconnected,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelSmall?.copyWith(
                  color: player.connected ? c.textSecondary : c.warning,
                ),
              ),
            ],
          ),
          if (onRemove != null)
            PositionedDirectional(
              top: -6,
              end: -6,
              child: IconButton(
                tooltip: l10n.playRemoveBotA11y(name),
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, color: c.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptySeatTile extends StatelessWidget {
  const _EmptySeatTile({required this.joining, this.onAddBot});

  final bool joining;
  final Future<void> Function()? onAddBot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgAll,
        color: c.surface.withValues(alpha: c.isDark ? 0.3 : 0.5),
        border: Border.all(color: c.outline, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (joining) ...[
            SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                valueColor: AlwaysStoppedAnimation(c.brand),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.playBotJoining,
              textAlign: TextAlign.center,
              style: context.textTheme.labelMedium,
            ),
          ] else ...[
            Icon(Icons.event_seat_rounded, color: c.textMuted, size: 30),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.playSeatOpen,
              textAlign: TextAlign.center,
              style: context.textTheme.labelMedium?.copyWith(
                color: c.textSecondary,
              ),
            ),
            if (onAddBot != null) ...[
              const SizedBox(height: AppSpacing.xs),
              PremiumButton(
                label: l10n.playAddBot,
                icon: Icons.smart_toy_rounded,
                size: PremiumButtonSize.small,
                variant: PremiumButtonVariant.secondary,
                onPressed: onAddBot,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _WaitingForHost extends StatelessWidget {
  const _WaitingForHost({this.hostName});

  final String? hostName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.brandSoft.withValues(alpha: c.isDark ? 0.2 : 0.6),
          borderRadius: AppRadii.mdAll,
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(c.brand),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                hostName == null
                    ? l10n.playLobbyWaitingForHost
                    : l10n.playLobbyWaitingForNamedHost(hostName!),
                style: context.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.text, this.icon, this.leading});

  final String text;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 12, 5),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: c.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ?? Icon(icon, size: 16, color: c.brand),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}
