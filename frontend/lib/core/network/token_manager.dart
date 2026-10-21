import 'dart:async';

import '../storage/secure_session_store.dart';
import '../time/server_clock.dart';
import 'api_exception.dart';
import 'api_models.dart';

/// Performs `POST /auth/refresh` (implemented by the ApiClient with a bare
/// Dio so the refresh call never recurses through the auth interceptor).
typedef RefreshCall = Future<AuthResponse> Function(String refreshToken);

/// Why the server ended the session.
enum SessionEnd {
  /// Expired, revoked or reused refresh token.
  expired,

  /// The account signed in on another device (`session_replaced`): only one
  /// device may be signed in at a time.
  replaced,
}

/// Owns the in-memory copy of the session tokens, persists rotations to
/// [SecureSessionStore], and runs a **single-flight** refresh: concurrent
/// 401s / expiring tokens share one `POST /auth/refresh`.
class TokenManager {
  TokenManager({required this._store, required this._clock});

  final SecureSessionStore _store;
  final ServerClock _clock;

  /// Wired by the provider graph (see `api_client.dart`).
  RefreshCall? refreshCall;

  StoredTokens? _tokens;
  Future<AuthResponse?>? _inflight;
  int _generation = 0;

  final _refreshed = StreamController<AuthResponse>.broadcast();
  final _expired = StreamController<SessionEnd>.broadcast();
  SessionEnd? _lastEnd;

  /// Emits every successful refresh (carries fresh `user` + `wallet`).
  Stream<AuthResponse> get onRefreshed => _refreshed.stream;

  /// Emits when the server rejected the refresh token (session over).
  Stream<SessionEnd> get onExpired => _expired.stream;

  /// Why the last session ended (null while a session is held or after a
  /// local logout).
  SessionEnd? get lastEnd => _lastEnd;

  bool get hasSession => _tokens != null;
  String? get accessToken => _tokens?.accessToken;
  String? get refreshToken => _tokens?.refreshToken;

  /// Loads persisted tokens (startup).
  Future<void> load() async {
    _tokens = await _store.readTokens();
  }

  /// Stores tokens from an [AuthResponse] (login, guest, refresh).
  Future<void> adopt(AuthResponse r) async {
    _generation++;
    _lastEnd = null;
    final t = StoredTokens(
      accessToken: r.accessToken,
      accessExpiresAt: r.accessTokenExpiresAt,
      refreshToken: r.refreshToken,
      refreshExpiresAt: r.refreshTokenExpiresAt,
    );
    _tokens = t;
    await _store.writeTokens(t);
  }

  /// Forgets the session (logout / revoked). Any in-flight refresh result is
  /// discarded.
  Future<void> clear() async {
    _generation++;
    _lastEnd = null;
    _tokens = null;
    _inflight = null;
    await _store.clearTokens();
  }

  bool accessValidFor(Duration margin) {
    final t = _tokens;
    if (t == null || t.accessToken.isEmpty) return false;
    return t.accessExpiresAt - _clock.nowMs() > margin.inMilliseconds;
  }

  /// Returns an access token valid for at least [minValidity], refreshing if
  /// needed. `null` when there is no session (or it was rejected). Throws
  /// [ApiException] on transient failures (network, maintenance…).
  Future<String?> validAccessToken({
    Duration minValidity = const Duration(seconds: 60),
  }) async {
    if (_tokens == null) return null;
    if (accessValidFor(minValidity)) return _tokens!.accessToken;
    final r = await refreshNow();
    return r == null ? null : _tokens?.accessToken;
  }

  /// After a 401 for a request sent with [staleAccessToken]: true when a
  /// newer token is available (someone else already refreshed, or this call
  /// refreshed), false when the session is over.
  Future<bool> recoverFrom401(String? staleAccessToken) async {
    final current = _tokens?.accessToken;
    if (current != null &&
        staleAccessToken != null &&
        current != staleAccessToken &&
        accessValidFor(const Duration(seconds: 5))) {
      return true;
    }
    return await refreshNow() != null;
  }

  /// Single-flight `POST /auth/refresh`. Returns the response, or `null` when
  /// there is no session or the server rejected the refresh token (tokens are
  /// then cleared and [onExpired] fires). Throws [ApiException] for transient
  /// failures without touching the stored tokens.
  Future<AuthResponse?> refreshNow() {
    final existing = _inflight;
    if (existing != null) return existing;
    final t = _tokens;
    final call = refreshCall;
    if (t == null || call == null) return Future.value(null);

    final generation = _generation;
    final future = _doRefresh(call, t.refreshToken, generation);
    _inflight = future;
    return future.whenComplete(() {
      if (identical(_inflight, future)) _inflight = null;
    });
  }

  Future<AuthResponse?> _doRefresh(
    RefreshCall call,
    String refreshToken,
    int generation,
  ) async {
    try {
      final r = await call(refreshToken);
      if (generation != _generation) return null; // logged out meanwhile
      await adopt(r);
      _refreshed.add(r);
      return r;
    } on ApiException catch (e) {
      if (generation != _generation) return null;
      final terminal =
          e.status == 401 ||
          e.status == 403 ||
          e.code == 'refresh_reused' ||
          e.code == 'session_replaced' ||
          e.code == 'unauthorized' ||
          e.code == 'invalid_credential';
      if (terminal) {
        await clear();
        final end = e.code == 'session_replaced'
            ? SessionEnd.replaced
            : SessionEnd.expired;
        _lastEnd = end;
        _expired.add(end);
        return null;
      }
      rethrow;
    }
  }

  void dispose() {
    _refreshed.close();
    _expired.close();
  }
}
