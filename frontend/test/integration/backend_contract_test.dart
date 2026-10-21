// Cross-stack contract test: the app's own protocol code (dart:io WebSocket
// connector with negotiated permessage-deflate, envelope decoding, typed
// events, RoomStateStore reducer with version + FNV-1a hash checks) against
// the real Go backend.
//
// Skipped unless BACKEND_URL is set, e.g.
//   BACKEND_URL=http://localhost:8080 flutter test test/integration/
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/envelope.dart';
import 'package:ludo_royale/core/protocol/events.dart';
import 'package:ludo_royale/core/protocol/room_state_reducer.dart';
import 'package:ludo_royale/core/realtime/realtime_socket.dart';
import 'package:ludo_royale/features/profile/domain/display_name.dart';

final String? _backend = Platform.environment['BACKEND_URL'];

const _appHeaders = {
  'X-App-Platform': 'ios',
  'X-App-Version': '1.0.0',
  'X-App-Build': '1',
};

Future<Map<String, dynamic>> _post(
  String path,
  Map<String, dynamic> body, {
  Map<String, String> extra = const {},
}) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$_backend$path'));
    req.headers.contentType = ContentType.json;
    _appHeaders.forEach(req.headers.set);
    extra.forEach(req.headers.set);
    req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    expect(res.statusCode, inInclusiveRange(200, 201), reason: text);
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// Sends [method] [path] with a bearer token; returns the status, the
/// decoded JSON body and the `Retry-After` header (any status).
Future<(int, Map<String, dynamic>, String?)> _send(
  String method,
  String path,
  String token, [
  Map<String, dynamic>? body,
]) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse('$_backend$path'));
    req.headers.contentType = ContentType.json;
    _appHeaders.forEach(req.headers.set);
    req.headers.set('Authorization', 'Bearer $token');
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    final json = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    return (res.statusCode, json, res.headers.value('retry-after'));
  } finally {
    client.close();
  }
}

/// Signs in a reusable test guest: resumes with a stored guest secret (also
/// exercising POST /auth/guest/resume) and only creates a new guest when
/// none is stored, which keeps repeated runs under the guest-creation limit.
Future<Map<String, dynamic>> _guest(
  String name, {
  Map<String, String> extra = const {},
}) async {
  final file = File(
    '${Directory.systemTemp.path}/ludo_contract_guest_$name.json',
  );
  if (file.existsSync()) {
    final secret = (jsonDecode(file.readAsStringSync()) as Map)['guestSecret'];
    try {
      return await _post('/api/v1/auth/guest/resume', {
        'guestSecret': secret,
      }, extra: extra);
    } on TestFailure {
      file.deleteSync();
    }
  }
  final created = await _post('/api/v1/auth/guest', {}, extra: extra);
  file.writeAsStringSync(jsonEncode({'guestSecret': created['guestSecret']}));
  return created;
}

/// A protocol client built only from production app code.
class _AppClient {
  _AppClient(this.name, this.token);

  final String name;
  final String token;
  final store = RoomStateStore();
  late final RealtimeSocket socket;
  ConnectionReadyEvent? ready;
  int _ids = 0;
  // Ids must be unique per user for 2 minutes across connections (server
  // de-duplication), so include a per-run random component like the app does.
  final String _runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  int hashMismatches = 0;
  int gaps = 0;
  int applied = 0;
  final List<String> errors = [];
  final _changes = StreamController<void>.broadcast();
  String? _acted;

  Future<void> connect(Uri wsUri) async {
    socket = await ioWebSocketConnector(wsUri, {
      'Authorization': 'Bearer $token',
      ..._appHeaders,
    });
    socket.stream.listen((frame) {
      final msg = decodeServerMessage(frame as String);
      final event = msg.event;
      if (event is ConnectionReadyEvent) ready = event;
      if (event is ServerErrorEvent) errors.add(event.code);
      final result = store.apply(event);
      switch (result) {
        case Applied():
          applied++;
        case NeedsSync(:final reason, :final roomId):
          if (reason == SyncReason.hashMismatch) hashMismatches++;
          if (reason == SyncReason.gap) gaps++;
          send('game.request_sync', {'roomId': roomId});
        case Ignored():
          break;
      }
      _changes.add(null);
      _act();
    });
  }

  void send(String type, Map<String, dynamic> payload) {
    socket.add(
      ClientMessage(
        type: type,
        id: '$name.$_runId.${++_ids}',
        payload: payload,
      ).encode(),
    );
  }

  int get mySeat {
    final room = store.state;
    if (room == null || ready == null) return -1;
    for (final p in room.players) {
      if (p.uid == ready!.uid) return p.seat;
    }
    return -1;
  }

  void _act() {
    final room = store.state;
    if (room == null || !room.isPlaying || room.turn.seat != mySeat) return;
    final key = '${room.turn.turnSeq}/${room.turn.phase}';
    if (key == _acted) return;
    _acted = key;
    // Act like a (fast) human: stay under the server's per-connection
    // command rate limit (10/s, burst 20).
    Future<void>.delayed(const Duration(milliseconds: 120), () => _actNow(key));
  }

  void _actNow(String key) {
    final room = store.state;
    if (room == null || !room.isPlaying || room.turn.seat != mySeat) return;
    if ('${room.turn.turnSeq}/${room.turn.phase}' != key) return;
    if (room.turn.phase == 'awaiting_roll') {
      send('game.roll_dice', {'roomId': room.id, 'turnSeq': room.turn.turnSeq});
    } else if (room.turn.phase == 'awaiting_move' &&
        room.turn.legal.length >= 2) {
      // With exactly one legal token the server applies the move itself.
      send('game.make_move', {
        'roomId': room.id,
        'turnSeq': room.turn.turnSeq,
        'token': room.turn.legal.last,
      });
    }
  }

