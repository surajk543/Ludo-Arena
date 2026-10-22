import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deployment environment (`APP_ENV`). Must match the backend's policy file.
enum AppEnvironment {
  development,
  preproduction,
  production;

  static AppEnvironment parse(String raw) => switch (raw.trim().toLowerCase()) {
    'production' || 'prod' => AppEnvironment.production,
    'preproduction' || 'preprod' || 'staging' => AppEnvironment.preproduction,
    _ => AppEnvironment.development,
  };
}

/// Firebase options for **Analytics only**, supplied through
/// `--dart-define-from-file=config/firebase.json` (gitignored). When any
/// required value is missing analytics runs as a no-op.
@immutable
class FirebaseAnalyticsConfig {
  const FirebaseAnalyticsConfig({
    required this.apiKey,
    required this.projectId,
    required this.messagingSenderId,
    required this.androidAppId,
    required this.iosAppId,
    this.iosApiKey = '',
    this.storageBucket = '',
  });

  final String apiKey;
  final String projectId;
  final String messagingSenderId;
  final String androidAppId;
  final String iosAppId;
  final String iosApiKey;
  final String storageBucket;

  /// The Firebase app id for [platform] (`android` | `ios`), or empty.
  String appIdFor(String platform) =>
      platform == 'ios' ? iosAppId : androidAppId;

  String apiKeyFor(String platform) =>
      platform == 'ios' && iosApiKey.isNotEmpty ? iosApiKey : apiKey;

  bool isCompleteFor(String platform) =>
      apiKeyFor(platform).isNotEmpty &&
      projectId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      appIdFor(platform).isNotEmpty &&
      !apiKeyFor(platform).startsWith('REPLACE_') &&
      !appIdFor(platform).startsWith('REPLACE_');

  /// Public, non-secret identifiers of the `ludo-royale-63887` Firebase
  /// project (Analytics only). API keys are NEVER committed: they come only
  /// from the gitignored `config/firebase.json`. Without an API key the app
  /// runs with no-op analytics.
  static const String defaultProjectId = 'ludo-royale-63887';
  static const String defaultMessagingSenderId = '124893613050';
  static const String defaultAndroidAppId =
      '1:124893613050:android:872c7caa8077bf3a827243';
  static const String defaultIosAppId =
      '1:124893613050:ios:cc3be63d4c1725dd827243';

  static const FirebaseAnalyticsConfig fromEnvironment =
      FirebaseAnalyticsConfig(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        projectId: String.fromEnvironment(
          'FIREBASE_PROJECT_ID',
          defaultValue: defaultProjectId,
        ),
        messagingSenderId: String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
          defaultValue: defaultMessagingSenderId,
        ),
        androidAppId: String.fromEnvironment(
          'FIREBASE_ANDROID_APP_ID',
          defaultValue: defaultAndroidAppId,
        ),
        iosAppId: String.fromEnvironment(
          'FIREBASE_IOS_APP_ID',
          defaultValue: defaultIosAppId,
        ),
        iosApiKey: String.fromEnvironment('FIREBASE_IOS_API_KEY'),
        storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      );
}

