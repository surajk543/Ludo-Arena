import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key/value contract so the session store can be faked in tests.
abstract interface class SecureKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Keychain (iOS) / Keystore-backed (Android) storage.
class FlutterSecureKeyValue implements SecureKeyValue {
  FlutterSecureKeyValue([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory implementation for tests.
class InMemorySecureKeyValue implements SecureKeyValue {
  InMemorySecureKeyValue([Map<String, String>? initial])
    : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Access/refresh tokens and their expiries (unix ms, server clock).
@immutable
class StoredTokens {
  const StoredTokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  final String accessToken;
  final int accessExpiresAt;
  final String refreshToken;
  final int refreshExpiresAt;
}

/// The ONLY place session credentials live: access token, refresh token,
/// their expiries, the guest secret, the iOS device id and the session
/// flags that decide whether the app may sign in on its own. Nothing here
/// ever goes to SharedPreferences, logs or analytics.
class SecureSessionStore {
  SecureSessionStore(this._kv);

  final SecureKeyValue _kv;

  static const _access = 'session.access_token';
  static const _accessExp = 'session.access_expires_at';
  static const _refresh = 'session.refresh_token';
  static const _refreshExp = 'session.refresh_expires_at';
  static const _guestSecret = 'session.guest_secret';
  static const _lastWasGuest = 'session.last_was_guest';
  static const _deviceId = 'session.device_id';
  static const _deviceBoundUid = 'session.device_bound_uid';
  static const _replaced = 'session.replaced';
  static const _signedOut = 'session.signed_out';

  Future<StoredTokens?> readTokens() async {
    try {
      final refresh = await _kv.read(_refresh);
      if (refresh == null || refresh.isEmpty) return null;
      return StoredTokens(
        accessToken: await _kv.read(_access) ?? '',
        accessExpiresAt: int.tryParse(await _kv.read(_accessExp) ?? '') ?? 0,
        refreshToken: refresh,
        refreshExpiresAt: int.tryParse(await _kv.read(_refreshExp) ?? '') ?? 0,
      );
    } catch (_) {
      // A corrupted keystore entry must not crash startup.
      return null;
    }
  }

  Future<void> writeTokens(StoredTokens tokens) async {
    await _kv.write(_access, tokens.accessToken);
    await _kv.write(_accessExp, '${tokens.accessExpiresAt}');
    await _kv.write(_refresh, tokens.refreshToken);
    await _kv.write(_refreshExp, '${tokens.refreshExpiresAt}');
  }

  Future<void> clearTokens() async {
    for (final k in [_access, _accessExp, _refresh, _refreshExp]) {
      try {
        await _kv.delete(k);
      } catch (_) {}
    }
  }

  Future<String?> readGuestSecret() async {
    try {
      final v = await _kv.read(_guestSecret);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeGuestSecret(String secret) =>
      _kv.write(_guestSecret, secret);

  Future<void> clearGuestSecret() async {
    try {
      await _kv.delete(_guestSecret);
    } catch (_) {}
  }

  /// Whether the most recent session was a guest session (decides whether a
  /// failed refresh may fall back to `/auth/guest/resume`).
  Future<bool> readLastSessionWasGuest() async {
    try {
      return await _kv.read(_lastWasGuest) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> writeLastSessionWasGuest(bool guest) =>
      _kv.write(_lastWasGuest, guest ? '1' : '0');

  /// The app-generated device id (iOS only: the keychain keeps it across
  /// updates and reinstalls on the same device). Never logged or sent to
  /// analytics.
  Future<String?> readDeviceId() => _readOrNull(_deviceId);

  Future<void> writeDeviceId(String id) => _kv.write(_deviceId, id);

  /// The account (`uid`) this device was last bound to (or found bound to
  /// another account) with `PUT /account/device`, so the binding is not
  /// re-sent on every launch.
  Future<String?> readDeviceBoundUid() => _readOrNull(_deviceBoundUid);

  Future<void> writeDeviceBoundUid(String uid) =>
      _kv.write(_deviceBoundUid, uid);

  Future<void> clearDeviceBoundUid() => _deleteQuietly(_deviceBoundUid);

  /// Signed out because the account signed in on another device.
  Future<void> markSessionReplaced() => _kv.write(_replaced, '1');

  /// Signed out by the user (or the account was deleted).
  Future<void> markSignedOut() => _kv.write(_signedOut, '1');

  /// Forgets a `session_replaced` sign-out (e.g. after the account was
  /// deleted: there is no other device to explain any more).
  Future<void> clearSessionReplaced() => _deleteQuietly(_replaced);

  /// True after a `session_replaced` sign-out or a user sign-out: the app
  /// must not sign in on its own (no guest or device resume) until the user
  /// signs in explicitly.
  Future<bool> readAutoSignInBlocked() async =>
      await _readOrNull(_replaced) == '1' ||
      await _readOrNull(_signedOut) == '1';

  /// After an explicit sign-in.
  Future<void> clearAutoSignInBlock() async {
    await _deleteQuietly(_replaced);
    await _deleteQuietly(_signedOut);
  }

  Future<String?> _readOrNull(String key) async {
    try {
      final v = await _kv.read(key);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteQuietly(String key) async {
    try {
      await _kv.delete(key);
    } catch (_) {}
  }
}

final secureKeyValueProvider = Provider<SecureKeyValue>(
  (ref) => FlutterSecureKeyValue(),
);

final secureSessionStoreProvider = Provider<SecureSessionStore>(
  (ref) => SecureSessionStore(ref.watch(secureKeyValueProvider)),
);
