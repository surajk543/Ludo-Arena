import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../app_policy/policy_signal.dart';
import '../lifecycle/app_lifecycle.dart';
import '../network/api_exception.dart';
import '../protocol/protocol.dart';
import '../telemetry/telemetry_reporter.dart';
import '../time/server_clock.dart';
import 'backoff.dart';
import 'realtime_socket.dart';
import 'realtime_status.dart';

/// A command failed: an `error` reply ([code] is the protocol error code),
/// a timeout (`timeout`), or no open connection
/// ([ClientErrorCodes.notConnected]). Localize with `localizedErrorMessage`.
class RealtimeCommandException implements Exception {
  const RealtimeCommandException(
    this.code, {
    this.message = '',
    this.retry = false,
  });

  final String code;

  /// Server English text (logs only).
  final String message;

  /// The same command may succeed later without user action.
  final bool retry;

  static const timeoutCode = 'timeout';

  bool get isNotConnected => code == ClientErrorCodes.notConnected;

  @override
  String toString() => 'RealtimeCommandException($code)';
}

/// Why the connection stopped reconnecting on its own.
enum RealtimeHaltReason {
  /// Closed with 4409: signed in on another device.
  replaced,

  /// 4426 / 4503 (close or handshake): the app gate takes over.
  policy,

  /// The refresh token was rejected; the session layer signs out.
  sessionEnded,

  /// Handshake answered 400: a client bug; retrying cannot help.
  badRequest,

  /// Closed with 4401 + reason `account deleted`: the account no longer
  /// exists. No refresh, no reconnect; the session layer signs out.
  accountDeleted,
}

typedef AccessTokenSource = Future<String?> Function();
typedef SessionRefresher = Future<bool> Function();

class _Pending {
  _Pending(this.completer, this.timer);

  final Completer<ServerMessage> completer;
  final Timer timer;
}

/// The single authenticated WebSocket (`/api/v1/ws`, `ludo-arena.v1`).
///
/// - [start] / [stop] are driven by the session (ready ↔ signed out).
/// - Reconnects with bounded full-jitter backoff; pauses while the app is
///   backgrounded and reconnects immediately on resume.
/// - App-level heartbeat: `ping` every 15 s, dead after 10 s without `pong`.
/// - Close codes / handshake statuses handled per websocket-protocol.md §1.
/// - [send] correlates replies by `r`; ids are unique across connections.
/// - [events] emits every inbound message in order (plus the synthetic
///   [LocalResyncRequired] when the bounded inbound buffer overflows).
class RealtimeConnection {
  RealtimeConnection({
    required this._uri,
    required this._appHeaders,
    required this._accessToken,
    required this._refreshSession,
    this._connector = ioWebSocketConnector,
    this._decoder = decodeServerMessage,
    this._onStatus,
    this._onPolicySignal,
    this._onServerTime,
    this._onTelemetry,
    this._onAccountDeleted,
    AppLifecycleBus? lifecycle,
    ReconnectBackoff? backoff,
    Random? random,
    NowFn? now,
    this.pingInterval = const Duration(seconds: 15),
    this.pongTimeout = const Duration(seconds: 10),
    this.readyTimeout = const Duration(seconds: 10),
    this.defaultCommandTimeout = const Duration(seconds: 10),
    this.rateLimitedReconnectDelay = const Duration(seconds: 10),
    this.inboundBufferLimit = 512,
  }) : _random = random ?? Random(),
       _now = now ?? DateTime.now {
    _backoff = backoff ?? ReconnectBackoff(random: _random);
    if (lifecycle != null) {
      _paused = !lifecycle.isForeground;
      _lifecycleSubs
        ..add(lifecycle.backgrounded.listen((_) => _onBackground()))
        ..add(lifecycle.resumed.listen((_) => _onResume()));
    }
  }

  final Uri _uri;
  final Map<String, String> _appHeaders;
  final AccessTokenSource _accessToken;
  final SessionRefresher _refreshSession;
  final WebSocketConnector _connector;
  final MessageDecoder _decoder;
  final void Function(RealtimeStatus)? _onStatus;
  final void Function(PolicySignalReason)? _onPolicySignal;
  final void Function(int, Duration)? _onServerTime;
  final void Function(TelemetryKind)? _onTelemetry;

  /// The server closed the socket because the account was deleted.
  final void Function()? _onAccountDeleted;
  final Random _random;
  final NowFn _now;
  late final ReconnectBackoff _backoff;

