import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/core/analytics/analytics_providers.dart';
import 'package:ludo_royale/core/analytics/noop_analytics_service.dart';
import 'package:ludo_royale/core/assets/profile_picture_cache.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/audio_haptics/reduced_motion.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/realtime_providers.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/core/theme/app_theme.dart';
import 'package:ludo_royale/core/time/server_clock.dart';
import 'package:ludo_royale/features/game/application/owned_emotes.dart';
import 'package:ludo_royale/features/game/application/viewer_loadout.dart';
import 'package:ludo_royale/features/home/application/play_options.dart';
import 'package:ludo_royale/features/private_rooms/application/room_share.dart';
import 'package:ludo_royale/features/private_rooms/application/rooms_repository.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/picture_fixtures.dart';

/// Fixed "now" for server-clock based widgets (deadlines are relative).
final DateTime kTestNow = DateTime(2026, 10, 21, 12);
int get kNowMs => kTestNow.millisecondsSinceEpoch;

// ---------------------------------------------------------------- builders

RoomPlayer player(
  int seat, {
  String? uid,
  String? name,
  bool bot = false,
  bool connected = true,
  bool forfeited = false,
  int strikes = 0,
  String? color,
  String frame = 'frame_none',
  int level = 4,
}) => RoomPlayer(
  seat: seat,
  uid: uid ?? 'u_$seat',
  name: name ?? 'Player$seat',
  avatar: seat,
  level: level,
  cosmetics: PlayerCosmetics(frame: frame),
  color: color ?? _colorFor(seat),
  connected: connected,
  bot: bot,
  forfeited: forfeited,
  strikes: strikes,
);

String _colorFor(int seat) => const ['red', 'green', 'yellow', 'blue'][seat];

/// A Ludo room. [players] defaults to 4 humans; seat 0 is `u_0` (the local
/// user in most tests).
RoomSnapshot ludoRoom({
  String id = 'r_1',
  int v = 10,
  List<RoomPlayer>? players,
  int turnSeat = 0,
  String phase = TurnPhases.awaitingRoll,
  int turnSeq = 5,
  int dice = 0,
  List<int> legal = const [],
  String status = RoomStatuses.playing,
  String mode = RoomModes.public,
  String variant = GameVariants.classic,
  List<List<int>>? tokens,
  int round = 1,
  RoomResult? result,
  RematchState? rematch,
  int hostSeat = -1,
  bool allowBots = false,
  String? code,
  int capacity = 4,
  int fillDeadline = 0,
  int? deadline,
}) {
  final ps = players ?? [for (var s = 0; s < 4; s++) player(s)];
  final perPlayer = variant == GameVariants.quick ? 2 : 4;
  return RoomSnapshot(
    id: id,
    v: v,
    game: GameIds.ludo,
    variant: variant,
    mode: mode,
    allowBots: allowBots,
    code: code,
    capacity: capacity,
    status: status,
    hostSeat: hostSeat,
    entryFee: 100000,
    pot: 100000 * ps.length,
    round: round,
    fillDeadline: fillDeadline,
    players: ps,
    turn: TurnState(
      seat: turnSeat,
      phase: status == RoomStatuses.finished ? TurnPhases.finished : phase,
      turnSeq: turnSeq,
      deadline: deadline ?? kNowMs + 20000,
      dice: dice,
      legal: legal,
    ),
    board: BoardState(
      ludoTokens:
          tokens ??
          [for (var s = 0; s < ps.length; s++) List<int>.filled(perPlayer, -1)],
    ),
    result: result,
    rematch: rematch,
  );
}

RoomSnapshot snakesRoom({
  String id = 'r_s',
  int v = 10,
  List<RoomPlayer>? players,
  int turnSeat = 0,
  int turnSeq = 5,
  List<int>? positions,
  String status = RoomStatuses.playing,
  String mode = RoomModes.public,
}) {
  final ps = players ?? [for (var s = 0; s < 4; s++) player(s)];
  return RoomSnapshot(
    id: id,
    v: v,
    game: GameIds.snakesLadders,
    mode: mode,
    capacity: ps.length,
    status: status,
    entryFee: 50000,
    players: ps,
    turn: TurnState(
      seat: turnSeat,
      phase: TurnPhases.awaitingRoll,
      turnSeq: turnSeq,
      deadline: kNowMs + 20000,
    ),
    board: BoardState(
      snakesPositions: positions ?? [for (var s = 0; s < ps.length; s++) 0],
    ),
  );
}

// ------------------------------------------------------------- controller

/// Stand-in for the core `ActiveRoomController`: no socket; tests push
/// snapshots / deltas exactly like the core (state first, then the event).
class FakeRoomController extends ActiveRoomController {
  FakeRoomController(this._initial);

  final ActiveRoomState _initial;
  final StreamController<RoomEvent> _events =
      StreamController<RoomEvent>.broadcast(sync: true);
  final List<String> calls = [];

  /// When set, `rollDice` / `makeMove` wait for it (command in flight).
  Completer<void>? commandGate;

