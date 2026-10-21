import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/analytics/analytics_providers.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/realtime_providers.dart';
import 'package:ludo_royale/core/settings/app_settings.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/core/telemetry/telemetry_reporter.dart';
import 'package:ludo_royale/core/time/server_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/fixtures.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  int hashOf(String canonical) => StateHash.fnv1a32(canonical);

  /// Test rig: connection + controller + recorders.
  ({
    Harness h,
    ProviderContainer c,
    RecordingAnalytics analytics,
    TelemetryReporter telemetry,
    List<RoomEvent> events,
    void Function(Duration) advanceClock,
  })
  rig(FakeAsync async) {
    var now = DateTime(2026, 10, 21, 12);
    final h = Harness(now: () => now);
    final analytics = RecordingAnalytics();
    final telemetry = TelemetryReporter(post: (_) async {});
    final c = ProviderContainer(
      overrides: [
        realtimeConnectionProvider.overrideWithValue(h.connection),
        analyticsServiceProvider.overrideWithValue(analytics),
        telemetryReporterProvider.overrideWithValue(telemetry),
        clockProvider.overrideWithValue(() => now),
        preferencesStoreProvider.overrideWithValue(PreferencesStore(prefs)),
      ],
    );
    final events = <RoomEvent>[];
    c.read(activeRoomControllerProvider);
    c.read(activeRoomControllerProvider.notifier).events.listen(events.add);
    return (
      h: h,
      c: c,
      analytics: analytics,
      telemetry: telemetry,
      events: events,
      advanceClock: (d) => now = now.add(d),
    );
  }

  FakeSocket open(Harness h, FakeAsync async, {String? activeRoomId}) {
    h.connection.start();
    async.flushMicrotasks();
    final s = h.connector.last;
    s.ready(activeRoomId: activeRoomId);
    async.flushMicrotasks();
    return s;
  }

  /// Answers the last `game.request_sync` with [room].
  void answerSync(FakeSocket s, FakeAsync async, Map<String, dynamic> room) {
    final req = s.sentOfType('game.request_sync').last;
    s.serverSend('game.state', {'room': room}, req['id'] as String);
    async.flushMicrotasks();
  }

  ActiveRoomState stateOf(ProviderContainer c) =>
      c.read(activeRoomControllerProvider);

  ActiveRoomController ctl(ProviderContainer c) =>
      c.read(activeRoomControllerProvider.notifier);

  test('connection.ready with activeRoomId requests a sync', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async, activeRoomId: 'r_1');
      final req = s.sentOfType('game.request_sync').single;
      expect(req['p'], {'roomId': 'r_1'});
      expect(stateOf(r.c).syncing, isTrue);

      answerSync(s, async, ludoRoomJson(turnSeat: 0));
      final st = stateOf(r.c);
      expect(st.room!.id, 'r_1');
      expect(st.selfUid, 'u_0');
      expect(st.selfSeat, 0);
      expect(st.syncing, isFalse);
      expect(st.isMyTurn, isTrue);
      expect(st.canRoll, isTrue);
      expect(r.events.single, isA<RoomSnapshotApplied>());
      r.c.dispose();
    });
  });

  test('applies deltas in order and emits them for animation', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.state', {'room': ludoRoomJson(v: 40)});
      s.serverSend('game.dice_result', {
        'roomId': 'r_1',
        'v': 41,
        'h': hashOf('L|8|1|-1,-1,5,56;0,-1,-1,-1'),
        'seat': 1,
        'value': 3,
        'turnSeq': 8,
        'phase': 'awaiting_move',
        'legal': [0],
      });
      s.serverSend('game.move_applied', {
        'roomId': 'r_1',
        'v': 42,
        'h': hashOf('L|8|1|-1,-1,5,56;3,-1,-1,-1'),
        'seat': 1,
        'token': 0,
        'from': 0,
        'to': 3,
      });
      s.serverSend('game.turn_changed', {
        'roomId': 'r_1',
        'v': 43,
        'h': hashOf('L|9|0|-1,-1,5,56;3,-1,-1,-1'),
        'seat': 0,
        'turnSeq': 9,
        'phase': 'awaiting_roll',
      });
      async.flushMicrotasks();
      final deltas = r.events.whereType<RoomDeltaApplied>().toList();
      expect(deltas.map((e) => e.delta.runtimeType), [
        DiceResultEvent,
        MoveAppliedEvent,
        TurnChangedEvent,
      ]);
      expect(deltas.every((d) => d.verified), isTrue);
      expect(deltas[1].previous.board.ludoTokens![1][0], 0);
      expect(deltas[1].room.board.ludoTokens![1][0], 3);
      expect(stateOf(r.c).room!.v, 43);
      expect(s.sentOfType('game.request_sync'), isEmpty);
      r.c.dispose();
    });
  });

  test('gaps request one (coalesced) sync', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.state', {'room': ludoRoomJson(v: 40)});
      s.serverSend('player.connected', {'roomId': 'r_1', 'v': 43, 'seat': 0});
      s.serverSend('player.connected', {'roomId': 'r_1', 'v': 44, 'seat': 0});
      async.flushMicrotasks();
      expect(s.sentOfType('game.request_sync'), hasLength(1));
      expect(stateOf(r.c).room!.v, 40);
      answerSync(s, async, ludoRoomJson(v: 44));
      expect(stateOf(r.c).room!.v, 44);
      expect(stateOf(r.c).syncing, isFalse);
      r.c.dispose();
    });
  });

  test('hash mismatch → sync, telemetry, unverified delta event', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.state', {'room': ludoRoomJson(v: 40)});
      s.serverSend('game.turn_changed', {
        'roomId': 'r_1',
        'v': 41,
        'h': 1,
        'seat': 0,
        'turnSeq': 8,
        'phase': 'awaiting_roll',
      });
      async.flushMicrotasks();
      expect(s.sentOfType('game.request_sync'), hasLength(1));
      expect(r.telemetry.pending[TelemetryKind.hashMismatch], 1);
      final d = r.events.whereType<RoomDeltaApplied>().single;
      expect(d.verified, isFalse);
      r.c.dispose();
    });
  });

  test('a delta with no room held requests a sync for that room', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('player.connected', {'roomId': 'r_9', 'v': 5, 'seat': 0});
      async.flushMicrotasks();
      expect(s.sentOfType('game.request_sync').single['p'], {'roomId': 'r_9'});
      r.c.dispose();
    });
  });

  test('rollDice echoes turnSeq and blocks double taps', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.state', {'room': ludoRoomJson(turnSeat: 0)});
      async.flushMicrotasks();

      bool? first;
      bool? second;
      ctl(r.c).rollDice().then((v) => first = v);
      ctl(r.c).rollDice().then((v) => second = v);
      async.flushMicrotasks();
      final rolls = s.sentOfType('game.roll_dice');
      expect(rolls, hasLength(1));
      expect(rolls.single['p'], {'roomId': 'r_1', 'turnSeq': 7});
      expect(stateOf(r.c).rollInFlight, isTrue);
      expect(stateOf(r.c).canRoll, isFalse);
      expect(second, isFalse);

      s.serverSend('game.dice_result', {
        'roomId': 'r_1',
        'v': 41,
        'seat': 0,
        'value': 6,
        'turnSeq': 8,
        'phase': 'awaiting_move',
        'legal': [2, 3],
      }, rolls.single['id'] as String);
      async.flushMicrotasks();
      expect(first, isTrue);
      expect(stateOf(r.c).rollInFlight, isFalse);
      expect(stateOf(r.c).canMove, isTrue);

      ctl(r.c).makeMove(2).ignore();
      async.flushMicrotasks();
      expect(s.sentOfType('game.make_move').single['p'], {
        'roomId': 'r_1',
        'turnSeq': 8,
        'token': 2,
      });
      r.c.dispose();
    });
  });

  test('command errors surface the code and lastErrorCode', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.state', {'room': ludoRoomJson(turnSeat: 0)});
      async.flushMicrotasks();
      Object? error;
      ctl(r.c).rollDice().catchError((Object e) {
        error = e;
        return false;
      });
      async.flushMicrotasks();
      s.serverSend('error', {
        'code': 'stale_state',
        'msg': '',
        'retry': false,
      }, s.sentOfType('game.roll_dice').single['id'] as String);
      async.flushMicrotasks();
      expect((error! as RealtimeCommandException).code, 'stale_state');
      expect(stateOf(r.c).lastErrorCode, 'stale_state');
      expect(stateOf(r.c).rollInFlight, isFalse);
      ctl(r.c).clearError();
      expect(stateOf(r.c).lastErrorCode, isNull);
      r.c.dispose();
    });
  });

  test('a Store emote carries its art to EmoteReceived; sending one sends '
      'its em_ id', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.state', {'room': ludoRoomJson()});
      async.flushMicrotasks();
      s.serverSend('chat.emote', {
        'roomId': 'r_1',
        'seat': 1,
        'emote': 'em_angry',
        'asset': {'path': 'emotes/angry.json', 'format': 'lottie'},
      });
      async.flushMicrotasks();
      final got = r.events.whereType<EmoteReceived>().single.emote;
      expect(got.emote, 'em_angry');
      expect(
        got.asset,
        const EmoteAsset(format: 'lottie', path: 'emotes/angry.json'),
      );

      ctl(r.c).sendEmote('em_angry').ignore();
      async.flushMicrotasks();
      final sent = s.sentOfType('chat.emote').single;
      expect(sent['p'], {'roomId': 'r_1', 'emote': 'em_angry'});
      s.serverSend('ack', {}, sent['id'] as String);
      async.flushMicrotasks();
      r.c.dispose();
    });
  });

  test('commands without a room throw not_in_room', () {
    fakeAsync((async) {
      final r = rig(async);
      open(r.h, async);
      Object? error;
      ctl(r.c).sendQuickChat('gg').catchError((Object e) => error = e);
      async.flushMicrotasks();
      expect((error! as RealtimeCommandException).code, 'not_in_room');
      r.c.dispose();
    });
  });

  test('quick chat and emotes honour the mute setting', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.state', {'room': ludoRoomJson()});
      async.flushMicrotasks();
      r.c
          .read(settingsControllerProvider.notifier)
          .set(SettingKey.quickChatMute, true);
      async.flushMicrotasks();
      s.serverSend('chat.quick', {'roomId': 'r_1', 'seat': 1, 'msg': 'gg'});
      s.serverSend('chat.emote', {
        'roomId': 'r_1',
        'seat': 1,
        'emote': 'emote_wave',
      });
      s.serverSend('chat.quick', {'roomId': 'r_1', 'seat': 0, 'msg': 'thanks'});
      s.serverSend('chat.quick', {'roomId': 'r_x', 'seat': 0, 'msg': 'oops'});
      async.flushMicrotasks();
      final chats = r.events.whereType<QuickChatReceived>().toList();
      expect(chats.single.chat.msg, 'thanks');
      expect(chats.single.fromSelf, isTrue);
      expect(r.events.whereType<EmoteReceived>(), isEmpty);

      r.c
          .read(settingsControllerProvider.notifier)
          .set(SettingKey.quickChatMute, false);
      async.flushMicrotasks();
      s.serverSend('chat.emote', {
        'roomId': 'r_1',
        'seat': 1,
        'emote': 'emote_wave',
      });
      async.flushMicrotasks();
      expect(r.events.whereType<EmoteReceived>().single.fromSelf, isFalse);
      r.c.dispose();
    });
  });

  test('matchmaking → game started → finished (analytics deduped)', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      ctl(r.c).joinMatchmaking(game: 'ludo', capacity: 2).ignore();
      async.flushMicrotasks();
      final join = s.sentOfType('matchmaking.join').single;
      expect(join['p'], {'game': 'ludo', 'variant': 'classic', 'capacity': 2});
      s.serverSend('matchmaking.status', {
        'status': 'searching',
        'game': 'ludo',
        'variant': 'classic',
        'capacity': 2,
        'roomId': 'r_1',
      });
      s.serverSend('room.updated', {
        'room': ludoRoomJson(status: 'lobby', bots: const [false, true]),
        'reason': 'joined',
      }, join['id'] as String);
      async.flushMicrotasks();
      expect(r.analytics.count('matchmakingStarted'), 1);
      expect(stateOf(r.c).isSearching, isTrue);

      s.serverSend('game.started', {
        'room': ludoRoomJson(v: 41, bots: const [false, true]),
      });
      // A resync snapshot of the same round must not count again.
      s.serverSend('game.state', {
        'room': ludoRoomJson(v: 41, bots: const [false, true]),
      });
      async.flushMicrotasks();
      expect(r.analytics.count('gameStarted'), 1);
      expect(r.analytics.count('matchmakingSucceeded'), 1);
      expect(stateOf(r.c).isSearching, isFalse);
      final ctx =
          r.analytics.args['gameStarted']!.first as AnalyticsGameContext;
      expect(ctx.opponentMix, OpponentMix.botOnly);
      expect(ctx.matchType, AnalyticsMatchType.public);
      expect(ctx.seatCount, 2);
      expect(ctx.dedupeKey, 'r_1#1');

      r.advanceClock(const Duration(minutes: 4));
      s.serverSend('game.finished', {
        'roomId': 'r_1',
        'v': 42,
        'result': {
          'winnerSeat': 0,
          'reason': 'completed',
          'placements': [0, 1],
          'payout': 0,
        },
        'rematch': {'open': true, 'deadline': 1, 'accepted': <int>[]},
      });
      s.serverSend('game.state', {
        'room': {
          ...ludoRoomJson(v: 42, status: 'finished', bots: const [false, true]),
          'result': {'winnerSeat': 0},
        },
      });
      async.flushMicrotasks();
      expect(r.analytics.count('gameCompleted'), 1);
      final args = r.analytics.args['gameCompleted']!;
      expect(args[1], GameOutcome.win);
      expect(args[2], const Duration(minutes: 4));
      r.c.dispose();
    });
  });

  test('leaving a running game reports abandoned and clears the room', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.started', {'room': ludoRoomJson(mode: 'private')});
      async.flushMicrotasks();
      ctl(r.c).leaveRoom().ignore();
      async.flushMicrotasks();
      final leave = s.sentOfType('room.leave').single;
      expect(leave['p'], {'roomId': 'r_1'});
      s.serverSend('ack', {}, leave['id'] as String);
      async.flushMicrotasks();
      expect(r.analytics.count('gameAbandoned'), 1);
      expect(stateOf(r.c).room, isNull);
      final cleared = r.events.whereType<RoomCleared>().single;
      expect(cleared.reason, RoomClearReason.left);
      // A late finish for the abandoned round is not reported as completed.
      expect(r.analytics.count('gameCompleted'), 0);
      r.c.dispose();
    });
  });

  test('join failure reports the error code', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      Object? error;
      ctl(r.c).joinRoom('k7q2mx').catchError((Object e) {
        error = e;
        return null;
      });
      async.flushMicrotasks();
      final join = s.sentOfType('room.join').single;
      expect(join['p'], {'code': 'K7Q2MX'});
      s.serverSend('error', {
        'code': 'invalid_code',
        'msg': '',
        'retry': false,
      }, join['id'] as String);
      async.flushMicrotasks();
      expect((error! as RealtimeCommandException).code, 'invalid_code');
      expect(r.analytics.calls, contains('privateRoomJoinFailed'));
      expect(r.analytics.args['privateRoomJoinFailed'], ['invalid_code']);
      r.c.dispose();
    });
  });

  test('createRoom resolves with the created room', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      RoomSnapshot? created;
      ctl(r.c)
          .createRoom(game: 'snakes_ladders', capacity: 3)
          .then((room) => created = room);
      async.flushMicrotasks();
      final req = s.sentOfType('room.create').single;
      final room = ludoRoomJson(status: 'lobby', mode: 'private')
        ..['code'] = 'K7Q2MX';
      s.serverSend('room.updated', {
        'room': room,
        'reason': 'created',
      }, req['id'] as String);
      async.flushMicrotasks();
      expect(created!.code, 'K7Q2MX');
      expect(stateOf(r.c).room!.code, 'K7Q2MX');
      expect(r.analytics.count('privateRoomCreated'), 1);
      final applied = r.events.whereType<RoomSnapshotApplied>().single;
      expect(applied.reason, 'created');
      r.c.dispose();
    });
  });

  test('closed rooms and lost seats clear the room', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('room.updated', {
        'room': ludoRoomJson(status: 'lobby', mode: 'practice'),
      });
      s.serverSend('room.updated', {
        'room': ludoRoomJson(v: 41, status: 'closed', mode: 'practice'),
      });
      async.flushMicrotasks();
      expect(stateOf(r.c).room, isNull);
      expect(
        r.events.whereType<RoomCleared>().single.reason,
        RoomClearReason.closed,
      );

      // A snapshot that no longer seats the user.
      s.serverSend('room.updated', {'room': ludoRoomJson(v: 3)});
      final without = ludoRoomJson(v: 4);
      (without['players'] as List).removeAt(0);
      s.serverSend('room.updated', {'room': without, 'reason': 'left'});
      async.flushMicrotasks();
      expect(stateOf(r.c).room, isNull);
      expect(
        r.events.whereType<RoomCleared>().last.reason,
        RoomClearReason.left,
      );
      r.c.dispose();
    });
  });

  test('sync answered with not_in_room clears the room', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.state', {'room': ludoRoomJson(v: 40)});
      s.serverSend('player.connected', {'roomId': 'r_1', 'v': 50, 'seat': 0});
      async.flushMicrotasks();
      final req = s.sentOfType('game.request_sync').single;
      s.serverSend('error', {
        'code': 'not_in_room',
        'msg': '',
        'retry': false,
      }, req['id'] as String);
      async.flushMicrotasks();
      expect(stateOf(r.c).room, isNull);
      expect(
        r.events.whereType<RoomCleared>().single.reason,
        RoomClearReason.notInRoom,
      );
      r.c.dispose();
    });
  });

  test('reconnecting with a room held resynchronises it', () {
    fakeAsync((async) {
      final r = rig(async);
      final s1 = open(r.h, async);
      s1.serverSend('game.state', {'room': ludoRoomJson(v: 40)});
      async.flushMicrotasks();
      s1.serverClose(1001);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 500));
      final s2 = r.h.connector.last;
      s2.ready();
      async.flushMicrotasks();
      expect(s2.sentOfType('game.request_sync').single['p'], {'roomId': 'r_1'});
      r.c.dispose();
    });
  });

  test('buffer overflow resync triggers game.request_sync', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      s.serverSend('game.state', {'room': ludoRoomJson(v: 40)});
      async.flushMicrotasks();
      // Simulate the connection's synthetic overflow signal.
      s.serverSend(ServerMessageTypes.localResyncRequired);
      async.flushMicrotasks();
      expect(s.sentOfType('game.request_sync'), hasLength(1));
      r.c.dispose();
    });
  });

  test('rematch accept reports requested vs accepted', () {
    fakeAsync((async) {
      final r = rig(async);
      final s = open(r.h, async);
      final finished = ludoRoomJson(status: 'finished', mode: 'private')
        ..['rematch'] = {
          'open': true,
          'deadline': 1,
          'accepted': <int>[1],
        };
      s.serverSend('game.state', {'room': finished});
      async.flushMicrotasks();
      ctl(r.c).rematch(accept: true).ignore();
      async.flushMicrotasks();
      final req = s.sentOfType('game.rematch').single;
      expect(req['p'], {'roomId': 'r_1', 'accept': true});
      s.serverSend('ack', {}, req['id'] as String);
      async.flushMicrotasks();
      expect(r.analytics.count('rematchAccepted'), 1);
      expect(r.analytics.count('rematchRequested'), 0);
      r.c.dispose();
    });
  });
}
