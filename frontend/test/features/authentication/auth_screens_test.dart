import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/network/api_client.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/authentication/presentation/link_account_screen.dart';
import 'package:ludo_royale/features/authentication/presentation/login_screen.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

void main() {
  testWidgets('login lists configured providers and plays as guest', (
    tester,
  ) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    final c = await pumpScreen(tester, env, const LoginScreen());
    expect(find.text('Continue with Google'), findsOneWidget);
    // Facebook disabled, Apple hidden on Android without web-flow config.
    expect(find.text('Continue with Facebook'), findsNothing);
    expect(find.text('Sign in with Apple'), findsNothing);

    await tester.tap(find.text('Play as guest'));
    await drain(tester);
    expect(c.read(sessionControllerProvider).isSignedIn, isTrue);
    expect(env.secure.values['session.guest_secret'], 'gs_new');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Apple is shown on iOS', (tester) async {
    final env = await TestEnv.create(platform: 'ios');
    await pumpScreen(tester, env, const LoginScreen());
    expect(find.text('Sign in with Apple'), findsOneWidget);
  });

  testWidgets('cancelled provider sign-in is silent', (tester) async {
    final env = await TestEnv.create();
    env.identity[LinkedProvider.google]!.next = null;
    final c = await pumpScreen(tester, env, const LoginScreen());
    await tester.tap(find.text('Continue with Google'));
    await drain(tester);
    expect(find.byType(SnackBar), findsNothing);
    expect(c.read(sessionControllerProvider).isSignedIn, isFalse);
  });

  testWidgets('backend failure shows a localized error', (tester) async {
    final env = await TestEnv.create();
    env.backend.on(
      'POST',
      '/auth/google',
      (_) => FakeResponse.error(503, 'provider_unavailable'),
    );
    await pumpScreen(
      tester,
      env,
      const LoginScreen(),
      locale: const Locale('id'),
    );
    await tester.tap(find.text('Lanjutkan dengan Google'));
    await drain(tester);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('expired session shows a banner on login', (tester) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend
      ..json(
        'POST',
        '/auth/google',
        authJson(isGuest: false, providers: ['google']),
      )
      ..on(
        'POST',
        '/auth/refresh',
        (_) => FakeResponse.error(401, 'refresh_reused'),
      );
    await pumpScreen(
      tester,
      env,
      const LoginScreen(),
      prepare: (c) async {
        await c
            .read(sessionControllerProvider.notifier)
            .signIn(LinkedProvider.google);
        // The server revokes the session: the next refresh is rejected.
        await c.read(tokenManagerProvider).refreshNow();
      },
    );
    expect(
      find.text('You were signed out. Please sign in again.'),
      findsOneWidget,
    );
  });

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('signed in on another device: popup + banner on login '
        '(${locale.languageCode})', (tester) async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      env.backend
        ..json(
          'POST',
          '/auth/google',
          authJson(isGuest: false, providers: ['google']),
        )
        ..on(
          'POST',
          '/auth/refresh',
          (_) => FakeResponse.error(401, 'session_replaced'),
        );
      await pumpScreen(
        tester,
        env,
        const LoginScreen(),
        locale: locale,
        prepare: (c) async {
          await c
              .read(sessionControllerProvider.notifier)
              .signIn(LinkedProvider.google);
          // Another device signs in: this session's refresh is refused.
          await c.read(tokenManagerProvider).refreshNow();
        },
      );
      await tester.pump();
      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.authSignedInElsewhereTitle), findsOneWidget);
      expect(find.text(l10n.authSignedInElsewhereMessage), findsOneWidget);
      expect(find.text(l10n.authSignedInElsewhereBanner), findsOneWidget);
      expect(find.text(l10n.authSessionExpiredBanner), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(l10n.commonOk));
      await tester.pumpAndSettle();
      expect(find.text(l10n.authSignedInElsewhereTitle), findsNothing);
      // The banner stays; nothing signed back in on its own.
      expect(find.text(l10n.authSignedInElsewhereBanner), findsOneWidget);
      expect(env.backend.calls('POST', '/auth/guest/resume'), isEmpty);
    });
  }

  group('Save Progress', () {
    GoRouter router() => GoRouter(
      initialLocation: AppRoutes.linkAccount,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: AppRoutes.linkAccount,
          builder: (_, _) => const LinkAccountScreen(),
        ),
      ],
    );

    testWidgets('link success shows the saved state', (tester) async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      env.backend.json(
        'POST',
        '/account/link/google',
        meJson(isGuest: false, providers: ['guest', 'google']),
      );
      env.backend.json(
        'GET',
        '/me',
        meJson(isGuest: false, providers: ['guest', 'google']),
      );
      final c = await pumpScreen(
        tester,
        env,
        const SizedBox(),
        router: router(),
        prepare: (c) =>
            c.read(sessionControllerProvider.notifier).continueAsGuest(),
      );
      expect(find.text('Save with Google'), findsOneWidget);
      await tester.tap(find.text('Save with Google'));
      await drain(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        c.read(sessionControllerProvider).user!.needsSaveProgress,
        isFalse,
      );
      expect(find.text('Your progress is saved'), findsOneWidget);
      expect(find.text('Save with Google'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('identity conflict: explain, then sign in to that account', (
      tester,
    ) async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      env.backend
        ..on(
          'POST',
          '/account/link/google',
          (_) => FakeResponse.error(
            409,
            'identity_conflict',
            details: {'provider': 'google'},
          ),
        )
        ..json(
          'POST',
          '/auth/google',
          authJson(
            id: 'acc-2',
            name: 'Ravi',
            isGuest: false,
            providers: ['google'],
          ),
        );
      final c = await pumpScreen(
        tester,
        env,
        const SizedBox(),
        router: router(),
        prepare: (c) =>
            c.read(sessionControllerProvider.notifier).continueAsGuest(),
      );
      await tester.tap(find.text('Save with Google'));
      await drain(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('This Google account is already in use'),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing will be merged'), findsOneWidget);
      expect(
        find.textContaining('switch back to it from Settings'),
        findsOneWidget,
      );

      await tester.tap(find.text('Sign in to that account'));
      await drain(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.read(sessionControllerProvider).user!.id, 'acc-2');
      expect(c.read(sessionControllerProvider).canSwitchBackToGuest, isTrue);
      expect(find.text('HOME'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('identity conflict: Cancel changes nothing', (tester) async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      env.backend.on(
        'POST',
        '/account/link/google',
        (_) => FakeResponse.error(409, 'identity_conflict'),
      );
      final c = await pumpScreen(
        tester,
        env,
        const SizedBox(),
        router: router(),
        prepare: (c) =>
            c.read(sessionControllerProvider.notifier).continueAsGuest(),
      );
      await tester.tap(find.text('Save with Google'));
      await drain(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.read(sessionControllerProvider).user!.id, 'acc-1');
      expect(env.backend.calls('POST', '/auth/google'), isEmpty);
    });
  });
}