/// Build-time configuration from `--dart-define`. Provider client ids are
/// public identifiers; no secrets are ever compiled into the app.
@immutable
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.environment,
    this.googleServerClientId = '',
    this.googleIosClientId = '',
    this.appleServiceId = '',
    this.appleRedirectUri = '',
    this.facebookEnabled = false,
    this.firebase,
    this.legalNoticesUrlOverride = '',
  });

  /// Base URL without the `/api/v1` suffix, e.g. `http://10.0.2.2:8080`.
  final String apiBaseUrl;
  final AppEnvironment environment;

  /// OAuth "web" client id the backend validates as the ID token audience
  /// (Android: required to receive an ID token).
  final String googleServerClientId;

  /// iOS OAuth client id (its reversed form goes in ios/Flutter/*.xcconfig).
  final String googleIosClientId;

  /// Apple Services ID used by the Android web flow.
  final String appleServiceId;

  /// Redirect URI registered for [appleServiceId] (the backend's
  /// `/api/v1/auth/apple/callback`).
  final String appleRedirectUri;

  /// Facebook login is shown only when explicitly enabled.
  final bool facebookEnabled;

  final FirebaseAnalyticsConfig? firebase;

  /// `LEGAL_NOTICES_URL`; empty means [defaultLegalNoticesUrl].
  final String legalNoticesUrlOverride;

  /// The published open-source notices page on the studio website.
  static const String defaultLegalNoticesUrl =
      'https://sungamestudio.com/ludo-arena/legal/';

  /// Public OAuth client ids (Google Cloud project `ludo-royale-63887`).
  /// The web ("server") client id is the ID-token audience the backend
  /// validates; Android has its own OAuth client (package + SHA-1) and needs
  /// no id in code. Override per build with `--dart-define`.
  static const String defaultGoogleServerClientId =
      '124893613050-93on2291jjunnk5u95lcpk15pk6vgr6c.apps.googleusercontent.com';
  static const String defaultGoogleIosClientId =
      '124893613050-etb8okpenf0il17tmb33pr3cet8s9jba.apps.googleusercontent.com';

  static const String _apiBaseUrlDefine = String.fromEnvironment(
    'API_BASE_URL',
  );
  static const String _envDefine = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// The production backend (nginx + TLS on the game VPS, `deploy/`).
  static const String productionApiBaseUrl = 'https://ludo.sungamestudio.com';

  /// Base URL when `API_BASE_URL` is not supplied: production builds use
  /// [productionApiBaseUrl], every other environment the local backend
  /// (the Android emulator reaches the host at `10.0.2.2`).
  static String defaultApiBaseUrl(
    AppEnvironment environment, {
    required bool android,
  }) => environment == AppEnvironment.production
      ? productionApiBaseUrl
      : (android ? 'http://10.0.2.2:8080' : 'http://localhost:8080');

  /// Sign in with Apple on Android (Apple's web flow): the Services ID and the
  /// backend callback registered as its return URL in the Apple developer
  /// account.
  static const String productionAppleServiceId = 'com.ludoarena.app.signin';
  static const String productionAppleRedirectUri =
      '$productionApiBaseUrl/api/v1/auth/apple/callback';

  /// `APPLE_SERVICE_ID` when not supplied: production builds use
  /// [productionAppleServiceId]; elsewhere Apple stays off on Android.
  static String defaultAppleServiceId(AppEnvironment environment) =>
      environment == AppEnvironment.production ? productionAppleServiceId : '';

  /// `APPLE_REDIRECT_URI` when not supplied (see [defaultAppleServiceId]).
  static String defaultAppleRedirectUri(AppEnvironment environment) =>
      environment == AppEnvironment.production
      ? productionAppleRedirectUri
      : '';

  /// Reads the `--dart-define` values; see [defaultApiBaseUrl],
  /// [defaultAppleServiceId] and [defaultAppleRedirectUri] for the values
  /// used when they are not supplied.
  factory AppConfig.fromEnvironment({bool? isAndroid}) {
    final android = isAndroid ?? (!kIsWeb && Platform.isAndroid);
    final environment = AppEnvironment.parse(_envDefine);
    final base = _apiBaseUrlDefine.isNotEmpty
        ? _apiBaseUrlDefine
        : defaultApiBaseUrl(environment, android: android);
    const appleServiceId = String.fromEnvironment('APPLE_SERVICE_ID');
    const appleRedirectUri = String.fromEnvironment('APPLE_REDIRECT_URI');
    return AppConfig(
      apiBaseUrl: normalizeBaseUrl(base),
      environment: environment,
      googleServerClientId: const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID',
        defaultValue: defaultGoogleServerClientId,
      ),
      googleIosClientId: const String.fromEnvironment(
        'GOOGLE_IOS_CLIENT_ID',
        defaultValue: defaultGoogleIosClientId,
      ),
      appleServiceId: appleServiceId.isNotEmpty
          ? appleServiceId
          : defaultAppleServiceId(environment),
      appleRedirectUri: appleRedirectUri.isNotEmpty
          ? appleRedirectUri
          : defaultAppleRedirectUri(environment),
      facebookEnabled: const bool.fromEnvironment('FACEBOOK_ENABLED'),
      firebase: FirebaseAnalyticsConfig.fromEnvironment,
      legalNoticesUrlOverride: const String.fromEnvironment(
        'LEGAL_NOTICES_URL',
      ).trim(),
    );
  }

  /// Strips trailing slashes and an accidental `/api/v1` suffix.
  static String normalizeBaseUrl(String raw) {
    var s = raw.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('/api/v1')) s = s.substring(0, s.length - '/api/v1'.length);
    return s;
  }

  /// Open-source notices page, opened in the external browser from
  /// Settings > About. Defaults to the studio website
  /// ([defaultLegalNoticesUrl]); `LEGAL_NOTICES_URL` overrides it (e.g. the
  /// backend's `GET /legal/open-source` as a fallback).
  String get legalNoticesUrl => legalNoticesUrlOverride.isNotEmpty
      ? legalNoticesUrlOverride
      : defaultLegalNoticesUrl;

  /// REST root, e.g. `http://10.0.2.2:8080/api/v1`.
  String get apiV1 => '$apiBaseUrl/api/v1';

  /// WebSocket endpoint (`ws://` / `wss://`).
  Uri get webSocketUri {
    final base = Uri.parse(apiBaseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/api/v1/ws',
    );
  }

  bool get isProduction => environment == AppEnvironment.production;

  /// Google needs the server client id on every platform (it is the ID token
  /// audience) and the iOS client id on iOS.
  bool googleEnabledFor(String platform) =>
      googleServerClientId.isNotEmpty &&
      (platform != 'ios' || googleIosClientId.isNotEmpty);

  /// Apple: native on iOS; on Android only with a configured web flow.
  bool appleEnabledFor(String platform) =>
      platform == 'ios' ||
      (platform == 'android' &&
          appleServiceId.isNotEmpty &&
          appleRedirectUri.isNotEmpty);

  bool get facebookAvailable => facebookEnabled;
}

/// Overridden in `bootstrap.dart` (and in tests).
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
