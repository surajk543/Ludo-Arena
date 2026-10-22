import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/device/device_identity.dart';
import 'package:ludo_arena/core/storage/secure_session_store.dart';

class _FailingKeyValue implements SecureKeyValue {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) =>
      Future.error(PlatformException(code: 'keychain'));
  @override
  Future<void> delete(String key) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(PlatformDeviceIdentity.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('Android (ANDROID_ID)', () {
    test('normalizes valid values and rejects unusable ones', () {
      String? n(String? v) => PlatformDeviceIdentity.normalizeAndroidId(v);
      expect(n('ABCDEF0123456789'), 'abcdef0123456789');
      expect(n(' 3f2a9c1d0e4b5a67 '), '3f2a9c1d0e4b5a67');
      // Older Android versions drop leading zeros.
      expect(n('1a2b3c'), '00000000001a2b3c');
      expect(n(null), isNull);
      expect(n(''), isNull);
      expect(n('0000000000000000'), isNull);
      expect(n('0'), isNull);
      expect(n('9774d56d682e549c'), isNull);
      expect(n('9774D56D682E549C'), isNull);
      expect(n('not-an-android-id'), isNull);
    });

    test('reads ANDROID_ID over the channel once and caches it', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'androidId');
        return 'ABCDEF0123456789';
      });
      final identity = PlatformDeviceIdentity(
        store: SecureSessionStore(InMemorySecureKeyValue()),
        platform: 'android',
      );
      expect(await identity.deviceId(), 'abcdef0123456789');
      expect(await identity.deviceId(), 'abcdef0123456789');
      expect(calls, 1);
    });

    test('pre-Oreo (null), known-bad values and channel failures → no '
        'id', () async {
      PlatformDeviceIdentity android() => PlatformDeviceIdentity(
        store: SecureSessionStore(InMemorySecureKeyValue()),
        platform: 'android',
      );
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await android().deviceId(), isNull);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => '9774d56d682e549c',
      );
      expect(await android().deviceId(), isNull);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'boom'),
      );
      expect(await android().deviceId(), isNull);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await android().deviceId(), isNull);
    });

    test('never stores anything in secure storage', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => 'abcdef0123456789',
      );
      final kv = InMemorySecureKeyValue();
      await PlatformDeviceIdentity(
        store: SecureSessionStore(kv),
        platform: 'android',
      ).deviceId();
      expect(kv.values, isEmpty);
    });
  });

  group('iOS (keychain UUID)', () {
    test('generates a UUID v4 once and keeps it in the keychain', () async {
      final kv = InMemorySecureKeyValue();
      final identity = PlatformDeviceIdentity(
        store: SecureSessionStore(kv),
        platform: 'ios',
      );
      final id = await identity.deviceId();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
      expect(PlatformDeviceIdentity.isValidDeviceId(id!), isTrue);
      expect(kv.values['session.device_id'], id);
      // An update or reinstall on the same device reads the same keychain.
      final reinstalled = PlatformDeviceIdentity(
        store: SecureSessionStore(kv),
        platform: 'ios',
      );
      expect(await reinstalled.deviceId(), id);
    });

    test('concurrent first calls share one generated id', () async {
      var generated = 0;
      final identity = PlatformDeviceIdentity(
        store: SecureSessionStore(InMemorySecureKeyValue()),
        platform: 'ios',
        newId: () => 'generated-id-000${++generated}',
      );
      final ids = await Future.wait([identity.deviceId(), identity.deviceId()]);
      expect(ids, ['generated-id-0001', 'generated-id-0001']);
      expect(generated, 1);
    });

    test('an invalid stored value is replaced', () async {
      final kv = InMemorySecureKeyValue({'session.device_id': 'bad id'});
      final id = await PlatformDeviceIdentity(
        store: SecureSessionStore(kv),
        platform: 'ios',
        newId: () => '11111111-2222-4333-8444-555555555555',
      ).deviceId();
      expect(id, '11111111-2222-4333-8444-555555555555');
      expect(kv.values['session.device_id'], id);
    });

    test('an id that cannot be persisted is not used', () async {
      final identity = PlatformDeviceIdentity(
        store: SecureSessionStore(_FailingKeyValue()),
        platform: 'ios',
      );
      expect(await identity.deviceId(), isNull);
    });
  });

  test('other platforms have no device id', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return 'abcdef0123456789';
    });
    final identity = PlatformDeviceIdentity(
      store: SecureSessionStore(InMemorySecureKeyValue()),
      platform: 'other',
    );
    expect(await identity.deviceId(), isNull);
    expect(calls, 0);
  });
}
