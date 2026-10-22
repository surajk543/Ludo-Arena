import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ludo_arena/core/analytics/analytics_providers.dart';
import 'package:ludo_arena/core/app_policy/policy_signal.dart';
import 'package:ludo_arena/core/assets/profile_picture_cache.dart';
import 'package:ludo_arena/core/audio_haptics/audio_service.dart';
import 'package:ludo_arena/core/config/app_config.dart';
import 'package:ludo_arena/core/config/app_info.dart';
import 'package:ludo_arena/core/device/device_identity.dart';
import 'package:ludo_arena/core/lifecycle/app_lifecycle.dart';
import 'package:ludo_arena/core/localization/language_controller.dart';
import 'package:ludo_arena/core/network/api_client.dart';
import 'package:ludo_arena/core/realtime/realtime_providers.dart';
import 'package:ludo_arena/core/realtime/realtime_socket.dart';
import 'package:ludo_arena/core/storage/preferences_store.dart';
import 'package:ludo_arena/core/storage/secure_session_store.dart';
import 'package:ludo_arena/core/time/server_clock.dart';
import 'package:ludo_arena/features/app_update/application/store_launcher.dart';
import 'package:ludo_arena/features/authentication/identity/identity_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_backend.dart';
import 'fakes.dart';
import 'picture_fixtures.dart';

/// Everything a test needs to drive the real controllers against fakes at
/// the HTTP / SDK boundary.
class TestEnv {
  TestEnv._({
    required this.prefs,
    required this.secure,
    required this.platform,
    required this.analyticsBackend,
  });

  final FakeBackend backend = FakeBackend();
  final RecordingAnalytics analytics = RecordingAnalytics();
  final FakeClock clock = FakeClock();
  final FakeStoreLauncher store = FakeStoreLauncher();

  /// Records every effect / music call of the screens under test.
  final SilentAudioService audio = SilentAudioService();

  /// Profile pictures: none resolve unless a test adds them to `ready`.
  final FakeProfilePictureCache pictures = FakeProfilePictureCache();

  /// Store emote art: none resolves unless a test adds it to `ready`.
  final FakeProfilePictureCache emotes = FakeProfilePictureCache();

  /// No device id by default (behaves like before device binding); set
  /// `device.id` to simulate an Android 8+ / iOS device.
  final FakeDeviceIdentity device = FakeDeviceIdentity();

  /// WebSocket connector for the realtime connection; by default sockets
  /// never connect.
  WebSocketConnector? wsConnector;
  final PreferencesStore prefs;
  final InMemorySecureKeyValue secure;
  final String platform;
  final AnalyticsBackend? analyticsBackend;
  late final Map<LinkedProvider, FakeIdentityClient> identity = {
    LinkedProvider.google: FakeIdentityClient(LinkedProvider.google),
    LinkedProvider.facebook: FakeIdentityClient(
      LinkedProvider.facebook,
      available: false,
    ),
    LinkedProvider.apple: FakeIdentityClient(
      LinkedProvider.apple,
      available: platform == 'ios',
    ),
  };

  static Future<TestEnv> create({
    Map<String, Object> prefs = const {},
    Map<String, String> secure = const {},
    String platform = 'android',
    AnalyticsBackend? analyticsBackend,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    return TestEnv._(
      prefs: PreferencesStore(await SharedPreferences.getInstance()),
      secure: InMemorySecureKeyValue(secure),
      platform: platform,
      analyticsBackend: analyticsBackend,
    );
  }

  /// Stores a session as if a previous launch had signed in.
  void seedSession({bool guest = true, String? guestSecret = 'gs_1'}) {
    secure.values.addAll({
      'session.access_token': 'old-at',
      'session.access_expires_at': '1',
      'session.refresh_token': 'old-rt',
      'session.refresh_expires_at': '4102444800000',
      'session.last_was_guest': guest ? '1' : '0',
      'session.guest_secret': ?guestSecret,
    });
  }

  /// Default happy-path routes.
  void routeHappyPath({String mode = 'normal'}) {
    backend
      ..json('GET', '/app/config', policyJson(mode: mode))
      ..json('POST', '/auth/refresh', authJson())
      ..json(
        'POST',
        '/auth/guest',
        authJson(guestSecret: 'gs_new'),
        status: 201,
      )
      ..json('POST', '/auth/guest/resume', authJson())
      ..json('GET', '/me', meJson())
      ..json('POST', '/auth/logout', const {}, status: 204)
      ..json('PUT', '/account/device', const {})
      ..json('DELETE', '/account/device', const {}, status: 204);
  }

  List<Override> get overrides => [
    preferencesStoreProvider.overrideWithValue(prefs),
    secureKeyValueProvider.overrideWithValue(secure),
    appInfoProvider.overrideWithValue(
      AppInfo(platform: platform, version: '1.0.0', build: 1),
    ),
    appConfigProvider.overrideWithValue(
      const AppConfig(
        apiBaseUrl: 'http://test.local',
        environment: AppEnvironment.development,
        googleServerClientId: 'server-client-id',
        googleIosClientId: 'ios-client-id',
      ),
    ),
    apiClientProvider.overrideWith(
      (ref) => ApiClient(
        config: ref.watch(appConfigProvider),
        info: ref.watch(appInfoProvider),
        tokens: ref.watch(tokenManagerProvider),
        policySignals: ref.watch(policySignalBusProvider),
        adapter: backend,
        delay: (_) async {},
      ),
    ),
    identityProviderClientsProvider.overrideWithValue(identity),
    deviceIdentityProvider.overrideWithValue(device),
    analyticsServiceProvider.overrideWithValue(analytics),
    analyticsBackendProvider.overrideWithValue(analyticsBackend),
    audioServiceProvider.overrideWithValue(audio),
    clockProvider.overrideWithValue(clock.call),
    storeLauncherProvider.overrideWithValue(store),
    deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
    // No file system or network for profile pictures in widget tests.
    profilePictureCacheProvider.overrideWithValue(pictures),
    emoteAssetCacheProvider.overrideWithValue(emotes),
    realtimeConnectionProvider.overrideWith((ref) {
      final c = RealtimeConnection(
        uri: Uri.parse('ws://test.local/api/v1/ws'),
        appHeaders: const {},
        accessToken: () async => 'at',
        refreshSession: () async => true,
        connector: wsConnector ?? (uri, headers) => never(),
        onAccountDeleted: ref.watch(accountDeletedSignalProvider).notify,
        lifecycle: ref.watch(appLifecycleProvider),
        onStatus: (s) {
          try {
            ref.read(realtimeStatusProvider.notifier).set(s);
          } catch (_) {}
        },
      );
      ref.onDispose(c.dispose);
      return c;
    }),
  ];

  ProviderContainer container({List<Override> extra = const []}) {
    final c = ProviderContainer(
      overrides: [...overrides, ...extra],
      retry: (_, _) => null,
    );
    return c;
  }
}

/// Lets fire-and-forget futures (e.g. best-effort revokes) complete.
Future<void> settle([int turns = 30]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