  /// Next command throws this code.
  String? nextErrorCode;

  /// Returned by createRoom / joinRoom / startPractice.
  RoomSnapshot? replyRoom;

  @override
  ActiveRoomState build() {
    ref.onDispose(_events.close);
    return _initial;
  }

  @override
  Stream<RoomEvent> get events => _events.stream;

  void emit(RoomEvent e) => _events.add(e);

  void pushSnapshot(RoomSnapshot room, {String? reason, bool game = false}) {
    final previous = state.room;
    state = state.copyWith(room: room);
    emit(
      RoomSnapshotApplied(
        room: room,
        source: game
            ? GameStartedEvent(room: room)
            : RoomUpdatedEvent(room: room, reason: reason),
        previous: previous,
      ),
    );
  }

  void pushDelta(RoomDeltaEvent delta, RoomSnapshot room) {
    final previous = state.room!;
    state = state.copyWith(room: room);
    emit(RoomDeltaApplied(delta: delta, room: room, previous: previous));
  }

  void clearRoom(RoomClearReason reason) {
    final id = state.room?.id;
    state = state.copyWith(room: null);
    emit(RoomCleared(reason: reason, roomId: id));
  }

  Future<void> _maybeFail() async {
    final code = nextErrorCode;
    if (code != null) {
      nextErrorCode = null;
      throw RealtimeCommandException(code);
    }
  }

  @override
  Future<bool> rollDice() async {
    if (state.rollInFlight || state.moveInFlight) return false;
    calls.add('roll:${state.room?.turn.turnSeq}');
    state = state.copyWith(rollInFlight: true);
    try {
      await commandGate?.future;
      await _maybeFail();
      return true;
    } finally {
      state = state.copyWith(rollInFlight: false);
    }
  }

  @override
  Future<bool> makeMove(int token) async {
    if (state.rollInFlight || state.moveInFlight) return false;
    calls.add('move:$token:${state.room?.turn.turnSeq}');
    state = state.copyWith(moveInFlight: true);
    try {
      await commandGate?.future;
      await _maybeFail();
      return true;
    } finally {
      state = state.copyWith(moveInFlight: false);
    }
  }

  @override
  Future<void> joinMatchmaking({
    required String game,
    String variant = GameVariants.classic,
    required int capacity,
  }) async {
    calls.add('matchmaking.join:$game:$variant:$capacity');
    await _maybeFail();
  }

  @override
  Future<void> cancelMatchmaking() async {
    calls.add('matchmaking.cancel');
    await _maybeFail();
  }

  @override
  Future<RoomSnapshot?> createRoom({
    required String game,
    String variant = GameVariants.classic,
    required int capacity,
  }) async {
    calls.add('room.create:$game:$variant:$capacity');
    await _maybeFail();
    return _reply('created');
  }

  @override
  Future<RoomSnapshot?> joinRoom(String code) async {
    calls.add('room.join:$code');
    await _maybeFail();
    return _reply('joined');
  }

  /// Like the core: the reply snapshot is applied (and emitted) before the
  /// command future completes.
  RoomSnapshot? _reply(String reason) {
    final room = replyRoom;
    if (room != null) pushSnapshot(room, reason: reason);
    return room;
  }

  @override
  Future<void> leaveRoom() async {
    calls.add('room.leave');
    final id = state.room?.id;
    state = state.copyWith(room: null);
    emit(RoomCleared(reason: RoomClearReason.left, roomId: id));
  }

  @override
  Future<RoomSnapshot?> startPractice({
    required String game,
    String variant = GameVariants.classic,
    required int bots,
  }) async {
    calls.add('practice.start:$game:$variant:$bots');
    await _maybeFail();
    return _reply('created');
  }

  @override
  Future<void> allowBots(bool allow) async =>
      calls.add('room.allow_bots:$allow');

  @override
  Future<void> addBot() async => calls.add('room.add_bot');

  @override
  Future<void> removeBot(int seat) async => calls.add('room.remove_bot:$seat');

  @override
  Future<void> invite(String friendUid) async => calls.add('room.invite');

  @override
  Future<void> startGame() async => calls.add('game.start');

  @override
  Future<void> requestSync({String? roomId}) async =>
      calls.add('game.request_sync');

  @override
  Future<void> rematch({required bool accept}) async =>
      calls.add('game.rematch:$accept');

  @override
  Future<void> sendQuickChat(String msgId) async =>
      calls.add('chat.quick:$msgId');

  @override
  Future<void> sendEmote(String emoteId) async =>
      calls.add('chat.emote:$emoteId');
}

/// Records analytics calls.
class RecordingPlayAnalytics extends NoopAnalyticsService {
  final List<String> events = [];

  @override
  void gameResultViewed(AnalyticsGameContext game) => events.add(
    'game_result_viewed:${game.gameType.param}:${game.matchType.param}:'
    '${game.opponentMix.param}',
  );

  @override
  void playerReported(String reason) => events.add('player_reported:$reason');

  @override
  void friendRequestSent(String source) =>
      events.add('friend_request_sent:$source');
}

