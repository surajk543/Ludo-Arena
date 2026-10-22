import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_arena/core/audio_haptics/audio_service.dart';
import 'package:ludo_arena/core/localization/number_format.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/features/authentication/application/session_controller.dart';
import 'package:ludo_arena/features/store/application/coin_packs_controller.dart';
import 'package:ludo_arena/features/store/application/coin_purchase_controller.dart';
import 'package:ludo_arena/features/store/application/shop_category.dart';
import 'package:ludo_arena/features/store/domain/coin_pack_models.dart';
import 'package:ludo_arena/features/store/domain/coin_pack_texts.dart';
import 'package:ludo_arena/features/store/iap/iap_store.dart';
import 'package:ludo_arena/features/store/presentation/shop_screen.dart';
import 'package:ludo_arena/features/wallet/wallet_controller.dart';
import 'package:ludo_arena/l10n/generated/app_localizations.dart';

import '../../helpers/screen_harness.dart' show pumpScreen;
import '../progression/meta_test_support.dart';
import 'coin_test_support.dart';
import 'store_test_support.dart';

const _purchases = '/store/purchases';

/// Store products for every pack: Google Play's localized prices.
Map<String, ProductDetails> _allProducts() => {
  'coins_starter': storeProduct(
    'coins_starter',
    price: '₹199.00',
    rawPrice: 199,
  ),
  'coins_popular': storeProduct(
    'coins_popular',
    price: '₹299.00',
    rawPrice: 299,
  ),
  'coins_great_value': storeProduct(
    'coins_great_value',
    price: '₹499.00',
    rawPrice: 499,
  ),
  'coins_best_value': storeProduct(
    'coins_best_value',
    price: '₹999.00',
    rawPrice: 999,
  ),
};

/// The coin pack analytics events recorded so far.
List<String> coinEvents(MetaFakes fakes) => [
  for (final e in fakes.analytics.events)
    if (e.startsWith('coin_pack')) e,
];

/// Instant retries (the backoff is real time otherwise).
final _noWait = coinDeliveryRetryProvider.overrideWithValue(
  CoinDeliveryRetry(sleep: (_) async {}),
);

