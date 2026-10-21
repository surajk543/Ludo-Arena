import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/core/network/api_models.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/collection/application/collection_controller.dart';
import 'package:ludo_royale/features/collection/domain/collection_models.dart';
import 'package:ludo_royale/features/collection/presentation/collection_screen.dart';
import 'package:ludo_royale/features/wallet/wallet_controller.dart';

import '../progression/meta_test_support.dart';

const _buyGolden = '/collection/items/dice_golden/purchase';

void main() {
  setUpAll(() async => initializeDateFormatting());

  group('filtering', () {
    final data = CollectionData.fromJson(collectionJson());

    test('by kind and owned/locked, in catalog order', () {
      expect(data.filtered('dice', CollectionFilter.all).map((i) => i.id), [
        'dice_classic',
        'dice_neon',
        'dice_golden',
        'dice_autumn',
      ]);
      expect(data.filtered('token', CollectionFilter.owned).map((i) => i.id), [
        'token_classic',
        'token_gem',
      ]);
      expect(data.filtered('token', CollectionFilter.locked).map((i) => i.id), [
        'token_royal',
        'token_crown',
      ]);
      expect(data.ownedOf('emote'), 3);
      expect(data.totalOf('emote'), 5);
      expect(data.ownedCount, 13);
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

    testWidgets('tabs and filters narrow the grid', (tester) async {
      await pumpMeta(tester, env, fakes, const CollectionScreen());
      expect(fakes.analytics.events, contains('collection_viewed'));
      expect(byKeyString('item-dice_classic'), findsOneWidget);
      expect(byKeyString('item-dice_golden'), findsOneWidget);

      await tester.tap(find.text('Owned').first);
      await tester.pump();
      expect(byKeyString('item-dice_golden'), findsNothing);
      expect(byKeyString('item-dice_classic'), findsOneWidget);

      await tester.tap(find.text('To unlock'));
      await tester.pump();
      expect(byKeyString('item-dice_classic'), findsNothing);
      expect(byKeyString('item-dice_neon'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.tap(find.text('Tokens').first);
      await tester.pump();
      expect(byKeyString('item-token_crown'), findsOneWidget);
      expect(byKeyString('item-dice_classic'), findsNothing);
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

    testWidgets('purchase confirmation shows price and balance; '
        'insufficient funds is explained', (tester) async {
      env.backend.on(
        'POST',
        _buyGolden,
        (_) => FakeResponse.error(422, 'insufficient_funds'),
      );
      await pumpMeta(tester, env, fakes, const CollectionScreen());
      await tester.tap(byKeyString('item-dice_golden'));
      await settleRoute(tester);
      await tester.tap(byKeyString('buy'));
      await settleRoute(tester);
      expect(find.text('Buy Royal Gold?'), findsOneWidget);
      expect(find.text('40 diamonds'), findsWidgets);
      expect(find.text('50 diamonds'), findsOneWidget); // balance
      expect(find.text('10 diamonds'), findsOneWidget); // after
      await tester.tap(find.text('Buy'));
      await settleRoute(tester);
      expect(env.backend.calls('POST', _buyGolden), hasLength(1));
      expect(find.text('Not enough diamonds for this item.'), findsOneWidget);
    });

    testWidgets('the confirmation blocks a purchase the balance cannot cover', (
      tester,
    ) async {
      await pumpMeta(
        tester,
        env,
        fakes,
        const CollectionScreen(initialKind: 'frame'),
      );
      await scrollTo(tester, byKeyString('item-frame_royal'));
      await tester.tap(byKeyString('item-frame_royal'));
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
}