  final Duration pingInterval;
  final Duration pongTimeout;
  final Duration readyTimeout;
  final Duration defaultCommandTimeout;
  final Duration rateLimitedReconnectDelay;
  final int inboundBufferLimit;

  final _events = StreamController<ServerMessage>.broadcast(sync: true);
  final _lifecycleSubs = <StreamSubscription<void>>[];
  final _pending = <String, _Pending>{};
  final _inbound = ListQueue<ServerMessage>();

  RealtimeSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  bool _ready = false;
  bool _wanted = false;
  bool _paused = false;
  bool _connecting = false;
  bool _dropped = false;
  bool _reconnectPending = false;
  bool _drainScheduled = false;
  bool _disposed = false;
  int _generation = 0;
  int _consecutiveUnauthorized = 0;
  RealtimeHaltReason? _halt;
  RealtimeStatus _status = RealtimeStatus.idle;
  ConnectionReadyEvent? _lastReady;

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _pongTimer;
  Timer? _readyTimer;
  Timer? _stableTimer;
  DateTime? _pingSentAt;

  String _idPrefix = '';
  int _idCounter = 0;

  // ------------------------------------------------------------- getters

  RealtimeStatus get status => _status;

  /// `connection.ready` received on the current socket.
  bool get isConnected => _socket != null && _ready;

  /// Why auto-reconnect stopped (null while running normally).
  RealtimeHaltReason? get haltReason => _halt;

  /// The last `connection.ready` (its `uid` identifies the user's seat).
  ConnectionReadyEvent? get lastReady => _lastReady;

  /// Every inbound server message, in arrival order.
  Stream<ServerMessage> get events => _events.stream;

  /// `wallet.updated` events.
  Stream<WalletUpdatedEvent> get walletUpdates => _events.stream
      .map((m) => m.event)
      .where((e) => e is WalletUpdatedEvent)
      .cast<WalletUpdatedEvent>();

  /// `progression.updated` events.
  Stream<ProgressionUpdatedEvent> get progressionUpdates => _events.stream
      .map((m) => m.event)
      .where((e) => e is ProgressionUpdatedEvent)
      .cast<ProgressionUpdatedEvent>();

  /// `wallet.updated` + `progression.updated`.
  Stream<ServerEvent> get accountEvents => _events.stream
      .map((m) => m.event)
      .where((e) => e is WalletUpdatedEvent || e is ProgressionUpdatedEvent);

  /// `social.invite` + `social.friend_request`.
  Stream<ServerEvent> get socialEvents => _events.stream
      .map((m) => m.event)
      .where((e) => e is SocialInviteEvent || e is FriendRequestEvent);

  // ------------------------------------------------------------ control

  /// Begins connecting (idempotent). Clears any halt.
  void start() {
    if (_disposed) return;
    _wanted = true;
    _halt = null;
    if (_socket != null || _connecting) return;
    _cancelReconnect();
    if (_paused) {
      _setStatus(RealtimeStatus.offline);
      return;
    }
    unawaited(_connect());
  }

  /// Closes the socket (1000) and stops reconnecting. Pending commands fail
  /// with `not_connected`.
  void stop() {
    _wanted = false;
    _halt = null;
    _dropped = false;
    _reconnectPending = false;
    _connecting = false;
    _generation++;
    _cancelReconnect();
    _detach(closeCode: WsCloseCodes.normal, reason: 'client stop');
    _setStatus(RealtimeStatus.idle);
  }

  /// User-initiated reconnect (e.g. "Reconnect" after 4409). Resets backoff
  /// and clears any halt.
  void reconnectNow() {
    if (_disposed) return;
    _wanted = true;
    _halt = null;
    _backoff.reset();
    if (_socket != null || _connecting) return;
    _cancelReconnect();
    if (_paused) {
      _setStatus(RealtimeStatus.offline);
      return;
    }
    unawaited(_connect());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    stop();
    _disposed = true;
    for (final s in _lifecycleSubs) {
      await s.cancel();
    }
    await _events.close();
  }

  // ------------------------------------------------------------ commands

