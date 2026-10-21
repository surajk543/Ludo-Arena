import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/analytics/analytics_providers.dart';
import '../core/analytics/firebase_bootstrap.dart';
import '../core/config/app_config.dart';
import '../core/config/app_info.dart';
import '../core/storage/preferences_store.dart';
import 'app.dart';
import 'error_fallback.dart';

/// Everything that must be ready BEFORE the first frame so the user never
/// sees a flash of the wrong theme/language or of home before the gate:
/// preferences (theme, locale, settings, consent), installed version, date
/// symbols, the release error fallback and (consent-gated) analytics.
///
/// Open-source notices are not shown inside the app: they are published as a
/// web page (`tool/export_oss_notices.dart`, backend `GET /legal/open-source`)
/// opened from Settings > About > Legal notices.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await PreferencesStore.load();
  final info = await _loadAppInfo();
  final config = AppConfig.fromEnvironment(isAndroid: info.isAndroid);

  await initializeDateFormatting();
  installErrorWidget();

  final consent = AnalyticsConsentController.readPersisted(prefs);
  final analyticsBackend = await initFirebaseAnalytics(
    config: config,
    info: info,
    consent: consent,
  );

  runApp(
    ProviderScope(
      // Riverpod 3 retries failing providers by default; our controllers
      // handle failures explicitly, so disable automatic retries.
      retry: (_, _) => null,
      overrides: [
        preferencesStoreProvider.overrideWithValue(prefs),
        appInfoProvider.overrideWithValue(info),
        appConfigProvider.overrideWithValue(config),
        analyticsBackendProvider.overrideWithValue(analyticsBackend),
      ],
      child: const LudoRoyaleApp(),
    ),
  );
}

Future<AppInfo> _loadAppInfo() async {
  try {
    return await AppInfo.load();
  } catch (e) {
    debugPrint('bootstrap: package info unavailable ($e)');
    return AppInfo(
      platform: AppInfo.currentPlatform(),
      version: '1.0.0',
      build: 1,
    );
  }
}
