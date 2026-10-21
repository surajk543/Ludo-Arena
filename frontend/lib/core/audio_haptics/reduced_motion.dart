import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import '../theme/tokens.dart';

/// Whether decorative motion should be reduced: the system accessibility
/// setting (`MediaQuery.disableAnimations`) OR the in-app setting.
///
/// Installed once above the router by `app.dart`; read anywhere with
/// `ReducedMotion.of(context)`.
class ReducedMotion extends InheritedWidget {
  const ReducedMotion({super.key, required this.reduce, required super.child});

  final bool reduce;

  /// True when animations should be skipped or shortened.
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ReducedMotion>();
    if (scope != null) return scope.reduce;
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// [normal] or [Duration.zero] when motion is reduced.
  static Duration duration(BuildContext context, Duration normal) =>
      of(context) ? Duration.zero : normal;

  @override
  bool updateShouldNotify(ReducedMotion oldWidget) =>
      oldWidget.reduce != reduce;
}

/// Wraps [child] with a [ReducedMotion] scope combining system + user
/// preferences.
class ReducedMotionScope extends ConsumerWidget {
  const ReducedMotionScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final user = ref.watch(
      settingsControllerProvider.select((s) => s.reducedMotion),
    );
    return ReducedMotion(reduce: system || user, child: child);
  }
}

/// Convenience for motion durations.
extension MotionContext on BuildContext {
  bool get reduceMotion => ReducedMotion.of(this);

  Duration motion([Duration normal = AppDurations.medium]) =>
      ReducedMotion.duration(this, normal);
}
