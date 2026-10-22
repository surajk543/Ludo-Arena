import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A recorded request seen by [FakeBackend].
class RecordedRequest {
  RecordedRequest(this.method, this.path, this.query, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Map<String, dynamic> headers;
  final Object? body;

  Map<String, dynamic> get json =>
      body is Map ? (body as Map).cast<String, dynamic>() : const {};

  String? header(String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name.toLowerCase()) return '${e.value}';
    }
    return null;
  }
}

/// Scripted response.
class FakeResponse {
  const FakeResponse(this.status, [this.body, this.headers = const {}]);

  /// `{"error":{"code","message","details"}}` helper.
  factory FakeResponse.error(
    int status,
    String code, {
    Map<String, dynamic> details = const {},
    Map<String, List<String>> headers = const {},
  }) => FakeResponse(status, {
    'error': {'code': code, 'message': code, 'details': details},
  }, headers);

  final int status;
  final Object? body;
  final Map<String, List<String>> headers;
}

typedef FakeHandler = FutureOr<FakeResponse> Function(RecordedRequest req);

/// A Dio [HttpClientAdapter] that routes `METHOD /path` (relative to
/// `/api/v1`) to scripted handlers. Unrouted requests answer 404.
class FakeBackend implements HttpClientAdapter {
  final Map<String, FakeHandler> _routes = {};
  final List<RecordedRequest> requests = [];

  /// When set, every request fails like a dead network.
  bool offline = false;

  void on(String method, String path, FakeHandler handler) =>
      _routes['${method.toUpperCase()} $path'] = handler;

  void json(String method, String path, Object body, {int status = 200}) =>
      on(method, path, (_) => FakeResponse(status, body));

  List<RecordedRequest> calls(String method, String path) => requests
      .where((r) => r.method == method.toUpperCase() && r.path == path)
      .toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var path = options.uri.path;
    const prefix = '/api/v1';
    if (path.startsWith(prefix)) path = path.substring(prefix.length);
    Object? body = options.data;
    if (body is String && body.isNotEmpty) {
      try {
        body = jsonDecode(body);
      } catch (_) {}
    }
    final req = RecordedRequest(
      options.method.toUpperCase(),
      path,
      Map<String, dynamic>.from(options.uri.queryParameters),
      Map<String, dynamic>.from(options.headers),
      body,
    );
    requests.add(req);
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final handler = _routes['${req.method} $path'];
    final res = handler == null
        ? FakeResponse.error(404, 'not_found')
        : await handler(req);
    final encoded = res.body == null ? '' : jsonEncode(res.body);
    return ResponseBody.fromString(
      encoded,
      res.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...res.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Canonical AuthResponse JSON for tests.
Map<String, dynamic> authJson({
  String id = 'acc-1',
  String uid = 'u_guest1',
  String name = 'Asha',
  bool isGuest = true,
  List<String> providers = const ['guest'],
  String actorType = 'human',
  String access = 'at-1',
  String refresh = 'rt-1',
  int accessExpiresAt = 4102444800000, // 2100-01-01
  int coins = 1000000,
  int diamonds = 50,
  String? guestSecret,
  bool isNewUser = false,
  int level = 4,
  int xp = 520,
}) => {
  'accessToken': access,
  'accessTokenExpiresAt': accessExpiresAt,
  'refreshToken': refresh,
  'refreshTokenExpiresAt': 4102444800000,
  'isNewUser': isNewUser,
  'user': userJson(
    id: id,
    uid: uid,
    name: name,
    isGuest: isGuest,
    providers: providers,
    actorType: actorType,
    level: level,
    xp: xp,
  ),
  'wallet': {'coins': coins, 'diamonds': diamonds},
  'guestSecret': ?guestSecret,
};

Map<String, dynamic> userJson({
  String id = 'acc-1',
  String uid = 'u_guest1',
  String name = 'Asha',
  bool isGuest = true,
  List<String> providers = const ['guest'],
  String actorType = 'human',
  int level = 4,
  int xp = 520,
}) => {
  'id': id,
  'uid': uid,
  'actorType': actorType,
  'displayName': name,
  'avatar': 3,
  'isGuest': isGuest,
  'linkedProviders': providers,
  'level': level,
  'xp': xp,
  'levelXp': 450,
  'nextLevelXp': 250,
  'title': 'title_rookie',
  'loadout': {
    'dice': 'dice_classic',
    'token': 'token_classic',
    'ludo_board': 'ludo_board_classic',
    'snakes_board': 'snakes_board_classic',
    'frame': 'frame_bronze',
    'title': 'title_rookie',
    'victory': 'victory_confetti',
  },
};

Map<String, dynamic> meJson({
  bool isGuest = true,
  List<String> providers = const ['guest'],
  String id = 'acc-1',
  String uid = 'u_guest1',
  String name = 'Asha',
  int coins = 1000000,
  int diamonds = 50,
}) => {
  'user': userJson(
    id: id,
    uid: uid,
    name: name,
    isGuest: isGuest,
    providers: providers,
  ),
  'wallet': {'coins': coins, 'diamonds': diamonds},
};

Map<String, dynamic> policyJson({
  String mode = 'normal',
  String latestVersion = '1.0.0',
  int latestBuild = 1,
  String minimumVersion = '1.0.0',
  int minimumBuild = 1,
  String storeUrl =
      'https://play.google.com/store/apps/details?id=com.ludoarena.app',
  bool storeAvailable = true,
  String title = '',
  String message = '',
  int reminderHours = 24,
  Map<String, dynamic>? maintenance,
  Map<String, int> entryFees = const {'ludo': 100000, 'snakes_ladders': 50000},
}) => {
  'configVersion': 3,
  'environment': 'development',
  'platform': 'android',
  'mode': mode,
  'installedVersion': '1.0.0',
  'installedBuild': 1,
  'minimumSupportedVersion': minimumVersion,
  'minimumSupportedBuild': minimumBuild,
  'latestVersion': latestVersion,
  'latestBuild': latestBuild,
  'storeUrl': storeUrl,
  'storeAvailable': storeAvailable,
  'title': title,
  'message': message,
  'optionalUpdateReminderHours': reminderHours,
  'maintenance':
      maintenance ??
      {
        'enabled': mode == 'maintenance',
        'message': '',
        'startsAtUtc': null,
        'scheduledEndUtc': null,
      },
  'rulesVersion': 1,
  'protocolVersion': 1,
  'entryFees': entryFees,
  'serverTime': 1761022800000,
};