  Future<void> until(bool Function() cond, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!cond()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          '$name: condition not met (state: ${store.state?.status}, errors: $errors)',
        );
      }
      await _changes.stream.first.timeout(
        const Duration(milliseconds: 300),
        onTimeout: () {},
      );
    }
  }
}

void main() {
  test(
    'PATCH /me: rejections carry the reasons the app localizes, a valid '
    'name is applied (or rate limited with Retry-After)',
    () async {
      final token = (await _guest('name'))['accessToken'] as String;
      const rejected = {
        'Ab': 'too_short',
        'Abcdefghijklmnopq': 'too_long',
        'Raj 😎': 'invalid_characters',
        'Bot Raj': 'reserved',
        'Super_Admin': 'reserved',
      };
      for (final MapEntry(key: name, value: reason) in rejected.entries) {
        // The app's client-side mirror agrees with the server.
        expect(DisplayNameRules.validate(name)?.reason, reason, reason: name);
        final (status, body, _) = await _send('PATCH', '/api/v1/me', token, {
          'displayName': name,
        });
        final error = (body['error'] as Map?) ?? const {};
        if (status == 429) {
          expect(error['code'], 'rate_limited');
          continue;
        }
        expect(status, 400, reason: '$name: $body');
        expect(error['code'], 'invalid_name', reason: name);
        expect((error['details'] as Map?)?['reason'], reason, reason: name);
      }

      final wanted =
          'Contract ${DateTime.now().microsecondsSinceEpoch % 10000}';
      final (status, body, retryAfter) = await _send(
        'PATCH',
        '/api/v1/me',
        token,
        {'displayName': '  ${wanted.replaceAll(' ', '   ')} '},
      );
      if (status == 429) {
        // Max changes per 24 h reached by earlier runs.
        expect((body['error'] as Map)['code'], 'rate_limited');
        expect(retryAfter, isNotNull);
        return;
      }
      expect(status, 200, reason: '$body');
      // Normalized by the server (trim + collapsed whitespace).
      expect((body['user'] as Map)['displayName'], wanted);
      expect(body['wallet'], isA<Map<String, dynamic>>());
      final (_, me, _) = await _send('GET', '/api/v1/me', token);
      expect((me['user'] as Map)['displayName'], wanted);
    },
    skip: _backend == null
        ? 'set BACKEND_URL to run against a live backend'
        : false,
  );

  test(
    'full game through the real backend with compression and hash-verified deltas',
    () async {
      final base = Uri.parse(_backend!);
      final wsUri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/api/v1/ws',
      );

      final a = await _guest('a');
      final b = await _guest('b', extra: {'Accept-Language': 'ar'});
      final ca = _AppClient('a', a['accessToken'] as String);
      final cb = _AppClient('b', b['accessToken'] as String);
      await ca.connect(wsUri);
      await cb.connect(wsUri);
      await ca.until(() => ca.ready != null, const Duration(seconds: 5));
      await cb.until(() => cb.ready != null, const Duration(seconds: 5));

      // Reused test guests may still be seated in a game from an earlier run:
      // leave it first (the server allows one active room per account).
      for (final c in [ca, cb]) {
        final leftover = c.ready!.activeRoomId;
        if (leftover != null && leftover.isNotEmpty) {
          c.send('room.leave', {'roomId': leftover});
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final c in [ca, cb]) {
        c.store.clear();
      }

      // permessage-deflate was negotiated by dart:io with the Go server.
      expect(ca.ready!.compression, contains('permessage-deflate'));

      // A private room guarantees both clients share one game (a shared dev
      // backend may hold other open public lobbies).
      ca.send('room.create', {
        'game': 'ludo',
        'variant': 'quick',
        'capacity': 2,
      });
      await ca.until(
        () => ca.store.state?.code != null,
        const Duration(seconds: 5),
      );
      cb.send('room.join', {'code': ca.store.state!.code!.toLowerCase()});
      await ca.until(
        () =>
            (ca.store.state?.players.length ?? 0) == 2 &&
            ca.store.state!.players.every((p) => p.connected),
        const Duration(seconds: 5),
      );
      ca.send('game.start', {'roomId': ca.store.state!.id});
      await ca.until(
        () => ca.store.state?.isPlaying ?? false,
        const Duration(seconds: 10),
      );
      expect(cb.store.state!.id, ca.store.state!.id);
      await Future.wait([
        ca.until(
          () => ca.store.state?.isFinished ?? false,
          const Duration(minutes: 3),
        ),
        cb.until(
          () => cb.store.state?.isFinished ?? false,
          const Duration(minutes: 3),
        ),
      ]);

      // Every delta applied by the app's reducer matched the server hash, and
      // both clients converged on the same authoritative final state.
      expect(ca.hashMismatches + cb.hashMismatches, 0);
      expect(ca.store.state!.result, isNotNull);
      expect(ca.store.state!.v, cb.store.state!.v);
      expect(
        ca.store.state!.board.ludoTokens,
        cb.store.state!.board.ludoTokens,
      );
      expect(ca.applied, greaterThan(20));
      // The client language never changes protocol values (b used Arabic).
      expect(cb.errors, isEmpty);

      await ca.socket.close(1000);
      await cb.socket.close(1000);
    },
    skip: _backend == null
        ? 'set BACKEND_URL to run against a live backend'
        : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
