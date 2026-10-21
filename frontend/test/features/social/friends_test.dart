import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/state/in_match_provider.dart';
import 'package:ludo_royale/features/social/domain/friend_code.dart';
import 'package:ludo_royale/features/social/presentation/friend_request_banner.dart';
import 'package:ludo_royale/features/social/presentation/friends_screen.dart';

import '../progression/meta_test_support.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());

  group('friend codes', () {
    test('format groups the code for reading', () {
      expect(FriendCode.format('u_3f9a1c2b7d4e'), 'u_3f9a 1c2b 7d4e');
      expect(FriendCode.format('u_guest1'), 'u_gues t1');
      expect(FriendCode.format('not-a-code'), 'not-a-code');
    });

    test('normalize accepts any case, separators and a missing prefix', () {
      expect(FriendCode.normalize('  U_3F9A 1C2B-7D4E '), 'u_3f9a1c2b7d4e');
      expect(FriendCode.normalize('3f9a1c2b7d4e'), 'u_3f9a1c2b7d4e');
      expect(FriendCode.normalize(''), '');
    });

    test('validate rejects empty, malformed and own codes', () {
      expect(FriendCode.validate('  '), FriendCodeProblem.empty);
      expect(FriendCode.validate('u_!!'), FriendCodeProblem.invalid);
      expect(FriendCode.validate('u_ab'), FriendCodeProblem.invalid);
      expect(
        FriendCode.validate('U_GUEST1', myUid: 'u_guest1'),
        FriendCodeProblem.own,
      );
      expect(FriendCode.validate('u_3f9a 1c2b 7d4e'), isNull);
    });
  });

  group('friends screen', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    testWidgets('shows my readable code, friends and online state', (
      tester,
    ) async {
      await pumpMeta(tester, env, fakes, const FriendsScreen());
      expect(find.text('u_gues t1'), findsOneWidget);
      expect(byKeyString('friend-u_ravi2345abcd'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('accept moves a request to friends', (tester) async {
      env.backend.json('POST', '/friends/requests/u_kabir9999qqqq/accept', {
        'friend': friendJson('u_kabir9999qqqq', 'Kabir', level: 3),
      });
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'requests'),
      );
      await tester.tap(byKeyString('accept-u_kabir9999qqqq'));
      await flush(tester);
      expect(
        env.backend.calls('POST', '/friends/requests/u_kabir9999qqqq/accept'),
        hasLength(1),
      );
      expect(byKeyString('incoming-u_kabir9999qqqq'), findsNothing);
      expect(find.text('You and Kabir are now friends!'), findsOneWidget);
      await tester.tap(find.text('Friends').first);
      await tester.pump();
      expect(byKeyString('friend-u_kabir9999qqqq'), findsOneWidget);
    });

    testWidgets('decline and cancel use DELETE and update the lists', (
      tester,
    ) async {
      env.backend
        ..json('DELETE', '/friends/u_kabir9999qqqq', const {}, status: 204)
        ..json('DELETE', '/friends/u_sara5555pppp', const {}, status: 204);
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'requests'),
      );
      await tester.tap(byKeyString('decline-u_kabir9999qqqq'));
      await flush(tester);
      expect(byKeyString('incoming-u_kabir9999qqqq'), findsNothing);
      expect(find.text('Request declined'), findsOneWidget);

      await tester.tap(byKeyString('cancel-u_sara5555pppp'));
      await flush(tester);
      expect(byKeyString('outgoing-u_sara5555pppp'), findsNothing);
      expect(
        env.backend.calls('DELETE', '/friends/u_sara5555pppp'),
        hasLength(1),
      );
      expect(find.text('No pending requests'), findsOneWidget);
    });

    testWidgets('remove friend asks for confirmation first', (tester) async {
      env.backend.json(
        'DELETE',
        '/friends/u_ravi2345abcd',
        const {},
        status: 204,
      );
      await pumpMeta(tester, env, fakes, const FriendsScreen());
      await tester.tap(
        find.descendant(
          of: byKeyString('friend-u_ravi2345abcd'),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settleRoute(tester);
      await tester.tap(find.text('Remove friend'));
      await settleRoute(tester);
      expect(find.text('Remove Ravi?'), findsOneWidget);

      // Cancel keeps the friend.
      await tester.tap(find.text('Cancel'));
      await settleRoute(tester);
      expect(env.backend.calls('DELETE', '/friends/u_ravi2345abcd'), isEmpty);

      await tester.tap(
        find.descendant(
          of: byKeyString('friend-u_ravi2345abcd'),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settleRoute(tester);
      await tester.tap(find.text('Remove friend'));
      await settleRoute(tester);
      await tester.tap(find.text('Remove'));
      await settleRoute(tester);
      expect(
        env.backend.calls('DELETE', '/friends/u_ravi2345abcd'),
        hasLength(1),
      );
      expect(byKeyString('friend-u_ravi2345abcd'), findsNothing);
    });

    testWidgets('an invalid code is rejected locally; unknown codes are '
        'explained', (tester) async {
      env.backend.on(
        'POST',
        '/friends/requests',
        (_) => FakeResponse.error(404, 'not_found'),
      );
      await pumpMeta(tester, env, fakes, const FriendsScreen());
      await tester.tap(byKeyString('add-friend'));
      await settleRoute(tester);

      await tester.enterText(byKeyString('friend-code-field'), 'u_!!');
      await tester.tap(byKeyString('send-friend-request'));
      await settleRoute(tester);
      expect(
        find.textContaining("doesn't look like a friend code"),
        findsOneWidget,
      );
      expect(env.backend.calls('POST', '/friends/requests'), isEmpty);

      await tester.enterText(byKeyString('friend-code-field'), 'u_guest1');
      await tester.tap(byKeyString('send-friend-request'));
      await settleRoute(tester);
      expect(find.text("That's your own friend code."), findsOneWidget);
      expect(env.backend.calls('POST', '/friends/requests'), isEmpty);

      await tester.enterText(
        byKeyString('friend-code-field'),
        'U_ZZZZ 9999 YYYY',
      );
      await tester.tap(byKeyString('send-friend-request'));
      await settleRoute(tester);
      final req = env.backend.calls('POST', '/friends/requests').single;
      expect(req.json, {'friendCode': 'u_zzzz9999yyyy'});
      expect(
        find.text('No player has this friend code. Check it and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('sending a request closes the sheet and confirms', (
      tester,
    ) async {
      env.backend.json('POST', '/friends/requests', {
        'friend': friendJson('u_zzzz9999yyyy', 'Zoya', status: 'outgoing'),
      }, status: 201);
      await pumpMeta(tester, env, fakes, const FriendsScreen());
      await tester.tap(byKeyString('add-friend'));
      await settleRoute(tester);
      await tester.enterText(
        byKeyString('friend-code-field'),
        'u_zzzz9999yyyy',
      );
      await tester.tap(byKeyString('send-friend-request'));
      await settleRoute(tester);
      expect(byKeyString('friend-code-field'), findsNothing);
      expect(find.text('Friend request sent to Zoya'), findsOneWidget);
    });

    testWidgets('recent opponents can be added', (tester) async {
      env.backend.json('POST', '/friends/requests', {
        'friend': friendJson('u_zaid1111aaaa', 'Zaid', status: 'outgoing'),
      }, status: 201);
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'recent'),
      );
      expect(find.text('Friends'), findsWidgets);
      await tester.tap(byKeyString('recent-add-u_zaid1111aaaa'));
      await flush(tester);
      expect(env.backend.calls('POST', '/friends/requests').single.json, {
        'friendCode': 'u_zaid1111aaaa',
      });
      expect(byKeyString('recent-add-u_zaid1111aaaa'), findsNothing);
      expect(find.text('Requested'), findsOneWidget);
    });

    testWidgets('a friend_request push refreshes the requests', (tester) async {
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'requests'),
      );
      final before = env.backend.calls('GET', '/friends').length;
      env.backend.json(
        'GET',
        '/friends',
        friendsJson(
          incoming: [
            friendJson('u_kabir9999qqqq', 'Kabir', status: 'incoming'),
            friendJson('u_neha4444rrrr', 'Neha', status: 'incoming'),
          ],
        ),
      );
      fakes.social.add(
        const FriendRequestEvent(fromUid: 'u_neha4444rrrr', fromName: 'Neha'),
      );
      await flush(tester);
      expect(env.backend.calls('GET', '/friends').length, before + 1);
      expect(byKeyString('incoming-u_neha4444rrrr'), findsOneWidget);
    });
  });

  group('friend request banner', () {
    testWidgets('appears for pushes, opens Requests, and waits out matches', (
      tester,
    ) async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      final fakes = MetaFakes();
      addTearDown(fakes.close);
      final navKey = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: navKey,
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/friends',
            builder: (_, s) =>
                FriendsScreen(initialTab: s.uri.queryParameters['tab']),
          ),
        ],
      );
      addTearDown(router.dispose);
      final c = await pumpMeta(
        tester,
        env,
        fakes,
        const SizedBox(),
        router: router,
        shell: (context, child) =>
            FriendRequestBannerHost(navigatorKey: navKey, child: child!),
      );

      // In a match: nothing is shown.
      c.read(inMatchProvider.notifier).set(true);
      fakes.social.add(
        const FriendRequestEvent(fromUid: 'u_neha4444rrrr', fromName: 'Neha'),
      );
      await flush(tester);
      expect(find.text('Neha wants to be your friend'), findsNothing);

      c.read(inMatchProvider.notifier).set(false);
      fakes.social.add(
        // A new push (non-const: a distinct event instance).
        FriendRequestEvent(fromUid: 'u_neha4444rrrr', fromName: 'Ne${'ha'}'),
      );
      await flush(tester);
      expect(find.text('Neha wants to be your friend'), findsOneWidget);

      await tester.tap(find.text('View'));
      await settleRoute(tester);
      expect(find.text('Neha wants to be your friend'), findsNothing);
      expect(find.text('Received'), findsOneWidget); // Requests tab
      expect(friendsRequestsLocation(), '/friends?tab=requests');
    });
  });
}