class FakeRoomsRepository implements RoomsRepository {
  RoomPreview? previewResult;
  Object? previewError;
  List<FriendSummary> friendList = const [];
  final List<String> lookups = [];

  @override
  Future<RoomPreview> preview(String code) async {
    lookups.add(code);
    final e = previewError;
    if (e != null) throw e;
    return previewResult!;
  }

  @override
  Future<List<FriendSummary>> friends() async => friendList;
}

// ----------------------------------------------------------------- harness

class PlayHarness {
  PlayHarness({required ActiveRoomState initial})
    : controller = FakeRoomController(initial);

  final FakeRoomController controller;
  final RecordingPlayAnalytics analytics = RecordingPlayAnalytics();
  final SilentAudioService audio = SilentAudioService();
  final FakeRoomsRepository rooms = FakeRoomsRepository();
  final StreamController<WalletUpdatedEvent> wallet =
      StreamController<WalletUpdatedEvent>.broadcast();
  final StreamController<ProgressionUpdatedEvent> progression =
      StreamController<ProgressionUpdatedEvent>.broadcast();
  final StreamController<ServerEvent> social =
      StreamController<ServerEvent>.broadcast();
  final List<String> shared = [];
  final FakeProfilePictureCache emotes = FakeProfilePictureCache();
  late ProviderContainer container;

  Future<List<Override>> overrides() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesStore(await SharedPreferences.getInstance());
    return [
      activeRoomControllerProvider.overrideWith(() => controller),
      preferencesStoreProvider.overrideWithValue(prefs),
      analyticsServiceProvider.overrideWithValue(analytics),
      audioServiceProvider.overrideWithValue(audio),
      clockProvider.overrideWithValue(() => kTestNow),
      serverClockProvider.overrideWithValue(ServerClock(() => kTestNow)),
      walletUpdatesProvider.overrideWith((ref) => wallet.stream),
      progressionUpdatesProvider.overrideWith((ref) => progression.stream),
      socialEventsProvider.overrideWith((ref) => social.stream),
      ownedEmotesProvider.overrideWith((ref) async => kStarterOwnedEmotes),
      // Store emote art: none resolves unless a test adds it to `ready`.
      emoteAssetCacheProvider.overrideWithValue(emotes),
      viewerBoardThemesProvider.overrideWithValue((ludo: null, snakes: null)),
      roomsRepositoryProvider.overrideWithValue(rooms),
      roomShareProvider.overrideWithValue((text, {subject, origin}) async {
        shared.add(text);
      }),
      entryFeeProvider.overrideWith(
        (ref, game) => game == GameIds.snakesLadders ? 50000 : 100000,
      ),
    ];
  }

  /// Pumps [screen] at '/' inside a GoRouter with stub destinations, in the
  /// real theme + localizations, with reduced motion (deterministic).
  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
    Size size = const Size(360, 740),
    bool connected = true,
    double textScale = 1.0,
    List<Override> extra = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final o = await overrides();
    addTearDown(() async {
      await wallet.close();
      await progression.close();
      await social.close();
    });

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => screen),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/game/:roomId',
          builder: (_, s) =>
              Scaffold(body: Text('GAME ${s.pathParameters['roomId']}')),
        ),
        GoRoute(
          path: '/rooms/:id/lobby',
          builder: (_, s) =>
              Scaffold(body: Text('LOBBY ${s.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/rooms/join',
          builder: (_, s) =>
              Scaffold(body: Text('JOIN ${s.uri.queryParameters['code']}')),
        ),
        GoRoute(
          path: '/matchmaking',
          builder: (_, s) => Scaffold(body: Text('MATCHMAKING ${s.uri}')),
        ),
        GoRoute(
          path: '/practice',
          builder: (_, s) => Scaffold(body: Text('PRACTICE ${s.uri}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    // The scope owns the container, so it is disposed together with the
    // widget tree (tickers never outlive it).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...o.where((a) => !extra.any((b) => identical(a.origin, b.origin))),
          ...extra,
          realtimeStatusProvider.overrideWith(
            () => _FixedStatus(
              connected
                  ? RealtimeStatus.connected
                  : RealtimeStatus.reconnecting,
            ),
          ),
        ],
        retry: (_, _) => null,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: ReducedMotionScope(child: child ?? const SizedBox()),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _FixedStatus extends RealtimeStatusController {
  _FixedStatus(this._initial);

  final RealtimeStatus _initial;

  @override
  RealtimeStatus build() => _initial;
}

/// Lets microtasks and zero-delay timers run inside a widget test.
Future<void> flush(WidgetTester tester, [int frames = 4]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Fails on any layout overflow reported during [body].
Future<void> expectNoOverflow(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  final overflow = errors
      .where((e) => e.exceptionAsString().contains('overflowed'))
      .toList();
  expect(
    overflow,
    isEmpty,
    reason: overflow.map((e) => e.exceptionAsString()).join('\n'),
  );
  for (final e in errors) {
    FlutterError.reportError(e);
  }
}

/// Scrolls the first scrollable until [finder] is built and visible.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}
