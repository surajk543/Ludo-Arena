import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ludo_royale/core/analytics/analytics_service.dart';
import 'package:ludo_royale/core/app_policy/policy_signal.dart';
import 'package:ludo_royale/core/lifecycle/app_lifecycle.dart';
import 'package:ludo_royale/core/realtime/backoff.dart';
import 'package:ludo_royale/core/realtime/realtime_connection.dart';
import 'package:ludo_royale/core/realtime/realtime_socket.dart';
import 'package:ludo_royale/core/realtime/realtime_status.dart';
import 'package:ludo_royale/core/telemetry/telemetry_reporter.dart';

/// In-memory socket. Inbound frames are delivered synchronously.
class FakeSocket implements RealtimeSocket {
  final _controller = StreamController<dynamic>(sync: true);
  final sent = <String>[];
  int? _closeCode;
  int? clientCloseCode;
  bool closedByClient = false;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(String data) => sent.add(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    closedByClient = true;
    clientCloseCode = code;
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => null;

  List<Map<String, dynamic>> get sentJson => [
    for (final s in sent) (jsonDecode(s) as Map).cast<String, dynamic>(),
  ];

  List<Map<String, dynamic>> sentOfType(String t) =>
      sentJson.where((m) => m['t'] == t).toList();

  Map<String, dynamic> get lastSent => sentJson.last;

  void serverSend(String type, [Map<String, dynamic>? p, String? r]) {
    _controller.add(jsonEncode({'t': type, 'r': ?r, 'p': ?p}));
  }

  void serverRaw(String raw) => _controller.add(raw);

  void ready({String uid = 'u_0', String? activeRoomId, int serverTime = 0}) {
    serverSend('connection.ready', {
      'uid': uid,
      'protocol': 1,
      'serverTime': serverTime,
      'activeRoomId': ?activeRoomId,
      'compression': 'none',
      'heartbeatSec': 20,
    });
  }

  void serverClose(int? code) {
    _closeCode = code;
    _controller.close();
  }
}

/// Connector that hands out scripted results.
class FakeConnector {
  final calls = <({Uri uri, Map<String, String> headers})>[];
  final sockets = <FakeSocket>[];

  /// Scripted outcomes: an int = handshake HTTP status failure, `null` =
  /// network failure, anything else (or empty queue) = success.
  final script = <Object?>[];

  static const success = #success;

  Future<RealtimeSocket> call(Uri uri, Map<String, String> headers) async {
    calls.add((uri: uri, headers: headers));
    if (script.isNotEmpty) {
      final next = script.removeAt(0);
      if (next is int) {
        throw RealtimeHandshakeException(httpStatus: next, message: 'status');
      }
      if (next == null) {
        throw const RealtimeHandshakeException(message: 'network');
      }
    }
    final s = FakeSocket();
    sockets.add(s);
    return s;
  }

  FakeSocket get last => sockets.last;
}

/// Wires a [RealtimeConnection] to fakes.
class Harness {
  Harness({
    DateTime Function()? now,
    Random? random,
    int inboundBufferLimit = 512,
  }) {
    connection = RealtimeConnection(
      uri: Uri.parse('ws://localhost:8080/api/v1/ws'),
      appHeaders: const {
        'X-App-Platform': 'android',
        'X-App-Version': '1.0.0',
        'X-App-Build': '1',
      },
      accessToken: () async {
        tokenCalls++;
        return token;
      },
      refreshSession: () async {
        refreshCalls++;
        if (refreshThrows) throw Exception('network');
        if (refreshResult) token = 'tok${refreshCalls + 1}';
        return refreshResult;
      },
      connector: connector.call,
      onStatus: statuses.add,
      onPolicySignal: policy.add,
      onServerTime: (ms, rtt) => serverTimes.add(ms),
      onTelemetry: telemetry.add,
      lifecycle: lifecycle,
      random: random ?? Random(7),
      backoff: ReconnectBackoff(random: random ?? Random(7)),
      now: now,
      inboundBufferLimit: inboundBufferLimit,
    );
  }

  final connector = FakeConnector();
  final statuses = <RealtimeStatus>[];
  final policy = <PolicySignalReason>[];
  final telemetry = <TelemetryKind>[];
  final serverTimes = <int>[];
  final lifecycle = AppLifecycleBus();
  String? token = 'tok1';
  int tokenCalls = 0;
  int refreshCalls = 0;
  bool refreshResult = true;
  bool refreshThrows = false;
  late final RealtimeConnection connection;

  RealtimeStatus get status => connection.status;
}

/// Records analytics calls by member name.
class RecordingAnalytics implements AnalyticsService {
  final calls = <String>[];
  final args = <String, List<Object?>>{};

  int count(String name) => calls.where((c) => c == name).length;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final raw = invocation.memberName.toString();
    final name = raw.substring('Symbol("'.length, raw.length - 2);
    calls.add(name);
    args[name] = [
      ...invocation.positionalArguments,
      ...invocation.namedArguments.values,
    ];
    return null;
  }
}
