import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_arena/app/routes.dart';
import 'package:ludo_arena/core/errors/error_messages.dart';
import 'package:ludo_arena/features/authentication/application/session_controller.dart';
import 'package:ludo_arena/features/authentication/presentation/delete_account_dialog.dart';
import 'package:ludo_arena/features/authentication/presentation/login_screen.dart';
import 'package:ludo_arena/features/settings/presentation/settings_screen.dart';
import 'package:ludo_arena/l10n/generated/app_localizations.dart';
import 'package:ludo_arena/shared/widgets/widgets.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

/// Settings → Delete account: tile → explanation + "I understand" →
/// `DELETE /account` → signed out → login confirms the deletion.
void main() {
  GoRouter router() => GoRouter(
    initialLocation: AppRoutes.settings,
    routes: [
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.linkAccount,
        builder: (_, _) => const Scaffold(body: Text('LINK')),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const Scaffold(body: Text('PROFILE')),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
    ],
  );

  Future<(TestEnv, ProviderContainer, GoRouter)> pumpSettings(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = Viewports.phone,
    double textScale = 1.0,
  }) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend.json('DELETE', '/account', const {}, status: 204);
    final r = router();
    final c = await pumpScreen(
      tester,
      env,
      const SizedBox(),
      router: r,
      locale: locale,
      size: size,
      textScale: textScale,
      prepare: (c) =>
          c.read(sessionControllerProvider.notifier).continueAsGuest(),
    );
    return (env, c, r);
  }

  final tile = find.byIcon(Icons.delete_forever_rounded);
  Finder dialog() => find.byType(DeleteAccountDialog);
  Finder deleteButton() => find.descendant(
    of: dialog(),
    matching: find.widgetWithText(PremiumButton, 'Delete account'),
  );
  PremiumButton button(WidgetTester tester) =>
      tester.widget<PremiumButton>(deleteButton());

  Future<void> openDialog(WidgetTester tester) async {
    await reveal(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(dialog(), findsOneWidget);
  }

  testWidgets('tile → explanation; the button needs "I understand"; delete '
      'signs out and login confirms it', (tester) async {
    final (env, c, r) = await pumpSettings(tester);
    await reveal(tester, tile);
    expect(
      find.text('Permanently delete your account and its data'),
      findsOneWidget,
    );
    await openDialog(tester);
    for (final t in const [
      'Delete your account?',
      'This permanently deletes your account and everything in it:',
      'Coins and diamonds',
      'Level, XP and missions',
      'Collection Room items',
      'Friends and friend requests',
      "This can't be undone. If you play again later, you'll start with a "
          'new account.',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(button(tester).onPressed, isNull);
    await tester.tap(deleteButton(), warnIfMissed: false);
    await drain(tester, 3);
    expect(env.backend.calls('DELETE', '/account'), isEmpty);

    await tester.tap(
      find.text(
        'I understand that my account and progress will be deleted forever.',
      ),
    );
    await tester.pump();
    expect(button(tester).onPressed, isNotNull);

    await tester.tap(deleteButton());
    await drain(tester);
    final req = env.backend.calls('DELETE', '/account').single;
    expect(req.json, {'confirm': 'DELETE'});
    expect(dialog(), findsNothing);
    final s = c.read(sessionControllerProvider);
    expect(s.status, SessionStatus.signedOut);
    expect(s.signOutReason, SignOutReason.accountDeleted);
    expect(env.analytics.events, contains('account_deleted'));
    expect(env.secure.values['session.signed_out'], '1');

    // The app gate routes to login: banner + toast, no "another device".
    r.go(AppRoutes.login);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Your account was deleted.'), findsNWidgets(2));
    expect(find.text('Signed in on another device'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Cancel closes the dialog without a request', (tester) async {
    final (env, c, _) = await pumpSettings(tester);
    await openDialog(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(dialog(), findsNothing);
    expect(env.backend.calls('DELETE', '/account'), isEmpty);
    expect(c.read(sessionControllerProvider).isSignedIn, isTrue);
  });

  testWidgets('a failure keeps the dialog open with an inline message; a '
      'retry succeeds', (tester) async {
    final (env, c, _) = await pumpSettings(tester);
    env.backend.on(
      'DELETE',
      '/account',
      (_) => FakeResponse.error(500, 'internal'),
    );
    await openDialog(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(deleteButton());
    await drain(tester);
    expect(dialog(), findsOneWidget);
    expect(
      find.text(
        'Your account was not deleted. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(c.read(sessionControllerProvider).isSignedIn, isTrue);
    expect(env.secure.values['session.refresh_token'], 'rt-1');

    env.backend.json('DELETE', '/account', const {}, status: 204);
    await tester.tap(deleteButton());
    await drain(tester);
    expect(dialog(), findsNothing);
    expect(
      c.read(sessionControllerProvider).signOutReason,
      SignOutReason.accountDeleted,
    );
    expect(env.backend.calls('DELETE', '/account'), hasLength(2));
  });

  testWidgets('rate limited → the localized rate-limit message', (
    tester,
  ) async {
    final (env, _, _) = await pumpSettings(tester);
    env.backend.on(
      'DELETE',
      '/account',
      (_) => FakeResponse.error(
        429,
        'rate_limited',
        headers: {
          'retry-after': ['120'],
        },
      ),
    );
    await openDialog(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(deleteButton());
    await drain(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      find.text(
        localizedErrorMessage(
          l10n,
          'rate_limited',
          retryAfter: const Duration(seconds: 120),
        ),
      ),
      findsOneWidget,
    );
    expect(dialog(), findsOneWidget);
  });

  testWidgets('cannot be dismissed while the delete is in flight', (
    tester,
  ) async {
    final (env, c, _) = await pumpSettings(tester);
    final gate = Completer<void>();
    env.backend.on('DELETE', '/account', (_) async {
      await gate.future;
      return const FakeResponse(204);
    });
    await openDialog(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(deleteButton());
    await drain(tester, 3);
    await tester.tapAt(const Offset(4, 4)); // barrier
    await tester.pump();
    expect(dialog(), findsOneWidget);
    expect(
      tester
          .widget<PremiumButton>(find.widgetWithText(PremiumButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    gate.complete();
    await drain(tester);
    expect(dialog(), findsNothing);
    expect(c.read(sessionControllerProvider).isSignedIn, isFalse);
  });

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('layout ${locale.languageCode} @320x640 x1.35: account '
        'section and dialog fit', (tester) async {
      await pumpSettings(
        tester,
        locale: locale,
        size: Viewports.small,
        textScale: 1.35,
      );
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
      await openDialog(tester);
      expect(tester.takeException(), isNull);
      final rtl = locale.languageCode == 'ar';
      expect(
        Directionality.of(tester.element(dialog())),
        rtl ? TextDirection.rtl : TextDirection.ltr,
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.authDeleteAccountConfirmCheck), findsOneWidget);
      final localized = find.descendant(
        of: dialog(),
        matching: find.widgetWithText(
          PremiumButton,
          l10n.authDeleteAccountConfirm,
        ),
      );
      expect(tester.widget<PremiumButton>(localized).onPressed, isNotNull);
    });
  }
}
