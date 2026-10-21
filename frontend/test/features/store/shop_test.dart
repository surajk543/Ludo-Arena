import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/network/api_models.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/collection/application/collection_controller.dart';
import 'package:ludo_royale/features/collection/domain/collection_models.dart';
import 'package:ludo_royale/features/collection/presentation/widgets/item_detail_sheet.dart';
import 'package:ludo_royale/features/meta_routes.dart';
import 'package:ludo_royale/features/store/application/shop_category.dart';
import 'package:ludo_royale/features/store/application/store_controller.dart';
import 'package:ludo_royale/features/store/data/store_api.dart';
import 'package:ludo_royale/features/store/domain/store_models.dart';
import 'package:ludo_royale/features/store/iap/iap_store.dart';
import 'package:ludo_royale/features/store/presentation/shop_screen.dart';
import 'package:ludo_royale/features/store/presentation/widgets/store_picture_sheet.dart';
import 'package:ludo_royale/features/wallet/wallet_controller.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import '../progression/meta_test_support.dart';
import 'coin_test_support.dart';
import 'store_test_support.dart';

const _list = '/store/profile-pictures';
String _buy(int i) => '/store/profile-pictures/pp_item_$i/purchase';
const _apply = '/me/profile-picture';
const _buyGolden = '/collection/items/dice_golden/purchase';

Map<String, dynamic> _owned(int i, {bool equipped = false}) => {
  ...storeShelf()[i],
  'owned': true,
  'equipped': equipped,
};

