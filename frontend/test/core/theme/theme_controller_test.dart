import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/storage/preferences_store.dart';
import 'package:ludo_arena/core/theme/app_theme.dart';
import 'package:ludo_arena/core/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = PreferencesStore(await SharedPreferences.getInstance());
  final c = ProviderContainer(
    overrides: [preferencesStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('defaults to system', () async {
    final c = await _container({});
    expect(c.read(themeModeControllerProvider), ThemeMode.system);
  });

  test('restores the persisted mode synchronously', () async {
    final c = await _container({PrefKeys.themeMode: 'dark'});
    expect(c.read(themeModeControllerProvider), ThemeMode.dark);
  });

  test('setMode persists and survives a restart', () async {
    final c = await _container({});
    await c.read(themeModeControllerProvider.notifier).setMode(ThemeMode.light);
    expect(c.read(themeModeControllerProvider), ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefKeys.themeMode), 'light');

    final restarted = ProviderContainer(
      overrides: [
        preferencesStoreProvider.overrideWithValue(PreferencesStore(prefs)),
      ],
    );
    addTearDown(restarted.dispose);
    expect(restarted.read(themeModeControllerProvider), ThemeMode.light);
  });

  test('toggle flips relative to the rendered brightness', () async {
    final c = await _container({});
    await c.read(themeModeControllerProvider.notifier).toggle(Brightness.light);
    expect(c.read(themeModeControllerProvider), ThemeMode.dark);
    await c.read(themeModeControllerProvider.notifier).toggle(Brightness.dark);
    expect(c.read(themeModeControllerProvider), ThemeMode.light);
  });

  test('unknown stored values fall back to system', () {
    expect(ThemeModeController.parse('purple'), ThemeMode.system);
    expect(ThemeModeController.parse(null), ThemeMode.system);
  });

  test('both themes expose the royal tokens and required seat colors', () {
    final light = AppTheme.light().extension<AppColors>()!;
    final dark = AppTheme.dark().extension<AppColors>()!;
    expect(light.isDark, isFalse);
    expect(dark.isDark, isTrue);
    expect(light.seats.red, const Color(0xFFE5484D));
    expect(light.seats.green, const Color(0xFF30A46C));
    expect(light.seats.yellow, const Color(0xFFF5B800));
    expect(light.seats.blue, const Color(0xFF3E63DD));
    expect(dark.seats.red, const Color(0xFFFF6369));
    expect(dark.seats.green, const Color(0xFF3DD68C));
    expect(dark.seats.yellow, const Color(0xFFFFD43B));
    expect(dark.seats.blue, const Color(0xFF6E8BFF));
    expect(light.seats.of(SeatColor.blue), light.seats.blue);
    // Text contrast against surfaces (WCAG AA for body text ≈ 4.5).
    double contrast(Color a, Color b) {
      final la = a.computeLuminance() + 0.05;
      final lb = b.computeLuminance() + 0.05;
      return la > lb ? la / lb : lb / la;
    }

    expect(contrast(light.textPrimary, light.surface), greaterThan(7));
    expect(contrast(dark.textPrimary, dark.surface), greaterThan(7));
    expect(contrast(light.textSecondary, light.surface), greaterThan(4.5));
    expect(contrast(dark.textSecondary, dark.surface), greaterThan(4.5));
  });

  test('typography uses Fredoka/Nunito with script fallbacks', () {
    final t = AppTheme.light().textTheme;
    expect(t.headlineMedium!.fontFamily, AppFonts.display);
    expect(t.bodyMedium!.fontFamily, AppFonts.body);
    expect(t.bodyMedium!.fontFamilyFallback, AppFonts.fallback);
    expect(AppFonts.fallback, containsAll(['Baloo2', 'BalooBhaijaan2']));
  });

  test('AppColors lerp is smooth for theme transitions', () {
    final mid = AppColors.light.lerp(AppColors.dark, 0.5);
    expect(mid.surface, isNot(AppColors.light.surface));
    expect(mid.surface, isNot(AppColors.dark.surface));
  });
}
