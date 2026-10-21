import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/lifecycle/app_lifecycle.dart';
import 'package:ludo_royale/core/realtime/realtime_providers.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/core/storage/secure_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connection is lazy, not auto-started, and drives the status '
      'provider', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        preferencesStoreProvider.overrideWithValue(PreferencesStore(prefs)),
        secureKeyValueProvider.overrideWithValue(InMemorySecureKeyValue()),
      ],
    );
    addTearDown(c.dispose);

    final connection = c.read(realtimeConnectionProvider);
    expect(connection.status, RealtimeStatus.idle);
    expect(c.read(realtimeStatusProvider), RealtimeStatus.idle);

    // Backgrounded: start() waits for resume and reports offline.
    c.read(appLifecycleProvider).emit(AppLifecycleState.paused);
    connection.start();
    expect(c.read(realtimeStatusProvider), RealtimeStatus.offline);

    // No stored session → resume tries, finds no token, goes idle.
    c.read(appLifecycleProvider).emit(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(realtimeStatusProvider), RealtimeStatus.idle);
    expect(connection.haltReason, RealtimeHaltReason.sessionEnded);

    // The room controller builds on top of it.
    expect(c.read(activeRoomControllerProvider).room, isNull);
  });
}
