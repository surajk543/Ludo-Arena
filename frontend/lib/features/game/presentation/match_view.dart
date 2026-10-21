import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/analytics/analytics_providers.dart';
import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';
import '../../../core/audio_haptics/reduced_motion.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/server_clock.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/game_visuals/game_visuals.dart';
import '../../../shared/widgets/widgets.dart';
import '../../social/application/muted_players.dart';
import '../../social/presentation/player_actions_sheet.dart';
import '../application/inactivity_removal.dart';
import '../application/match_event_sequencer.dart';
import '../application/match_result_view.dart';
import '../application/quick_chat.dart';
import '../application/turn_input_guard.dart';
import '../application/viewer_loadout.dart';
import 'in_match_scope.dart';
import 'match_board_binding.dart';
import 'match_feedback.dart';
import 'play_nav.dart';
import 'play_text.dart';
import 'widgets/chat_bubbles.dart';
import 'widgets/match_overlays.dart';
import 'widgets/player_panel.dart';
import 'widgets/quick_chat_sheet.dart';
import 'widgets/results_panel.dart';

/// Shared in-game scaffold for Ludo and Snakes & Ladders.
///
/// - Consumes `ActiveRoomController.events` in order through a
///   [MatchEventSequencer] (dice → move → turn, snap on snapshots).
/// - Player panels around the board (seat corners), dice dock, status line.
/// - Roll / move with the live `turnSeq`, guarded against duplicate taps.
/// - Quick chat + emotes with a client throttle, local mute and per-player
///   mute (from the player's pod).
/// - Reconnect banner (non-blocking), leave/forfeit confirmation.
/// - Victory effect → results with rewards and rematch.
class MatchView extends ConsumerStatefulWidget {
  const MatchView({
    super.key,
    required this.roomId,
    required this.bindingFactory,
  });

  final String roomId;
  final MatchBoardBindingFactory bindingFactory;

  @override
  ConsumerState<MatchView> createState() => _MatchViewState();
}

/// One room round's board binding + sequencer.
class _Stage {
  _Stage(this.key, this.round, this.binding, this.sequencer, this.turns);

  final String key;
  final int round;
  final MatchBoardBinding binding;
  final MatchEventSequencer sequencer;

  /// Clockwise quarter turns of the view that put the local player in the
  /// bottom-left corner (same value the Ludo board binding uses).
  final int turns;

  void dispose() {
    sequencer.dispose();
    binding.dispose();
  }
}

String _stageKey(RoomSnapshot r) => '${r.id}#${r.round}#${seatCountOf(r)}';

/// Physical board corners (the board is never mirrored).
enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

/// Corner of [color] in the view turned by [turns] clockwise quarter turns.
_Corner _cornerOf(SeatColor color, int turns) => switch (color.rotated(turns)) {
  SeatColor.red => _Corner.topLeft,
  SeatColor.green => _Corner.topRight,
  SeatColor.yellow => _Corner.bottomRight,
  SeatColor.blue => _Corner.bottomLeft,
};

class _MatchViewState extends ConsumerState<MatchView> {
  _Stage? _stage;
  StreamSubscription<RoomEvent>? _sub;
  final TurnInputGuard _guard = TurnInputGuard();
  final ChatBubbleHub _bubbles = ChatBubbleHub();
  late final QuickChatThrottle _throttle;
  late final MatchFeedback _feedback;
  final Map<int, LayerLink> _links = {};
  final Map<int, int> _turnTotals = {};
  final Set<String> _resultsLogged = {};

  /// Stages whose room was already finished when the screen opened.
  final Set<String> _finishedOnOpen = {};

  bool _localMute = false;
  bool _playerSheetOpen = false;
  bool _commandInFlight = false;
  bool _leaving = false;
  bool _navigating = false;

  /// The server removed the local player for missing turns in a row.
  bool _removed = false;
  bool _waitingNextRound = false;
  String? _finishedKey;
  bool _showVictory = false;
  bool _showResults = false;
  MatchRewards _rewards = const MatchRewards();
  Timer? _progressionTimer;

  String? _caption;
  Timer? _captionTimer;