/// The Shop's category pill with [label].
Finder _category(String label) => find.descendant(
  of: byKeyString('shop-categories'),
  matching: find.bySemanticsLabel(label),
);

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

    test('Shop categories: Coins, Pictures, then every kind with priced '
        'items', () {
      expect(shopCategories(null), [
        kCoinsCategory,
        kPictureCategory,
        ...kDefaultShopKinds,
      ]);
      final data = CollectionData.fromJson(collectionJson());
      // Titles and badges are only earned, never sold.
      expect(shopCategories(data), [
        'coins',
        'picture',
        'dice',
        'token',
        'ludo_board',
        'snakes_board',
        'trail',
        'victory',
        'frame',
        'emote',
      ]);
      // A kind whose items are all owned keeps its category.
      final owned = CollectionData.fromJson(
        collectionJson(extraOwned: {'emote_crown'}),
      );
      expect(shopCategories(owned), contains('emote'));
      expect(owned.shopItems('emote'), isEmpty);
    });
  });

  group('shelf controllers (fake API)', () {
    late TestEnv env;
    late MetaFakes fakes;
    late ProviderContainer c;

    Future<void> loaded(NotifierProvider<StoreController, StoreState> p) async {
      for (var i = 0; i < 50 && c.read(p).loading; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeStore(env);
      routeCoinPacks(env);
      fakes = MetaFakes();
      c = metaContainer(env, fakes);
      await signIn(c);
      c.listen(storeProvider, (_, _) {});
      await loaded(storeProvider);
    });
    tearDown(() => fakes.close());

    StoreController shop() => c.read(storeProvider.notifier);
    StoreState s() => c.read(storeProvider);
    ProfilePicture item(int i) => s().byId('pp_item_$i')!;

    Future<StoreController> owned() async {
      c.listen(ownedPicturesProvider, (_, _) {});
      await loaded(ownedPicturesProvider);
      return c.read(ownedPicturesProvider.notifier);
    }

    ProfilePicture ownedItem(int i) =>
        c.read(ownedPicturesProvider).byId('pp_item_$i')!;

    test('the Shop lists only pictures not owned yet, page by page', () async {
      expect(s().items, hasLength(24));
      expect(s().total, 28);
      expect(s().byId('pp_item_1'), isNull);
      expect(s().byId('pp_item_2'), isNull);
      expect(s().hasMore, isTrue);
      final first = env.backend.calls('GET', _list).single;
      expect(first.query, {
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
      expect(calls.last.query['excludeOwned'], 'true');

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
          storePageJson(
            storeShelf().sublist(start, end),
            nextCursor: end < 30 ? 'c$end' : null,
          ),
        );
      });
      await shop().loadMore();
      expect(s().moreError, isNotNull);
      expect(s().items, hasLength(24));
      await shop().loadMore(); // no automatic retry loop
      expect(env.backend.calls('GET', _list), hasLength(2));
      fail = false;
      await shop().loadMore(retry: true);
      expect(s().moreError, isNull);
      // Page 2 repeats nothing already shown.
      expect(s().items, hasLength(28));
    });

    test('switching the filter loads that filter from its first page; the '
        'owned shelf lists filter=owned', () async {
      shop().setFilter(StoreFilter.still);
      expect(s().loading, isTrue);
      await loaded(storeProvider);
      final last = env.backend.calls('GET', _list).last.query;
      expect(last['filter'], 'static');
      expect(last['excludeOwned'], 'true');
      expect(s().items.every((p) => !p.isAnimated && !p.owned), isTrue);

      await owned();
      final ownedCall = env.backend.calls('GET', _list).last.query;
      expect(ownedCall, {'filter': 'owned', 'limit': '24'});
      expect(c.read(ownedPicturesProvider).items.map((p) => p.id), [
        'pp_item_1',
        'pp_item_2',
      ]);
    });

    test('a purchase applies the server wallet and the picture leaves the '
        'Shop; a transient failure keeps the Idempotency-Key', () async {
      var attempts = 0;
      env.backend.on('POST', _buy(0), (req) {
        attempts++;
        if (attempts == 1) return FakeResponse.error(503, 'internal');
        return FakeResponse(200, {
          'item': _owned(0),
          'wallet': {'coins': 1000000, 'diamonds': 40},
        });
      });
      final first = await shop().purchase(item(0));
      expect((first as StoreFailed).code, 'internal');
      expect(shop().pendingPurchaseKey('pp_item_0'), 'idem-key-1');
      expect(s().byId('pp_item_0'), isNotNull);

      expect(await shop().purchase(item(0)), isA<StoreSucceeded>());
      final keys = env.backend
          .calls('POST', _buy(0))
          .map((r) => r.header('Idempotency-Key'));
      expect(keys, ['idem-key-1', 'idem-key-1']);
      expect(shop().pendingPurchaseKey('pp_item_0'), isNull);
      expect(s().byId('pp_item_0'), isNull);
      expect(s().total, 27);
      expect(c.read(walletControllerProvider).diamonds, 40);
      expect(
        fakes.analytics.events,
        contains('cosmetic_unlocked:$kProfilePictureItemKind:'),
      );
    });

    test('already_owned also leaves the Shop; insufficient_funds refreshes '
        'the balance and keeps the picture', () async {
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
      expect(s().byId('pp_item_0'), isNull);
      expect(
        ((await shop().purchase(item(4))) as StoreFailed).code,
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
      final ctl = await owned();
      expect(await ctl.apply(ownedItem(1)), isA<StoreSucceeded>());
      expect(env.backend.calls('PUT', _apply).last.json, {'id': 'pp_item_1'});
      expect(ownedItem(1).equipped, isTrue);
      expect(ownedItem(2).equipped, isFalse);
      expect(c.read(ownedPicturesProvider).equippedId, 'pp_item_1');
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

      expect(await ctl.apply(null), isA<StoreSucceeded>());
      expect(env.backend.calls('PUT', _apply).last.json, {'id': null});
      expect(
        c.read(ownedPicturesProvider).items.where((p) => p.equipped),
        isEmpty,
      );
      expect(c.read(sessionControllerProvider).user!.picture, isNull);
    });

    test('item_locked on apply shows the item as not owned', () async {
      env.backend.on(
        'PUT',
        _apply,
        (_) => FakeResponse.error(422, 'item_locked'),
      );
      final ctl = await owned();
      final r = await ctl.apply(ownedItem(1));
      expect((r as StoreFailed).code, 'item_locked');
      expect(ownedItem(1).owned, isFalse);
      expect(c.read(sessionControllerProvider).user!.picture, isNull);
    });

    test('the API sends the documented requests', () async {
      final api = c.read(storeApiProvider);
      await api.list(
        filter: StoreFilter.animated,
        excludeOwned: true,
        cursor: 'c12',
        limit: 12,
      );
      expect(env.backend.calls('GET', _list).last.query, {
        'filter': 'animated',
        'excludeOwned': 'true',
        'limit': '12',
        'cursor': 'c12',
      });
    });
  });

  group('screen: Pictures', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      routeStore(env);
      routeCoinPacks(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    // `/shop?category=picture` (the Shop itself opens on Coins).
    Future<ProviderContainer> pumpShop(WidgetTester tester) async {
      final c = await pumpMeta(
        tester,
        env,
        fakes,
        const ShopScreen(initialCategory: kPictureCategory),
      );
      await flush(tester);
      return c;
    }

    Finder tile(int i) => byKeyString('pp-pp_item_$i');

    Future<void> openSheet(WidgetTester tester, int i) async {
      await scrollTo(tester, tile(i));
      await tester.tap(tile(i));
      await settleRoute(tester);
    }

    testWidgets('Pictures lists unowned pictures only; reaching the end '
        'loads the next page', (tester) async {
      await pumpShop(tester);
      expect(find.text('Shop'), findsOneWidget);
      expect(find.text('Profile pictures'), findsOneWidget);
      expect(tile(0), findsOneWidget);
      expect(tile(1), findsNothing); // owned
      expect(tile(2), findsNothing); // owned and equipped
      expect(find.text('Equipped'), findsNothing);
      expect(find.text('Owned'), findsNothing); // no Owned filter either
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

    testWidgets('filter pills switch the shelf; an empty shelf points to the '
        'Collection', (tester) async {
      await pumpShop(tester);
      await tester.tap(find.text('Animated'));
      await flush(tester);
      final q = env.backend.calls('GET', _list).last.query;
      expect(q['filter'], 'animated');
      expect(q['excludeOwned'], 'true');
      expect(tile(0), findsNothing); // an image
      expect(tile(3), findsOneWidget);

      routeStore(env, shelf: const []);
      await tester.tap(find.text('Static'));
      await flush(tester);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(byKeyString('shop-view-in-collection'), findsOneWidget);
    });

    testWidgets('buy, then apply now from the sheet; the picture leaves the '
        'Shop', (tester) async {
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
      final c = await pumpShop(tester);
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
      expect(c.read(storeProvider).byId('pp_item_0'), isNull);
      // The sheet stays on the bought picture: Apply now / View in
      // Collection.
      expect(find.text('Apply now'), findsOneWidget);
      expect(byKeyString('store-view-in-collection'), findsOneWidget);

      await tester.tap(byKeyString('store-apply'));
      await settleRoute(tester);
      expect(env.backend.calls('PUT', _apply).single.json, {'id': 'pp_item_0'});
      expect(find.text('Picture applied!'), findsOneWidget);
      expect(env.audio.played, contains(Sfx.uiConfirm));
      expect(c.read(sessionControllerProvider).user!.picture!.id, 'pp_item_0');
      expect(byKeyString('store-remove'), findsOneWidget);

      Navigator.of(tester.element(find.byType(StorePictureSheet))).pop();
      await settleRoute(tester);
      expect(tile(0), findsNothing);
    });

    testWidgets('not enough diamonds: Buy is disabled with a note', (
      tester,
    ) async {
      await pumpShop(tester);
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
      await pumpShop(tester);
      await openSheet(tester, 0);
      await tester.tap(byKeyString('store-buy'));
      await settleRoute(tester);
      expect(find.text('You already own this item.'), findsOneWidget);
      expect(byKeyString('store-apply'), findsOneWidget);
    });

    testWidgets('a failed first page offers Retry', (tester) async {
      var fail = true;
      env.backend.on('GET', _list, (req) {
        if (fail) return FakeResponse.error(500, 'internal');
        return FakeResponse(200, storePageJson(storeShelf().take(6).toList()));
      });
      await pumpShop(tester);
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await flush(tester);
      expect(tile(0), findsOneWidget);
    });
  });

  group('screen: cosmetic categories', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      routeStore(env);
      routeCoinPacks(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    Finder shopItem(String id) => byKeyString('shop-item-$id');

    testWidgets('category pills: only kinds with priced items; each shows '
        'its unowned priced items', (tester) async {
      await pumpMeta(tester, env, fakes, const ShopScreen());
      for (final label in const [
        'Coins',
        'Pictures',
        'Dice',
        'Tokens',
        'Ludo boards',
        'Snakes boards',
        'Trails',
        'Victory',
        'Frames',
        'Emotes',
      ]) {
        expect(_category(label), findsOneWidget, reason: label);
      }
      expect(_category('Titles'), findsNothing);
      expect(_category('Badges'), findsNothing);

      await tester.ensureVisible(_category('Dice'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_category('Dice'));
      await flush(tester);
      expect(shopItem('dice_golden'), findsOneWidget);
      expect(shopItem('dice_classic'), findsNothing); // owned starter
      expect(shopItem('dice_neon'), findsNothing); // earned by level
      expect(shopItem('dice_autumn'), findsNothing); // event reward
      expect(byKeyString('pp-pp_item_0'), findsNothing);

      await tester.ensureVisible(_category('Tokens'));
      await tester.tap(_category('Tokens'));
      await flush(tester);
      expect(shopItem('token_crown'), findsOneWidget);
      expect(shopItem('dice_golden'), findsNothing);
      expect(find.text('Tokens'), findsWidgets); // hero title
    });

    testWidgets('buy a cosmetic: confirmation, Idempotency-Key, then equip '
        'and View in Collection; it leaves the Shop', (tester) async {
      env.backend
        ..json('POST', _buyGolden, {
          'item': collectionItemJson(
            'dice_golden',
            owned: true,
            loadout: kStarterLoadout,
          ),
          'wallet': {'coins': 1000000, 'diamonds': 10},
        })
        ..json('PUT', '/collection/loadout', {
          'loadout': {...kStarterLoadout, 'dice': 'dice_golden'},
        });
      final c = await pumpMeta(
        tester,
        env,
        fakes,
        const ShopScreen(initialCategory: 'dice'),
      );
      await tester.tap(shopItem('dice_golden'));
      await settleRoute(tester);
      await tester.tap(byKeyString('buy'));
      await settleRoute(tester);
      expect(find.text('Buy Royal Gold?'), findsOneWidget);
      expect(find.text('50 diamonds'), findsOneWidget); // balance
      expect(find.text('10 diamonds'), findsOneWidget); // after
      await tester.tap(find.text('Buy'));
      await settleRoute(tester);
      final req = env.backend.calls('POST', _buyGolden).single;
      expect(req.header('Idempotency-Key'), 'idem-key-1');
      expect(
        find.text('Royal Gold is now in your collection!'),
        findsOneWidget,
      );
      expect(c.read(walletControllerProvider).diamonds, 10);
      expect(fakes.analytics.events, contains('cosmetic_unlocked:dice:epic'));

      // Equip right away, or open it in the Collection.
      expect(byKeyString('view-in-collection'), findsOneWidget);
      await tester.tap(byKeyString('equip'));
      await settleRoute(tester);
      expect(env.backend.calls('PUT', '/collection/loadout'), hasLength(1));
      expect(find.text('Equipped!'), findsOneWidget);
      expect(
        c.read(sessionControllerProvider).user!.loadout.dice,
        'dice_golden',
      );

      Navigator.of(tester.element(find.text('Royal Gold').first)).pop();
      await settleRoute(tester);
      expect(shopItem('dice_golden'), findsNothing);
      expect(find.text('You own them all!'), findsOneWidget);
      expect(byKeyString('shop-view-in-collection'), findsOneWidget);
    });

    testWidgets('insufficient funds from the server is explained', (
      tester,
    ) async {
      env.backend.on(
        'POST',
        _buyGolden,
        (_) => FakeResponse.error(422, 'insufficient_funds'),
      );
      await pumpMeta(
        tester,
        env,
        fakes,
        const ShopScreen(initialCategory: 'dice'),
      );
      await tester.tap(shopItem('dice_golden'));
      await settleRoute(tester);
      await tester.tap(byKeyString('buy'));
      await settleRoute(tester);
      await tester.tap(find.text('Buy'));
      await settleRoute(tester);
      expect(env.backend.calls('POST', _buyGolden), hasLength(1));
      expect(find.text('Not enough diamonds for this item.'), findsOneWidget);
      expect(byKeyString('buy'), findsOneWidget); // still for sale
    });

    testWidgets('the confirmation blocks a purchase the balance cannot cover', (
      tester,
    ) async {
      await pumpMeta(
        tester,
        env,
        fakes,
        const ShopScreen(initialCategory: 'frame'),
      );
      expect(shopItem('frame_royal'), findsOneWidget);
      expect(shopItem('frame_silver'), findsNothing); // level reward
      await tester.tap(shopItem('frame_royal'));
      await settleRoute(tester);
      await tester.tap(byKeyString('buy'));
      await settleRoute(tester);
      // 60 diamonds > 50 → no Buy action, explanation instead.
      expect(find.text('Buy'), findsNothing);
      expect(
        find.textContaining('you need another 10 diamonds'),
        findsOneWidget,
      );
      expect(
        env.backend.calls('POST', '/collection/items/frame_royal/purchase'),
        isEmpty,
      );
    });
  });

  group('routing', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      routeStore(env);
      routeCoinPacks(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    GoRouter router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(AppRoutes.shop),
              child: const Text('open shop'),
            ),
          ),
        ),
        ...metaRoutes,
      ],
    );

    void expectSelected(WidgetTester tester, String label) => expect(
      tester.getSemantics(_category(label)),
      isSemantics(isSelected: true),
      reason: label,
    );

    testWidgets('/store redirects to /shop, keeping the category', (
      tester,
    ) async {
      final r = router('/store?category=dice');
      await pumpMeta(tester, env, fakes, const SizedBox(), router: r);
      expect(find.byType(ShopScreen), findsOneWidget);
      expect(
        r.routerDelegate.currentConfiguration.uri.toString(),
        '/shop?category=dice',
      );
      expect(byKeyString('shop-item-dice_golden'), findsOneWidget);
      expectSelected(tester, 'Dice');
    });

    testWidgets('every visit opens on Coins, whatever was chosen last; a '
        '?category= link still wins', (tester) async {
      final c = await pumpMeta(
        tester,
        env,
        fakes,
        const SizedBox(),
        router: router(AppRoutes.home),
      );
      await tester.tap(find.text('open shop'));
      await settleRoute(tester);
      expectSelected(tester, 'Coins');
      expect(c.read(shopCategoryProvider), kCoinsCategory);
      expect(byKeyString('coin-pack-coins_starter'), findsOneWidget);
      await tester.ensureVisible(_category('Tokens'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_category('Tokens'));
      await flush(tester);
      expect(c.read(shopCategoryProvider), 'token');

      Navigator.of(tester.element(find.byType(ShopScreen))).pop();
      await settleRoute(tester);
      expect(find.byType(ShopScreen), findsNothing);
      await tester.tap(find.text('open shop'));
      await settleRoute(tester);
      expectSelected(tester, 'Coins');
      expect(c.read(shopCategoryProvider), kCoinsCategory);
      expect(byKeyString('shop-item-token_crown'), findsNothing);
      expect(byKeyString('coin-pack-coins_starter'), findsOneWidget);
    });

    testWidgets('/shop?category=picture opens Pictures', (tester) async {
      await pumpMeta(
        tester,
        env,
        fakes,
        const SizedBox(),
        router: router('/shop?category=picture'),
      );
      expectSelected(tester, 'Pictures');
      expect(byKeyString('pp-pp_item_0'), findsOneWidget);
      expect(byKeyString('coin-pack-coins_starter'), findsNothing);
    });
  });

  // 320×640 at the largest text scale, every language, both themes: every
  // Shop category, the picture sheet and a cosmetic sheet lay out without
  // overflow (RTL for ar/ur).
  for (final locale in const ['en', 'hi', 'ur', 'id', 'ar']) {
    for (final mode in ThemeMode.values.skip(1)) {
      testWidgets('shop + sheets $locale ${mode.name} @320x640 x1.35', (
        tester,
      ) async {
        final env = await TestEnv.create();
        env.routeHappyPath();
        routeMeta(env);
        routeStore(env);
        routeCoinPacks(env);
        final fakes = MetaFakes();
        addTearDown(fakes.close);
        // Store prices for two packs (one long), fallback prices for the
        // others.
        final store = FakeIapStore(
          products: {
            'coins_popular': storeProduct(
              'coins_popular',
              price: '₹299.00',
              rawPrice: 299,
            ),
            'coins_best_value': storeProduct(
              'coins_best_value',
              price: 'Rp 199.000,00',
              rawPrice: 199000,
              currency: 'IDR',
            ),
          },
        );
        addTearDown(store.close);
        final c = await pumpMeta(
          tester,
          env,
          fakes,
          const ShopScreen(),
          locale: Locale(locale),
          themeMode: mode,
          size: Viewports.small,
          textScale: 1.35,
          extra: [iapStoreProvider.overrideWithValue(store)],
        );
        await flush(tester);
        expect(tester.takeException(), isNull);
        // Opens on Coins: every pack card, then the note.
        expect(c.read(shopCategoryProvider), kCoinsCategory);
        for (final id in const [
          'coins_starter',
          'coins_popular',
          'coins_great_value',
          'coins_best_value',
        ]) {
          await scrollTo(tester, byKeyString('coin-pack-$id'));
          expect(tester.takeException(), isNull, reason: id);
        }
        expect(find.text('Rp 199.000,00'), findsOneWidget);
        await scrollThrough(tester);
        await flush(tester);
        expect(tester.takeException(), isNull, reason: 'coins');
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 4000));
        await flush(tester);

        // Pictures (second pill).
        final pills = find.descendant(
          of: find.byKey(
            const ValueKey('shop-categories'),
            skipOffstage: false,
          ),
          matching: find.byType(InkWell, skipOffstage: false),
          skipOffstage: false,
        );
        await tester.ensureVisible(pills.at(1));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(pills.at(1));
        await flush(tester);
        expect(c.read(shopCategoryProvider), kPictureCategory);
        // Cheap, too expensive, long names (scrolling down only).
        for (final i in [0, 3, 4, 5]) {
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
          Directionality.of(tester.element(find.byType(ShopScreen))),
          rtl ? TextDirection.rtl : TextDirection.ltr,
        );

        // Every cosmetic category (tapping its pill), and the sheet of its
        // first item.
        final data = c.read(collectionProvider).value!;
        final kinds = shopCategories(data);
        // 0 = Coins, 1 = Pictures (both above).
        for (var i = 2; i < kinds.length; i++) {
          final kind = kinds[i];
          final pill = pills.at(i);
          await tester.ensureVisible(pill);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(pill);
          await flush(tester);
          expect(tester.takeException(), isNull, reason: kind);
          expect(c.read(shopCategoryProvider), kind);
          final first = byKeyString(
            'shop-item-${data.shopItems(kind).first.id}',
          );
          await scrollTo(tester, first);
          await tester.tap(first);
          await settleRoute(tester);
          expect(tester.takeException(), isNull, reason: '$kind sheet');
          Navigator.of(tester.element(find.byType(CollectionItemSheet))).pop();
          await settleRoute(tester);
        }
      });
    }
  }
}
