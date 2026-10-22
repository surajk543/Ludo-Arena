import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_arena/app/routes.dart';
import 'package:ludo_arena/features/authentication/application/session_controller.dart';
import 'package:ludo_arena/features/home/presentation/home_screen.dart';
import 'package:ludo_arena/features/profile/presentation/display_name_sheet.dart';
import 'package:ludo_arena/features/profile/presentation/profile_screen.dart';
import 'package:ludo_arena/l10n/generated/app_localizations.dart';
import 'package:ludo_arena/shared/widgets/widgets.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

const _field = ValueKey('display-name-field');
const _save = ValueKey('display-name-save');
const _cancel = ValueKey('display-name-cancel');
const _counter = ValueKey('display-name-counter');
const _banner = ValueKey('display-name-error');
const _editButton = ValueKey('profile-edit-name');
const _profileName = ValueKey('profile-display-name');

final _en = lookupAppLocalizations(const Locale('en'));

void main() {
  /// Signed-in guest "Asha" on the real profile screen. PATCH /me echoes
  /// the requested name unless the test routes it differently.
  Future<(TestEnv, ProviderContainer)> pumpProfile(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
    Size size = Viewports.phone,
    double textScale = 1.0,
  }) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    env.backend.on(
      'PATCH',
      '/me',
      (req) => FakeResponse(
        200,
        meJson(name: req.json['displayName'] as String? ?? ''),
      ),
    );
    final container = await pumpScreen(
      tester,
      env,
      const ProfileScreen(),
      locale: locale,
      themeMode: themeMode,
      size: size,
      textScale: textScale,
      prepare: (c) =>
          c.read(sessionControllerProvider.notifier).continueAsGuest(),
    );
    return (env, container);
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(_editButton));
    await tester.pumpAndSettle();
    expect(find.byType(DisplayNameForm), findsOneWidget);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(_field), text);
    await tester.pump();
  }

  String? errorText(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(_field)).decoration?.errorText;

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<PremiumButton>(find.byKey(_save)).onPressed != null;

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_save));
    await tester.tap(find.byKey(_save));
    await drain(tester);
    await tester.pumpAndSettle();
  }

  group('opening the editor', () {
    testWidgets('pencil next to the name opens a prefilled sheet', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpProfile(tester);
      expect(find.byTooltip('Edit name'), findsOneWidget);
      expect(find.bySemanticsLabel('Edit name'), findsOneWidget);

      await openEditor(tester);
      expect(find.text('Change your name'), findsOneWidget);
      expect(find.text('Display name'), findsOneWidget);
      expect(find.text(_en.profileNameRules), findsOneWidget);
      expect(find.text(_en.profileNameNote), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(_field));
      expect(field.controller!.text, 'Asha');
      expect(tester.widget<Text>(find.byKey(_counter)).data, '4/16');
      // Merged into the text field's node, after its label.
      expect(
        find.bySemanticsLabel(RegExp('4 of 16 characters')),
        findsOneWidget,
      );
      // Unchanged name: nothing to save yet, no error shown.
      expect(saveEnabled(tester), isFalse);
      expect(errorText(tester), isNull);
      semantics.dispose();
    });

    testWidgets('Save stays disabled for the same name with extra spaces', (
      tester,
    ) async {
      await pumpProfile(tester);
      await openEditor(tester);
      await type(tester, '   Asha  ');
      expect(saveEnabled(tester), isFalse);
      expect(errorText(tester), isNull);
      await type(tester, 'Asha R');
      expect(saveEnabled(tester), isTrue);
      expect(tester.widget<Text>(find.byKey(_counter)).data, '6/16');
    });

    testWidgets('Cancel closes the sheet without a request', (tester) async {
      final (env, _) = await pumpProfile(tester);
      await openEditor(tester);
      await type(tester, 'Someone Else');
      await tester.tap(find.byKey(_cancel));
      await tester.pumpAndSettle();
      expect(find.byType(DisplayNameForm), findsNothing);
      expect(env.backend.calls('PATCH', '/me'), isEmpty);
      expect(tester.widget<Text>(find.byKey(_profileName)).data, 'Asha');
    });
  });

  group('client-side validation', () {
    final rejected = <String, String>{
      'Ab': _en.errorInvalidNameTooShort,
      'Abcdefghijklmnopq': _en.errorInvalidNameTooLong,
      'Raj 😎': _en.errorInvalidNameCharacters,
      r'Raj$$': _en.errorInvalidNameCharacters,
      '12345': _en.errorInvalidNameCharacters,
      'Bot Raj': _en.errorInvalidNameReserved,
      'admin': _en.errorInvalidNameReserved,
      'Ludo_Arena': _en.errorInvalidNameReserved,
      'Ludo_Royale': _en.errorInvalidNameReserved,
    };
    rejected.forEach((name, message) {
      testWidgets('"$name" → $message', (tester) async {
        final (env, _) = await pumpProfile(tester);
        await openEditor(tester);
        await type(tester, name);
        expect(errorText(tester), message);
        expect(find.text(message), findsOneWidget);
        expect(saveEnabled(tester), isFalse);
        // Submitting from the keyboard is blocked too.
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await drain(tester, 3);
        expect(env.backend.calls('PATCH', '/me'), isEmpty);
      });
    });

    testWidgets('the counter turns past the limit', (tester) async {
      await pumpProfile(tester);
      await openEditor(tester);
      await type(tester, 'Abcdefghijklmnopq');
      expect(tester.widget<Text>(find.byKey(_counter)).data, '17/16');
    });

    final accepted = <String, Locale>{
      'राहुल': const Locale('hi'),
      'علی رضا': const Locale('ur'),
      'نور الهدى': const Locale('ar'),
      'Budi Santoso': const Locale('id'),
      'Siti_Nur.2': const Locale('id'),
    };
    accepted.forEach((name, locale) {
      testWidgets('"$name" is accepted (${locale.languageCode})', (
        tester,
      ) async {
        await pumpProfile(tester, locale: locale);
        await openEditor(tester);
        await type(tester, name);
        expect(errorText(tester), isNull);
        expect(saveEnabled(tester), isTrue);
      });
    });
  });

  group('saving', () {
    testWidgets('sends PATCH /me and updates the profile + toast', (
      tester,
    ) async {
      final (env, container) = await pumpProfile(tester);
      await openEditor(tester);
      await type(tester, '  Rahul   K ');
      await tapSave(tester);

      final req = env.backend.calls('PATCH', '/me').single;
      expect(req.json, {'displayName': 'Rahul K'});
      expect(req.header('Authorization'), 'Bearer at-1');
      expect(find.byType(DisplayNameForm), findsNothing);
      expect(tester.widget<Text>(find.byKey(_profileName)).data, 'Rahul K');
      expect(find.text('Your name is now Rahul K'), findsOneWidget);
      expect(
        container.read(sessionControllerProvider).user!.displayName,
        'Rahul K',
      );
      expect(env.analytics.events, contains('display_name_changed'));
    });

    testWidgets('the Home header shows the new name right away', (
      tester,
    ) async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      env.backend.on(
        'PATCH',
        '/me',
        (req) =>
            FakeResponse(200, meJson(name: req.json['displayName'] as String)),
      );
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: AppRoutes.profile,
            builder: (_, _) => const ProfileScreen(),
          ),
        ],
      );
      await pumpScreen(
        tester,
        env,
        const SizedBox(),
        router: router,
        prepare: (c) =>
            c.read(sessionControllerProvider.notifier).continueAsGuest(),
      );
      expect(find.text('Asha'), findsOneWidget);

      router.push(AppRoutes.profile);
      await tester.pumpAndSettle();
      await openEditor(tester);
      await type(tester, 'राहुल');
      await tapSave(tester);
      expect(tester.widget<Text>(find.byKey(_profileName)).data, 'राहुल');

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('राहुल'), findsOneWidget);
      expect(find.text('Asha'), findsNothing);
    });

    final serverReasons = <String, String>{
      'too_short': _en.errorInvalidNameTooShort,
      'too_long': _en.errorInvalidNameTooLong,
      'invalid_characters': _en.errorInvalidNameCharacters,
      'reserved': _en.errorInvalidNameReserved,
      'inappropriate': _en.errorInvalidNameInappropriate,
      'something_new': _en.errorInvalidName,
    };
    serverReasons.forEach((reason, message) {
      testWidgets('server 400 invalid_name/$reason → localized message', (
        tester,
      ) async {
        final (env, container) = await pumpProfile(tester);
        env.backend.on(
          'PATCH',
          '/me',
          (_) => FakeResponse.error(
            400,
            'invalid_name',
            details: {'reason': reason},
          ),
        );
        await openEditor(tester);
        await type(tester, 'Nice Name');
        await tapSave(tester);

        expect(find.byType(DisplayNameForm), findsOneWidget);
        expect(errorText(tester), message);
        // The server's verdict holds until the name is edited.
        expect(saveEnabled(tester), isFalse);
        expect(
          container.read(sessionControllerProvider).user!.displayName,
          'Asha',
        );
        await type(tester, 'Nicer Name');
        expect(errorText(tester), isNull);
        expect(saveEnabled(tester), isTrue);
      });
    });

    testWidgets('server reason is localized (Arabic)', (tester) async {
      final (env, _) = await pumpProfile(tester, locale: const Locale('ar'));
      env.backend.on(
        'PATCH',
        '/me',
        (_) => FakeResponse.error(
          400,
          'invalid_name',
          details: {'reason': 'inappropriate'},
        ),
      );
      await openEditor(tester);
      await type(tester, 'نور الهدى');
      await tapSave(tester);
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(errorText(tester), ar.errorInvalidNameInappropriate);
    });

    testWidgets('429 shows the daily limit with the wait', (tester) async {
      final (env, _) = await pumpProfile(tester);
      env.backend.on(
        'PATCH',
        '/me',
        (_) => FakeResponse.error(
          429,
          'rate_limited',
          headers: {
            'retry-after': ['18720'], // 5 h 12 min
          },
        ),
      );
      await openEditor(tester);
      await type(tester, 'Rahul K');
      await tapSave(tester);
      expect(
        find.text(
          "You've changed your name too often. Try again in 5 h 12 min.",
        ),
        findsOneWidget,
      );
      expect(find.byKey(_banner), findsOneWidget);
      expect(errorText(tester), isNull);
      // A later retry is allowed.
      expect(saveEnabled(tester), isTrue);
      expect(env.backend.calls('PATCH', '/me'), hasLength(1));
    });

    testWidgets('429 without Retry-After, localized (Hindi)', (tester) async {
      final (env, _) = await pumpProfile(tester, locale: const Locale('hi'));
      env.backend.on(
        'PATCH',
        '/me',
        (_) => FakeResponse.error(429, 'rate_limited'),
      );
      await openEditor(tester);
      await type(tester, 'राहुल');
      await tapSave(tester);
      final hi = lookupAppLocalizations(const Locale('hi'));
      expect(find.text(hi.profileNameChangeLimit), findsOneWidget);
    });

    testWidgets('429 with a Hindi wait', (tester) async {
      final (env, _) = await pumpProfile(tester, locale: const Locale('hi'));
      env.backend.on(
        'PATCH',
        '/me',
        (_) => FakeResponse.error(
          429,
          'rate_limited',
          headers: {
            'retry-after': ['18720'],
          },
        ),
      );
      await openEditor(tester);
      await type(tester, 'राहुल');
      await tapSave(tester);
      expect(
        find.text(
          'आपने बहुत बार नाम बदला है। 5 घंटे 12 मिनट बाद फिर कोशिश करें।',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a short 429 uses the generic seconds message', (tester) async {
      final (env, _) = await pumpProfile(tester);
      env.backend.on(
        'PATCH',
        '/me',
        (_) => FakeResponse.error(
          429,
          'rate_limited',
          headers: {
            'retry-after': ['7'],
          },
        ),
      );
      await openEditor(tester);
      await type(tester, 'Rahul K');
      await tapSave(tester);
      expect(find.text(_en.errorRateLimitedRetry(7)), findsOneWidget);
    });

    testWidgets('other failures show a retryable banner', (tester) async {
      final (env, _) = await pumpProfile(tester);
      env.backend.on(
        'PATCH',
        '/me',
        (_) => FakeResponse.error(500, 'internal'),
      );
      await openEditor(tester);
      await type(tester, 'Rahul K');
      await tapSave(tester);
      expect(find.text(_en.errorInternal), findsOneWidget);
      expect(saveEnabled(tester), isTrue);

      env.backend.on(
        'PATCH',
        '/me',
        (req) =>
            FakeResponse(200, meJson(name: req.json['displayName'] as String)),
      );
      await tapSave(tester);
      expect(find.byType(DisplayNameForm), findsNothing);
      expect(tester.widget<Text>(find.byKey(_profileName)).data, 'Rahul K');
    });
  });

  group('layout', () {
    testWidgets('RTL (ar): sheet is right-to-left, labels localized', (
      tester,
    ) async {
      await pumpProfile(tester, locale: const Locale('ar'));
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(find.byTooltip(ar.profileEditNameTooltip), findsOneWidget);
      await openEditor(tester);
      expect(
        Directionality.of(tester.element(find.byKey(_field))),
        TextDirection.rtl,
      );
      expect(find.text(ar.profileEditNameTitle), findsOneWidget);
      expect(find.text(ar.profileNameLabel), findsOneWidget);
      // Start of the line is on the right: the pencil (end) sits left of
      // the name's center in RTL.
      await tester.tap(find.byKey(_cancel));
      await tester.pumpAndSettle();
      final pencil = tester.getCenter(find.byKey(_editButton));
      final name = tester.getCenter(find.byKey(_profileName));
      expect(pencil.dx, lessThan(name.dx));
      expect(tester.takeException(), isNull);
    });

    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets(
        '320×640, text ×1.35, dark, ${locale.languageCode}: no overflow',
        (tester) async {
          final (env, _) = await pumpProfile(
            tester,
            locale: locale,
            themeMode: ThemeMode.dark,
            size: Viewports.small,
            textScale: 1.35,
          );
          expect(tester.takeException(), isNull);
          await openEditor(tester);
          expect(tester.takeException(), isNull);
          // Longest states: a field error plus the server banner.
          env.backend.on(
            'PATCH',
            '/me',
            (_) => FakeResponse.error(429, 'rate_limited'),
          );
          await type(tester, 'Abcdefghij Klmnop');
          expect(errorText(tester), isNotNull);
          expect(tester.takeException(), isNull);
          await type(tester, 'Abcdefghij Klmno');
          await tapSave(tester);
          expect(find.byKey(_banner), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('keyboard open: sheet stays above it and scrolls', (
      tester,
    ) async {
      final (env, _) = await pumpProfile(
        tester,
        size: Viewports.small,
        textScale: 1.35,
      );
      await openEditor(tester);
      const keyboard = 300.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      const visibleBottom = 640 - keyboard;
      expect(tester.getRect(find.byKey(_field)).top, lessThan(visibleBottom));
      await tester.ensureVisible(find.byKey(_save));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_save)).bottom,
        lessThanOrEqualTo(visibleBottom),
      );
      expect(
        tester.getRect(find.byType(AppBottomSheetFrame)).top,
        greaterThanOrEqualTo(0),
      );

      // Still usable with the keyboard up: typing scrolls the caret into
      // view, and the user can scroll down to Save.
      await type(tester, 'Rahul K');
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_field)).bottom,
        lessThanOrEqualTo(visibleBottom),
      );
      await tester.ensureVisible(find.byKey(_save));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_save)).bottom,
        lessThanOrEqualTo(visibleBottom),
      );
      await tester.tap(find.byKey(_save));
      await drain(tester);
      await tester.pumpAndSettle();
      expect(env.backend.calls('PATCH', '/me'), hasLength(1));
      expect(find.byType(DisplayNameForm), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
