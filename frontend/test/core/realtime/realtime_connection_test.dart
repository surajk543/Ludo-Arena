import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/app_policy/policy_signal.dart';
import 'package:ludo_arena/core/network/api_exception.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/core/realtime/realtime_connection.dart';
import 'package:ludo_arena/core/realtime/realtime_status.dart';
import 'package:ludo_arena/core/telemetry/telemetry_reporter.dart';

import 'fakes.dart';

void main() {
  /// Starts the connection and completes the handshake + connection.ready.
  FakeSocket connect(Harness h, FakeAsync async, {String? activeRoomId}) {
    h.connection.start();
    async.flushMicrotasks();
    final s = h.connector.last;
    s.ready(activeRoomId: activeRoomId, serverTime: 1761022800000);
    async.flushMicrotasks();
    return s;
  }

  group('handshake', () {
    test('sends auth + app headers and becomes connected', () {
      fakeAsync((async) {
        final h = Harness();
        connect(h, async);
        final call = h.connector.calls.single;
        expect(call.uri.toString(), 'ws://localhost:8080/api/v1/ws');
        expect(call.headers['Authorization'], 'Bearer tok1');
        expect(call.headers['X-App-Platform'], 'android');
        expect(call.headers['X-App-Version'], '1.0.0');
        expect(call.headers['X-App-Build'], '1');
        expect(call.headers.containsKey('X-Reconnect'), isFalse);
        expect(h.statuses, [
          RealtimeStatus.connecting,
          RealtimeStatus.connected,
        ]);
        expect(h.connection.isConnected, isTrue);
        expect(h.connection.lastReady!.uid, 'u_0');
        expect(h.serverTimes, [1761022800000]);
      });
    });

    test('no session token → idle, no socket', () {
      fakeAsync((async) {
        final h = Harness()..token = null;
        h.connection.start();
        async.flushMicrotasks();
        expect(h.connector.calls, isEmpty);
        expect(h.status, RealtimeStatus.idle);
        expect(h.connection.haltReason, RealtimeHaltReason.sessionEnded);
      });
    });

    test('401 → refresh then retry with the new token', () {
      fakeAsync((async) {
        final h = Harness();
        h.connector.script.add(401);
        h.connection.start();
        async.flushMicrotasks();
        expect(h.refreshCalls, 1);
        expect(h.connector.calls, hasLength(2));
        expect(h.connector.calls[1].headers['Authorization'], 'Bearer tok2');
      });
    });

    test('401 with rejected refresh → stop (idle)', () {
      fakeAsync((async) {
        final h = Harness()..refreshResult = false;
        h.connector.script.add(401);
        h.connection.start();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 2));
        expect(h.connector.calls, hasLength(1));
        expect(h.status, RealtimeStatus.idle);
        expect(h.connection.haltReason, RealtimeHaltReason.sessionEnded);
      });
    });

    test('426 / 503 → policy signal and halt until start()', () {
      for (final entry in {
        426: PolicySignalReason.wsUpdateRequired,
        503: PolicySignalReason.wsMaintenance,
      }.entries) {
        fakeAsync((async) {
          final h = Harness();
          h.connector.script.add(entry.key);
          h.connection.start();
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 5));
          expect(h.policy, [entry.value]);
          expect(h.connector.calls, hasLength(1));
          expect(h.connection.haltReason, RealtimeHaltReason.policy);
          h.connection.start();
          async.flushMicrotasks();
          expect(h.connector.calls, hasLength(2));
        });
      }
    });

    test('400 → stop (client bug)', () {
      fakeAsync((async) {
        final h = Harness();
        h.connector.script.add(400);
        h.connection.start();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 5));
        expect(h.connector.calls, hasLength(1));
        expect(h.connection.haltReason, RealtimeHaltReason.badRequest);
      });
    });

    test('429 and network failures back off and retry', () {
      fakeAsync((async) {
        final h = Harness();
        h.connector.script.addAll([429, null]);
        h.connection.start();
        async.flushMicrotasks();
        expect(h.connector.calls, hasLength(1));
        expect(h.status, RealtimeStatus.reconnecting);
        async.elapse(const Duration(milliseconds: 500)); // attempt 0 ceiling
        expect(h.connector.calls, hasLength(2));
        // Network failure → policy re-check hint + backoff.
        expect(h.policy, [PolicySignalReason.wsHandshakeFailed]);
        async.elapse(const Duration(seconds: 1)); // attempt 1 ceiling
        expect(h.connector.calls, hasLength(3));
        h.connector.last.ready();
        async.flushMicrotasks();
        expect(h.status, RealtimeStatus.connected);
      });
    });

    test('ready timeout → reconnect', () {
      fakeAsync((async) {
        final h = Harness();
        h.connection.start();
        async.flushMicrotasks();
        expect(h.connector.calls, hasLength(1));
        async.elapse(const Duration(seconds: 10));
        expect(h.connector.sockets.first.closedByClient, isTrue);
        async.elapse(const Duration(milliseconds: 500));
        expect(h.connector.calls, hasLength(2));
      });
    });
  });

  group('commands', () {
    test('reply correlation by r; event emitted before completion', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        final order = <String>[];
        h.connection.events.listen((m) => order.add('event:${m.type}'));
        ServerMessage? reply;
        h.connection
            .send('game.roll_dice', {'roomId': 'r_1', 'turnSeq': 12})
            .then((m) {
              order.add('reply');
              reply = m;
            });
        async.flushMicrotasks();
        final sent = s.lastSent;
        expect(sent['t'], 'game.roll_dice');
        expect(sent['p'], {'roomId': 'r_1', 'turnSeq': 12});
        final id = sent['id'] as String;
        expect(id.length, inInclusiveRange(1, 64));

        s.serverSend('game.dice_result', {
          'roomId': 'r_1',
          'v': 41,
          'seat': 0,
          'value': 4,
          'turnSeq': 13,
          'phase': 'awaiting_roll',
        }, id);
        async.flushMicrotasks();
        expect(reply!.event, isA<DiceResultEvent>());
        expect(order, ['event:game.dice_result', 'reply']);
      });
    });

    test('ids are unique within and across connections', () {
      fakeAsync((async) {
        final h = Harness();
        final s1 = connect(h, async);
        for (var i = 0; i < 3; i++) {
          h.connection.send('chat.quick', {
            'roomId': 'r',
            'msg': 'gg',
          }).ignore();
        }
        async.flushMicrotasks();
        s1.serverClose(1001);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        final s2 = h.connector.last;
        expect(s2, isNot(same(s1)));
        s2.ready();
        async.flushMicrotasks();
        for (var i = 0; i < 3; i++) {
          h.connection.send('chat.quick', {
            'roomId': 'r',
            'msg': 'gg',
          }).ignore();
        }
        async.flushMicrotasks();
        final ids = [
          ...s1.sentOfType('chat.quick').map((m) => m['id']),
          ...s2.sentOfType('chat.quick').map((m) => m['id']),
        ];
        expect(ids.toSet(), hasLength(6));
        expect(h.connector.calls[1].headers['X-Reconnect'], '1');
      });
    });

    test('error reply throws RealtimeCommandException with the code', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        Object? error;
        h.connection
            .send('game.make_move', {'roomId': 'r', 'turnSeq': 1, 'token': 0})
            .catchError((Object e) {
              error = e;
              return ServerMessage.localResync;
            });
        async.flushMicrotasks();
        s.serverSend('error', {
          'code': 'not_your_turn',
          'msg': 'It is not your turn.',
          'retry': false,
        }, s.lastSent['id'] as String);
        async.flushMicrotasks();
        expect(error, isA<RealtimeCommandException>());
        expect((error! as RealtimeCommandException).code, 'not_your_turn');
      });
    });

    test('timeout', () {
      fakeAsync((async) {
        final h = Harness();
        connect(h, async);
        Object? error;
        h.connection
            .send('room.join', {
              'code': 'ABC',
            }, timeout: const Duration(seconds: 3))
            .catchError((Object e) {
              error = e;
              return ServerMessage.localResync;
            });
        async.elapse(const Duration(seconds: 3));
        expect((error! as RealtimeCommandException).code, 'timeout');
      });
    });

    test('not connected fails immediately; pending fail on drop', () {
      fakeAsync((async) {
        final h = Harness();
        Object? early;
        h.connection.send('ping.x', {}).catchError((Object e) {
          early = e;
          return ServerMessage.localResync;
        });
        async.flushMicrotasks();
        expect(
          (early! as RealtimeCommandException).code,
          ClientErrorCodes.notConnected,
        );

        final s = connect(h, async);
        Object? late;
        h.connection.send('room.leave', {'roomId': 'r'}).catchError((Object e) {
          late = e;
          return ServerMessage.localResync;
        });
        async.flushMicrotasks();
        s.serverClose(1001);
        async.flushMicrotasks();
        expect(
          (late! as RealtimeCommandException).code,
          ClientErrorCodes.notConnected,
        );
      });
    });

    test('ack dup completes the command', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        ServerMessage? reply;
        h.connection.send('room.leave', {'roomId': 'r'}).then((m) => reply = m);
        async.flushMicrotasks();
        s.serverSend('ack', {'dup': true}, s.lastSent['id'] as String);
        async.flushMicrotasks();
        expect((reply!.event as AckEvent).dup, isTrue);
      });
    });
  });

  group('close codes', () {
    for (final code in [1000, 1001, 1008, 4400, 4508, null]) {
      test('$code → reconnect with backoff (X-Reconnect)', () {
        fakeAsync((async) {
          final h = Harness();
          final s = connect(h, async);
          s.serverClose(code);
          async.flushMicrotasks();
          expect(h.status, RealtimeStatus.reconnecting);
          async.elapse(const Duration(milliseconds: 500));
          expect(h.connector.calls, hasLength(2));
          expect(h.connector.calls[1].headers['X-Reconnect'], '1');
          h.connector.last.ready();
          async.flushMicrotasks();
          expect(h.status, RealtimeStatus.connected);
          expect(h.telemetry, contains(TelemetryKind.reconnectSuccess));
        });
      });
    }

    test('4401 → refresh then reconnect immediately', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        s.serverClose(4401);
        async.flushMicrotasks();
        expect(h.refreshCalls, 1);
        expect(h.connector.calls, hasLength(2));
        expect(h.connector.calls[1].headers['Authorization'], 'Bearer tok2');
      });
    });

    test('4401 with rejected refresh → idle, no reconnect', () {
      fakeAsync((async) {
        final h = Harness()..refreshResult = false;
        final s = connect(h, async);
        s.serverClose(4401);
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(h.connector.calls, hasLength(1));
        expect(h.status, RealtimeStatus.idle);
      });
    });

    test('4409 → replaced, no auto reconnect; reconnectNow resumes', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        s.serverClose(4409);
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 5));
        expect(h.status, RealtimeStatus.replaced);
        expect(h.connector.calls, hasLength(1));
        expect(h.connection.haltReason, RealtimeHaltReason.replaced);
        h.connection.reconnectNow();
        async.flushMicrotasks();
        expect(h.connector.calls, hasLength(2));
      });
    });

    test('4426 / 4503 → policy signal, halt', () {
      for (final entry in {
        4426: PolicySignalReason.wsUpdateRequired,
        4503: PolicySignalReason.wsMaintenance,
      }.entries) {
        fakeAsync((async) {
          final h = Harness();
          final s = connect(h, async);
          s.serverClose(entry.key);
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 5));
          expect(h.policy, [entry.value]);
          expect(h.connector.calls, hasLength(1));
          expect(h.connection.haltReason, RealtimeHaltReason.policy);
        });
      }
    });

    test('4429 → waits at least 10 s', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        s.serverClose(4429);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 9900));
        expect(h.connector.calls, hasLength(1));
        async.elapse(const Duration(milliseconds: 200));
        expect(h.connector.calls, hasLength(2));
      });
    });

    test('stop() closes with 1000 and never reconnects', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        h.connection.stop();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 5));
        expect(s.clientCloseCode, 1000);
        expect(h.status, RealtimeStatus.idle);
        expect(h.connector.calls, hasLength(1));
      });
    });

    test('backoff delays grow but stay within the full-jitter bound', () {
      fakeAsync((async) {
        final h = Harness();
        h.connector.script.addAll([null, null, null, null]);
        h.connection.start();
        async.flushMicrotasks();
        // attempt n waits at most 0.5 s × 2^n after the previous failure.
        for (final ceilingMs in [500, 1000, 2000, 4000]) {
          final before = h.connector.calls.length;
          var waited = 0;
          while (h.connector.calls.length == before) {
            async.elapse(const Duration(milliseconds: 10));
            waited += 10;
            expect(waited, lessThanOrEqualTo(ceilingMs + 10));
          }
          expect(h.connector.calls.length, before + 1);
        }
        h.connector.last.ready();
        async.flushMicrotasks();
        expect(h.status, RealtimeStatus.connected);
        expect(h.telemetry, isEmpty); // never connected → not a "reconnect"
      });
    });
  });

  group('heartbeat', () {
    test('ping every 15 s; missing pong for 10 s → reconnect', () {
      fakeAsync((async) {
        var now = DateTime(2026, 10, 21);
        final h = Harness(now: () => now);
        final s = connect(h, async);
        async.elapse(const Duration(seconds: 15));
        expect(s.sentOfType('ping'), hasLength(1));
        expect(s.sentOfType('ping').single.containsKey('id'), isFalse);
        now = now.add(const Duration(milliseconds: 80));
        s.serverSend('pong', {'ts': 1761022900000});
        async.flushMicrotasks();
        expect(h.serverTimes.last, 1761022900000);
        expect(h.status, RealtimeStatus.connected);

        async.elapse(const Duration(seconds: 15));
        expect(s.sentOfType('ping'), hasLength(2));
        async.elapse(const Duration(seconds: 10));
        expect(s.closedByClient, isTrue);
        expect(h.status, RealtimeStatus.reconnecting);
        async.elapse(const Duration(milliseconds: 500));
        expect(h.connector.calls, hasLength(2));
      });
    });
  });

  group('lifecycle', () {
    test('backgrounded: no reconnect attempts; resume reconnects at once', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        h.lifecycle.emit(AppLifecycleState.paused);
        s.serverClose(1006);
        async.flushMicrotasks();
        expect(h.status, RealtimeStatus.offline);
        async.elapse(const Duration(minutes: 5));
        expect(h.connector.calls, hasLength(1));
        h.lifecycle.emit(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(h.connector.calls, hasLength(2));
      });
    });

    test('resume while connected probes with a ping', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        h.lifecycle.emit(AppLifecycleState.hidden);
        h.lifecycle.emit(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(s.sentOfType('ping'), hasLength(1));
      });
    });

    test('backgrounding sends app.focus false; resume sends true', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        expect(s.sentOfType('app.focus'), isEmpty); // connect = foreground
        h.lifecycle.emit(AppLifecycleState.paused);
        async.flushMicrotasks();
        expect(s.sentOfType('app.focus').single['p'], {'foreground': false});
        h.lifecycle.emit(AppLifecycleState.resumed);
        async.flushMicrotasks();
        final sent = s.sentOfType('app.focus');
        expect(sent, hasLength(2));
        expect(sent.last['p'], {'foreground': true});
        // Ids are unique (server de-duplication).
        expect(sent.first['id'], isNot(sent.last['id']));
        // Unanswered: the fire-and-forget command times out silently (an
        // unhandled error would fail this zone).
        async.elapse(const Duration(seconds: 11));
        expect(s.sentOfType('app.focus'), hasLength(2));
      });
    });

    test(
      'no app.focus without a ready socket; a reconnect counts as foreground',
      () {
        fakeAsync((async) {
          final h = Harness();
          final s = connect(h, async);
          h.lifecycle.emit(AppLifecycleState.paused);
          async.flushMicrotasks();
          s.serverClose(1006);
          async.flushMicrotasks();
          h.lifecycle.emit(AppLifecycleState.resumed);
          async.flushMicrotasks();
          final fresh = h.connector.last;
          expect(identical(fresh, s), isFalse);
          fresh.ready();
          async.flushMicrotasks();
          expect(fresh.sentOfType('app.focus'), isEmpty);
          expect(s.sentOfType('app.focus'), hasLength(1)); // only the pause
        });
      },
    );

    test('an error reply to app.focus never throws', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        h.lifecycle.emit(AppLifecycleState.hidden);
        async.flushMicrotasks();
        final id = s.sentOfType('app.focus').single['id'] as String;
        s.serverSend('error', {'code': 'bad_request', 'message': 'x'}, id);
        async.flushMicrotasks();
        expect(h.status, RealtimeStatus.connected);
      });
    });

    test('start while backgrounded waits for resume', () {
      fakeAsync((async) {
        final h = Harness();
        h.lifecycle.emit(AppLifecycleState.paused);
        h.connection.start();
        async.flushMicrotasks();
        expect(h.status, RealtimeStatus.offline);
        expect(h.connector.calls, isEmpty);
        h.lifecycle.emit(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(h.connector.calls, hasLength(1));
      });
    });
  });

  group('inbound', () {
    test('malformed frames are dropped and counted', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        final seen = <String>[];
        h.connection.events.listen((m) => seen.add(m.type));
        s.serverRaw('{oops');
        s.serverSend('future.type', {'a': 1});
        async.flushMicrotasks();
        expect(seen, ['future.type']);
        expect(h.telemetry, [TelemetryKind.clientError]);
      });
    });

    test('buffer overflow drops deltas and emits a local resync', () {
      fakeAsync((async) {
        final h = Harness(inboundBufferLimit: 4);
        final s = connect(h, async);
        final seen = <String>[];
        h.connection.events.listen((m) => seen.add(m.type));
        s.serverSend('wallet.updated', {'coins': 1, 'diamonds': 0});
        for (var v = 41; v < 45; v++) {
          s.serverSend('player.connected', {'roomId': 'r', 'v': v, 'seat': 0});
        }
        async.flushMicrotasks();
        expect(seen, [
          'wallet.updated',
          ServerMessageTypes.localResyncRequired,
        ]);
      });
    });

    test('typed account and social streams', () {
      fakeAsync((async) {
        final h = Harness();
        final s = connect(h, async);
        final wallets = <WalletUpdatedEvent>[];
        final progress = <ProgressionUpdatedEvent>[];
        final social = <ServerEvent>[];
        final account = <ServerEvent>[];
        h.connection.walletUpdates.listen(wallets.add);
        h.connection.progressionUpdates.listen(progress.add);
        h.connection.socialEvents.listen(social.add);
        h.connection.accountEvents.listen(account.add);
        s.serverSend('wallet.updated', {
          'coins': 5,
          'diamonds': 1,
          'delta': {'coins': 5, 'diamonds': 0},
          'reason': 'payout',
        });
        s.serverSend('progression.updated', {'xp': 10, 'level': 2});
        s.serverSend('social.friend_request', {
          'fromUid': 'u_9',
          'fromName': 'A',
        });
        async.flushMicrotasks();
        expect(wallets.single.coins, 5);
        expect(progress.single.level, 2);
        expect(social.single, isA<FriendRequestEvent>());
        expect(account, hasLength(2));
      });
    });
  });

  test('dispose is safe and stops everything', () async {
    final h = Harness();
    unawaited(h.connection.dispose());
    await Future<void>.delayed(Duration.zero);
    h.connection.start();
    expect(h.connector.calls, isEmpty);
  });
}
