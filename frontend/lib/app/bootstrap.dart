import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/analytics/analytics_providers.dart';
import '../core/analytics/firebase_bootstrap.dart';
import '../core/config/app_config.dart';
import '../core/config/app_info.dart';
import '../core/storage/preferences_store.dart';
import 'app.dart';

/// Everything that must be ready BEFORE the first frame so the user never
/// sees a flash of the wrong theme/language or of home before the gate:
/// preferences (theme, locale, settings, consent), installed version, date
/// symbols, licenses and (consent-gated) analytics.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await PreferencesStore.load();
  final info = await _loadAppInfo();
  final config = AppConfig.fromEnvironment(isAndroid: info.isAndroid);

  await initializeDateFormatting();
  _registerFontLicenses();

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

/// Bundled fonts are SIL Open Font License 1.1; show them on the licenses
/// page next to the Dart/Flutter package licenses.
void _registerFontLicenses() {
  const fonts = {
    'Fredoka': 'assets/fonts/OFL-Fredoka.txt',
    'Nunito': 'assets/fonts/OFL-Nunito.txt',
    'Baloo 2': 'assets/fonts/OFL-Baloo2.txt',
    'Baloo Bhaijaan 2': 'assets/fonts/OFL-BalooBhaijaan2.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final entry in fonts.entries) {
      try {
        final text = await rootBundle.loadString(entry.value);
        yield LicenseEntryWithLineBreaks([entry.key], text);
      } catch (_) {
        // Missing license text must never break the licenses page.
      }
    }
  });
}
