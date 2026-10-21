import 'dart:async';
import 'dart:io' show HttpDate, SocketException;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_policy/policy_signal.dart';
import '../config/app_config.dart';
import '../config/app_info.dart';
import '../localization/language_controller.dart';
import '../storage/secure_session_store.dart';
import '../time/server_clock.dart';
import 'api_exception.dart';
import 'api_models.dart';
import 'token_manager.dart';

export 'api_exception.dart';
export 'api_models.dart';

/// REST client for `/api/v1`.
///
/// - Adds `X-App-Platform`, `X-App-Version`, `X-App-Build` (+
///   `Accept-Language`) to every request.
/// - Adds `Authorization: Bearer …` unless `auth: false`; refreshes expiring
///   tokens before sending and retries once after a 401 using a single-flight
///   refresh (rotated tokens are persisted by [TokenManager]).
/// - Maps error bodies to [ApiException]; 426/503 notify the app gate;
///   429 honours `Retry-After` (one automatic retry for safe requests when
///   the wait is short).
class ApiClient {
  ApiClient({
    required AppConfig config,
    required AppInfo info,
    required TokenManager tokens,
    required PolicySignalBus policySignals,
    this._languageCode,
    HttpClientAdapter? adapter,
    Future<void> Function(Duration)? delay,
    this.maxAutoRetryAfter = const Duration(seconds: 3),
  }) : _tokens = tokens,
       _policy = policySignals,
       _delay = delay ?? Future<void>.delayed,
       _dio = Dio(_options(config, info)),
       _bare = Dio(_options(config, info)) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _bare.httpClientAdapter = adapter;
    }
    final headers = InterceptorsWrapper(
      onRequest: (o, h) {
        final lang = _languageCode?.call();
        if (lang != null) o.headers['Accept-Language'] = lang;
        h.next(o);
      },
    );
    _bare.interceptors.add(headers);
    _dio.interceptors
      ..add(headers)
      ..add(_AuthInterceptor(this));
    tokens.refreshCall = refreshTokens;
  }

  static BaseOptions _options(AppConfig config, AppInfo info) => BaseOptions(
    baseUrl: config.apiV1,
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
    headers: info.headers,
    // Error statuses are mapped by us, not thrown as generic DioExceptions
    // with lost bodies.
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  );

  final TokenManager _tokens;
  final PolicySignalBus _policy;
  final String Function()? _languageCode;
  final Future<void> Function(Duration) _delay;
  final Dio _dio;
  final Dio _bare;
  final Duration maxAutoRetryAfter;

  TokenManager get tokens => _tokens;

  // ---------------------------------------------------------------- verbs

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) => _send('GET', path, query: query, auth: auth, safeToRetry: true);

  /// [bearer] sends that access token as is (with `auth: false`: no
  /// refresh, no 401 retry), e.g. to revoke a session that is being left.
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    bool auth = true,
    String? idempotencyKey,
    String? bearer,
  }) => _send(
    'POST',
    path,
    body: body ?? const <String, dynamic>{},
    auth: auth,
    idempotencyKey: idempotencyKey,
    bearer: bearer,
    safeToRetry: idempotencyKey != null,
  );

  Future<Map<String, dynamic>> put(
    String path, {
    Object? body,
    bool auth = true,
  }) => _send('PUT', path, body: body, auth: auth);

  Future<Map<String, dynamic>> delete(String path, {bool auth = true}) =>
      _send('DELETE', path, auth: auth);

  /// `POST /auth/refresh` without the auth interceptor.
  Future<AuthResponse> refreshTokens(String refreshToken) async {
    final json = await _send(
      'POST',
      '/auth/refresh',
      body: {'refreshToken': refreshToken},
      auth: false,
      client: _bare,
    );
    return AuthResponse.fromJson(json);
  }

  // ------------------------------------------------------------- internals

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool auth = true,
    String? idempotencyKey,
    String? bearer,
    bool safeToRetry = false,
    Dio? client,
  }) async {
    final dio = client ?? _dio;
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final res = await dio.request<Object?>(
          path,
          data: body,
          queryParameters: query,
          options: Options(
            method: method,
            headers: {
              'Idempotency-Key': ?idempotencyKey,
              'Authorization': ?(bearer == null ? null : 'Bearer $bearer'),
            },
            extra: {'auth': auth},
          ),
        );
        final data = res.data;
        if (data is Map) return data.cast<String, dynamic>();
        return const <String, dynamic>{};
      } on DioException catch (e) {
        final mapped = mapDioException(e);
        if (mapped.code == 'update_required') {
          _policy.notify(PolicySignalReason.restUpdateRequired);
        } else if (mapped.status == 503 && mapped.code == 'maintenance') {
          _policy.notify(PolicySignalReason.restMaintenance);
        }
        final wait = mapped.retryAfter;
        if (mapped.status == 429 &&
            safeToRetry &&
            attempt == 1 &&
            wait != null &&
            wait <= maxAutoRetryAfter) {
          await _delay(wait);
          continue;
        }
        throw mapped;
      }
    }
  }

  /// Maps any Dio failure to an [ApiException].
  static ApiException mapDioException(DioException e) {
    final inner = e.error;
    if (inner is ApiException) return inner;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException.timeout();
      case DioExceptionType.cancel:
        return const ApiException(code: ClientErrorCodes.cancelled, status: 0);
      case DioExceptionType.connectionError:
        return ApiException.network(e.message ?? '');
      case DioExceptionType.badCertificate:
        return const ApiException.network('bad certificate');
      case DioExceptionType.badResponse:
        return _fromResponse(e.response);
      case DioExceptionType.unknown:
        if (inner is SocketException) {
          return ApiException.network(inner.message);
        }
        if (e.response != null) return _fromResponse(e.response);
        return ApiException.network(e.message ?? '');
    }
  }

  static ApiException _fromResponse(Response<Object?>? res) {
    final status = res?.statusCode ?? 0;
    final data = res?.data;
    var code = _defaultCodeFor(status);
    var message = '';
    var details = const <String, dynamic>{};
    if (data is Map && data['error'] is Map) {
      final err = (data['error'] as Map).cast<String, dynamic>();
      if (err['code'] is String && (err['code'] as String).isNotEmpty) {
        code = err['code'] as String;
      }
      if (err['message'] is String) message = err['message'] as String;
      if (err['details'] is Map) {
        details = (err['details'] as Map).cast<String, dynamic>();
      }
    }
    return ApiException(
      code: code,
      status: status,
      message: message,
      details: details,
      retryAfter: parseRetryAfter(res?.headers.value('retry-after')),
    );
  }

  static String _defaultCodeFor(int status) => switch (status) {
    400 => 'bad_request',
    401 => 'unauthorized',
    403 => 'forbidden',
    404 => 'not_found',
    426 => 'update_required',
    429 => 'rate_limited',
    503 => 'maintenance',
    >= 500 => 'internal',
    _ => ClientErrorCodes.badResponse,
  };

  /// `Retry-After` is either delta-seconds or an HTTP date.
  static Duration? parseRetryAfter(String? raw, [DateTime? now]) {
    if (raw == null || raw.trim().isEmpty) return null;
    final secs = int.tryParse(raw.trim());
    if (secs != null) return Duration(seconds: secs < 0 ? 0 : secs);
    try {
      final at = HttpDate.parse(raw.trim());
      final d = at.difference(now ?? DateTime.now());
      return d.isNegative ? Duration.zero : d;
    } catch (_) {
      return null;
    }
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);

  final ApiClient _client;

  bool _wantsAuth(RequestOptions o) => o.extra['auth'] != false;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_wantsAuth(options)) return handler.next(options);
    try {
      final token = await _client.tokens.validAccessToken();
      if (token == null) {
        return handler.reject(
          DioException(
            requestOptions: options,
            error: const ApiException(code: 'unauthorized', status: 401),
            type: DioExceptionType.unknown,
          ),
        );
      }
      options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    } on ApiException catch (e) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: e,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final o = err.requestOptions;
    final status = err.response?.statusCode;
    if (status != 401 || !_wantsAuth(o) || o.extra['retried'] == true) {
      return handler.next(err);
    }
    final sent = (o.headers['Authorization'] as String?)?.replaceFirst(
      'Bearer ',
      '',
    );
    try {
      final ok = await _client.tokens.recoverFrom401(sent);
      final token = _client.tokens.accessToken;
      if (!ok || token == null) return handler.next(err);
      o.headers['Authorization'] = 'Bearer $token';
      o.extra['retried'] = true;
      final res = await _client._dio.fetch<Object?>(o);
      handler.resolve(res);
    } on DioException catch (e) {
      handler.next(e);
    } on ApiException catch (e) {
      handler.next(
        DioException(
          requestOptions: o,
          error: e,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }
}

// ------------------------------------------------------------- providers

final tokenManagerProvider = Provider<TokenManager>((ref) {
  final m = TokenManager(
    store: ref.watch(secureSessionStoreProvider),
    clock: ref.watch(serverClockProvider),
  );
  ref.onDispose(m.dispose);
  return m;
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    config: ref.watch(appConfigProvider),
    info: ref.watch(appInfoProvider),
    tokens: ref.watch(tokenManagerProvider),
    policySignals: ref.watch(policySignalBusProvider),
    languageCode: () => ref.read(languageControllerProvider).languageCode,
  ),
);
