import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_arena/app/routes.dart';
import 'package:ludo_arena/core/network/api_models.dart';
import 'package:ludo_arena/features/authentication/application/session_controller.dart';
import 'package:ludo_arena/features/collection/application/collection_controller.dart';
import 'package:ludo_arena/features/collection/domain/collection_models.dart';
import 'package:ludo_arena/features/collection/presentation/collection_screen.dart';
import 'package:ludo_arena/features/store/application/shop_category.dart';
import 'package:ludo_arena/features/wallet/wallet_controller.dart';

import '../progression/meta_test_support.dart';
import '../store/store_test_support.dart';

const _buyGolden = '/collection/items/dice_golden/purchase';

void main() {
  setUpAll(() async => initializeDateFormatting());

  group('filtering', () {
    final data = CollectionData.fromJson(collectionJson());

    test('by kind and owned/locked, in catalog order; items for sale and '
        'not owned are left to the Shop', () {
      expect(data.filtered('dice', CollectionFilter.all).map((i) => i.id), [
        'dice_classic',
        'dice_neon',
        'dice_autumn',
      ]);
      expect(data.filtered('token', CollectionFilter.owned).map((i) => i.id), [
        'token_classic',
        'token_gem',
      ]);
      // Still to earn (level 10); the Crown Piece is sold in the Shop.
      expect(data.filtered('token', CollectionFilter.locked).map((i) => i.id), [
        'token_royal',
      ]);
      // Mission-only badges show locked with how to earn them.
      expect(data.filtered('badge', CollectionFilter.locked).map((i) => i.id), [
        'badge_first_win',
        'badge_friendly',
      ]);
      expect(data.ownedOf('emote'), 3);
      expect(data.totalOf('emote'), 4);
      expect(data.ownedCount, 13);
      expect(data.collectionCount, 29);
      expect(data.shopItems('dice').map((i) => i.id), ['dice_golden']);
      expect(data.shopItems('title'), isEmpty);
    });

    test('a bought item moves from the Shop to the Collection', () {
      final bought = CollectionData.fromJson(
        collectionJson(extraOwned: {'dice_golden'}),
      );
      expect(bought.filtered('dice', CollectionFilter.owned).map((i) => i.id), [
        'dice_classic',
        'dice_golden',
      ]);
      expect(bought.shopItems('dice'), isEmpty);
      expect(bought.totalOf('dice'), 4);
    });

    test('starter collection is equipped and owned', () {
      final equipped = data.items.where((i) => i.equipped).map((i) => i.id);
      expect(equipped, containsAll(['dice_classic', 'title_rookie']));
      expect(data.byId('emote_wave')!.equippable, isFalse);
      expect(data.byId('dice_golden')!.canPurchase, isTrue);
      expect(data.byId('dice_neon')!.canPurchase, isFalse);
    });

    test('withLoadout moves the equipped flag within the slot only', () {
      final next = data.withLoadout(
        Loadout.fromJson({...kStarterLoadout, 'dice': 'dice_neon'}),
      );
      expect(next.byId('dice_neon')!.equipped, isTrue);
      expect(next.byId('dice_classic')!.equipped, isFalse);
      expect(next.byId('title_rookie')!.equipped, isTrue);
    });
  });

  group('controller (fake API)', () {
    late TestEnv env;
    late MetaFakes fakes;
    late ProviderContainer c;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
      c = metaContainer(env, fakes);
      await signIn(c);
      c.listen(collectionProvider, (_, _) {});
      await c.read(collectionProvider.future);
    });
    tearDown(() => fakes.close());

    CollectionController ctl() => c.read(collectionProvider.notifier);
    CollectionItem item(String id) =>
        c.read(collectionProvider).value!.byId(id)!;

    test('equip sends the slot, updates loadout and session', () async {
      env.backend.on('PUT', '/collection/loadout', (req) {
        expect(req.json, {'slot': 'token', 'itemId': 'token_gem'});
        return FakeResponse(200, {
          'loadout': {...kStarterLoadout, 'token': 'token_gem'},
        });
      });
      final r = await ctl().equip(item('token_gem'));
      expect(r, isA<CollectionSucceeded>());
      expect(item('token_gem').equipped, isTrue);
      expect(item('token_classic').equipped, isFalse);
      expect(
        c.read(sessionControllerProvider).user!.loadout.token,
        'token_gem',
      );
      expect(fakes.analytics.events, contains('cosmetic_equipped:token'));
    });

    test('equip default sends a null item id', () async {
      env.backend.on('PUT', '/collection/loadout', (req) {
        expect(req.json, {'slot': 'frame', 'itemId': null});
        return FakeResponse(200, {'loadout': kStarterLoadout});
      });
      expect(await ctl().equipDefault('frame'), isA<CollectionSucceeded>());
    });

    test('item_locked is reported and nothing is equipped', () async {
      env.backend.on(
        'PUT',
        '/collection/loadout',
        (_) => FakeResponse.error(422, 'item_locked'),
      );
      final r = await ctl().equip(item('dice_neon'));
      expect((r as CollectionFailed).code, 'item_locked');
      expect(item('dice_neon').equipped, isFalse);
      expect(
        fakes.analytics.events.where((e) => e.startsWith('cosmetic_equipped')),
        isEmpty,
      );
    });

    test(
      'purchase applies the server wallet and ownership exactly once',
      () async {
        env.backend.json('POST', _buyGolden, {
          'item': collectionItemJson(
            'dice_golden',
            owned: true,
            loadout: kStarterLoadout,
          ),
          'wallet': {'coins': 1000000, 'diamonds': 10},
        });
        final r = await ctl().purchase(item('dice_golden'));
        expect(r, isA<CollectionSucceeded>());
        expect(item('dice_golden').owned, isTrue);
        expect(c.read(walletControllerProvider).diamonds, 10);
        final req = env.backend.calls('POST', _buyGolden).single;
        expect(req.header('Idempotency-Key'), 'idem-key-1');
        expect(fakes.analytics.events, contains('cosmetic_unlocked:dice:epic'));
      },
    );

    test('insufficient_funds changes nothing and refreshes balances', () async {
      env.backend
        ..on(
          'POST',
          _buyGolden,
          (_) => FakeResponse.error(422, 'insufficient_funds'),
        )
        ..json('GET', '/wallet', {'coins': 1000000, 'diamonds': 5});
      final r = await ctl().purchase(item('dice_golden'));
      expect((r as CollectionFailed).code, 'insufficient_funds');
      expect(ctl().pendingPurchaseKey('dice_golden'), isNull);
      expect(item('dice_golden').owned, isFalse);
      await settle();
      expect(c.read(walletControllerProvider).diamonds, 5);
      expect(
        fakes.analytics.events.where((e) => e.startsWith('cosmetic_unlocked')),
        isEmpty,
      );
    });

    test('a network failure keeps the purchase key for the retry', () async {
      env.backend.offline = true;
      await ctl().purchase(item('dice_golden'));
      expect(ctl().pendingPurchaseKey('dice_golden'), 'idem-key-1');
      env.backend
        ..offline = false
        ..json('POST', _buyGolden, {
          'item': collectionItemJson(
            'dice_golden',
            owned: true,
            loadout: kStarterLoadout,
          ),
          'wallet': {'coins': 1000000, 'diamonds': 10},
        });
      await ctl().purchase(item('dice_golden'));
      final keys = env.backend
          .calls('POST', _buyGolden)
          .map((r) => r.header('Idempotency-Key'))
          .toList();
      expect(keys, ['idem-key-1', 'idem-key-1']);
    });
  });

  group('screen', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    testWidgets('tabs and filters narrow the grid; items for sale are left '
        'to the Shop', (tester) async {
      await pumpMeta(tester, env, fakes, const CollectionScreen());
      expect(fakes.analytics.events, contains('collection_viewed'));
      expect(byKeyString('item-dice_classic'), findsOneWidget);
      expect(byKeyString('item-dice_neon'), findsOneWidget);
      expect(byKeyString('item-dice_golden'), findsNothing); // in the Shop

      await tester.tap(find.text('Owned').first);
      await tester.pump();
      expect(byKeyString('item-dice_neon'), findsNothing);
      expect(byKeyString('item-dice_classic'), findsOneWidget);

      await tester.tap(find.text('To unlock'));
      await tester.pump();
      expect(byKeyString('item-dice_classic'), findsNothing);
      expect(byKeyString('item-dice_neon'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.tap(find.text('Tokens').first);
      await tester.pump();
      expect(byKeyString('item-token_crown'), findsNothing); // in the Shop
      expect(byKeyString('item-dice_classic'), findsNothing);
      // Still to earn: shown locked with how to earn it.
      expect(byKeyString('item-token_royal'), findsOneWidget);
      expect(
        find.descendant(
          of: byKeyString('item-token_royal'),
          matching: find.text('Reach level 10'),
        ),
        findsOneWidget,
      );
      await scrollTo(tester, byKeyString('collection-more-in-shop'));
      expect(byKeyString('collection-more-in-shop'), findsOneWidget);
    });

    testWidgets('equip from the detail sheet', (tester) async {
      env.backend.json('PUT', '/collection/loadout', {
        'loadout': {...kStarterLoadout, 'token': 'token_gem'},
      });
      await pumpMeta(
        tester,
        env,
        fakes,
        const CollectionScreen(initialKind: 'token'),
      );
      await tester.tap(byKeyString('item-token_gem'));
      await settleRoute(tester);
      expect(
        find.text('Faceted gem tokens that catch the light.'),
        findsOneWidget,
      );
      await tester.tap(byKeyString('equip'));
      await settleRoute(tester);
      expect(env.backend.calls('PUT', '/collection/loadout'), hasLength(1));
      expect(find.text('Equipped!'), findsOneWidget);
      expect(byKeyString('equip-default'), findsOneWidget);
    });

    testWidgets('a locked level item explains how to earn it', (tester) async {
      await pumpMeta(
        tester,
        env,
        fakes,
        const CollectionScreen(initialKind: 'token'),
      );
      await tester.tap(byKeyString('item-token_royal'));
      await settleRoute(tester);
      expect(
        find.text('Unlocks automatically when you reach level 10.'),
        findsOneWidget,
      );
      expect(byKeyString('buy'), findsNothing);
    });

    testWidgets('a bought item is in the Collection with its equip flow', (
      tester,
    ) async {
      env.backend
        ..json(
          'GET',
          '/collection',
          collectionJson(extraOwned: {'dice_golden'}),
        )
        ..json('PUT', '/collection/loadout', {
          'loadout': {...kStarterLoadout, 'dice': 'dice_golden'},
        });
      await pumpMeta(tester, env, fakes, const CollectionScreen());
      expect(byKeyString('item-dice_golden'), findsOneWidget);
      // Nothing else of this kind for sale: no Shop link.
      expect(
        find.byKey(
          const ValueKey('collection-more-in-shop'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      await tester.tap(byKeyString('item-dice_golden'));
      await settleRoute(tester);
      expect(byKeyString('buy'), findsNothing);
      expect(byKeyString('view-in-collection'), findsNothing);
      await tester.tap(byKeyString('equip'));
      await settleRoute(tester);
      expect(env.backend.calls('PUT', '/collection/loadout').single.json, {
        'slot': 'dice',
        'itemId': 'dice_golden',
      });
      expect(find.text('Equipped!'), findsOneWidget);
    });

    testWidgets('Pictures lists the owned pictures; apply and back to the '
        'classic avatar', (tester) async {
      routeStore(env);
      env.backend.on('PUT', '/me/profile-picture', (req) {
        final id = req.json['id'];
        return FakeResponse(200, {
          'equipped': id == null
              ? null
              : {...storeShelf()[1], 'owned': true, 'equipped': true},
        });
      });
      final c = await pumpMeta(
        tester,
        env,
        fakes,
        const CollectionScreen(initialKind: kPictureCategory),
      );
      await flush(tester);
      final call = env.backend.calls('GET', '/store/profile-pictures').last;
      expect(call.query['filter'], 'owned');
      expect(byKeyString('pp-pp_item_1'), findsOneWidget);
      expect(byKeyString('pp-pp_item_2'), findsOneWidget);
      expect(byKeyString('pp-pp_item_0'), findsNothing); // not owned
      expect(find.text('Equipped'), findsWidgets); // #2
      // No owned/locked filter on pictures.
      expect(byKeyString('collection-filter'), findsNothing);

      await tester.tap(byKeyString('pp-pp_item_1'));
      await settleRoute(tester);
      expect(byKeyString('store-buy'), findsNothing);
      expect(byKeyString('store-view-in-collection'), findsNothing);
      await tester.tap(byKeyString('store-apply'));
      await settleRoute(tester);
      expect(find.text('Picture applied!'), findsOneWidget);
      expect(c.read(sessionControllerProvider).user!.picture!.id, 'pp_item_1');
      await tester.tap(byKeyString('store-remove'));
      await settleRoute(tester);
      expect(find.text('Back to your classic avatar.'), findsOneWidget);
      expect(c.read(sessionControllerProvider).user!.picture, isNull);
    });
  });

  group('screen → Shop', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    GoRouter router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: AppRoutes.collection,
          builder: (_, state) =>
              CollectionScreen(initialKind: state.uri.queryParameters['kind']),
        ),
        GoRoute(
          path: AppRoutes.shop,
          builder: (_, state) => Scaffold(body: Text('AT ${state.uri}')),
        ),
      ],
    );

    testWidgets('Find more in the Shop opens that Shop category', (
      tester,
    ) async {
      await pumpMeta(
        tester,
        env,
        fakes,
        const SizedBox(),
        router: router('/collection?kind=token'),
      );
      await scrollTo(tester, byKeyString('collection-more-in-shop'));
      await tester.tap(byKeyString('collection-more-in-shop'));
      await settleRoute(tester);
      expect(find.text('AT /shop?category=token'), findsOneWidget);
    });

    testWidgets('an empty category offers Go to Shop', (tester) async {
      // Badges here are only sold (none owned or to earn).
      final json = collectionJson();
      json['items'] = [
        for (final i in json['items'] as List)
          if ((i as Map)['kind'] == 'badge')
            {
              ...i,
              'owned': false,
              'acquisition': {
                'type': 'purchase',
                'price': {'diamonds': 5},
                'label': '5 diamonds',
              },
            }
          else
            i,
      ];
      env.backend.json('GET', '/collection', json);
      await pumpMeta(
        tester,
        env,
        fakes,
        const SizedBox(),
        router: router('/collection?kind=badge'),
      );
      expect(
        find.text('Nothing to collect here yet. Take a look in the Shop!'),
        findsOneWidget,
      );
      await tester.tap(byKeyString('collection-go-to-shop'));
      await settleRoute(tester);
      expect(find.text('AT /shop?category=badge'), findsOneWidget);
    });

    testWidgets('no pictures yet: Go to Shop opens the Shop pictures', (
      tester,
    ) async {
      routeStore(env, shelf: const []);
      await pumpMeta(
        tester,
        env,
        fakes,
        const SizedBox(),
        router: router('/collection?kind=picture'),
      );
      await flush(tester);
      expect(find.text('No pictures yet'), findsOneWidget);
      expect(
        find.text('Pictures you buy in the Shop show up here.'),
        findsOneWidget,
      );
      await tester.tap(byKeyString('collection-go-to-shop'));
      await settleRoute(tester);
      expect(find.text('AT /shop?category=picture'), findsOneWidget);
    });
  });

  // 320×640 at the largest text scale, every language, both themes: every
  // Collection tab (Pictures included) lays out without overflow.
  for (final locale in const ['en', 'hi', 'ur', 'id', 'ar']) {
    for (final mode in ThemeMode.values.skip(1)) {
      testWidgets('collection tabs $locale ${mode.name} @320x640 x1.35', (
        tester,
      ) async {
        final env = await TestEnv.create();
        env.routeHappyPath();
        routeMeta(env);
        routeStore(env);
        final fakes = MetaFakes();
        addTearDown(fakes.close);
        await pumpMeta(
          tester,
          env,
          fakes,
          const CollectionScreen(),
          locale: Locale(locale),
          themeMode: mode,
          size: Viewports.small,
          textScale: 1.35,
        );
        await flush(tester);
        expect(tester.takeException(), isNull);
        for (var i = 0; i < kCollectionTabs.length; i++) {
          final pill = find
              .descendant(
                of: find.byKey(
                  const ValueKey('collection-kinds'),
                  skipOffstage: false,
                ),
                matching: find.byType(InkWell, skipOffstage: false),
                skipOffstage: false,
              )
              .at(i);
          await tester.ensureVisible(pill);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(pill);
          await flush(tester);
          expect(tester.takeException(), isNull, reason: kCollectionTabs[i]);
          await scrollThrough(tester);
          expect(tester.takeException(), isNull, reason: kCollectionTabs[i]);
        }
        final rtl = locale == 'ar' || locale == 'ur';
        expect(
          Directionality.of(tester.element(find.byType(CollectionScreen))),
          rtl ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }
  }
}