  /// Sends a command and resolves with its direct reply (the message whose
  /// `r` equals the generated id — `ack`, `room.updated`,
  /// `game.dice_result`, …). The reply is ALSO emitted on [events] first.
  ///
  /// Throws [RealtimeCommandException]: the server `error` code, `timeout`,
  /// or `not_connected` (immediately, when no connection is open).
  Future<ServerMessage> send(
    String type,
    Map<String, dynamic> payload, {
    Duration? timeout,
  }) {
    final socket = _socket;
    if (socket == null || !_ready) {
      return Future.error(
        const RealtimeCommandException(ClientErrorCodes.notConnected),
      );
    }
    final id = '$_idPrefix${(++_idCounter).toRadixString(36)}';
    final completer = Completer<ServerMessage>();
    final timer = Timer(timeout ?? defaultCommandTimeout, () {
      final p = _pending.remove(id);
      if (p != null && !p.completer.isCompleted) {
        p.completer.completeError(
          const RealtimeCommandException(RealtimeCommandException.timeoutCode),
        );
      }
    });
    _pending[id] = _Pending(completer, timer);
    try {
      socket.add(ClientMessage(type: type, id: id, payload: payload).encode());
    } catch (_) {
      _pending.remove(id);
      timer.cancel();
      return Future.error(
        const RealtimeCommandException(ClientErrorCodes.notConnected),
      );
    }
    return completer.future;
  }

  // ---------------------------------------------------------- lifecycle

  void _onBackground() {
    _paused = true;
    _cancelReconnect();
    if (_socket == null && _wanted && _halt == null) {
      _setStatus(RealtimeStatus.offline);
    }
  }

  void _onResume() {
    _paused = false;
    if (!_wanted || _halt != null || _disposed) return;
    if (_socket != null) {
      // The OS may have silently killed the socket: probe it now.
      if (_ready) _sendPing();
      return;
    }
    if (_connecting) return;
    _backoff.reset();
    unawaited(_connect());
  }

  // --------------------------------------------------------- connecting

  bool _current(int gen) => gen == _generation && !_disposed;

  Future<void> _connect() async {
    if (_connecting || !_wanted || _halt != null || _paused || _disposed) {
      return;
    }
    _connecting = true;
    _cancelReconnect();
    _setStatus(
      _dropped ? RealtimeStatus.reconnecting : RealtimeStatus.connecting,
    );
    final gen = ++_generation;
    try {
      final String? token;
      try {
        token = await _accessToken();
      } catch (_) {
        if (_current(gen)) {
          _connecting = false;
          _onHandshakeFailure(null, tokenFailure: true);
        }
        return;
      }
      if (!_current(gen)) return;
      if (token == null) {
        _connecting = false;
        _haltWith(RealtimeHaltReason.sessionEnded, RealtimeStatus.idle);
        return;
      }
      final headers = <String, String>{
        ..._appHeaders,
        'Authorization': 'Bearer $token',
        if (_dropped) 'X-Reconnect': '1',
      };
      final RealtimeSocket socket;
      try {
        socket = await _connector(_uri, headers);
      } on RealtimeHandshakeException catch (e) {
        if (_current(gen)) {
          _connecting = false;
          _onHandshakeFailure(e.httpStatus);
        }
        return;
      } catch (_) {
        if (_current(gen)) {
          _connecting = false;
          _onHandshakeFailure(null);
        }
        return;
      }
      if (!_current(gen) || !_wanted || _halt != null) {
        unawaited(_safeClose(socket, WsCloseCodes.normal, 'superseded'));
        return;
      }
      _connecting = false;
      _attach(socket, gen);
    } finally {
      if (gen == _generation && _socket == null && _connecting) {
        _connecting = false;
      }
    }
  }

  void _attach(RealtimeSocket socket, int gen) {
    _socket = socket;
    _ready = false;
    _idPrefix = '${_randomId(6)}.';
    _idCounter = 0;
    _socketSub = socket.stream.listen(
      (data) {
        if (gen != _generation) return;
        if (data is String) _enqueue(data);
      },
      onError: (Object _) {},
      onDone: () {
        if (gen != _generation || !identical(_socket, socket)) return;
        _handleDrop(socket.closeCode, reason: socket.closeReason);
      },
      cancelOnError: false,
    );
    _readyTimer = Timer(readyTimeout, () {
      if (gen == _generation && !_ready) _handleDrop(null, closeSocket: true);
    });
  }

