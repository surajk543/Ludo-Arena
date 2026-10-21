import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/localization/language_controller.dart';
import 'package:ludo_royale/core/localization/supported_locales.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/wallet/wallet_controller.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';

Future<ProviderContainer> _container(
  Map<String, Object> prefs,
  List<Locale> device,
) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = PreferencesStore(await SharedPreferences.getInstance());
  final c = ProviderContainer(
    overrides: [
      preferencesStoreProvider.overrideWithValue(store),
      deviceLocalesProvider.overrideWithValue(device),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('central list of supported locales matches the generated ones', () {
    expect(
      SupportedLocales.all.map((l) => l.languageCode).toSet(),
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
    );
    expect(SupportedLocales.isRtl(const Locale('ar')), isTrue);
    expect(SupportedLocales.isRtl(const Locale('ur')), isTrue);
    expect(SupportedLocales.isRtl(const Locale('hi')), isFalse);
  });

  test('defaults to the device locale when supported', () async {
    final c = await _container({}, const [Locale('hi', 'IN')]);
    expect(c.read(languageControllerProvider), const Locale('hi'));
  });

  test('regional variants map to the base language', () async {
    final c = await _container({}, const [Locale('ar', 'EG')]);
    expect(c.read(languageControllerProvider), const Locale('ar'));
  });

  test(
    'unsupported device locale falls back through the list, then en',
    () async {
      final c1 = await _container({}, const [Locale('fr'), Locale('id')]);
      expect(c1.read(languageControllerProvider), const Locale('id'));
      final c2 = await _container({}, const [Locale('fr'), Locale('de')]);
      expect(c2.read(languageControllerProvider), const Locale('en'));
    },
  );

  test('persisted choice wins over the device and survives restart', () async {
    final c = await _container({}, const [Locale('en')]);
    expect(
      c.read(languageControllerProvider.notifier).hasExplicitChoice,
      isFalse,
    );
    await c
        .read(languageControllerProvider.notifier)
        .setLocale(const Locale('ur'));
    expect(c.read(languageControllerProvider), const Locale('ur'));
    expect(
      c.read(languageControllerProvider.notifier).hasExplicitChoice,
      isTrue,
    );

    final prefs = await SharedPreferences.getInstance();
    final restarted = ProviderContainer(
      overrides: [
        preferencesStoreProvider.overrideWithValue(PreferencesStore(prefs)),
        deviceLocalesProvider.overrideWithValue(const [Locale('hi')]),
      ],
    );
    addTearDown(restarted.dispose);
    expect(restarted.read(languageControllerProvider), const Locale('ur'));
  });

  test('unsupported explicit choice falls back to English', () async {
    final c = await _container({}, const [Locale('en')]);
    await c
        .read(languageControllerProvider.notifier)
        .setLocale(const Locale('fr'));
    expect(c.read(languageControllerProvider), const Locale('en'));
  });

  test(
    'switching language never signs out or touches session/wallet',
    () async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      final c = env.container();
      addTearDown(c.dispose);
      await c.read(sessionControllerProvider.notifier).continueAsGuest();
      final requestsBefore = env.backend.requests.length;
      final tokensBefore = Map.of(env.secure.values);

      for (final l in SupportedLocales.all) {
        await c.read(languageControllerProvider.notifier).setLocale(l);
        expect(c.read(languageControllerProvider), l);
      }

      expect(c.read(sessionControllerProvider).isSignedIn, isTrue);
      expect(c.read(walletControllerProvider).coins, 1000000);
      expect(env.backend.requests.length, requestsBefore);
      expect(env.secure.values, tokensBefore);
      expect(meJson()['user'], isNotNull);
    },
  );

  test('every locale has a native language name', () {
    final names = {
      for (final l in SupportedLocales.all)
        l.languageCode: lookupAppLocalizations(l).languageNameNative,
    };
    expect(names, {
      'en': 'English',
      'hi': 'हिन्दी',
      'ur': 'اردو',
      'ar': 'العربية',
      'id': 'Bahasa Indonesia',
    });
  });
}
