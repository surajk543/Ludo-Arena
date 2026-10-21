import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_store.dart';

/// Light / dark / system theme selection, persisted and restored before the
/// first frame (the preferences store is loaded in bootstrap). Changing the
/// theme only rebuilds visuals: no route, socket or game state is touched.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      parse(ref.read(preferencesStoreProvider).getString(PrefKeys.themeMode));

  static ThemeMode parse(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref
        .read(preferencesStoreProvider)
        .setString(PrefKeys.themeMode, mode.name);
  }

  /// Quick toggle used by the Home theme shortcut: resolves "system" against
  /// the current platform brightness and flips it.
  Future<void> toggle(Brightness current) =>
      setMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
