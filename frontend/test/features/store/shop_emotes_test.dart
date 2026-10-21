import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lottie/lottie.dart';
import 'package:ludo_royale/core/assets/profile_picture_cache.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/network/api_models.dart';
import 'package:ludo_royale/features/collection/domain/collection_models.dart';
import 'package:ludo_royale/features/collection/presentation/collection_screen.dart';
import 'package:ludo_royale/features/collection/presentation/widgets/item_detail_sheet.dart';
import 'package:ludo_royale/features/game/application/owned_emotes.dart';
import 'package:ludo_royale/features/meta_routes.dart';
import 'package:ludo_royale/features/store/application/emote_shelf_controller.dart';
import 'package:ludo_royale/features/store/application/shop_category.dart';
import 'package:ludo_royale/features/store/application/store_controller.dart';
import 'package:ludo_royale/features/store/data/store_api.dart';
import 'package:ludo_royale/features/store/domain/store_models.dart';
import 'package:ludo_royale/features/store/presentation/shop_screen.dart';
import 'package:ludo_royale/features/store/presentation/widgets/emote_shelf.dart';
import 'package:ludo_royale/features/store/presentation/widgets/store_emote_sheet.dart';
import 'package:ludo_royale/features/wallet/wallet_controller.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import '../../helpers/picture_fixtures.dart';
import '../progression/meta_test_support.dart';
import 'store_test_support.dart';

const _list = '/store/emotes';
String _buy(int i) => '/store/emotes/em_item_$i/purchase';

Finder _tile(int i) => byKeyString('em-em_item_$i');

/// Marks emote [i] of [shelf] owned on the fake server and answers the
/// purchase like the real one.
void _routeBuy(TestEnv env, List<Map<String, dynamic>> shelf, int i) {
  env.backend.on('POST', _buy(i), (_) {
    shelf[i]['owned'] = true;
    return FakeResponse(200, {
      'item': {...shelf[i], 'owned': true},
      'wallet': {'coins': 1000000, 'diamonds': 40},
    });
  });
}

