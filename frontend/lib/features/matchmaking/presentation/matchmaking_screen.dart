import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/server_clock.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../game/application/play_config.dart';
import '../../game/presentation/play_nav.dart';
import '../../game/presentation/play_text.dart';
import '../../game/presentation/widgets/seat_orbit.dart';
import '../../home/application/play_options.dart' show entryFeeProvider;

enum _Phase { connecting, joining, searching, timeout, failed }

/// Public matchmaking: joins the queue for the requested game / variant /
/// capacity, shows seats filling with the real players from `room.updated`
/// and the fill countdown (server clock), and goes straight to the game on
/// `game.started`.
class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({super.key, required this.request});

  final PlayRequest request;

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen> {
  _Phase _phase = _Phase.connecting;
  String? _errorCode;
  String? _staleRoomId;
  bool _navigated = false;
  bool _cancelling = false;
  bool _joinRequested = false;
  StreamSubscription<RoomEvent>? _sub;
  ProviderSubscription<RealtimeStatus>? _statusSub;
  final Map<int, int> _fillTotals = {};

  @override
  void initState() {
    super.initState();
    final live = ref.read(activeRoomControllerProvider).room;
    if (live != null && !live.isPlaying && !live.isLobby) {
      // A finished room from the previous match: ignore it here.
      _staleRoomId = live.id;
    }
    _sub = ref
        .read(activeRoomControllerProvider.notifier)
        .events
        .listen(_onEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _statusSub?.close();
    super.dispose();
  }

  void _start() {
    if (!mounted) return;
    final live = ref.read(activeRoomControllerProvider).room;
    if (live != null && live.isPlaying) {
      _goToRoom(live);
      return;
    }
    if (ref.read(realtimeStatusProvider) == RealtimeStatus.connected) {
      _join();
      return;
    }
    setState(() => _phase = _Phase.connecting);
    _statusSub?.close();
    _statusSub = ref.listenManual<RealtimeStatus>(realtimeStatusProvider, (
      _,
      status,
    ) {
      if (status == RealtimeStatus.connected && _phase == _Phase.connecting) {
        _statusSub?.close();
        _statusSub = null;
        _join();
      }
    });
  }

  Future<void> _join() async {
    if (!mounted || _joinRequested) return;
    _joinRequested = true;
    setState(() {
      _phase = _Phase.joining;
      _errorCode = null;
    });
    final r = widget.request;
    try {
      await ref
          .read(activeRoomControllerProvider.notifier)
          .joinMatchmaking(
            game: r.game,
            variant: r.variant,
            capacity: r.capacity,
          );
      if (!mounted || _navigated) return;
      if (_phase == _Phase.joining) setState(() => _phase = _Phase.searching);
    } on RealtimeCommandException catch (e) {
      if (!mounted || _navigated) return;
      final live = ref.read(activeRoomControllerProvider).room;
      if (e.code == 'already_in_room' &&
          live != null &&
          (live.isPlaying || live.isLobby)) {
        _goToRoom(live);
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _errorCode = e.code;
      });
    } finally {
      _joinRequested = false;
    }
  }

  void _onEvent(RoomEvent e) {
    if (!mounted || _navigated) return;
    switch (e) {
      case MatchmakingUpdated(:final status):
        if (status.status == MatchmakingStatuses.timeout) {
          setState(() => _phase = _Phase.timeout);
        } else if (status.status == MatchmakingStatuses.cancelled &&
            !_cancelling) {
          setState(() => _phase = _Phase.timeout);
        } else if (status.isSearching && _phase != _Phase.searching) {
          setState(() => _phase = _Phase.searching);
        }
      case RoomSnapshotApplied(:final room):
        if (room.id == _staleRoomId) return;
        if (room.isPlaying) {
          // `game.started`: the server found the match.
          _goToRoom(room, started: true);
        } else if (room.isLobby && _phase != _Phase.searching) {
          setState(() => _phase = _Phase.searching);
        }
      case RoomErrorReceived(:final error):
        if (_phase == _Phase.searching || _phase == _Phase.joining) {
          setState(() {
            _phase = _Phase.failed;
            _errorCode = error.code;
          });
        }
      default:
        break;
    }
  }

  /// [started]: the game started while this screen was searching (a
  /// server-confirmed "match found"), not a resumed room.
  void _goToRoom(RoomSnapshot room, {bool started = false}) {
    if (_navigated) return;
    _navigated = true;
    if (started && room.isPlaying) {
      ref.read(audioServiceProvider).play(Sfx.matchStart);
    }
    if (room.mode == RoomModes.public || room.isPlaying) {
      PlayNav.toGame(context, room.id);
    } else {
      PlayNav.toRoom(context, room);
    }
  }

  Future<void> _cancel() async {
    if (_navigated) return;
    if (_phase != _Phase.searching && _phase != _Phase.joining) {
      PlayNav.exit(context);
      return;
    }
    _cancelling = true;
    try {
      await ref.read(activeRoomControllerProvider.notifier).cancelMatchmaking();
    } on RealtimeCommandException catch (_) {
      // The game may have started meanwhile (game.started navigates).
    }
    if (!mounted || _navigated) return;
    _navigated = true;
    PlayNav.exit(context);
  }

  void _retry() {
    setState(() {
      _phase = _Phase.connecting;
      _errorCode = null;
    });
    _start();
  }

  int _fillTotal(int deadline) => _fillTotals.putIfAbsent(deadline, () {
    final left = ref
        .read(serverClockProvider)
        .remainingUntil(deadline)
        .inMilliseconds;
    return math.max(left, 30000);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final live = ref.watch(activeRoomControllerProvider);
    final r = widget.request;
    final room = live.room;
    final lobby =
        room != null &&
            room.id != _staleRoomId &&
            room.mode == RoomModes.public &&
            room.isLobby
        ? room
        : null;

    // Safety net: started without a delivered event (e.g. resync).
    if (room != null &&
        room.id != _staleRoomId &&
        room.isPlaying &&
        !_navigated &&
        (_phase == _Phase.searching || _phase == _Phase.joining)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goToRoom(room, started: true);
      });
    }

    final players = lobby?.players ?? const <RoomPlayer>[];
    final capacity = lobby?.capacity ?? r.capacity;
    // Once seated, show the lobby's own fee: that is what the server charges
    // (a room keeps the fee it was created with).
    final configuredFee = ref.watch(entryFeeProvider(r.game));
    final fee = lobby?.entryFee ?? configuredFee;
    final locale = Localizations.localeOf(context);

    final Widget body = switch (_phase) {
      _Phase.timeout => _Outcome(
        icon: Icons.hourglass_disabled_rounded,
        title: l10n.playMatchmakingTimeoutTitle,
        message: l10n.playMatchmakingTimeoutMessage,
        onRetry: _retry,
      ),
      _Phase.failed => _Outcome(
        icon: _errorCode == 'insufficient_funds'
            ? Icons.savings_rounded
            : Icons.error_outline_rounded,
        title: _errorCode == 'insufficient_funds'
            ? l10n.playNotEnoughCoinsTitle
            : l10n.playMatchmakingErrorTitle,
        message: localizedErrorMessage(l10n, _errorCode ?? 'unknown'),
        onRetry:
            _errorCode != null &&
                _errorCode != 'insufficient_funds' &&
                _errorCode != 'update_required'
            ? _retry
            : null,
      ),
      _ => _Searching(
        phase: _phase,
        players: players,
        capacity: capacity,
        selfUid: live.selfUid,
        fillDeadline: lobby?.fillDeadline ?? 0,
        fillTotal: _fillTotal,
      ),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayeredBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 0),
                  child: Row(
                    children: [
                      IconCircleButton(
                        icon: Icons.close_rounded,
                        tooltip: l10n.playMatchmakingCancel,
                        sound: Sfx.uiClose,
                        onPressed: _cancel,
                        size: 40,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n.playMatchmakingTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.titleLarge,
                        ),
                      ),
                      const ConnectionIndicator(compact: true),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _Pill(
                        icon: r.isLudo
                            ? Icons.grid_view_rounded
                            : Icons.stairs_rounded,
                        text: PlayText.gameTitle(l10n, r.game, r.variant),
                      ),
                      _Pill(
                        icon: Icons.people_alt_rounded,
                        text: l10n.commonPlayerCount(capacity),
                      ),
                      _Pill(
                        leading: const CoinIcon(size: 16),
                        text: l10n.playEntryFee(formatCoins(fee, locale)),
                      ),
                    ],
                  ),
                ),
                Expanded(child: body),
                if (_phase != _Phase.timeout && _phase != _Phase.failed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      0,
                      AppSpacing.xl,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.playMatchmakingFeeNote,
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        PremiumButton(
                          label: l10n.playMatchmakingCancel,
                          icon: Icons.close_rounded,
                          variant: PremiumButtonVariant.secondary,
                          sound: Sfx.uiClose,
                          onPressed: _cancel,
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      0,
                      AppSpacing.xl,
                      AppSpacing.lg,
                    ),
                    child: PremiumButton(
                      label: l10n.playBackHome,
                      icon: Icons.home_rounded,
                      variant: PremiumButtonVariant.ghost,
                      onPressed: () => PlayNav.home(context),
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

class _Searching extends StatelessWidget {
  const _Searching({
    required this.phase,
    required this.players,
    required this.capacity,
    required this.selfUid,
    required this.fillDeadline,
    required this.fillTotal,
  });

  final _Phase phase;
  final List<RoomPlayer> players;
  final int capacity;
  final String? selfUid;
  final int fillDeadline;
  final int Function(int deadline) fillTotal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final status = switch (phase) {
      _Phase.connecting => l10n.playMatchmakingConnecting,
      _Phase.joining => l10n.playMatchmakingJoining,
      _ =>
        players.length >= capacity
            ? l10n.playMatchmakingStarting
            : l10n.playMatchmakingSearching,
    };
    final count = Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        '${players.length}/$capacity',
        style: context.textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    final center = fillDeadline > 0
        ? Padding(
            padding: const EdgeInsets.all(6),
            child: LayoutBuilder(
              builder: (context, constraints) => CountdownRing(
                deadlineMs: fillDeadline,
                totalMs: fillTotal(fillDeadline),
                size: constraints.biggest.shortestSide,
                strokeWidth: 4,
                color: BrandPalette.gold400,
                child: FittedBox(child: count),
              ),
            ),
          )
        : FittedBox(
            child: Padding(padding: const EdgeInsets.all(12), child: count),
          );

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Semantics(
              label: l10n.playMatchmakingPlayers(players.length, capacity),
              child: SeatOrbit(
                capacity: capacity,
                players: players,
                selfUid: selfUid,
                center: center,
              ),
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            status,
            textAlign: TextAlign.center,
            style: context.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            fillDeadline > 0
                ? l10n.playMatchmakingStartsSoon
                : l10n.playMatchmakingStartsWhenFull,
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(
              color: c.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      illustration: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.brandSoft.withValues(alpha: c.isDark ? 0.25 : 1),
        ),
        child: Icon(icon, size: 48, color: c.brand),
      ),
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : PremiumButton(
              label: l10n.playTryAgain,
              icon: Icons.refresh_rounded,
              expand: false,
              size: PremiumButtonSize.medium,
              onPressed: onRetry,
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon, this.leading});

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
