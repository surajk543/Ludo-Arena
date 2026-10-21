import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/profile/presentation/profile_picture_sheet.dart';
import 'package:ludo_royale/features/profile/presentation/profile_screen.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';
import '../store/store_test_support.dart';

const _list = '/store/profile-pictures';
const _apply = '/me/profile-picture';
const _avatar = ValueKey('profile-change-picture');
const _applyButton = ValueKey('picture-picker-apply');

Finder _choice(String id) => find.byKey(ValueKey('picture-choice-$id'));

/// Owned: #1, #2 (equipped), plus [extra] more owned pictures.
List<Map<String, dynamic>> _ownedShelf({int extra = 0}) => [
  storeItemJson(1, owned: true),
  storeItemJson(2, owned: true, equipped: true),
  for (var i = 0; i < extra; i++) storeItemJson(10 + i, owned: true),
];

void main() {
  late TestEnv env;

  setUp(() async {
    env = await TestEnv.create();
    env.routeHappyPath();
    routeStore(env, shelf: _ownedShelf());
    env.backend.on('PUT', _apply, (req) {
      final id = req.json['id'] as String?;
      return FakeResponse(200, {
        'equipped': id == null
            ? null
            : {
                ...storeItemJson(int.parse(id.split('_').last), owned: true),
                'equipped': true,
              },
      });
    });
  });

  GoRouter router() => GoRouter(
    initialLocation: AppRoutes.profile,
    routes: [
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.store,
        builder: (_, _) => const Scaffold(body: Text('AT /store')),
      ),
    ],
  );

  Future<ProviderContainer> pumpProfile(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
    Size size = Viewports.phone,
    double textScale = 1.0,
  }) => pumpScreen(
    tester,
    env,
    const ProfileScreen(),
    router: router(),
    locale: locale,
    themeMode: themeMode,
    size: size,
    textScale: textScale,
    prepare: (c) =>
        c.read(sessionControllerProvider.notifier).continueAsGuest(),
  );

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byKey(_avatar));
    await drain(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('tapping the avatar opens the picker: owned pictures plus the '
      'classic avatar, the equipped one marked', (tester) async {
    await pumpProfile(tester);
    await openPicker(tester);
    expect(find.text('Choose your picture'), findsOneWidget);
    expect(env.backend.calls('GET', _list).single.query['filter'], 'owned');
    expect(_choice('classic'), findsOneWidget);
    expect(_choice('pp_item_1'), findsOneWidget);
    expect(_choice('pp_item_2'), findsOneWidget);
    expect(
      find.descendant(
        of: _choice('pp_item_2'),
        matching: find.text('Equipped'),
      ),
      findsOneWidget,
    );
    expect(find.text('Equipped'), findsOneWidget);
    // Nothing to apply until another choice is picked.
    expect(
      tester.widget<PremiumButton>(find.byKey(_applyButton)).onPressed,
      isNull,
    );
  });

  testWidgets('picking an owned picture applies it and updates the profile', (
    tester,
  ) async {
    final c = await pumpProfile(tester);
    await openPicker(tester);
    await tester.tap(_choice('pp_item_1'));
    await tester.pump();
    await tester.tap(find.byKey(_applyButton));
    await drain(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(env.backend.calls('PUT', _apply).single.json, {'id': 'pp_item_1'});
    expect(find.byType(ProfilePicturePicker), findsNothing); // closed
    expect(find.text('Picture applied!'), findsOneWidget);
    expect(env.audio.played, contains(Sfx.uiConfirm));
    final picture = c.read(sessionControllerProvider).user!.picture!;
    expect(picture.id, 'pp_item_1');
    // The profile avatar now draws the picture (built-in while it loads).
    expect(find.byType(ProfilePictureView), findsOneWidget);
    expect(env.pictures.requested, contains(picture.path));
  });

  testWidgets('the classic avatar removes the picture', (tester) async {
    final c = await pumpProfile(tester);
    await openPicker(tester);
    await tester.tap(_choice('classic'));
    await tester.pump();
    await tester.tap(find.byKey(_applyButton));
    await drain(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(env.backend.calls('PUT', _apply).single.json, {'id': null});
    expect(find.text('Back to your classic avatar.'), findsOneWidget);
    expect(c.read(sessionControllerProvider).user!.picture, isNull);
  });

  testWidgets('a failed apply keeps the sheet open with the reason', (
    tester,
  ) async {
    env.backend.on(
      'PUT',
      _apply,
      (_) => FakeResponse.error(422, 'item_locked'),
    );
    await pumpProfile(tester);
    await openPicker(tester);
    await tester.tap(_choice('pp_item_1'));
    await tester.pump();
    await tester.tap(find.byKey(_applyButton));
    await drain(tester);
    expect(find.byType(ProfilePicturePicker), findsOneWidget);
    expect(find.byKey(const ValueKey('picture-picker-error')), findsOneWidget);
    expect(find.text('This item is still locked.'), findsOneWidget);
  });

  testWidgets('owned pictures are paged: Show more loads the next page', (
    tester,
  ) async {
    routeStore(env, shelf: _ownedShelf(extra: 3), pageSize: 2);
    await pumpProfile(tester);
    await openPicker(tester);
    expect(_choice('pp_item_2'), findsOneWidget);
    expect(_choice('pp_item_10'), findsNothing);

    final more = find.byKey(const ValueKey('picture-picker-more'));
    await tester.ensureVisible(more);
    await tester.pump();
    await tester.tap(more);
    await drain(tester);
    expect(env.backend.calls('GET', _list).last.query['cursor'], 'c2');
    expect(_choice('pp_item_10'), findsOneWidget);
    expect(_choice('pp_item_11'), findsOneWidget);
  });

  testWidgets('no owned pictures: the empty state points to the Store', (
    tester,
  ) async {
    routeStore(env, shelf: const []);
    await pumpProfile(tester);
    await openPicker(tester);
    expect(find.byKey(const ValueKey('picture-picker-empty')), findsOneWidget);
    expect(find.text('No pictures yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('picture-picker-store')));
    await drain(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('AT /store'), findsOneWidget);
  });

  testWidgets('Get more opens the Store', (tester) async {
    await pumpProfile(tester);
    await openPicker(tester);
    final link = find.byKey(const ValueKey('picture-picker-get-more'));
    await tester.ensureVisible(link);
    await tester.pump();
    await tester.tap(link);
    await drain(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('AT /store'), findsOneWidget);
    expect(env.backend.calls('PUT', _apply), isEmpty);
  });

  for (final (locale, mode) in const [
    (Locale('en'), ThemeMode.dark),
    (Locale('ar'), ThemeMode.light),
    (Locale('hi'), ThemeMode.dark),
    (Locale('ur'), ThemeMode.light),
    (Locale('id'), ThemeMode.dark),
  ]) {
    testWidgets('picker ${locale.languageCode} ${mode.name} @320x640 x1.35', (
      tester,
    ) async {
      routeStore(env, shelf: _ownedShelf(extra: 30));
      await pumpProfile(
        tester,
        locale: locale,
        themeMode: mode,
        size: Viewports.small,
        textScale: 1.35,
      );
      await openPicker(tester);
      expect(tester.takeException(), isNull);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
