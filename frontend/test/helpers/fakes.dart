import 'dart:async';

import 'package:ludo_royale/core/analytics/analytics_service.dart';
import 'package:ludo_royale/core/analytics/noop_analytics_service.dart';
import 'package:ludo_royale/core/device/device_identity.dart';
import 'package:ludo_royale/core/network/api_models.dart';
import 'package:ludo_royale/features/app_update/application/store_launcher.dart';
import 'package:ludo_royale/features/authentication/data/provider_credential.dart';
import 'package:ludo_royale/features/authentication/identity/identity_provider_client.dart';

/// Identity provider that returns a scripted credential (or cancels/fails).
class FakeIdentityClient implements IdentityProviderClient {
  FakeIdentityClient(this.provider, {this.available = true});

  @override
  final LinkedProvider provider;
  bool available;

  /// Marker: return the provider's default test credential.
  static const Object useDefault = Object();

  /// Next result: a credential, `null` (cancelled), an exception to throw,
  /// or [useDefault].
  Object? next = useDefault;
  int calls = 0;
  int signOuts = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<ProviderCredential?> obtainCredential() async {
    calls++;
    final n = next;
    if (n is Exception) throw n;
    if (n is ProviderCredential) return n;
    if (!identical(n, useDefault)) return null;
    return switch (provider) {
      LinkedProvider.google => const GoogleCredential(idToken: 'google-id'),
      LinkedProvider.facebook => const FacebookCredential.classic(
        accessToken: 'fb-token',
      ),
      _ => const AppleCredential(identityToken: 'apple-id', rawNonce: 'raw'),
    };
  }

  @override
  Future<void> signOut() async => signOuts++;
}

/// Device id source; `null` (the default) = a device without an id, which
/// keeps the pre-device-binding behaviour.
class FakeDeviceIdentity implements DeviceIdentity {
  FakeDeviceIdentity([this.id]);

  String? id;
  int calls = 0;

  @override
  Future<String?> deviceId() async {
    calls++;
    return id;
  }
}

/// Records analytics calls by name.
class RecordingAnalytics extends NoopAnalyticsService {
  RecordingAnalytics();

  final List<String> events = [];
  String? actor;

  /// The actor type when `account_deleted` was logged (must still be
  /// `human`: the event is sent before the session is cleared).
  String? actorAtAccountDeleted;

  @override
  void setActorType(String? actorType) => actor = actorType;
  @override
  void loginStarted(LoginMethod method) =>
      events.add('login_started:${method.name}');
  @override
  void loginSucceeded(LoginMethod method) =>
      events.add('login_succeeded:${method.name}');
  @override
  void loginFailed(LoginMethod method) =>
      events.add('login_failed:${method.name}');
  @override
  void guestLoginSucceeded() => events.add('guest_login_succeeded');
  @override
  void accountLinkSucceeded(LoginMethod method) =>
      events.add('account_link_succeeded:${method.name}');
  @override
  void accountDeleted() {
    actorAtAccountDeleted = actor;
    events.add('account_deleted');
  }

  @override
  void displayNameChanged() => events.add('display_name_changed');
  @override
  void appUpdatePromptShown(String mode) =>
      events.add('app_update_prompt_shown:$mode');
  @override
  void themeChanged(String mode) => events.add('theme_changed:$mode');
  @override
  void languageChanged(String locale) => events.add('language_changed:$locale');
  @override
  void settingsChanged(String setting, bool enabled) =>
      events.add('settings_changed:$setting:$enabled');
  @override
  void levelUp(int level) => events.add('level_up:$level');
}

/// Store launcher that records URLs.
class FakeStoreLauncher implements StoreLauncher {
  final List<String> opened = [];
  bool result = true;

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return result;
  }
}

/// Mutable clock for throttling tests.
class FakeClock {
  FakeClock([DateTime? start]) : now = start ?? DateTime(2026, 10, 21, 12);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// A connector that never connects (keeps widget tests free of sockets).
Future<T> never<T>() => Completer<T>().future;
