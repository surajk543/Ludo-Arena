import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/core/theme/app_theme.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps [child] in ProviderScope + MaterialApp (themes, localizations).
Future<Widget> buildHarness(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  List<Override> overrides = const [],
  SilentAudioService? audio,
  bool scaffold = true,
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = PreferencesStore(await SharedPreferences.getInstance());
  return ProviderScope(
    overrides: [
      audioServiceProvider.overrideWithValue(audio ?? SilentAudioService()),
      preferencesStoreProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: disableAnimations
          ? (context, w) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: w!,
            )
          : null,
      home: scaffold ? Scaffold(body: child) : child,
    ),
  );
}

/// Sets a phone-sized logical viewport (dpr 1) and resets it after the test.
void setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