  @override
  void initState() {
    super.initState();
    _feedback = MatchFeedback(
      audio: ref.read(audioServiceProvider),
      haptics: ref.read(hapticsServiceProvider),
    );
    _throttle = QuickChatThrottle(now: ref.read(clockProvider));
    final live = ref.read(activeRoomControllerProvider);
    final room = live.room;
    if (room != null && room.id == widget.roomId) {
      _stage = _createStage(room, live.selfSeat);
      if (room.isFinished) {
        _finishedOnOpen.add(_stageKey(room));
        _armProgressionTimeout();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _onPresented());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _leaveIfRemoved(room);
      });
    }
    _sub = ref
        .read(activeRoomControllerProvider.notifier)
        .events
        .listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _progressionTimer?.cancel();
    _captionTimer?.cancel();
    _bubbles.dispose();
    final stage = _stage;
    _stage = null;
    if (stage != null) {
      stage.sequencer.presented.removeListener(_onPresented);
      stage.sequencer.busy.removeListener(_onBusy);
      stage.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------- stages

  _Stage _createStage(RoomSnapshot room, int? selfSeat) {
    final binding = widget.bindingFactory(
      room,
      selfSeat: selfSeat,
      feedback: _feedback,
    );
    final sequencer = MatchEventSequencer(
      animator: _ObservingAnimator(
        binding,
        onDice: _onDicePlayed,
        onTurn: _onTurnPlayed,
        onOther: _onOtherPlayed,
      ),
      initial: room,
    );
    sequencer.presented.addListener(_onPresented);
    sequencer.busy.addListener(_onBusy);
    return _Stage(
      _stageKey(room),
      room.round,
      binding,
      sequencer,
      boardTurnsFor(room, selfSeat),
    );
  }

  void _replaceStage(RoomSnapshot room) {
    final old = _stage;
    final selfSeat = ref.read(activeRoomControllerProvider).selfSeat;
    setState(() {
      _stage = _createStage(room, selfSeat);
      _guard.reset();
      _rewards = const MatchRewards();
      _progressionTimer?.cancel();
      _showVictory = false;
      _showResults = false;
      _finishedKey = null;
      _waitingNextRound = false;
      _commandInFlight = false;
      _turnTotals.clear();
      _bubbles.clear();
    });
    if (old != null) {
      old.sequencer.presented.removeListener(_onPresented);
      old.sequencer.busy.removeListener(_onBusy);
      // Widgets still reference the old controllers until the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  // ------------------------------------------------------------- events

  void _onEvent(RoomEvent e) {
    if (!mounted || _removed) return;
    switch (e) {
      case RoomSnapshotApplied(:final room):
        if (room.id != widget.roomId) {
          _followRoom(room);
          return;
        }
        if (_leaveIfRemoved(room)) return;
        final stage = _stage;
        if (stage == null || _stageKey(room) != stage.key) {
          _onNewRound(room);
          return;
        }
        if (_waitingNextRound && room.isPlaying) {
          setState(() => _waitingNextRound = false);
        }
        stage.sequencer.add(e);
      case RoomDeltaApplied(:final room):
        if (_leaveIfRemoved(room)) return;
        _stage?.sequencer.add(e);
      case QuickChatReceived(:final chat, :final fromSelf):
        _showBubble(chat.seat, fromSelf, text: chat.msg);
      case EmoteReceived(:final emote, :final fromSelf):
        _showBubble(
          emote.seat,
          fromSelf,
          emoteId: emote.emote,
          emoteAsset: emote.asset,
        );
      case RoomCleared(:final reason):
        if (_leaving || _navigating) return;
        _navigating = true;
        final l10n = AppLocalizations.of(context);
        AppToast.show(
          context,
          reason == RoomClearReason.closed
              ? l10n.playRoomClosed
              : l10n.playMatchUnavailable,
          kind: ToastKind.warning,
        );
        PlayNav.home(context);
      default:
        break;
    }
  }

  /// The server removed the local player for missing turns in a row (live
  /// `player.forfeited` or a snapshot after a resync): tell them why, once
  /// per room round, and leave the match — also when that forfeit ended a
  /// two-player game (no results). Returns true when leaving.
  bool _leaveIfRemoved(RoomSnapshot room) {
    if (_removed) return true;
    if (room.id != widget.roomId) return false;
    final selfUid = ref.read(activeRoomControllerProvider).selfUid;
    final missed = inactivityRemovalOf(room, selfUid);
    if (missed == null) return false;
    _removed = true;
    _navigating = true;
    if (!_leaving && ref.read(inactivityRemovalNoticesProvider).claim(room)) {
      AppToast.show(
        context,
        AppLocalizations.of(context).playRemovedForInactivity(missed),
        kind: ToastKind.warning,
        duration: const Duration(seconds: 5),
      );
    }
    unawaited(_leaveTo(AppRoutes.home));
    return true;
  }

  /// A snapshot for another room (e.g. a public rematch created a new
  /// private room with the accepting players).
  void _followRoom(RoomSnapshot room) {
    if (_navigating || _leaving) return;
    if (!(room.isLobby || room.isPlaying)) return;
    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PlayNav.toRoom(context, room);
    });
  }

  /// Same room, new round (rematch) or a seat-count change.
  void _onNewRound(RoomSnapshot room) {
    if (room.isLobby) {
      if (room.isPrivate) {
        if (_navigating) return;
        _navigating = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) PlayNav.toLobby(context, room.id);
        });
      } else {
        // Practice / public: the next round starts by itself.
        setState(() => _waitingNextRound = true);
      }
      return;
    }
    final previous = _stage;
    final newRound = previous != null && room.round != previous.round;
    if (previous == null && room.isFinished) {
      _finishedOnOpen.add(_stageKey(room));
    }
    _replaceStage(room);
    // A rematch / next round the server just started.
    if (newRound && room.isPlaying) _feedback.matchStart();
  }

  void _onPresented() {
    final stage = _stage;
    if (!mounted || stage == null) return;
    final room = stage.sequencer.presented.value;
    if (room.isFinished && _finishedKey != stage.key) {
      _finishedKey = stage.key;
      final selfUid = ref.read(activeRoomControllerProvider).selfUid;
      final result = MatchResultView.from(room, selfUid);
      // Only a finish seen live gets a cue (not a finished room re-opened),
      // and spectators hear nothing.
      if (!_finishedOnOpen.contains(stage.key)) {
        switch (result.outcome) {
          case MatchOutcome.won:
            _feedback.win();
          case MatchOutcome.lost || MatchOutcome.forfeited:
            _feedback.lose();
          case MatchOutcome.spectator:
            break;
        }
      }
      _showVictory = result.winner != null;
      if (!_showVictory) _revealResults();
    }
    setState(() {});
  }

  void _onBusy() {
    if (mounted) setState(() {});
  }

  void _revealResults() {
    if (!mounted) return;
    final stage = _stage;
    setState(() {
      _showVictory = false;
      _showResults = true;
    });
    if (stage == null) return;
    final room = stage.sequencer.presented.value;
    final key = '${room.id}#${room.round}';
    if (_resultsLogged.add(key)) {
      final selfUid = ref.read(activeRoomControllerProvider).selfUid;
      ref
          .read(analyticsServiceProvider)
          .gameResultViewed(matchAnalyticsContext(room, selfUid));
    }
  }

  // --------------------------------------------------------- animations

  void _onDicePlayed(DiceResultEvent e, RoomSnapshot room) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final player = room.playerAtSeat(e.seat);
    if (e.voided) {
      _showCaption(l10n.playVoidedThreeSixes);
    } else if (e.auto && player != null) {
      _showCaption(l10n.playAutoPlayed(PlayText.playerName(l10n, player)));
    }
  }

  void _onTurnPlayed(TurnChangedEvent e, RoomSnapshot room) {
    final selfSeat = room
        .playerByUid(ref.read(activeRoomControllerProvider).selfUid)
        ?.seat;
    if (selfSeat != null && e.seat == selfSeat && room.isPlaying) {
      _feedback.myTurn();
    }
  }

  void _onOtherPlayed(RoomDeltaEvent e, RoomSnapshot room) {
    if (!mounted || e is! PlayerForfeitedEvent) return;
    final l10n = AppLocalizations.of(context);
    final player = room.playerAtSeat(e.seat);
    if (player == null) return;
    final name = PlayText.playerName(l10n, player);
    _showCaption(
      e.reason == ForfeitReasons.timeouts
          ? l10n.playForfeitTimeouts(
              name,
              e.strikes > 0 ? e.strikes : ForfeitReasons.defaultMaxStrikes,
            )
          : l10n.playForfeitLeft(name),
    );
  }

  void _showCaption(String text) {
    _captionTimer?.cancel();
    setState(() => _caption = text);
    _captionTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _caption = null);
    });
  }

  // ---------------------------------------------------------- chat

  void _showBubble(
    int seat,
    bool fromSelf, {
    String? text,
    String? emoteId,
    EmoteAsset? emoteAsset,
  }) {
    final policy = ChatMutePolicy(
      settingsMuted: ref.read(settingsControllerProvider).quickChatMuted,
      localMuted: _localMute,
    );
    if (!policy.shouldShow(fromSelf: fromSelf)) return;
    if (!fromSelf && _seatMuted(seat)) return;
    final l10n = AppLocalizations.of(context);
    final line = text == null ? null : PlayText.quickChat(l10n, text);
    if (text != null && line == null) return; // unknown id: never shown raw
    _bubbles.show(seat, text: line, emoteId: emoteId, emoteAsset: emoteAsset);
    _feedback.chat();
  }

  /// Whether the player in [seat] is muted from their pod.
  bool _seatMuted(int seat) {
    final room =
        _stage?.sequencer.presented.value ??
        ref.read(activeRoomControllerProvider).room;
    final uid = room?.playerAtSeat(seat)?.uid;
    return uid != null && ref.read(mutedPlayersProvider).contains(uid);
  }

  Future<void> _openChat() async {
    await QuickChatSheet.show(
      context,
      throttle: _throttle,
      localMuted: _localMute,
      settingsMuted: ref.read(settingsControllerProvider).quickChatMuted,
      onPick: _sendChat,
      onMuteChanged: (v) {
        setState(() => _localMute = v);
        if (v) _bubbles.clear();
      },
    );
  }

  Future<void> _sendChat(QuickChatPick pick) async {
    if (!_throttle.tryAcquire()) return;
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(activeRoomControllerProvider.notifier);
    try {
      switch (pick) {
        case QuickMessagePick(:final id):
          await controller.sendQuickChat(id);
        case EmotePick(:final emoteId):
          await controller.sendEmote(emoteId);
      }
    } on RealtimeCommandException catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        localizedErrorMessage(l10n, e.code),
        kind: ToastKind.warning,
      );
    }
  }

  // ------------------------------------------------------- player sheet

  /// Opponent options (add friend / mute / report), the same for every
  /// opponent. Never for my own seat; only the profile for spectators.
  Future<void> _openPlayer(RoomPlayer p) async {
    final live = ref.read(activeRoomControllerProvider);
    if (_playerSheetOpen || p.uid == live.selfUid) return;
    final l10n = AppLocalizations.of(context);
    final room = _stage?.sequencer.presented.value;
    final seated = room?.playerByUid(live.selfUid) != null;
    _playerSheetOpen = true;
    try {
      await PlayerActionsSheet.show(
        context,
        player: PlayerSheetTarget(
          uid: p.uid,
          name: PlayText.playerName(l10n, p),
          avatar: p.avatar,
          picture: p.picture,
          level: p.level,
          frameId: p.cosmetics.frame,
          seatColor: SeatColor.tryFromName(p.color),
        ),
        roomId: room?.id ?? widget.roomId,
        canAct: seated,
      );
    } finally {
      _playerSheetOpen = false;
    }
    // Muting from the sheet also hides the bubble already on screen.
    if (mounted && ref.read(mutedPlayersProvider).contains(p.uid)) {
      _bubbles.hide(p.seat);
    }
  }

  // ------------------------------------------------------------ actions

  bool _inFlight(ActiveRoomState live) =>
      _commandInFlight || live.rollInFlight || live.moveInFlight;

  Future<void> _roll() async {
    final stage = _stage;
    final live = ref.read(activeRoomControllerProvider);
    final room = live.room;
    if (stage == null || room == null) return;
    if (!_guard.canRoll(
      live: room,
      presented: stage.sequencer.presented.value,
      selfSeat: live.selfSeat,
      busy: stage.sequencer.busy.value,
      commandInFlight: _inFlight(live),
    )) {
      return;
    }
    final seq = room.turn.turnSeq;
    final l10n = AppLocalizations.of(context);
    _guard.markRollSent(seq);
    _feedback.rollTapped();
    stage.binding.dice.beginRoll();
    setState(() => _commandInFlight = true);
    try {
      final sent = await ref
          .read(activeRoomControllerProvider.notifier)
          .rollDice();
      if (!sent) {
        _guard.rollFailed(seq);
        if (identical(_stage, stage)) stage.binding.dice.cancel();
      }
    } on RealtimeCommandException catch (e) {
      _guard.rollFailed(seq);
      if (identical(_stage, stage)) stage.binding.dice.cancel();
      if (mounted && e.code != 'stale_state') {
        AppToast.show(
          context,
          localizedErrorMessage(l10n, e.code),
          kind: ToastKind.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _commandInFlight = false);
    }
  }

  Future<void> _move(int token) async {
    final stage = _stage;
    final live = ref.read(activeRoomControllerProvider);
    final room = live.room;
    if (stage == null || room == null) return;
    if (!_guard.canMove(
      live: room,
      presented: stage.sequencer.presented.value,
      selfSeat: live.selfSeat,
      busy: stage.sequencer.busy.value,
      token: token,
      commandInFlight: _inFlight(live),
    )) {
      return;
    }
    final seq = room.turn.turnSeq;
    final l10n = AppLocalizations.of(context);
    _guard.markMoveSent(seq);
    _feedback.tokenTapped();
    stage.binding.clearLegalMoves();
    setState(() => _commandInFlight = true);
    try {
      final sent = await ref
          .read(activeRoomControllerProvider.notifier)
          .makeMove(token);
      if (!sent) _restoreMoves(stage, seq);
    } on RealtimeCommandException catch (e) {
      _restoreMoves(stage, seq);
      if (mounted && e.code != 'stale_state') {
        AppToast.show(
          context,
          localizedErrorMessage(l10n, e.code),
          kind: ToastKind.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _commandInFlight = false);
    }
  }

  void _restoreMoves(_Stage stage, int seq) {
    _guard.moveFailed(seq);
    final live = ref.read(activeRoomControllerProvider).room;
    if (identical(_stage, stage) &&
        live != null &&
        live.turn.turnSeq == seq &&
        !stage.sequencer.busy.value) {
      stage.binding.showLegalMoves(live);
    }
  }

  Future<void> _onBack() async {
    final live = ref.read(activeRoomControllerProvider).room;
    if (live != null && live.id == widget.roomId && live.isPlaying) {
      final ok = await confirmLeaveMatch(context, practice: live.isPractice);
      if (!ok || !mounted) return;
    }
    await _leaveTo(AppRoutes.home);
  }

  /// Leaves the room (playing: forfeit; finished: leave) and navigates.
  Future<void> _leaveTo(String location) async {
    if (_leaving) return;
    _leaving = true;
    final router = GoRouter.of(context);
    try {
      await ref
          .read(activeRoomControllerProvider.notifier)
          .leaveRoom()
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Best effort: the server also auto-leaves finished rooms.
    }
    router.go(location);
  }

  Future<void> _playAgain() async {
    final room = _stage?.sequencer.presented.value;
    if (room == null) return _leaveTo(AppRoutes.home);
    final bots = room.players.where((p) => p.bot).length.clamp(1, 3);
    final target = room.isPractice
        ? AppRoutes.practiceFor(
            game: room.game,
            variant: room.variant,
            bots: bots,
          )
        : AppRoutes.matchmakingFor(
            game: room.game,
            variant: room.variant,
            capacity: room.capacity,
          );
    await _leaveTo(target);
  }

  Future<void> _rematch(bool accept) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(activeRoomControllerProvider.notifier)
          .rematch(accept: accept);
    } on RealtimeCommandException catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        localizedErrorMessage(l10n, e.code),
        kind: ToastKind.warning,
      );
    }
  }

  // ------------------------------------------------------------ rewards

  void _armProgressionTimeout() {
    _progressionTimer?.cancel();
    _progressionTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted || _rewards.progression != null) return;
      setState(() => _rewards = _rewards.copyWith(progressionTimedOut: true));
    });
  }

  void _onAccountEvent(ServerEvent e) {
    final live = ref.read(activeRoomControllerProvider).room;
    if (live == null || live.id != widget.roomId || !live.isFinished) return;
    final next = _rewards.apply(e);
    if (identical(next, _rewards)) return;
    if (e is WalletUpdatedEvent) _feedback.coins();
    if (e is ProgressionUpdatedEvent && e.levelUp) _feedback.levelUp();
    setState(() => _rewards = next);
  }

  int _turnTotal(RoomSnapshot room) {
    final deadline = room.turn.deadline;
    return _turnTotals.putIfAbsent(deadline, () {
      final left = ref
          .read(serverClockProvider)
          .remainingUntil(deadline)
          .inMilliseconds;
      final player = room.playerAtSeat(room.turn.seat);
      final nominal = player != null && !player.connected ? 8000 : 20000;
      return math.min(60000, math.max(left, nominal));
    });
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<WalletUpdatedEvent>>(walletUpdatesProvider, (
      _,
      next,
    ) {
      final e = next.value;
      if (e != null) _onAccountEvent(e);
    });
    ref.listen<AsyncValue<ProgressionUpdatedEvent>>(
      progressionUpdatesProvider,
      (_, next) {
        final e = next.value;
        if (e != null) _onAccountEvent(e);
      },
    );
    ref.listen<String?>(
      activeRoomControllerProvider.select((s) => s.room?.status),
      (previous, next) {
        if (next == RoomStatuses.finished &&
            previous != RoomStatuses.finished) {
          _armProgressionTimeout();
        }
      },
    );

    final l10n = AppLocalizations.of(context);
    final stage = _stage;
    if (stage == null) {
      return Scaffold(body: LoadingState(message: l10n.playLoadingMatch));
    }
    final live = ref.watch(activeRoomControllerProvider);
    final presented = stage.sequencer.presented.value;
    final busy = stage.sequencer.busy.value;
    final reduce = ReducedMotion.of(context);
    final themes = ref.watch(viewerBoardThemesProvider);
    final selfUid = live.selfUid;
    final selfSeat = presented.playerByUid(selfUid)?.seat;
    final inFlight = _inFlight(live);

    final canRoll = _guard.canRoll(
      live: live.room,
      presented: presented,
      selfSeat: live.selfSeat,
      busy: busy,
      commandInFlight: inFlight,
    );
    final canPick = _guard.canPickToken(
      live: live.room,
      presented: presented,
      selfSeat: live.selfSeat,
      busy: busy,
      commandInFlight: inFlight,
    );

    final board = stage.binding.buildBoard(
      context,
      MatchBoardArgs(
        presented: presented,
        reducedMotion: reduce,
        onTokenTap: canPick ? _move : null,
        ludoBoardTheme: themes.ludo,
        snakesBoardTheme: themes.snakes,
      ),
    );

    final finished = presented.isFinished;
    final winner = finished
        ? presented.playerAtSeat(presented.result?.winnerSeat ?? -1)
        : null;
    final palette = GamePalette.of(context);

    return InMatchScope(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LayeredBackground(
            style: LayeredBackgroundStyle.calm,
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _MatchLayout(
                      room: presented,
                      selfSeat: selfSeat,
                      turns: stage.turns,
                      board: board,
                      boardAspectRatio: stage.binding.boardAspectRatio,
                      links: _links,
                      turnTotal: _turnTotal,
                      onPlayerTap: _openPlayer,
                      mutedUids: ref.watch(mutedPlayersProvider),
                      topBar: _TopBar(
                        room: presented,
                        onLeave: _onBack,
                        onChat: _openChat,
                        chatMuted:
                            _localMute ||
                            ref.watch(
                              settingsControllerProvider.select(
                                (s) => s.quickChatMuted,
                              ),
                            ),
                      ),
                      dice: (size) => _DiceDock(
                        binding: stage.binding,
                        room: presented,
                        enabled: canRoll,
                        onRoll: _roll,
                        reducedMotion: reduce,
                        size: size,
                      ),
                      status: _StatusLine(
                        room: presented,
                        selfSeat: selfSeat,
                        canRoll: canRoll,
                        canPick: canPick,
                        caption: _caption,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 56,
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    child: ReconnectBanner(syncing: live.syncing),
                  ),
                  Positioned.fill(
                    child: ChatBubbleLayer(
                      hub: _bubbles,
                      links: _links,
                      topSeats: {
                        for (final p in presented.players)
                          if (_isTopSeat(p, stage.turns)) p.seat,
                      },
                      seatColors: {
                        for (final p in presented.players)
                          p.seat:
                              SeatColor.tryFromName(p.color) ?? SeatColor.red,
                      },
                    ),
                  ),
                  if (_showVictory && winner != null)
                    Positioned.fill(
                      child: VictoryOverlay(
                        key: ValueKey('victory-${stage.key}'),
                        victoryId: VictoryStyles.resolve(
                          winner.cosmetics.victory,
                        ),
                        color: palette.seat(
                          SeatColor.tryFromName(winner.color) ?? SeatColor.red,
                        ),
                        reducedMotion: reduce,
                        onDone: _revealResults,
                      ),
                    ),
                  if (_showResults && finished)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: ResultsPanel(
                          room: presented,
                          selfUid: selfUid,
                          rewards: _rewards,
                          onRematch: _rematch,
                          onPlayAgain: _playAgain,
                          onHome: () => _leaveTo(AppRoutes.home),
                          onPlayerTap: _openPlayer,
                        ),
                      ),
                    ),
                  if (_waitingNextRound)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: LoadingState(
                          message: l10n.playStartingNextRound,
                        ),
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

bool _isTopSeat(RoomPlayer p, int turns) {
  final color = SeatColor.tryFromName(p.color) ?? SeatColor.red;
  final corner = _cornerOf(color, turns);
  return corner == _Corner.topLeft || corner == _Corner.topRight;
}

/// Forwards sequencer calls to the board binding and reports finished
/// steps (captions, turn cue).
class _ObservingAnimator implements MatchAnimator {
  _ObservingAnimator(
    this._inner, {
    required this.onDice,
    required this.onTurn,
    required this.onOther,
  });

  final MatchBoardBinding _inner;
  final void Function(DiceResultEvent, RoomSnapshot) onDice;
  final void Function(TurnChangedEvent, RoomSnapshot) onTurn;
  final void Function(RoomDeltaEvent, RoomSnapshot) onOther;

  @override
  void snapTo(RoomSnapshot room) => _inner.snapTo(room);

  @override
  void cancelAnimations() => _inner.cancelAnimations();

  @override
  Future<void> playDice(
    DiceResultEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) async {
    await _inner.playDice(event, room, previous);
    onDice(event, room);
  }

  @override
  Future<void> playMove(
    MoveAppliedEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) => _inner.playMove(event, room, previous);

  @override
  Future<void> playTurnChange(TurnChangedEvent event, RoomSnapshot room) async {
    await _inner.playTurnChange(event, room);
    onTurn(event, room);
  }

  @override
  Future<void> playOther(
    RoomDeltaEvent event,
    RoomSnapshot room,
    RoomSnapshot previous,
  ) async {
    await _inner.playOther(event, room, previous);
    onOther(event, room);
  }
}

// ------------------------------------------------------------------ layout

class _MatchLayout extends StatelessWidget {
  const _MatchLayout({
    required this.room,
    required this.selfSeat,
    required this.turns,
    required this.board,
    this.boardAspectRatio = 1,
    required this.links,
    required this.turnTotal,
    required this.onPlayerTap,
    required this.topBar,
    required this.dice,
    required this.status,
    this.mutedUids = const {},
  });

  final RoomSnapshot room;
  final int? selfSeat;
  final int turns;
  final Widget board;

  /// Width / height of [board] (see MatchBoardBinding.boardAspectRatio).
  final double boardAspectRatio;
  final Map<int, LayerLink> links;
  final int Function(RoomSnapshot) turnTotal;
  final ValueChanged<RoomPlayer> onPlayerTap;

  /// Players muted from their pod (a muted icon on the pod).
  final Set<String> mutedUids;
  final Widget topBar;

  /// The dice dock at a diameter (see [_PortraitFit.dock]).
  final Widget Function(double size) dice;
  final Widget status;

  RoomPlayer? _at(_Corner corner) {
    for (final p in room.players) {
      final color = SeatColor.tryFromName(p.color);
      if (color != null && _cornerOf(color, turns) == corner) return p;
    }
    return null;
  }

  Widget _panel(BuildContext context, RoomPlayer? p, {double? height}) {
    if (p == null) return const SizedBox.shrink();
    final ambient = Directionality.of(context);
    final link = links.putIfAbsent(p.seat, LayerLink.new);
    final isTurn = room.isPlaying && room.turn.seat == p.seat;
    return CompositedTransformTarget(
      link: link,
      child: Directionality(
        textDirection: ambient,
        child: PlayerPanel(
          player: p,
          room: room,
          isSelf: p.seat == selfSeat,
          isTurn: isTurn,
          turnTotalMs: isTurn ? turnTotal(room) : 20000,
          height: height,
          muted: p.seat != selfSeat && mutedUids.contains(p.uid),
          onTap: p.seat == selfSeat ? null : () => onPlayerTap(p),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > constraints.maxHeight * 1.15;
        if (wide) return _landscape(context, constraints);
        return _portrait(context);
      },
    );
  }

  Widget _portrait(BuildContext context) {
    final ambient = Directionality.of(context);
    return Column(
      children: [
        topBar,
        // Measured below the top bar and above the status line (both follow
        // the text scale), inside the SafeArea.
        Expanded(
          child: LayoutBuilder(
            builder: (context, area) {
              final fit = _PortraitFit(context, area.biggest, boardAspectRatio);
              Widget row(
                _Corner start,
                _Corner end,
                Widget middle,
              ) => Directionality(
                // Panels follow the board's physical corners (the
                // board is LTR).
                textDirection: TextDirection.ltr,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _panel(context, _at(start), height: fit.podHeight),
                    ),
                    Directionality(textDirection: ambient, child: middle),
                    Expanded(
                      child: _panel(context, _at(end), height: fit.podHeight),
                    ),
                  ],
                ),
              );
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _PortraitFit.sidePad,
                      _PortraitFit.topGap,
                      _PortraitFit.sidePad,
                      0,
                    ),
                    child: row(
                      _Corner.topLeft,
                      _Corner.topRight,
                      // Same middle width as the dice slot below, so all
                      // four pods get the same width (and size).
                      SizedBox(width: fit.diceSlot),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(_PortraitFit.boardPad),
                      child: Center(child: board),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _PortraitFit.sidePad,
                    ),
                    child: row(
                      _Corner.bottomLeft,
                      _Corner.bottomRight,
                      SizedBox(
                        width: fit.diceSlot,
                        child: Center(child: dice(fit.dock)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        status,
      ],
    );
  }

  Widget _landscape(BuildContext context, BoxConstraints constraints) {
    final side = math.min(340.0, constraints.maxWidth * 0.38);
    final players = [...room.players]..sort((a, b) => a.seat - b.seat);
    return Column(
      children: [
        topBar,
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(child: board),
                ),
              ),
              SizedBox(
                width: side,
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final p in players) ...[
                        _panel(context, p),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Center(child: dice(_DiceDock.defaultSize)),
                      status,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Portrait sizing between the top bar and the status line: the board keeps
/// its full width (area width − 2 × [boardPad]) at its own aspect ratio, and
/// the two pod rows split the height left over, so pods and board fill the
/// screen instead of leaving gaps around the board. Pods never take height
/// from the board: shorter than a row pod, they keep their natural size.
class _PortraitFit {
  factory _PortraitFit(
    BuildContext context,
    Size area,
    double boardAspectRatio,
  ) {
    final board = (area.width - 2 * boardPad) / boardAspectRatio;
    final podHeight = ((area.height - topGap - 2 * boardPad - board) / 2)
        .floorToDouble();
    return _PortraitFit._(podHeight, _dockFor(context, area, podHeight));
  }

  _PortraitFit._(this.podHeight, this.dock);

  /// The dock grows a little with tall rows, but only into width the pods
  /// cannot use (their avatars are limited by the height). In 64–80 dp rows
  /// it shrinks to the row, so the bottom row is no taller than the pods
  /// and the board keeps its width; in shorter (cramped) layouts, where
  /// the board gives way anyway, it keeps its default size.
  static double _dockFor(BuildContext context, Size area, double podHeight) {
    if (podHeight < _DiceDock.minSize) return _DiceDock.defaultSize;
    if (podHeight < _DiceDock.defaultSize) return podHeight;
    final podWidth = (area.width - 2 * sidePad - _baseSlot) / 2;
    final spare = math.max(
      0.0,
      podWidth - PlayerPanel.fillWidthFor(context, podHeight),
    );
    return math
        .min(
          (podHeight * 0.75).clamp(_DiceDock.defaultSize, _DiceDock.maxSize),
          _DiceDock.defaultSize + 2 * spare,
        )
        .floorToDouble();
  }

  /// Middle slot for the default dock.
  static const double _baseSlot = _DiceDock.defaultSize + 4;

  static const double sidePad = 8;
  static const double topGap = 4;

  /// Between the pod rows and the board (and at the board's sides).
  static const double boardPad = 6;

  /// Height each pod row may fill (see [PlayerPanel.height]).
  final double podHeight;

  /// Dice dock diameter.
  final double dock;

  /// Middle slot of both pod rows (dock + 4 dp): all four pods share the
  /// same width.
  double get diceSlot => dock + 4;
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.room,
    required this.onLeave,
    required this.onChat,
    required this.chatMuted,
  });

  final RoomSnapshot room;
  final VoidCallback onLeave;
  final VoidCallback onChat;
  final bool chatMuted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final subtitle = [
      PlayText.mode(l10n, room.mode),
      if (room.round > 1) l10n.playRoundLabel(room.round),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 2),
      child: Row(
        children: [
          IconCircleButton(
            icon: room.isFinished ? Icons.home_rounded : Icons.close_rounded,
            tooltip: room.isFinished ? l10n.playHome : l10n.playLeave,
            onPressed: onLeave,
            size: 40,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  PlayText.gameTitle(l10n, room.game, room.variant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleMedium,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const ConnectionIndicator(compact: true),
          const SizedBox(width: AppSpacing.xs),
          IconCircleButton(
            icon: chatMuted
                ? Icons.speaker_notes_off_rounded
                : Icons.chat_bubble_rounded,
            tooltip: l10n.playChatOpen,
            onPressed: room.isPlaying || room.isFinished ? onChat : null,
            size: 40,
          ),
        ],
      ),
    );
  }
}

class _DiceDock extends StatelessWidget {
  const _DiceDock({
    required this.binding,
    required this.room,
    required this.enabled,
    required this.onRoll,
    required this.reducedMotion,
    this.size = defaultSize,
  });

  static const double defaultSize = 80;
  static const double minSize = 64;
  static const double maxSize = 92;

  final MatchBoardBinding binding;
  final RoomSnapshot room;
  final bool enabled;
  final VoidCallback onRoll;
  final bool reducedMotion;

  /// Dock diameter; the die is 70 % of it (56 dp in the 80 dp dock).
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of(context);
    final c = context.colors;
    final current = room.isPlaying ? room.playerAtSeat(room.turn.seat) : null;
    final seat = SeatColor.tryFromName(current?.color);
    final accent = seat == null ? c.brand : palette.seat(seat);
    // The whole dock is tappable (≥ 48 dp); the die carries the semantics.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onRoll : null,
      excludeFromSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.surface.withValues(alpha: c.isDark ? 0.6 : 0.85),
          border: Border.all(
            color: enabled ? accent : c.outline.withValues(alpha: 0.6),
            width: enabled ? 2.5 : 1,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 16,
                  ),
                ]
              : c.shadow(AppElevation.low),
        ),
        alignment: Alignment.center,
        child: DiceView(
          controller: binding.dice,
          skin: DiceSkins.resolve(current?.cosmetics.dice),
          size: (size * 0.7).roundToDouble(),
          enabled: enabled,
          onTap: enabled ? onRoll : null,
          accent: accent,
          reducedMotion: reducedMotion,
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.room,
    required this.selfSeat,
    required this.canRoll,
    required this.canPick,
    this.caption,
  });

  final RoomSnapshot room;
  final int? selfSeat;
  final bool canRoll;
  final bool canPick;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final reduce = ReducedMotion.of(context);
    String? text = caption;
    var highlight = caption != null;
    if (text == null && room.isPlaying) {
      final current = room.playerAtSeat(room.turn.seat);
      final mine = selfSeat != null && room.turn.seat == selfSeat;
      if (mine && canRoll) {
        text = l10n.playTurnYourRoll;
        highlight = true;
      } else if (mine && canPick) {
        text = l10n.playTurnPickToken;
        highlight = true;
      } else if (mine) {
        text = l10n.playTurnYours;
      } else if (current != null) {
        // Same wording for every opponent: bots are never distinguishable.
        text = l10n.playTurnOther(PlayText.playerName(l10n, current));
      }
    }
    return SizedBox(
      height: 40,
      child: Center(
        child: AnimatedSwitcher(
          duration: reduce ? Duration.zero : AppDurations.fast,
          child: text == null
              ? const SizedBox.shrink()
              : Semantics(
                  key: ValueKey(text),
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: context.textTheme.labelLarge?.copyWith(
                        color: highlight ? c.brand : c.textSecondary,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
