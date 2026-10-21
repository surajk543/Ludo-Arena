import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';

/// Semantic haptic patterns.
enum Haptic {
  /// Tab/segment/toggle changes.
  selection,

  /// Button taps.
  light,

  /// Dice landing, token placed.
  medium,

  /// Captures, errors.
  heavy,

  /// Win / reward.
  success,
}

/// Haptic feedback honoring the Haptics setting. Never throws.
class HapticsService {
  HapticsService({required this._enabled});

  final bool Function() _enabled;

  void trigger(Haptic kind) {
    if (!_enabled()) return;
    try {
      switch (kind) {
        case Haptic.selection:
          HapticFeedback.selectionClick();
        case Haptic.light:
          HapticFeedback.lightImpact();
        case Haptic.medium:
          HapticFeedback.mediumImpact();
        case Haptic.heavy:
          HapticFeedback.heavyImpact();
        case Haptic.success:
          HapticFeedback.mediumImpact();
          Future<void>.delayed(
            const Duration(milliseconds: 90),
            HapticFeedback.lightImpact,
          );
      }
    } catch (_) {}
  }

  void selection() => trigger(Haptic.selection);
  void light() => trigger(Haptic.light);
  void medium() => trigger(Haptic.medium);
  void heavy() => trigger(Haptic.heavy);
  void success() => trigger(Haptic.success);
}

final hapticsServiceProvider = Provider<HapticsService>(
  (ref) => HapticsService(
    enabled: () => ref.read(settingsControllerProvider).hapticsEnabled,
  ),
);
