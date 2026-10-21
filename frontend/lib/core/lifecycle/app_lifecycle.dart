import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Broadcasts app lifecycle transitions to non-widget services (realtime
/// connection, gate controller). Driven by an [AppLifecycleListener]
/// installed in `app.dart`; tests push states directly with [emit].
class AppLifecycleBus {
  final _controller = StreamController<AppLifecycleState>.broadcast(sync: true);
  AppLifecycleState _current = AppLifecycleState.resumed;

  AppLifecycleState get current => _current;
  bool get isForeground => _current == AppLifecycleState.resumed;

  Stream<AppLifecycleState> get changes => _controller.stream;

  /// Emits only "foreground again" transitions.
  Stream<void> get resumed =>
      changes.where((s) => s == AppLifecycleState.resumed).map((_) {});

  /// Emits when the app leaves the foreground (paused/hidden).
  Stream<void> get backgrounded => changes
      .where(
        (s) => s == AppLifecycleState.paused || s == AppLifecycleState.hidden,
      )
      .map((_) {});

  void emit(AppLifecycleState state) {
    if (state == _current) return;
    // `inactive` is transient (dialogs, app switcher); ignore it.
    if (state == AppLifecycleState.inactive) return;
    _current = state;
    _controller.add(state);
  }

  void dispose() => _controller.close();
}

final appLifecycleProvider = Provider<AppLifecycleBus>((ref) {
  final bus = AppLifecycleBus();
  ref.onDispose(bus.dispose);
  return bus;
});
