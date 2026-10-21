import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';

import 'fixtures.dart';

void main() {
  group('ClientMessage', () {
    test('encodes t/id/p', () {
      final m = ClientMessage(
        type: ClientMessageTypes.gameRollDice,
        id: 'c7',
        payload: const {'roomId': 'r_1', 'turnSeq': 12},
      );
      expect(jsonDecode(m.encode()), {
        't': 'game.roll_dice',
        'id': 'c7',
        'p': {'roomId': 'r_1', 'turnSeq': 12},
      });
    });

    test('ping has no id and no payload', () {
      expect(jsonDecode(const ClientMessage.ping().encode()), {'t': 'ping'});
    });

    test('empty payload is omitted', () {
      final m = ClientMessage(
        type: ClientMessageTypes.matchmakingCancel,
        id: 'a1',
        payload: const {},
      );
      expect(jsonDecode(m.encode()), {'t': 'matchmaking.cancel', 'id': 'a1'});
    });
  });

  group('decodeServerMessage', () {
    test('reply with typed payload', () {
      final m = decodeServerMessage(
        '{"t":"game.dice_result","r":"c7","p":{"roomId":"r_1","v":41,"h":5,'
        '"seat":0,"value":6,"turnSeq":13,"phase":"awaiting_move",'
        '"deadline":1,"legal":[0,2],"sixStreak":1,"strikes":0}}',
      );
      expect(m.type, 'game.dice_result');
      expect(m.replyTo, 'c7');
      final e = m.event as DiceResultEvent;
      expect(e.value, 6);
      expect(e.legal, [0, 2]);
      expect(e.v, 41);
      expect(e.h, 5);
      expect(e.voided, isFalse);
    });

    test('error payload', () {
      final m = decodeServerMessage(
        '{"t":"error","r":"c7","p":{"code":"not_your_turn","msg":"x","retry":false}}',
      );
      expect(m.isError, isTrue);
      final e = m.event as ServerErrorEvent;
      expect(e.code, 'not_your_turn');
      expect(e.retry, isFalse);
    });

    test('unknown type and unknown fields are tolerated', () {
      final m = decodeServerMessage(
        '{"t":"future.thing","p":{"x":1},"extra":true}',
      );
      expect(m.event, isA<UnknownEvent>());
      final m2 = decodeServerMessage(
        '{"t":"pong","p":{"ts":99,"newField":"y"},"zz":1}',
      );
      expect((m2.event as PongEvent).ts, 99);
    });

    test('missing payload decodes with defaults', () {
      final m = decodeServerMessage('{"t":"ack"}');
      expect((m.event as AckEvent).dup, isFalse);
      final dup = decodeServerMessage('{"t":"ack","r":"a","p":{"dup":true}}');
      expect((dup.event as AckEvent).dup, isTrue);
    });

    test('malformed frames throw ProtocolDecodeException', () {
      expect(
        () => decodeServerMessage('{not json'),
        throwsA(isA<ProtocolDecodeException>()),
      );
      expect(
        () => decodeServerMessage('[1,2]'),
        throwsA(isA<ProtocolDecodeException>()),
      );
      expect(
        () => decodeServerMessage('{"p":{}}'),
        throwsA(isA<ProtocolDecodeException>()),
      );
    });

    test('room snapshot round-trips', () {
      final json = ludoRoomJson();
      json['code'] = 'K7Q2MX';
      json['h'] = 2902942580;
      json['result'] = {
        'winnerSeat': 0,
        'reason': 'completed',
        'placements': [0, 1],
        'payout': 2000,
      };
      json['rematch'] = {
        'open': true,
        'deadline': 5,
        'accepted': [0],
        'declined': <int>[],
      };
      final m = decodeServerMessage(
        jsonEncode({
          't': 'game.state',
          'p': {'room': json},
        }),
      );
      final room = (m.event as GameStateEvent).room;
      expect(room.code, 'K7Q2MX');
      expect(room.players, hasLength(2));
      expect(room.players.first.cosmetics.dice, 'dice_classic');
      expect(room.board.ludoTokens, [
        [-1, -1, 5, 56],
        [0, -1, -1, -1],
      ]);
      expect(room.board.snakesPositions, isNull);
      expect(room.result!.payout, 2000);
      expect(room.rematch!.accepted, [0]);
      expect(RoomSnapshot.fromJson(room.toJson()), room);
    });

    test('every server type decodes to its typed event', () {
      final samples = <String, Map<String, dynamic>>{
        'connection.ready': {
          'uid': 'u_1',
          'protocol': 1,
          'serverTime': 5,
          'activeRoomId': 'r_1',
          'compression': 'none',
          'heartbeatSec': 20,
        },
        'matchmaking.status': {
          'status': 'searching',
          'game': 'ludo',
          'variant': 'quick',
          'capacity': 2,
          'roomId': 'r_1',
        },
        'room.updated': {'room': ludoRoomJson(), 'reason': 'joined'},
        'game.started': {'room': ludoRoomJson()},
        'game.move_applied': {
          'roomId': 'r_1',
          'v': 2,
          'seat': 0,
          'token': 1,
          'from': 3,
          'to': 9,
          'captures': [
            {'seat': 1, 'token': 0},
          ],
          'home': false,
        },
        'game.turn_changed': {
          'roomId': 'r_1',
          'v': 3,
          'seat': 1,
          'turnSeq': 4,
          'phase': 'awaiting_roll',
          'deadline': 9,
          'sixStreak': 0,
        },
        'player.connected': {'roomId': 'r_1', 'v': 4, 'seat': 1},
        'player.disconnected': {'roomId': 'r_1', 'v': 5, 'seat': 1},
        'player.forfeited': {
          'roomId': 'r_1',
          'v': 6,
          'seat': 1,
          'reason': 'timeouts',
        },
        'game.finished': {
          'roomId': 'r_1',
          'v': 7,
          'result': {'winnerSeat': 0},
          'rematch': {'open': true},
        },
        'room.rematch': {
          'roomId': 'r_1',
          'v': 8,
          'rematch': {
            'open': true,
            'accepted': [0, 1],
          },
        },
        'wallet.updated': {
          'coins': 10,
          'diamonds': 2,
          'delta': {'coins': -5, 'diamonds': 0},
          'reason': 'entry_fee',
        },
        'progression.updated': {
          'xp': 120,
          'level': 2,
          'xpGained': 35,
          'levelUp': true,
          'unlocked': ['frame_bronze'],
          'missions': [
            {'id': 'm1', 'progress': 1, 'target': 3, 'completed': false},
          ],
        },
        'chat.quick': {'roomId': 'r_1', 'seat': 0, 'msg': 'gg'},
        'chat.emote': {'roomId': 'r_1', 'seat': 1, 'emote': 'emote_wave'},
        'social.invite': {
          'inviteId': 'i1',
          'fromUid': 'u_2',
          'fromName': 'Asha',
          'roomId': 'r_9',
          'code': 'K7Q2MX',
          'game': 'ludo',
          'expiresAt': 99,
        },
        'social.friend_request': {'fromUid': 'u_3', 'fromName': 'Ravi'},
      };
      final expected = <String, Type>{
        'connection.ready': ConnectionReadyEvent,
        'matchmaking.status': MatchmakingStatusEvent,
        'room.updated': RoomUpdatedEvent,
        'game.started': GameStartedEvent,
        'game.move_applied': MoveAppliedEvent,
        'game.turn_changed': TurnChangedEvent,
        'player.connected': PlayerConnectionEvent,
        'player.disconnected': PlayerConnectionEvent,
        'player.forfeited': PlayerForfeitedEvent,
        'game.finished': GameFinishedEvent,
        'room.rematch': RoomRematchEvent,
        'wallet.updated': WalletUpdatedEvent,
        'progression.updated': ProgressionUpdatedEvent,
        'chat.quick': QuickChatEvent,
        'chat.emote': EmoteEvent,
        'social.invite': SocialInviteEvent,
        'social.friend_request': FriendRequestEvent,
      };
      for (final entry in samples.entries) {
        final m = decodeServerMessage(
          jsonEncode({'t': entry.key, 'p': entry.value}),
        );
        expect(m.event.runtimeType, expected[entry.key], reason: entry.key);
        expect(m.event.type, entry.key, reason: entry.key);
      }

      final wallet =
          decodeServerMessage(
                jsonEncode({
                  't': 'wallet.updated',
                  'p': samples['wallet.updated'],
                }),
              ).event
              as WalletUpdatedEvent;
      expect(wallet.deltaCoins, -5);
      final prog =
          decodeServerMessage(
                jsonEncode({
                  't': 'progression.updated',
                  'p': samples['progression.updated'],
                }),
              ).event
              as ProgressionUpdatedEvent;
      expect(prog.levelUp, isTrue);
      expect(prog.unlocked, ['frame_bronze']);
      expect(prog.missions.single.target, 3);
      final ready =
          decodeServerMessage(
                jsonEncode({
                  't': 'connection.ready',
                  'p': samples['connection.ready'],
                }),
              ).event
              as ConnectionReadyEvent;
      expect(ready.activeRoomId, 'r_1');
      final move =
          decodeServerMessage(
                jsonEncode({
                  't': 'game.move_applied',
                  'p': samples['game.move_applied'],
                }),
              ).event
              as MoveAppliedEvent;
      expect(move.captures.single, const CapturedToken(seat: 1, token: 0));
    });

    test('snakes move with transition', () {
      final m = decodeServerMessage(
        '{"t":"game.move_applied","p":{"roomId":"r","v":2,"h":1,"seat":0,'
        '"from":33,"to":44,"landing":36,"transition":{"kind":"ladder",'
        '"from":36,"to":44}}}',
      );
      final e = m.event as MoveAppliedEvent;
      expect(e.landing, 36);
      expect(e.transition!.isLadder, isTrue);
      expect(e.transition!.to, 44);
    });
  });
}
