import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../storage/secure_session_store.dart';

/// A per-device id that survives app updates and reinstalls, used only to
/// bring a reinstalled app back to its account (`POST /auth/device/resume`,
/// `POST /auth/guest`, `PUT /account/device`).
///
/// It is sent in request bodies only: never logged, never sent to
/// analytics, never put in a URL.
abstract interface class DeviceIdentity {
  /// The device id, or `null` when this device has none (the app then keeps
  /// the guest-secret behaviour).
  Future<String?> deviceId();
}

/// - Android 8+ (API 26): `Settings.Secure.ANDROID_ID`, which is scoped to
///   the app signing key and survives reinstalls. Before Android 8 the value
///   is shared with every app, so it is not used (`null`).
/// - iOS: a random UUID v4 kept in the keychain (`session.device_id`,
///   accessible after first unlock, this device only), which survives
///   updates and reinstalls on the same device. `identifierForVendor` is not
///   used: it changes on reinstall.
/// - Anything else: `null`.
class PlatformDeviceIdentity implements DeviceIdentity {
  PlatformDeviceIdentity({
    required this._store,
    String? platform,
    this._channel = const MethodChannel(channelName),
    String Function()? newId,
  }) : _platform = platform ?? _currentPlatform(),
       _newId = newId ?? (() => const Uuid().v4());

  static const channelName = 'ludo_royale/device_id';

  final SecureSessionStore _store;
  final String _platform;
  final MethodChannel _channel;
  final String Function() _newId;

  String? _cached;
  Future<String?>? _inflight;

  static String _currentPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  @override
  Future<String?> deviceId() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    // Single flight: two concurrent first calls on iOS must not generate
    // two different ids.
    return _inflight ??= _load().then((id) {
      _cached = id;
      _inflight = null;
      return id;
    });
  }

  Future<String?> _load() async {
    switch (_platform) {
      case 'android':
        try {
          final raw = await _channel.invokeMethod<String>('androidId');
          return normalizeAndroidId(raw);
        } on PlatformException {
          return null;
        } on MissingPluginException {
          return null;
        }
      case 'ios':
        try {
          final stored = await _store.readDeviceId();
          if (stored != null && isValidDeviceId(stored)) return stored;
          final id = _newId();
          await _store.writeDeviceId(id);
          // Only use an id that was actually persisted: an id that changes
          // on every launch would bind a new account each time.
          return await _store.readDeviceId() == id ? id : null;
        } catch (_) {
          return null;
        }
      default:
        return null;
    }
  }

  /// Known-bad ANDROID_ID shipped by many pre-release / emulator builds.
  static const _badAndroidId = '9774d56d682e549c';

  /// Lower-cased, zero-padded to 16 hex digits (older Android versions drop
  /// leading zeros); `null` for missing, all-zero or known-bad values.
  @visibleForTesting
  static String? normalizeAndroidId(String? raw) {
    if (raw == null) return null;
    var id = raw.trim().toLowerCase();
    if (id.isEmpty || !RegExp(r'^[0-9a-f]{1,64}$').hasMatch(id)) return null;
    if (RegExp(r'^0+$').hasMatch(id) || id == _badAndroidId) return null;
    if (id.length < 16) id = id.padLeft(16, '0');
    return isValidDeviceId(id) ? id : null;
  }

  /// The server accepts 16–64 characters of `[A-Za-z0-9-]`.
  static bool isValidDeviceId(String id) =>
      RegExp(r'^[A-Za-z0-9-]{16,64}$').hasMatch(id);
}

/// Overridden in tests with a fake.
final deviceIdentityProvider = Provider<DeviceIdentity>(
  (ref) => PlatformDeviceIdentity(store: ref.watch(secureSessionStoreProvider)),
);
