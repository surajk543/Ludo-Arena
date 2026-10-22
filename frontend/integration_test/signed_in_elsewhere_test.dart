// On-device check of "one device per account" against a live backend:
//
//   flutter test integration_test/signed_in_elsewhere_test.dart -d <device> \
//     --dart-define=API_BASE_URL=http://localhost:8080
//
// The app restores (or creates) a guest session; the test then signs in to
// the same account as a second device (`POST /auth/guest/resume` with this
// device's guest secret, or `POST /auth/device/resume` when the account was
// restored through the device id and has no secret on this install). The
// server must end this device's session at once:
// the app lands on the login screen with the "Signed in on another device"
// popup and does not sign back in by itself. Prints SCREENSHOT_WINDOW_OPEN
// while the popup is shown so it can be captured from the host.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ludo_arena/core/config/app_config.dart';
import 'package:ludo_arena/core/config/app_info.dart';
import 'package:ludo_arena/core/device/device_identity.dart';
import 'package:ludo_arena/core/storage/secure_session_store.dart';
import 'package:ludo_arena/features/authentication/application/session_controller.dart';
import 'package:ludo_arena/features/authentication/presentation/login_screen.dart';
import 'package:ludo_arena/features/home/presentation/home_screen.dart';
import 'package:ludo_arena/l10n/generated/app_localizations.dart';
import 'package:ludo_arena/main.dart' as app;

Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Future<void> Function()? onEachTick,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (condition()) return true;
    if (onEachTick != null) await onEachTick();
  }
  return false;
}

Future<void> tapIfPresent(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Signs in to this device's account as another device would
/// (`POST [path]` with [body]).
Future<int> signInElsewhere(
  AppConfig config,
  AppInfo info,
  String path,
  Map<String, String> body,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('${config.apiV1}$path'));
    req.headers.contentType = ContentType.json;
    info.headers.forEach(req.headers.set);
    req.write(jsonEncode(body));
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a sign-in on another device signs this device out', (
    tester,
  ) async {
    await app.main();

    // Signed in: Home, or straight into a resumed match.
    final signedIn = await pumpUntil(
      tester,
      () {
        final ctx = find.byType(MaterialApp).evaluate();
        if (ctx.isEmpty) return false;
        return ProviderScope.containerOf(
          ctx.first,
        ).read(sessionControllerProvider).isSignedIn;
      },
      timeout: const Duration(seconds: 60),
      onEachTick: () async {
        await tapIfPresent(tester, find.text('Continue'));
        await tapIfPresent(tester, find.text('Play as guest'));
        await tapIfPresent(tester, find.text('No thanks'));
        await tapIfPresent(tester, find.text('Later'));
      },
    );
    expect(signedIn, isTrue, reason: 'not signed in');
    await pumpUntil(
      tester,
      () => find.byType(HomeScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 5),
    );
    // Let the socket connect.
    await tester.pump(const Duration(seconds: 3));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final secret = await container
        .read(secureSessionStoreProvider)
        .readGuestSecret();
    final deviceId = await container.read(deviceIdentityProvider).deviceId();
    expect(
      secret ?? deviceId,
      isNotNull,
      reason: 'this check needs a guest secret or a device id',
    );
    final status = await signInElsewhere(
      container.read(appConfigProvider),
      container.read(appInfoProvider),
      secret != null ? '/auth/guest/resume' : '/auth/device/resume',
      secret != null ? {'guestSecret': secret} : {'deviceId': deviceId!},
    );
    expect(status, 200);

    final l10n = lookupAppLocalizations(const Locale('en'));
    final shown = await pumpUntil(
      tester,
      () =>
          find.byType(LoginScreen).evaluate().isNotEmpty &&
          find.text(l10n.authSignedInElsewhereTitle).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
      // A fresh test install has no language choice yet: the picker comes
      // before the login screen.
      onEachTick: () => tapIfPresent(tester, find.text('Continue')),
    );
    expect(shown, isTrue, reason: 'popup not shown');
    expect(
      container.read(sessionControllerProvider).signOutReason,
      SignOutReason.replaced,
    );

    // ignore: avoid_print
    print('SCREENSHOT_WINDOW_OPEN');
    await pumpUntil(tester, () => false, timeout: const Duration(seconds: 12));
    // ignore: avoid_print
    print('SCREENSHOT_WINDOW_CLOSED');

    await tester.tap(find.text(l10n.commonOk));
    await pumpUntil(tester, () => false, timeout: const Duration(seconds: 5));
    // Never signs back in on its own.
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(container.read(sessionControllerProvider).isSignedIn, isFalse);
  });
}