  void _onReady(ConnectionReadyEvent e) {
    _ready = true;
    _lastReady = e;
    _readyTimer?.cancel();
    _readyTimer = null;
    _consecutiveUnauthorized = 0;
    if (e.serverTime > 0) _onServerTime?.call(e.serverTime, Duration.zero);
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) => _sendPing());
    _stableTimer?.cancel();
    _stableTimer = Timer(_backoff.stableAfter, _backoff.reset);
    if (_reconnectPending && _dropped) {
      _onTelemetry?.call(TelemetryKind.reconnectSuccess);
    }
    _reconnectPending = false;
    _setStatus(RealtimeStatus.connected);
  }

  // ---------------------------------------------------------- heartbeat

  void _sendPing() {
    final socket = _socket;
    if (socket == null || !_ready || _pongTimer != null) return;
    final gen = _generation;
    _pingSentAt = _now();
    try {
      socket.add(const ClientMessage.ping().encode());
    } catch (_) {
      _handleDrop(null, closeSocket: true);
      return;
    }
    _pongTimer = Timer(pongTimeout, () {
      _pongTimer = null;
      if (gen == _generation) {
        _handleDrop(WsCloseCodes.heartbeatTimeout, closeSocket: true);
      }
    });
  }

  void _onPong(PongEvent e) {
    _pongTimer?.cancel();
    _pongTimer = null;
    final sent = _pingSentAt;
    final rtt = sent == null ? Duration.zero : _now().difference(sent);
    if (e.ts > 0) {
      _onServerTime?.call(e.ts, rtt.isNegative ? Duration.zero : rtt);
    }
  }

  // ------------------------------------------------------------ inbound

  void _enqueue(String raw) {
    final ServerMessage msg;
    try {
      msg = _decoder(raw);
    } on ProtocolDecodeException catch (e) {
      debugPrint('realtime: dropped malformed frame ($e)');
      _onTelemetry?.call(TelemetryKind.clientError);
      return;
    }
    _inbound.add(msg);
    if (_inbound.length > inboundBufferLimit) _overflow();
    if (!_drainScheduled) {
      _drainScheduled = true;
      scheduleMicrotask(_drain);
    }
  }

  /// Mirrors the server's outbound-queue policy: drop buffered versioned
  /// deltas (and chatter), then ask for an authoritative snapshot.
  void _overflow() {
    final kept = ListQueue<ServerMessage>();
    for (final m in _inbound) {
      final e = m.event;
      final droppable =
          e is RoomDeltaEvent ||
          e is QuickChatEvent ||
          e is EmoteEvent ||
          e is PongEvent ||
          e is LocalResyncRequired;
      if (droppable) {
        // A dropped direct reply still means the command was accepted.
        if (m.replyTo != null) _completePending(m);
        continue;
      }
      kept.add(m);
    }
    while (kept.length >= inboundBufferLimit) {
      final m = kept.removeFirst();
      if (m.replyTo != null) _completePending(m);
    }
    kept.add(ServerMessage.localResync);
    _inbound
      ..clear()
      ..addAll(kept);
  }

  void _drain() {
    _drainScheduled = false;
    while (_inbound.isNotEmpty) {
      _dispatch(_inbound.removeFirst());
    }
  }

  void _dispatch(ServerMessage m) {
    switch (m.event) {
      case final ConnectionReadyEvent e:
        _onReady(e);
      case final PongEvent e:
        _onPong(e);
      default:
        break;
    }
    if (!_events.isClosed) _events.add(m);
    if (m.replyTo != null) _completePending(m);
  }

  void _completePending(ServerMessage m) {
    final p = _pending.remove(m.replyTo);
    if (p == null) return;
    p.timer.cancel();
    if (p.completer.isCompleted) return;
    final e = m.event;
    if (e is ServerErrorEvent) {
      p.completer.completeError(
        RealtimeCommandException(e.code, message: e.msg, retry: e.retry),
      );
    } else {
      p.completer.complete(m);
    }
  }

  // -------------------------------------------------------------- drops

  void _handleDrop(int? code, {bool closeSocket = false, String? reason}) {
    _detach(
      closeCode: closeSocket ? WsCloseCodes.heartbeatTimeout : null,
      reason: 'heartbeat',
    );
    if (!_wanted || _disposed) {
      _setStatus(RealtimeStatus.idle);
      return;
    }
    _dropped = true;
    switch (code) {
      case WsCloseCodes.sessionRevoked
          when reason == WsCloseReasons.accountDeleted:
        // Not "signed in on another device" and nothing to refresh.
        _haltWith(RealtimeHaltReason.accountDeleted, RealtimeStatus.idle);
        _onAccountDeleted?.call();
      case WsCloseCodes.sessionRevoked:
        unawaited(_refreshThenReconnect());
      case WsCloseCodes.sessionReplaced:
        _haltWith(RealtimeHaltReason.replaced, RealtimeStatus.replaced);
      case WsCloseCodes.updateRequired:
        _onPolicySignal?.call(PolicySignalReason.wsUpdateRequired);
        _haltWith(RealtimeHaltReason.policy, RealtimeStatus.offline);
      case WsCloseCodes.maintenance:
        _onPolicySignal?.call(PolicySignalReason.wsMaintenance);
        _haltWith(RealtimeHaltReason.policy, RealtimeStatus.offline);
      case WsCloseCodes.rateLimited:
        _scheduleReconnect(minDelay: rateLimitedReconnectDelay);
      default:
        // 1000 (unexpected), 1001, 1008, 4400, 4508, heartbeat timeout,
        // abnormal closure (null) and anything unknown.
        _scheduleReconnect();
    }
  }

  void _onHandshakeFailure(int? httpStatus, {bool tokenFailure = false}) {
    if (_dropped) _onTelemetry?.call(TelemetryKind.reconnectFailure);
    switch (httpStatus) {
      case 401:
        _consecutiveUnauthorized++;
        if (_consecutiveUnauthorized > 2) {
          _scheduleReconnect();
        } else {
          unawaited(_refreshThenReconnect());
        }
      case 426:
        _onPolicySignal?.call(PolicySignalReason.wsUpdateRequired);
        _haltWith(RealtimeHaltReason.policy, RealtimeStatus.offline);
      case 503:
        _onPolicySignal?.call(PolicySignalReason.wsMaintenance);
        _haltWith(RealtimeHaltReason.policy, RealtimeStatus.offline);
      case 429:
        _scheduleReconnect();
      case 400:
        debugPrint('realtime: handshake rejected with 400 (client bug)');
        _haltWith(RealtimeHaltReason.badRequest, RealtimeStatus.offline);
      default:
        if (!tokenFailure) {
          _onPolicySignal?.call(PolicySignalReason.wsHandshakeFailed);
        }
        _scheduleReconnect();
    }
  }

  Future<void> _refreshThenReconnect() async {
    if (!_wanted || _halt != null) return;
    _setStatus(RealtimeStatus.reconnecting);
    final gen = _generation;
    final bool ok;
    try {
      ok = await _refreshSession();
    } catch (_) {
      if (gen == _generation) _scheduleReconnect();
      return;
    }
    if (gen != _generation || !_wanted || _halt != null || _disposed) return;
    if (!ok) {
      _haltWith(RealtimeHaltReason.sessionEnded, RealtimeStatus.idle);
      return;
    }
    if (_paused) {
      _reconnectPending = true;
      _setStatus(RealtimeStatus.offline);
      return;
    }
    _reconnectPending = true;
    unawaited(_connect());
  }

  void _scheduleReconnect({Duration minDelay = Duration.zero}) {
    if (!_wanted || _halt != null || _disposed) return;
    _reconnectPending = true;
    if (_paused) {
      _setStatus(RealtimeStatus.offline);
      return;
    }
    var delay = _backoff.next();
    if (delay < minDelay) delay = minDelay;
    _setStatus(RealtimeStatus.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  void _haltWith(RealtimeHaltReason reason, RealtimeStatus status) {
    _halt = reason;
    _cancelReconnect();
    _setStatus(status);
  }

  /// Drops the current socket: cancels timers, fails pending commands.
  void _detach({int? closeCode, String? reason}) {
    final socket = _socket;
    _socket = null;
    _ready = false;
    _generation++;
    unawaited(_socketSub?.cancel());
    _socketSub = null;
    for (final t in [_pingTimer, _pongTimer, _readyTimer, _stableTimer]) {
      t?.cancel();
    }
    _pingTimer = _pongTimer = _readyTimer = _stableTimer = null;
    if (socket != null && closeCode != null) {
      unawaited(_safeClose(socket, closeCode, reason));
    }
    _failPending();
  }

  void _failPending() {
    if (_pending.isEmpty) return;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final p in pending) {
      p.timer.cancel();
      if (!p.completer.isCompleted) {
        p.completer.completeError(
          const RealtimeCommandException(ClientErrorCodes.notConnected),
        );
      }
    }
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _safeClose(RealtimeSocket s, int code, String? reason) async {
    try {
      await s.close(code, reason);
    } catch (_) {}
  }

  void _setStatus(RealtimeStatus s) {
    if (_status == s) return;
    _status = s;
    _onStatus?.call(s);
  }

  String _randomId(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      List.generate(
        length,
        (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
      ),
    );
  }
}
