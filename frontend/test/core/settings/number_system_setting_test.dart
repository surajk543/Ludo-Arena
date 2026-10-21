import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/localization/number_format.dart';
import 'package:ludo_royale/core/settings/app_settings.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<(ProviderContainer, PreferencesStore)> boot([
    Map<String, Object> stored = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = PreferencesStore(await SharedPreferences.getInstance());
    final c = ProviderContainer(
      overrides: [preferencesStoreProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return (c, prefs);
  }

  test('unset by default: amounts follow the language', () async {
    final (c, _) = await boot();
    expect(c.read(settingsControllerProvider).numberSystem, isNull);
    expect(const AppSettings().numberSystem, isNull);
  });

  test('a choice applies at once, persists and is restored', () async {
    final (c, prefs) = await boot();
    await c
        .read(settingsControllerProvider.notifier)
        .setNumberSystem(NumberSystem.international);
    expect(
      c.read(settingsControllerProvider).numberSystem,
      NumberSystem.international,
    );
    expect(prefs.getString(PrefKeys.numberSystem), 'international');
    // Other settings are untouched.
    expect(c.read(settingsControllerProvider).soundEnabled, isTrue);

    // Next launch.
    final (restored, _) = await boot({PrefKeys.numberSystem: 'international'});
    expect(
      restored.read(settingsControllerProvider).numberSystem,
      NumberSystem.international,
    );

    await c
        .read(settingsControllerProvider.notifier)
        .setNumberSystem(NumberSystem.indian);
    expect(prefs.getString(PrefKeys.numberSystem), 'indian');
  });

  test('an unknown stored value falls back to the language default', () async {
    final (c, _) = await boot({PrefKeys.numberSystem: 'roman'});
    expect(c.read(settingsControllerProvider).numberSystem, isNull);
  });

  test('equality includes the number system', () {
    const a = AppSettings();
    final b = a.copyWith(numberSystem: NumberSystem.indian);
    expect(a == b, isFalse);
    expect(b, a.copyWith(numberSystem: NumberSystem.indian));
    expect(b.hashCode, a.copyWith(numberSystem: NumberSystem.indian).hashCode);
  });
}
