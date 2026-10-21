import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/network/api_models.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/store/application/store_controller.dart';
import 'package:ludo_royale/features/store/data/store_api.dart';
import 'package:ludo_royale/features/store/domain/store_models.dart';
import 'package:ludo_royale/features/store/presentation/store_screen.dart';
import 'package:ludo_royale/features/store/presentation/widgets/store_picture_sheet.dart';
import 'package:ludo_royale/features/wallet/wallet_controller.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import '../progression/meta_test_support.dart';
import 'store_test_support.dart';

const _list = '/store/profile-pictures';
String _buy(int i) => '/store/profile-pictures/pp_item_$i/purchase';
const _apply = '/me/profile-picture';

Map<String, dynamic> _owned(int i, {bool equipped = false}) => {
  ...storeShelf()[i],
  'owned': true,
  'equipped': equipped,
};

void main() {
  setUpAll(() async => initializeDateFormatting());

  group('models', () {
    test('a page parses items, cursor, total and the applied picture', () {
      final page = StorePage.fromJson(
        storePageJson(
          storeShelf().take(3).toList(),
          nextCursor: 'c3',
          total: 30,
        ),
      );
      expect(page.items.map((p) => p.id), [
        'pp_item_0',
        'pp_item_1',
        'pp_item_2',
      ]);
      expect(page.nextCursor, 'c3');
      expect(page.total, 30);
      expect(page.equipped, 'pp_item_2');
      final first = page.items.first;
      expect(first.priceDiamonds, 10);
      expect(first.isAnimated, isFalse);
      expect(first.picture!.path, 'profile_pictures/image/item-0.png');
      expect(page.items[2].owned && page.items[2].equipped, isTrue);

      final last = StorePage.fromJson(storePageJson([], equipped: null));
      expect(last.nextCursor, isNull);
      expect(last.equipped, isNull);
    });

    test('an unusable path still lists the item, without a picture', () {
      final p = ProfilePicture.fromJson({
        ...storeItemJson(1),
        'path': '../../x',
      });
      expect(p.id, 'pp_item_1');
      expect(p.picture, isNull);
    });

    test('affordability is display only', () {
      final p = ProfilePicture.fromJson(storeItemJson(3, price: 60));
      expect(p.affordableWith(const Wallet(coins: 0, diamonds: 50)), isFalse);
      expect(p.shortfall(const Wallet(coins: 0, diamonds: 50)), 10);
      expect(p.affordableWith(null), isTrue);
    });
  });

  group('controller (fake API)', () {
    late TestEnv env;
    late MetaFakes fakes;
    late ProviderContainer c;

    Future<void> loaded() async {
      for (var i = 0; i < 50 && c.read(storeProvider).loading; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeStore(env);
      fakes = MetaFakes();
      c = metaContainer(env, fakes);
      await signIn(c);
      c.listen(storeProvider, (_, _) {});
      await loaded();
    });
    tearDown(() => fakes.close());

    StoreController ctl() => c.read(storeProvider.notifier);
    StoreState s() => c.read(storeProvider);
    ProfilePicture item(int i) => s().byId('pp_item_$i')!;

    test('loads the first page, then appends the next one once', () async {
      expect(s().items, hasLength(24));
      expect(s().hasMore, isTrue);
      expect(s().equippedId, 'pp_item_2');
      final first = env.backend.calls('GET', _list).single;
      expect(first.query, {'filter': 'all', 'limit': '24'});

      await Future.wait([ctl().loadMore(), ctl().loadMore()]);
      expect(s().items, hasLength(30));
      expect(s().hasMore, isFalse);
      final calls = env.backend.calls('GET', _list);
      expect(calls, hasLength(2));
      expect(calls.last.query['cursor'], 'c24');

      await ctl().loadMore(); // at the end: no request
      expect(env.backend.calls('GET', _list), hasLength(2));
    });

    test('a failed next page keeps the shelf and retries on demand', () async {
      var fail = true;
      env.backend.on('GET', _list, (req) {
        if (req.query['cursor'] != null && fail) {
          return FakeResponse.error(500, 'internal');
        }
        final start = req.query['cursor'] == null ? 0 : 24;
        final end = start == 0 ? 24 : 30;
        return FakeResponse(
          200,
          storePageJson(
            storeShelf().sublist(start, end),
            nextCursor: end < 30 ? 'c$end' : null,
          ),
        );
      });
      await ctl().loadMore();
      expect(s().moreError, isNotNull);
      expect(s().items, hasLength(24));
      await ctl().loadMore(); // no automatic retry loop
      expect(env.backend.calls('GET', _list), hasLength(2));
      fail = false;
      await ctl().loadMore(retry: true);
      expect(s().moreError, isNull);
      expect(s().items, hasLength(30));
    });

    test(
      'switching the filter loads that filter from its first page',
      () async {
        ctl().setFilter(StoreFilter.owned);
        expect(s().loading, isTrue);
        expect(s().items, isEmpty);
        await loaded();
        expect(s().filter, StoreFilter.owned);
        expect(s().items.map((p) => p.id), ['pp_item_1', 'pp_item_2']);
        expect(env.backend.calls('GET', _list).last.query['filter'], 'owned');

        ctl().setFilter(StoreFilter.still);
        await loaded();
        expect(env.backend.calls('GET', _list).last.query['filter'], 'static');
        expect(s().items.every((p) => !p.isAnimated), isTrue);
      },
    );

    test('a purchase applies the server wallet and ownership; a transient '
        'failure keeps the Idempotency-Key for the retry', () async {
      var attempts = 0;
      env.backend.on('POST', _buy(0), (req) {
        attempts++;
        if (attempts == 1) return FakeResponse.error(503, 'internal');
        return FakeResponse(200, {
          'item': _owned(0),
          'wallet': {'coins': 1000000, 'diamonds': 40},
        });
      });
      final first = await ctl().purchase(item(0));
      expect((first as StoreFailed).code, 'internal');
      expect(ctl().pendingPurchaseKey('pp_item_0'), 'idem-key-1');

      expect(await ctl().purchase(item(0)), isA<StoreSucceeded>());
      final keys = env.backend
          .calls('POST', _buy(0))
          .map((r) => r.header('Idempotency-Key'));
      expect(keys, ['idem-key-1', 'idem-key-1']);
      expect(ctl().pendingPurchaseKey('pp_item_0'), isNull);
      expect(item(0).owned, isTrue);
      expect(c.read(walletControllerProvider).diamonds, 40);
      expect(
        fakes.analytics.events,
        contains('cosmetic_unlocked:$kProfilePictureItemKind:'),
      );
    });

    test('already_owned shows the item as owned; insufficient_funds '
        'refreshes the balance', () async {
      env.backend
        ..on('POST', _buy(0), (_) => FakeResponse.error(409, 'already_owned'))
        ..on(
          'POST',
          _buy(4),
          (_) => FakeResponse.error(422, 'insufficient_funds'),
        )
        ..json('GET', '/wallet', {'coins': 1000000, 'diamonds': 3});
      expect(
        ((await ctl().purchase(item(0))) as StoreFailed).code,
        'already_owned',
      );
      expect(item(0).owned, isTrue);
      expect(
        ((await ctl().purchase(item(4))) as StoreFailed).code,
        'insufficient_funds',
      );
      await settle();
      expect(env.backend.calls('GET', '/wallet'), hasLength(1));
      expect(c.read(walletControllerProvider).diamonds, 3);
      expect(item(4).owned, isFalse);
    });

    test('apply moves the equipped flag and updates the signed-in user at '
        'once; null goes back to the built-in avatar', () async {
      env.backend.on('PUT', _apply, (req) {
        final id = req.json['id'];
        return FakeResponse(200, {
          'equipped': id == null ? null : _owned(1, equipped: true),
        });
      });
      expect(await ctl().apply(item(1)), isA<StoreSucceeded>());
      expect(env.backend.calls('PUT', _apply).last.json, {'id': 'pp_item_1'});
      expect(item(1).equipped, isTrue);
      expect(item(2).equipped, isFalse);
      expect(s().equippedId, 'pp_item_1');
      final user = c.read(sessionControllerProvider).user!;
      expect(user.picture!.id, 'pp_item_1');
      expect(
        user.picture!.path,
        'profile_pictures/lottie_animation/item-1.json',
      );
      expect(
        fakes.analytics.events,
        contains('cosmetic_equipped:$kProfilePictureItemKind'),
      );

      expect(await ctl().apply(null), isA<StoreSucceeded>());
      expect(env.backend.calls('PUT', _apply).last.json, {'id': null});
      expect(s().items.where((p) => p.equipped), isEmpty);
      expect(c.read(sessionControllerProvider).user!.picture, isNull);
    });

    test('item_locked on apply shows the item as not owned', () async {
      env.backend.on(
        'PUT',
        _apply,
        (_) => FakeResponse.error(422, 'item_locked'),
      );
      final r = await ctl().apply(item(1));
      expect((r as StoreFailed).code, 'item_locked');
      expect(item(1).owned, isFalse);
      expect(c.read(sessionControllerProvider).user!.picture, isNull);
    });

    test('the API sends the documented requests', () async {
      final api = c.read(storeApiProvider);
      await api.list(filter: StoreFilter.animated, cursor: 'c24', limit: 12);
      expect(env.backend.calls('GET', _list).last.query, {
        'filter': 'animated',
        'limit': '12',
        'cursor': 'c24',
      });
    });
  });

  group('screen', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeStore(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    Future<ProviderContainer> pumpStore(WidgetTester tester) async {
      final c = await pumpMeta(tester, env, fakes, const StoreScreen());
      await flush(tester);
      return c;
    }

    Finder tile(int i) => byKeyString('pp-pp_item_$i');

    Future<void> openSheet(WidgetTester tester, int i) async {
      await scrollTo(tester, tile(i));
      await tester.tap(tile(i));
      await settleRoute(tester);
    }

    testWidgets('shows the first page; reaching the end loads the next page', (
      tester,
    ) async {
      await pumpStore(tester);
      expect(find.text('Profile pictures'), findsOneWidget);
      expect(tile(0), findsOneWidget);
      expect(find.text('Equipped'), findsWidgets);
      expect(env.backend.calls('GET', _list), hasLength(1));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await flush(tester);
      final calls = env.backend.calls('GET', _list);
      expect(calls, hasLength(2));
      expect(calls.last.query['cursor'], 'c24');
      await scrollTo(tester, tile(29));
      expect(tile(29), findsOneWidget);
      expect(env.backend.calls('GET', _list), hasLength(2));
    });

    testWidgets('filter pills switch the shelf; an empty Owned shelf offers '
        'Browse all', (tester) async {
      routeStore(
        env,
        shelf: [
          for (final i in storeShelf())
            {...i, 'owned': false, 'equipped': false},
        ],
      );
      await pumpStore(tester);
      await tester.tap(find.text('Animated'));
      await flush(tester);
      expect(env.backend.calls('GET', _list).last.query['filter'], 'animated');
      expect(tile(0), findsNothing); // an image
      expect(tile(1), findsOneWidget);

      final ownedPill = find.text('Owned').first;
      await tester.ensureVisible(ownedPill);
      await tester.pump();
      await tester.tap(ownedPill);
      await flush(tester);
      expect(find.text('No pictures yet'), findsOneWidget);
      await tester.tap(byKeyString('store-browse-all'));
      await flush(tester);
      expect(env.backend.calls('GET', _list).last.query['filter'], 'all');
      expect(tile(0), findsOneWidget);
    });

    testWidgets('buy, then apply from the sheet', (tester) async {
      env.backend
        ..json('POST', _buy(0), {
          'item': _owned(0),
          'wallet': {'coins': 1000000, 'diamonds': 40},
        })
        ..on(
          'PUT',
          _apply,
          (_) => FakeResponse(200, {'equipped': _owned(0, equipped: true)}),
        );
      final c = await pumpStore(tester);
      await openSheet(tester, 0);
      expect(find.text('10 diamonds'), findsOneWidget); // price
      expect(find.text('50 diamonds'), findsOneWidget); // balance

      await tester.tap(byKeyString('store-buy'));
      await settleRoute(tester);
      final buy = env.backend.calls('POST', _buy(0)).single;
      expect(buy.header('Idempotency-Key'), 'idem-key-1');
      expect(find.text('Item 0 is yours forever!'), findsOneWidget);
      expect(env.audio.played, contains(Sfx.purchase));
      expect(c.read(walletControllerProvider).diamonds, 40);

      await tester.tap(byKeyString('store-apply'));
      await settleRoute(tester);
      expect(env.backend.calls('PUT', _apply).single.json, {'id': 'pp_item_0'});
      expect(find.text('Picture applied!'), findsOneWidget);
      expect(env.audio.played, contains(Sfx.uiConfirm));
      expect(c.read(sessionControllerProvider).user!.picture!.id, 'pp_item_0');
      expect(byKeyString('store-remove'), findsOneWidget);
    });

    testWidgets('not enough diamonds: Buy is disabled with a note', (
      tester,
    ) async {
      await pumpStore(tester);
      await openSheet(tester, 3);
      final buy = tester.widget<PremiumButton>(byKeyString('store-buy'));
      expect(buy.onPressed, isNull);
      expect(byKeyString('store-need-more'), findsOneWidget);
      expect(find.textContaining('another 10 diamonds'), findsOneWidget);
      await tester.tap(byKeyString('store-buy'), warnIfMissed: false);
      await settleRoute(tester);
      expect(env.backend.calls('POST', _buy(3)), isEmpty);
    });

    testWidgets('already owned on the server: explained, then Apply', (
      tester,
    ) async {
      env.backend.on(
        'POST',
        _buy(0),
        (_) => FakeResponse.error(409, 'already_owned'),
      );
      await pumpStore(tester);
      await openSheet(tester, 0);
      await tester.tap(byKeyString('store-buy'));
      await settleRoute(tester);
      expect(find.text('You already own this item.'), findsOneWidget);
      expect(byKeyString('store-apply'), findsOneWidget);
    });

    testWidgets('remove goes back to the classic avatar', (tester) async {
      env.backend.json('PUT', _apply, {'equipped': null});
      final c = await pumpStore(tester);
      await openSheet(tester, 2);
      await tester.tap(byKeyString('store-remove'));
      await settleRoute(tester);
      expect(env.backend.calls('PUT', _apply).single.json, {'id': null});
      expect(find.text('Back to your classic avatar.'), findsOneWidget);
      expect(c.read(sessionControllerProvider).user!.picture, isNull);
      expect(byKeyString('store-apply'), findsOneWidget);
    });

    testWidgets('a failed first page offers Retry', (tester) async {
      var fail = true;
      env.backend.on('GET', _list, (req) {
        if (fail) return FakeResponse.error(500, 'internal');
        return FakeResponse(200, storePageJson(storeShelf().take(6).toList()));
      });
      await pumpStore(tester);
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await flush(tester);
      expect(tile(0), findsOneWidget);
    });
  });

  // 320×640 at the largest text scale, every language, both themes: the
  // grid and the sheet lay out without overflow (RTL for ar/ur).
  for (final locale in const ['en', 'hi', 'ur', 'id', 'ar']) {
    for (final mode in ThemeMode.values.skip(1)) {
      testWidgets('store + sheet $locale ${mode.name} @320x640 x1.35', (
        tester,
      ) async {
        final env = await TestEnv.create();
        env.routeHappyPath();
        routeStore(env);
        final fakes = MetaFakes();
        addTearDown(fakes.close);
        await pumpMeta(
          tester,
          env,
          fakes,
          const StoreScreen(),
          locale: Locale(locale),
          themeMode: mode,
          size: Viewports.small,
          textScale: 1.35,
        );
        await flush(tester);
        expect(tester.takeException(), isNull);
        // Owned, equipped, too expensive, long name (scrolling down only).
        for (final i in [1, 2, 3, 4]) {
          await scrollTo(tester, byKeyString('pp-pp_item_$i'));
          await tester.tap(byKeyString('pp-pp_item_$i'));
          await settleRoute(tester);
          expect(tester.takeException(), isNull, reason: 'sheet $i');
          Navigator.of(tester.element(find.byType(StorePictureSheet))).pop();
          await settleRoute(tester);
        }
        await scrollThrough(tester);
        await flush(tester);
        expect(tester.takeException(), isNull);
        final rtl = locale == 'ar' || locale == 'ur';
        expect(
          Directionality.of(tester.element(find.byType(StoreScreen))),
          rtl ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }
  }
}
