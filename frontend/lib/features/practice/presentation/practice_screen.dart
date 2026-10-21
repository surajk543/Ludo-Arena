import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../game/application/play_config.dart';
import '../../game/presentation/play_nav.dart';
import '../../game/presentation/play_text.dart';
import '../../game/presentation/widgets/play_form.dart';
import '../../game/presentation/widgets/seat_orbit.dart';

enum _Phase { configuring, starting, botsJoining, failed }

/// `/practice` — practice against 1–3 bots (free, no coins). Starts with
/// `practice.start`, shows the bots sitting down (clearly labelled BOT) and
/// goes straight to the game once it starts.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key, required this.request});

  final PlayRequest request;

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  late PlayRequest _config = widget.request;
  _Phase _phase = _Phase.configuring;
  String? _errorCode;
  String? _roomId;
  String? _staleRoomId;
  bool _navigated = false;
  StreamSubscription<RoomEvent>? _sub;

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
    if (widget.request.explicit) {
      _phase = _Phase.starting;
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.starting;
      _errorCode = null;
    });
    try {
      final room = await ref
          .read(activeRoomControllerProvider.notifier)
          .startPractice(
            game: _config.game,
            variant: _config.variant,
            bots: _config.bots,
          );
      if (!mounted || _navigated) return;
      if (room != null) {
        _roomId = room.id;
        if (room.isPlaying) {
          _go(room, started: true);
          return;
        }
      }
      setState(() => _phase = _Phase.botsJoining);
    } on RealtimeCommandException catch (e) {
      if (!mounted || _navigated) return;
      final live = ref.read(activeRoomControllerProvider).room;
      if (e.code == 'already_in_room' &&
          live != null &&
          (live.isPlaying || live.isLobby)) {
        _go(live);
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _errorCode = e.code;
      });
    }
  }

  /// [started]: the server just started this practice game (not a resumed
  /// room).
  void _go(RoomSnapshot room, {bool started = false}) {
    if (_navigated) return;
    _navigated = true;
    if (started && room.isPlaying) {
      ref.read(audioServiceProvider).play(Sfx.matchStart);
    }
    PlayNav.toRoom(context, room);
  }

  void _onEvent(RoomEvent e) {
    if (!mounted || _navigated) return;
    switch (e) {
      case RoomSnapshotApplied(:final room):
        if (room.id == _staleRoomId || !room.isPractice) return;
        _roomId ??= room.id;
        if (room.isPlaying && room.id == _roomId) _go(room, started: true);
      case RoomErrorReceived(:final error):
        if (_phase == _Phase.starting || _phase == _Phase.botsJoining) {
          setState(() {
            _phase = _Phase.failed;
            _errorCode = error.code;
          });
        }
      case RoomCleared(:final roomId):
        if (roomId == _roomId && _phase == _Phase.botsJoining) {
          setState(() {
            _phase = _Phase.failed;
            _errorCode = _errorCode ?? 'bots_unavailable';
          });
        }
      default:
        break;
    }
  }

  Future<void> _cancel() async {
    if (_phase == _Phase.botsJoining || _phase == _Phase.starting) {
      try {
        await ref
            .read(activeRoomControllerProvider.notifier)
            .leaveRoom()
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    if (mounted && !_navigated) {
      _navigated = true;
      PlayNav.exit(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final live = ref.watch(activeRoomControllerProvider);
    final room =
        live.room != null &&
            live.room!.id != _staleRoomId &&
            live.room!.isPractice
        ? live.room
        : null;

    final Widget body = switch (_phase) {
      _Phase.configuring => _Config(
        config: _config,
        onChanged: (v) => setState(() => _config = v),
        onStart: _start,
      ),
      _Phase.failed => EmptyState(
        illustration: Icon(Icons.smart_toy_rounded, size: 72, color: c.brand),
        title: _errorCode == 'bots_unavailable'
            ? l10n.playPracticeBotsUnavailableTitle
            : l10n.playPracticeErrorTitle,
        message: localizedErrorMessage(l10n, _errorCode ?? 'unknown'),
        action: PremiumButton(
          label: l10n.playTryAgain,
          icon: Icons.refresh_rounded,
          expand: false,
          size: PremiumButtonSize.medium,
          onPressed: _start,
        ),
      ),
      _ => _Joining(
        room: room,
        selfUid: live.selfUid,
        totalBots: _config.bots,
        starting: _phase == _Phase.starting,
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
                PlayHeader(
                  title: l10n.playPracticeTitle,
                  onBack: _cancel,
                  closeIcon: _phase != _Phase.configuring,
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Config extends StatelessWidget {
  const _Config({
    required this.config,
    required this.onChanged,
    required this.onStart,
  });

  final PlayRequest config;
  final ValueChanged<PlayRequest> onChanged;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          children: [
            PlayGamePicker(
              value: config.game,
              onChanged: (g) => onChanged(config.copyWith(game: g)),
            ),
            PlayFieldLabel(l10n.playPracticeBotsLabel),
            ChoiceChips<int>(
              value: config.bots,
              onChanged: (v) => onChanged(config.copyWith(bots: v)),
              options: [
                for (final n in const [1, 2, 3])
                  ChoiceOption(value: n, label: l10n.playPracticeBotCount(n)),
              ],
            ),
            if (config.game == GameIds.ludo)
              PlayVariantPicker(
                value: config.variant,
                onChanged: (v) => onChanged(config.copyWith(variant: v)),
              ),
            const SizedBox(height: AppSpacing.lg),
            PlayNote(icon: Icons.school_rounded, text: l10n.playPracticeNote),
            const SizedBox(height: AppSpacing.xl),
            PremiumButton(
              label: l10n.playPracticeStart,
              icon: Icons.smart_toy_rounded,
              sound: Sfx.lobbyPlay,
              onPressed: onStart,
            ),
          ],
        ),
      ),
    );
  }
}

class _Joining extends StatelessWidget {
  const _Joining({
    required this.room,
    required this.selfUid,
    required this.totalBots,
    required this.starting,
  });

  final RoomSnapshot? room;
  final String? selfUid;
  final int totalBots;
  final bool starting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final players = room?.players ?? const <RoomPlayer>[];
    // Practice: everyone seated besides the player is a computer player.
    final seatedBots = selfUid == null
        ? math.max(0, players.length - 1)
        : players.where((p) => p.uid != selfUid).length;
    final capacity = room?.capacity ?? (totalBots + 1);
    final text = starting || room == null
        ? l10n.playPracticeSettingUp
        : l10n.playPracticeBotsJoining(seatedBots, totalBots);
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SeatOrbit(
              capacity: capacity,
              players: players,
              selfUid: selfUid,
              center: const Padding(
                padding: EdgeInsets.all(14),
                child: FittedBox(
                  child: Icon(Icons.smart_toy_rounded, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: context.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            room == null
                ? PlayText.mode(l10n, RoomModes.practice)
                : PlayText.gameTitle(l10n, room!.game, room!.variant),
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(
              color: c.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}