void main() {
  setUpAll(() async => initializeDateFormatting());

  group('models', () {
    test('the catalogue parses, sorts and finds packs by product id', () {
      final c = CoinPackCatalog.fromJson(coinCatalogJson());
      expect(c.packs.map((p) => p.id), [
        'coins_starter',
        'coins_popular',
        'coins_great_value',
        'coins_best_value',
      ]);
      expect(c.purchasesAvailable, isTrue);
      expect(c.accountToken, kTestAccountToken);
      final best = c.byProductId('coins_best_value')!;
      expect(best.coins, 35000000);
      expect(best.diamonds, 250);
      expect(best.fallbackPrice.amount, 999);
      expect(best.fallbackPrice.currency, 'INR');
      expect(best.badge, CoinPackBadge.bestValue);
      expect(c.packs[1].badge, CoinPackBadge.popular);
      expect(c.packs.first.highlighted, isFalse);
      expect(c.packs.map((p) => p.analyticsSlug), [
        'starter',
        'popular',
        'great_value',
        'best_value',
      ]);
      expect(c.productIds, hasLength(4));
      expect(isCoinPackProductId('coins_new'), isTrue);
      expect(isCoinPackProductId('pp_wolf'), isFalse);
    });

    test('labels are localized by id; unknown packs keep the server label; '
        'the fallback price is whole rupees', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final hi = lookupAppLocalizations(const Locale('hi'));
      final c = CoinPackCatalog.fromJson(coinCatalogJson());
      expect(c.packs.map((p) => CoinPackTexts.label(en, p)), [
        'Starter',
        'Popular',
        'Great Value',
        'Best Value',
      ]);
      expect(CoinPackTexts.label(hi, c.packs.last), 'बेस्ट वैल्यू');
      final odd = CoinPack.fromJson(
        coinPackJson('coins_mega', 'Mega', 1, 1, 1999),
      );
      expect(CoinPackTexts.label(hi, odd), 'Mega');
      expect(
        CoinPackTexts.price(const Locale('en'), c.packs.first, null),
        '₹199',
      );
      expect(
        CoinPackTexts.price(
          const Locale('en'),
          c.packs.first,
          storeProduct('coins_starter', price: 'US\$2.49', rawPrice: 2.49),
        ),
        'US\$2.49',
      );
    });

    test('a grant parses wallet, amounts and the replay flag', () {
      final g = CoinPurchaseGrant.fromJson(
        grantJson('coins_popular', coins: 8000000, diamonds: 8, replayed: true),
      );
      expect(g.wallet.coins, 6000000);
      expect(g.coins, 8000000);
      expect(g.diamonds, 8);
      expect(g.pack!.id, 'coins_popular');
      expect(g.replayed, isTrue);
    });
  });

  group('purchase flow (fake store, fake API)', () {
    late TestEnv env;
    late MetaFakes fakes;
    late FakeIapStore store;
    late ProviderContainer c;

    Future<void> pump([int turns = 60]) async {
      for (var i = 0; i < turns; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<ProviderContainer> start({
      String platform = 'android',
      bool signedIn = true,
      bool available = true,
    }) async {
      env = await TestEnv.create(platform: platform);
      env.routeHappyPath();
      routeCoinPacks(env, available: available);
      fakes = MetaFakes();
      store = FakeIapStore(products: _allProducts());
      final container = metaContainer(
        env,
        fakes,
        extra: [iapStoreProvider.overrideWithValue(store), _noWait],
      );
      container
        ..listen(coinPurchaseControllerProvider, (_, _) {})
        ..listen(coinPacksProvider, (_, _) {});
      if (signedIn) await signIn(container);
      await pump();
      return container;
    }

    tearDown(() async {
      await fakes.close();
      await store.close();
    });

    CoinPurchaseController ctl() =>
        c.read(coinPurchaseControllerProvider.notifier);
    CoinPack pack(String id) =>
        c.read(coinPacksProvider).catalog!.packs.firstWhere((p) => p.id == id);
    List<CoinNoticeKind> noticeKinds() => [
      for (final n in c.read(coinPurchaseControllerProvider).notices) n.kind,
    ];

    test('buy → store sheet with the account token → server grant → '
        'consumed, wallet, analytics, one celebration', () async {
      c = await start();
      env.backend.json('POST', _purchases, grantJson('coins_starter'));
      store.autoResult = PurchaseStatus.purchased;

      expect(
        c.read(coinPacksProvider).productFor(pack('coins_starter')),
        isNotNull,
      );
      expect(await ctl().buy(pack('coins_starter')), CoinBuyResult.started);
      await pump();

      expect(store.buys, [('coins_starter', kTestAccountToken)]);
      final post = env.backend.calls('POST', _purchases).single;
      expect(post.json, {
        'platform': 'android',
        'productId': 'coins_starter',
        'purchaseToken': 'play-token-1',
      });
      expect(
        store.finished.single.verificationData.serverVerificationData,
        'play-token-1',
      );
      expect(c.read(walletControllerProvider).coins, 6000000);
      expect(c.read(walletControllerProvider).diamonds, 55);
      expect(coinEvents(fakes), ['coin_pack_purchased:starter:199.0:INR']);
      final notice = ctl().takeNotice()!;
      expect(notice.kind, CoinNoticeKind.granted);
      expect((notice.coins, notice.diamonds), (5000000, 5));
      expect(ctl().takeNotice(), isNull);
      expect(c.read(coinPurchaseControllerProvider).busy, isEmpty);

      // The store offers the same purchase again (e.g. consume raced): no
      // second request, consumed again.
      store.emit([storePurchase('coins_starter', token: 'play-token-1')]);
      await pump();
      expect(env.backend.calls('POST', _purchases), hasLength(1));
      expect(store.finished, hasLength(2));
    });

    test('network and 5xx failures are retried; the purchase is consumed '
        'only after the 200', () async {
      c = await start();
      var calls = 0;
      env.backend.on('POST', _purchases, (_) {
        calls++;
        if (calls < 3) return coinError(503, 'internal');
        return FakeResponse(200, grantJson('coins_popular', coins: 8000000));
      });
      store.emit([storePurchase('coins_popular', token: 'tok-p')]);
      await pump(120);
      expect(calls, 3);
      expect(store.finished, hasLength(1));
      expect(noticeKinds(), [CoinNoticeKind.granted]);
    });

    test('a refused purchase is never consumed and is reported once; a '
        'later start delivers it again', () async {
      c = await start();
      env.backend.on(
        'POST',
        _purchases,
        (_) => coinError(422, 'purchase_invalid'),
      );
      final p = storePurchase('coins_great_value', token: 'tok-bad');
      store.emit([p]);
      await pump();
      store.emit([p]);
      await pump();
      expect(env.backend.calls('POST', _purchases), hasLength(2));
      expect(store.finished, isEmpty);
      final n = ctl().takeNotice()!;
      expect(n.kind, CoinNoticeKind.failed);
      expect(n.code, 'purchase_invalid');
      expect(ctl().takeNotice(), isNull); // not repeated
      expect(coinEvents(fakes), isEmpty);
    });

    test('an unreachable server leaves the purchase with the store; the next '
        'start re-delivers it (Android restore) and grants it', () async {
      c = await start();
      env.backend.offline = true;
      final p = storePurchase('coins_best_value', token: 'tok-off');
      store.unconsumed.add(p);
      store.emit([p]);
      await pump(120);
      expect(env.backend.calls('POST', _purchases), hasLength(4)); // attempts
      expect(store.finished, isEmpty);
      expect(noticeKinds(), [CoinNoticeKind.delayed]);
      c.dispose();
      await fakes.close();

      // Next app start: signed in again, Google Play re-delivers the
      // unconsumed purchase as "restored".
      final env2 = await TestEnv.create();
      env2.routeHappyPath();
      routeCoinPacks(env2);
      env2.backend.json(
        'POST',
        _purchases,
        grantJson('coins_best_value', coins: 35000000, diamonds: 250),
      );
      fakes = MetaFakes();
      final store2 = FakeIapStore(products: _allProducts())..unconsumed.add(p);
      addTearDown(store2.close);
      c = metaContainer(
        env2,
        fakes,
        extra: [iapStoreProvider.overrideWithValue(store2), _noWait],
      );
      c.listen(coinPurchaseControllerProvider, (_, _) {});
      await signIn(c);
      await pump();
      expect(store2.redeliveries, 1);
      final post = env2.backend.calls('POST', _purchases).single;
      expect(post.json['purchaseToken'], 'tok-off');
      expect(store2.finished, hasLength(1));
      expect(store2.unconsumed, isEmpty);
      expect(c.read(walletControllerProvider).coins, 6000000);
      // First grant for the server: counted and celebrated.
      expect(coinEvents(fakes), ['coin_pack_purchased:best_value:999.0:INR']);
      expect(noticeKinds(), [CoinNoticeKind.granted]);
    });

    test('a replayed grant is consumed and updates the wallet, without a '
        'second celebration or analytics event', () async {
      c = await start();
      env.backend.json(
        'POST',
        _purchases,
        grantJson('coins_starter', replayed: true, walletCoins: 7000000),
      );
      store.emit([
        storePurchase(
          'coins_starter',
          token: 'tok-old',
          status: PurchaseStatus.restored,
        ),
      ]);
      await pump();
      expect(store.finished, hasLength(1));
      expect(c.read(walletControllerProvider).coins, 7000000);
      expect(coinEvents(fakes), isEmpty);
      expect(noticeKinds(), isEmpty);
    });

    test('concurrent deliveries of one purchase send one request', () async {
      c = await start();
      env.backend.on('POST', _purchases, (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return FakeResponse(200, grantJson('coins_starter'));
      });
      final p = storePurchase('coins_starter', token: 'tok-dup');
      store
        ..emit([p])
        ..emit([p, p]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await pump();
      expect(env.backend.calls('POST', _purchases), hasLength(1));
      expect(noticeKinds(), [CoinNoticeKind.granted]);
    });

    test('purchases that arrive signed out wait for the sign-in', () async {
      c = await start(signedIn: false);
      env.backend.json('POST', _purchases, grantJson('coins_starter'));
      store.emit([storePurchase('coins_starter', token: 'tok-early')]);
      await pump();
      expect(env.backend.calls('POST', _purchases), isEmpty);
      await signIn(c);
      await pump();
      expect(env.backend.calls('POST', _purchases), hasLength(1));
      expect(store.finished, hasLength(1));
      expect(store.redeliveries, 1);
    });

    test('iOS sends the transaction id and the signed transaction', () async {
      c = await start(platform: 'ios');
      env.backend.json('POST', _purchases, grantJson('coins_popular'));
      store.emit([
        storePurchase(
          'coins_popular',
          token: 'eyJhbGciOiJFUzI1NiJ9.payload.sig',
          transactionId: '2000000123456789',
        ),
      ]);
      await pump();
      expect(env.backend.calls('POST', _purchases).single.json, {
        'platform': 'ios',
        'productId': 'coins_popular',
        'transactionId': '2000000123456789',
        'signedTransaction': 'eyJhbGciOiJFUzI1NiJ9.payload.sig',
      });
      expect(store.finished, hasLength(1));
    });

    test('unavailable: server not configured, store missing or product not '
        'in the store → nothing is opened', () async {
      c = await start(available: false);
      expect(await ctl().buy(pack('coins_starter')), CoinBuyResult.unavailable);
      expect(store.buys, isEmpty);
      c.dispose();
      await fakes.close();
      await store.close();

      c = await start();
      store.available = false;
      expect(await ctl().buy(pack('coins_starter')), CoinBuyResult.unavailable);
      store.available = true;
      store.products.remove('coins_starter');
      await c.read(coinPacksProvider.notifier).refresh();
      expect(await ctl().buy(pack('coins_starter')), CoinBuyResult.unavailable);
      expect(store.buys, isEmpty);
    });

    test('pending, cancelled and failed store results', () async {
      c = await start();
      store.emit([
        storePurchase(
          'coins_starter',
          token: 'tok-wait',
          status: PurchaseStatus.pending,
        ),
        storePurchase(
          'coins_popular',
          token: 'tok-cancel',
          status: PurchaseStatus.canceled,
        ),
        storePurchase(
          'coins_great_value',
          token: 'tok-err',
          status: PurchaseStatus.error,
        ),
        // Not a coin pack: ignored.
        storePurchase('pp_wolf', token: 'tok-other'),
      ]);
      await pump();
      expect(env.backend.calls('POST', _purchases), isEmpty);
      expect(noticeKinds(), [CoinNoticeKind.pending, CoinNoticeKind.failed]);
      expect(store.dismissed.map((p) => p.productID), [
        'coins_popular',
        'coins_great_value',
      ]);
      expect(store.finished, isEmpty);
    });

    test('Google Play refusing to open (an older purchase is unconsumed) '
        're-delivers that purchase', () async {
      c = await start();
      env.backend.json('POST', _purchases, grantJson('coins_starter'));
      store
        ..openSheet = false
        ..unconsumed.add(storePurchase('coins_starter', token: 'tok-stuck'));
      final before = store.redeliveries;
      expect(await ctl().buy(pack('coins_starter')), CoinBuyResult.failed);
      await pump();
      expect(store.redeliveries, before + 1);
      expect(env.backend.calls('POST', _purchases), hasLength(1));
      expect(store.finished, hasLength(1));
    });
  });

  group('screen: Coins', () {
    late TestEnv env;
    late MetaFakes fakes;
    late FakeIapStore store;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      routeStore(env);
      routeCoinPacks(env);
      fakes = MetaFakes();
      // Only Popular is configured in the store so far.
      store = FakeIapStore(
        products: {
          'coins_popular': storeProduct(
            'coins_popular',
            price: '₹299.00',
            rawPrice: 299,
          ),
        },
      );
    });
    tearDown(() async {
      await fakes.close();
      await store.close();
    });

    Future<ProviderContainer> pumpShop(WidgetTester tester) async {
      final c = await pumpMeta(
        tester,
        env,
        fakes,
        const ShopScreen(),
        extra: [iapStoreProvider.overrideWithValue(store), _noWait],
      );
      await flush(tester);
      return c;
    }

    testWidgets('the Shop opens on Coins: four packs with labels, coins, '
        'diamonds, the store price or the fallback ₹ price', (tester) async {
      final c = await pumpShop(tester);
      expect(c.read(shopCategoryProvider), kCoinsCategory);
      expect(find.text('Coin packs'), findsOneWidget);
      for (final label in const [
        'Starter',
        'Popular',
        'Great Value',
        'Best Value',
      ]) {
        await scrollTo(tester, find.text(label));
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 4000));
      await flush(tester);
      expect(find.text('50 Lakh coins'), findsOneWidget);
      expect(find.text('+5 diamonds'), findsOneWidget);
      expect(find.text('80 Lakh coins'), findsOneWidget);
      expect(find.text('₹199'), findsOneWidget); // fallback
      expect(find.text('₹299.00'), findsOneWidget); // store
      expect(find.text('₹299'), findsNothing);
      await scrollTo(tester, byKeyString('coin-pack-coins_best_value'));
      expect(find.text('3.5 Crore coins'), findsOneWidget);
      expect(find.text('+250 diamonds'), findsOneWidget);
      expect(find.text('₹999'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Best Value: 3.5 Crore coins and 250 diamonds for ₹999',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the payments note names Google Play, never the App Store', (
      tester,
    ) async {
      await pumpShop(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await flush(tester);
      expect(
        find.textContaining('Payments are handled by Google Play'),
        findsOneWidget,
      );
      expect(find.textContaining('App Store'), findsNothing);
    });

    testWidgets('buy a pack: the server grant shows "Coins added!" with the '
        'purchase sound and updates the balance', (tester) async {
      env.backend.json(
        'POST',
        _purchases,
        grantJson(
          'coins_popular',
          coins: 8000000,
          diamonds: 8,
          walletCoins: 9000000,
          walletDiamonds: 58,
        ),
      );
      store.autoResult = PurchaseStatus.purchased;
      final c = await pumpShop(tester);
      await scrollTo(tester, byKeyString('coin-pack-buy-coins_popular'));
      await tester.tap(byKeyString('coin-pack-buy-coins_popular'));
      await settleRoute(tester);
      expect(store.buys.single.$1, 'coins_popular');
      expect(env.backend.calls('POST', _purchases), hasLength(1));
      expect(find.text('Coins added!'), findsOneWidget);
      expect(
        find.text('80 Lakh coins and 8 diamonds are now in your wallet.'),
        findsOneWidget,
      );
      expect(env.audio.played, contains(Sfx.purchase));
      expect(c.read(walletControllerProvider).coins, 9000000);
      expect(store.finished, hasLength(1));
      expect(
        fakes.analytics.events,
        contains('coin_pack_purchased:popular:299.0:INR'),
      );
      await tester.tap(find.text('Nice!'));
      await settleRoute(tester);
      expect(find.text('Coins added!'), findsNothing);
    });

    testWidgets('a pack the store does not sell yet: "This pack isn\'t '
        'available yet"', (tester) async {
      await pumpShop(tester);
      await tester.tap(byKeyString('coin-pack-buy-coins_starter'));
      await settleRoute(tester);
      expect(find.text("This pack isn't available yet."), findsOneWidget);
      expect(store.buys, isEmpty);
    });

    testWidgets('a refused purchase explains it; nothing is consumed', (
      tester,
    ) async {
      env.backend.on(
        'POST',
        _purchases,
        (_) => coinError(422, 'purchase_invalid'),
      );
      store.autoResult = PurchaseStatus.purchased;
      await pumpShop(tester);
      await scrollTo(tester, byKeyString('coin-pack-buy-coins_popular'));
      await tester.tap(byKeyString('coin-pack-buy-coins_popular'));
      await settleRoute(tester);
      expect(
        find.text('This purchase couldn\'t be verified, so nothing was added.'),
        findsOneWidget,
      );
      expect(store.finished, isEmpty);
    });

    testWidgets('a pushed refund only updates the balance (no coin toast)', (
      tester,
    ) async {
      final c = await pumpShop(tester);
      fakes.wallet.add(
        const WalletUpdatedEvent(
          coins: 0,
          diamonds: 40,
          deltaCoins: -5000000,
          deltaDiamonds: -5,
          reason: 'refund',
        ),
      );
      await flush(tester);
      expect(c.read(walletControllerProvider).coins, 0);
      expect(c.read(walletControllerProvider).lastReason, 'refund');
      expect(tester.takeException(), isNull);
    });
  });

  group('screen: Coins on iOS', () {
    late TestEnv env;
    late MetaFakes fakes;
    late FakeIapStore store;

    setUp(() async {
      env = await TestEnv.create(platform: 'ios');
      env.routeHappyPath();
      routeMeta(env);
      routeStore(env);
      routeCoinPacks(env);
      fakes = MetaFakes();
      store = FakeIapStore(products: const {});
    });
    tearDown(() async {
      await fakes.close();
      await store.close();
    });

    testWidgets('the payments note names the App Store only (guideline '
        '2.3.10)', (tester) async {
      await pumpMeta(
        tester,
        env,
        fakes,
        const ShopScreen(),
        extra: [iapStoreProvider.overrideWithValue(store), _noWait],
      );
      await flush(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await flush(tester);
      expect(
        find.textContaining('Payments are handled by the App Store'),
        findsOneWidget,
      );
      expect(find.textContaining('Google Play'), findsNothing);
    });
  });

  group('number system', () {
    tearDown(() => AppNumberFormat.preferredSystem = null);

    for (final (system, coins, best) in const [
      ('indian', '50 Lakh coins', '3.5 Crore coins'),
      ('international', '5M coins', '35M coins'),
    ]) {
      testWidgets('coins follow the $system number system', (tester) async {
        final env = await TestEnv.create(
          prefs: {'settings.number_system': system},
        );
        env.routeHappyPath();
        routeCoinPacks(env);
        routeStore(env);
        env.backend.json('GET', '/collection', collectionJson());
        await pumpScreen(
          tester,
          env,
          const ShopScreen(),
          prepare: (c) =>
              c.read(sessionControllerProvider.notifier).continueAsGuest(),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(coins), findsOneWidget);
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -2000),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(best), findsOneWidget);
      });
    }
  });
}