void main() {
  setUpAll(() async => initializeDateFormatting());

  group('models', () {
    test('a page parses items, cursor and total; prices are diamonds', () {
      final page = EmotePage.fromJson(
        emotePageJson(
          emoteShelf().take(3).toList(),
          nextCursor: 'c3',
          total: 30,
        ),
      );
      expect(page.items.map((e) => e.id), [
        'em_item_0',
        'em_item_1',
        'em_item_2',
      ]);
      expect(page.nextCursor, 'c3');
      expect(page.total, 30);
      final first = page.items.first;
      expect(first.priceDiamonds, 10);
      expect(first.isAnimated, isTrue);
      expect(first.asset!.path, 'emotes/item-0.json');
      expect(page.items[1].owned, isTrue);
      expect(EmotePage.fromJson(emotePageJson([])).nextCursor, isNull);
    });

    test('an unusable path still lists the emote, without art', () {
      final e = ShopEmote.fromJson({...shopEmoteJson(1), 'path': '../x.json'});
      expect(e.id, 'em_item_1');
      expect(e.asset, isNull);
      expect(
        ShopEmote.fromJson({
          ...shopEmoteJson(1),
          'path': 'profile_pictures/image/x.png',
        }).asset,
        isNull,
      );
      final dear = ShopEmote.fromJson(shopEmoteJson(3, price: 60));
      expect(dear.affordableWith(const Wallet(coins: 0, diamonds: 50)), false);
      expect(dear.shortfall(const Wallet(coins: 0, diamonds: 50)), 10);
    });

    test('Emotes is always a Shop category', () {
      expect(shopCategories(null), contains(kShopEmoteCategory));
      final data = CollectionData.fromJson(
        collectionJson(extraOwned: {'emote_crown'}),
      );
      expect(data.shopItems('emote'), isEmpty);
      expect(shopCategories(data).last, kShopEmoteCategory);
    });
  });

  group('shelf controllers (fake API)', () {
    late TestEnv env;
    late MetaFakes fakes;
    late ProviderContainer c;
    late List<Map<String, dynamic>> shelf;

    Future<void> loaded(EmoteShelfProvider p) async {
      for (var i = 0; i < 50 && c.read(p).loading; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      shelf = routeStoreEmotes(env);
      fakes = MetaFakes();
      c = metaContainer(env, fakes);
      await signIn(c);
      c.listen(shopEmotesProvider, (_, _) {});
      await loaded(shopEmotesProvider);
    });
    tearDown(() => fakes.close());

    EmoteShelfController shop() => c.read(shopEmotesProvider.notifier);
    EmoteShelfState s() => c.read(shopEmotesProvider);
    ShopEmote item(int i) => s().byId('em_item_$i')!;

    test('the Shop lists only emotes not owned yet, page by page', () async {
      expect(s().items, hasLength(24));
      expect(s().total, 28);
      expect(s().byId('em_item_1'), isNull);
      expect(s().hasMore, isTrue);
      expect(env.backend.calls('GET', _list).single.query, {
        'filter': 'all',
        'excludeOwned': 'true',
        'limit': '24',
      });

      await Future.wait([shop().loadMore(), shop().loadMore()]);
      expect(s().items, hasLength(28));
      expect(s().hasMore, isFalse);
      final calls = env.backend.calls('GET', _list);
      expect(calls, hasLength(2));
      expect(calls.last.query['cursor'], 'c24');
      await shop().loadMore(); // at the end: no request
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
          emotePageJson(
            emoteShelf().sublist(start, end),
            nextCursor: end < 30 ? 'c$end' : null,
          ),
        );
      });
      await shop().loadMore();
      expect(s().moreError, isNotNull);
      await shop().loadMore(); // no automatic retry loop
      expect(env.backend.calls('GET', _list), hasLength(2));
      fail = false;
      await shop().loadMore(retry: true);
      expect(s().moreError, isNull);
      expect(s().items.length, greaterThan(24));
    });

    test('a purchase applies the server wallet, the emote leaves the Shop '
        'and joins the owned shelf; a transient failure keeps the '
        'Idempotency-Key', () async {
      c.listen(ownedStoreEmotesProvider, (_, _) {});
      await loaded(ownedStoreEmotesProvider);
      expect(c.read(ownedStoreEmotesProvider).total, 2);
      expect(env.backend.calls('GET', _list).last.query, {
        'filter': 'owned',
        'limit': '24',
      });

      var attempts = 0;
      env.backend.on('POST', _buy(0), (req) {
        if (++attempts == 1) return FakeResponse.error(503, 'internal');
        shelf[0]['owned'] = true;
        return FakeResponse(200, {
          'item': {...shelf[0], 'owned': true},
          'wallet': {'coins': 1000000, 'diamonds': 40},
        });
      });
      final first = await shop().purchase(item(0));
      expect((first as StoreFailed).code, 'internal');
      expect(shop().pendingPurchaseKey('em_item_0'), 'idem-key-1');
      expect(s().byId('em_item_0'), isNotNull);

      expect(await shop().purchase(item(0)), isA<StoreSucceeded>());
      expect(
        env.backend
            .calls('POST', _buy(0))
            .map((r) => r.header('Idempotency-Key')),
        ['idem-key-1', 'idem-key-1'],
      );
      expect(shop().pendingPurchaseKey('em_item_0'), isNull);
      expect(s().byId('em_item_0'), isNull);
      expect(s().total, 27);
      expect(c.read(walletControllerProvider).diamonds, 40);
      expect(
        fakes.analytics.events,
        contains('cosmetic_unlocked:$kStoreEmoteItemKind:'),
      );
      // The owned shelf reloads with it.
      await settle();
      await loaded(ownedStoreEmotesProvider);
      expect(c.read(ownedStoreEmotesProvider).byId('em_item_0'), isNotNull);
      expect(c.read(ownedStoreEmotesProvider).total, 3);
    });

    test('already_owned also leaves the Shop; insufficient_funds refreshes '
        'the balance and keeps the emote', () async {
      env.backend
        ..on('POST', _buy(0), (_) => FakeResponse.error(409, 'already_owned'))
        ..on(
          'POST',
          _buy(4),
          (_) => FakeResponse.error(422, 'insufficient_funds'),
        )
        ..json('GET', '/wallet', {'coins': 1000000, 'diamonds': 3});
      expect(
        ((await shop().purchase(item(0))) as StoreFailed).code,
        'already_owned',
      );
      expect(s().byId('em_item_0'), isNull);
      expect(
        ((await shop().purchase(item(4))) as StoreFailed).code,
        'insufficient_funds',
      );
      await settle();
      expect(env.backend.calls('GET', '/wallet'), hasLength(1));
      expect(c.read(walletControllerProvider).diamonds, 3);
      expect(item(4).owned, isFalse);
    });

    test('the in-match picker lists built-in emotes, then the bought Store '
        'emotes with their art', () async {
      routeMeta(env);
      shelf = routeStoreEmotes(env, pageSize: 1); // pages through
      final before = env.backend.calls('GET', _list).length;
      final sub = c.listen(ownedEmotesProvider, (_, _) {});
      addTearDown(sub.close);
      final emotes = await c.read(ownedEmotesProvider.future);
      expect(emotes.map((e) => e.id), [
        'emote_wave',
        'emote_thumbs',
        'emote_laugh',
        'em_item_1',
        'em_item_2',
      ]);
      expect(emotes[3].asset!.path, 'emotes/item-1.json');
      expect(emotes[3].name, 'Emote 1');
      expect(emotes.first.asset, isNull);
      final calls = env.backend.calls('GET', _list).skip(before).toList();
      expect(calls, hasLength(2));
      expect(calls.map((r) => r.query['filter']).toSet(), {'owned'});
      expect(calls.first.query['limit'], '50');
      expect(calls.last.query['cursor'], 'c1');

      // The Store being unavailable leaves the built-in emotes.
      env.backend.on('GET', _list, (_) => FakeResponse.error(500, 'internal'));
      c.invalidate(ownedEmotesProvider);
      expect((await c.read(ownedEmotesProvider.future)).map((e) => e.id), [
        'emote_wave',
        'emote_thumbs',
        'emote_laugh',
      ]);
    });

    test('the API sends the documented requests', () async {
      final api = c.read(storeApiProvider);
      await api.listEmotes(filter: EmoteFilter.owned, cursor: 'c12', limit: 12);
      expect(env.backend.calls('GET', _list).last.query, {
        'filter': 'owned',
        'limit': '12',
        'cursor': 'c12',
      });
    });
  });

  group('screens', () {
    late TestEnv env;
    late MetaFakes fakes;
    late List<Map<String, dynamic>> shelf;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      routeStore(env);
      shelf = routeStoreEmotes(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    Future<ProviderContainer> pumpShop(WidgetTester tester) async {
      final c = await pumpMeta(
        tester,
        env,
        fakes,
        const ShopScreen(initialCategory: kShopEmoteCategory),
      );
      await flush(tester);
      return c;
    }

    Future<void> openSheet(WidgetTester tester, int i) async {
      await scrollTo(tester, _tile(i));
      await tester.tap(_tile(i));
      await settleRoute(tester);
    }

    testWidgets('Emotes: the priced catalogue emote on top, then the Store '
        'emotes not owned; reaching the end loads the next page', (
      tester,
    ) async {
      await pumpShop(tester);
      expect(
        find.text(
          'Send them in any match. Buy once with diamonds, keep '
          'them forever.',
        ),
        findsOneWidget,
      );
      expect(byKeyString('shop-item-emote_crown'), findsOneWidget);
      expect(find.text('Animated emotes'), findsOneWidget);
      expect(_tile(0), findsOneWidget);
      expect(_tile(1), findsNothing); // owned
      expect(_tile(2), findsNothing); // owned
      expect(find.text('Owned'), findsNothing);
      expect(env.backend.calls('GET', _list), hasLength(1));
      // The Shop draws the art from the emote cache.
      expect(env.emotes.requested, contains('emotes/item-0.json'));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await flush(tester);
      final calls = env.backend.calls('GET', _list);
      expect(calls, hasLength(2));
      expect(calls.last.query['cursor'], 'c24');
      await scrollTo(tester, _tile(29));
      expect(_tile(29), findsOneWidget);
    });

    testWidgets('a cached emote animates on its tile', (tester) async {
      env.emotes.ready['emotes/item-0.json'] = LoadedLottiePicture(
        testComposition(),
      );
      await pumpShop(tester);
      expect(
        find.descendant(of: _tile(0), matching: find.byType(Lottie)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tile(5), matching: find.byType(Lottie)),
        findsNothing,
      );
    });

    testWidgets('buy from the sheet: the emote leaves the Shop and shows in '
        'the Collection', (tester) async {
      _routeBuy(env, shelf, 0);
      final router = GoRouter(
        initialLocation: '/shop?category=emote',
        routes: metaRoutes,
      );
      final c = await pumpMeta(
        tester,
        env,
        fakes,
        const SizedBox(),
        router: router,
      );
      await flush(tester);
      await openSheet(tester, 0);
      expect(find.text('Animated emote'), findsOneWidget);
      expect(find.text('10 diamonds'), findsOneWidget); // price
      expect(find.text('50 diamonds'), findsOneWidget); // balance

      await tester.tap(byKeyString('store-emote-buy'));
      await settleRoute(tester);
      final buy = env.backend.calls('POST', _buy(0)).single;
      expect(buy.header('Idempotency-Key'), 'idem-key-1');
      expect(find.text('Emote 0 is yours forever!'), findsOneWidget);
      expect(env.audio.played, contains(Sfx.purchase));
      expect(c.read(walletControllerProvider).diamonds, 40);
      expect(c.read(shopEmotesProvider).byId('em_item_0'), isNull);
      expect(byKeyString('store-emote-use-note'), findsOneWidget);

      await tester.tap(byKeyString('store-emote-view-in-collection'));
      await settleRoute(tester);
      expect(find.byType(CollectionScreen), findsOneWidget);
      await flush(tester);
      await scrollTo(tester, byKeyString('em-em_item_0'));
      expect(byKeyString('em-em_item_0'), findsOneWidget);
      expect(byKeyString('em-em_item_1'), findsOneWidget);
      // Owned in the Collection: the sheet has no Buy.
      await tester.tap(byKeyString('em-em_item_0'));
      await settleRoute(tester);
      expect(byKeyString('store-emote-buy'), findsNothing);
      expect(byKeyString('store-emote-use-note'), findsOneWidget);
      expect(find.byType(StoreEmoteSheet), findsOneWidget);
    });

    testWidgets('not enough diamonds: Buy is disabled with a note', (
      tester,
    ) async {
      await pumpShop(tester);
      await openSheet(tester, 3);
      final buy = tester.widget<PremiumButton>(byKeyString('store-emote-buy'));
      expect(buy.onPressed, isNull);
      expect(byKeyString('store-emote-need-more'), findsOneWidget);
      expect(find.textContaining('another 10 diamonds'), findsOneWidget);
      await tester.tap(byKeyString('store-emote-buy'), warnIfMissed: false);
      await settleRoute(tester);
      expect(env.backend.calls('POST', _buy(3)), isEmpty);
    });

    testWidgets('the catalogue emote opens the Collection item sheet', (
      tester,
    ) async {
      await pumpShop(tester);
      await tester.tap(byKeyString('shop-item-emote_crown'));
      await settleRoute(tester);
      expect(find.byType(CollectionItemSheet), findsOneWidget);
    });

    testWidgets('everything owned: You own them all, View in Collection', (
      tester,
    ) async {
      env.backend.json(
        'GET',
        '/collection',
        collectionJson(extraOwned: {'emote_crown'}),
      );
      routeStoreEmotes(
        env,
        shelf: [for (var i = 0; i < 3; i++) shopEmoteJson(i, owned: true)],
      );
      await pumpShop(tester);
      expect(find.text('You own them all!'), findsOneWidget);
      expect(byKeyString('shop-view-in-collection'), findsOneWidget);
    });

    testWidgets('a failed first page offers Retry', (tester) async {
      var fail = true;
      env.backend.on('GET', _list, (req) {
        if (fail) return FakeResponse.error(500, 'internal');
        return FakeResponse(200, emotePageJson(emoteShelf().take(6).toList()));
      });
      await pumpShop(tester);
      expect(byKeyString('shop-item-emote_crown'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await flush(tester);
      expect(_tile(0), findsOneWidget);
    });

    testWidgets('Collection Emotes: built-in emotes, then the bought Store '
        'emotes page by page; the tab counts both', (tester) async {
      final owned = [
        for (var i = 0; i < 30; i++) shopEmoteJson(i, owned: true),
      ];
      routeStoreEmotes(env, shelf: owned);
      await pumpMeta(
        tester,
        env,
        fakes,
        const CollectionScreen(initialKind: kShopEmoteCategory),
      );
      await flush(tester);
      expect(byKeyString('item-emote_wave'), findsOneWidget);
      // 3 of 4 catalogue emotes + 30 bought.
      expect(find.text('33/34'), findsOneWidget);
      final first = env.backend.calls('GET', _list).first.query;
      expect(first['filter'], 'owned');
      expect(first.containsKey('excludeOwned'), isFalse);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
      await flush(tester);
      final calls = env.backend.calls('GET', _list);
      expect(calls.last.query['cursor'], 'c24');
      await scrollTo(tester, _tile(29));
      expect(_tile(29), findsOneWidget);

      // "To unlock" lists only what is still to earn.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 9000));
      await flush(tester);
      await tester.tap(find.text('To unlock'));
      await tester.pump();
      expect(byKeyString('collection-store-emotes'), findsNothing);
      expect(_tile(0), findsNothing);
    });

    testWidgets('Collection Emotes without bought emotes points to the Shop', (
      tester,
    ) async {
      routeStoreEmotes(env, shelf: [shopEmoteJson(0)]);
      await pumpMeta(
        tester,
        env,
        fakes,
        const CollectionScreen(initialKind: kShopEmoteCategory),
      );
      await flush(tester);
      await scrollTo(tester, byKeyString('collection-store-emotes-empty'));
      expect(
        find.text('Animated emotes you buy in the Shop show up here.'),
        findsOneWidget,
      );
      await scrollTo(tester, byKeyString('collection-more-in-shop'));
      expect(byKeyString('collection-more-in-shop'), findsOneWidget);
    });
  });

  // Phone widths and a tablet, the text scales up to the app's maximum
  // (1.35, app.dart) and beyond, LTR and RTL: the Shop's Emotes, the emote
  // sheet and the Collection's Emotes tab lay out without overflow. (At 2×
  // the Shop's app-bar balance chips, which predate the emotes, need more
  // than 360 px: the app never renders above 1.35×, so the Shop runs at 2×
  // from 412 px; the Collection and the sheet at every width.)
  const sizes = [
    Size(320, 640),
    Size(360, 740),
    Size(412, 892),
    Viewports.tablet,
  ];
  for (final locale in const ['en', 'ar']) {
    for (final size in sizes) {
      for (final scale in const [1.0, 1.3, 1.35, 2.0]) {
        final name =
            'emotes $locale ${size.width.toInt()}x${size.height.toInt()} '
            'x$scale';
        testWidgets(name, (tester) async {
          final env = await TestEnv.create();
          env.routeHappyPath();
          routeMeta(env);
          routeStoreEmotes(env);
          for (final p in ['emotes/item-0.json', 'emotes/item-1.json']) {
            env.emotes.ready[p] = LoadedLottiePicture(testComposition());
          }
          final fakes = MetaFakes();
          addTearDown(fakes.close);
          final shop = scale <= 1.35 || size.width >= 412;
          if (shop) {
            await pumpMeta(
              tester,
              env,
              fakes,
              const ShopScreen(initialCategory: kShopEmoteCategory),
              locale: Locale(locale),
              themeMode: scale == 1.3 ? ThemeMode.dark : ThemeMode.light,
              size: size,
              textScale: scale,
            );
            await flush(tester);
            expect(tester.takeException(), isNull);
            // Cheap (cached art), too expensive, long name.
            for (final i in [0, 3, 4]) {
              await scrollTo(tester, _tile(i));
              await tester.tap(_tile(i));
              await settleRoute(tester);
              expect(tester.takeException(), isNull, reason: 'sheet $i');
              Navigator.of(tester.element(find.byType(StoreEmoteSheet))).pop();
              await settleRoute(tester);
            }
            await scrollThrough(tester);
            await flush(tester);
            expect(tester.takeException(), isNull);
            expect(
              Directionality.of(tester.element(find.byType(ShopScreen))),
              locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            );
            await tester.pumpWidget(const SizedBox());
          }

          await pumpMeta(
            tester,
            env,
            fakes,
            const CollectionScreen(initialKind: kShopEmoteCategory),
            locale: Locale(locale),
            size: size,
            textScale: scale,
          );
          await flush(tester);
          expect(tester.takeException(), isNull, reason: 'collection');
          // An owned emote's sheet (cached art).
          await scrollTo(tester, _tile(1));
          await tester.tap(_tile(1));
          await settleRoute(tester);
          expect(tester.takeException(), isNull, reason: 'owned sheet');
          Navigator.of(tester.element(find.byType(StoreEmoteSheet))).pop();
          await settleRoute(tester);
          await scrollThrough(tester);
          await flush(tester);
          expect(tester.takeException(), isNull, reason: 'collection');
          if (!shop) {
            // The Shop's grid and Buy sheet without its app bar.
            await tester.pumpWidget(const SizedBox());
            await pumpMeta(
              tester,
              env,
              fakes,
              Builder(
                builder: (context) => Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      Consumer(
                        builder: (context, ref, _) => SliverMainAxisGroup(
                          slivers: emoteShelfSlivers(
                            context,
                            state: ref.watch(shopEmotesProvider),
                            shelf: shopEmotesProvider,
                            onRetry: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              locale: Locale(locale),
              size: size,
              textScale: scale,
            );
            await flush(tester);
            expect(tester.takeException(), isNull, reason: 'shop grid');
            for (final i in [0, 3, 4]) {
              await scrollTo(tester, _tile(i));
              await tester.tap(_tile(i));
              await settleRoute(tester);
              expect(tester.takeException(), isNull, reason: 'buy sheet $i');
              Navigator.of(tester.element(find.byType(StoreEmoteSheet))).pop();
              await settleRoute(tester);
            }
          }
        });
      }
    }
  }
}
