import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/core/lifecycle/app_lifecycle.dart';
import 'package:ludo_royale/core/network/api_client.dart';
import 'package:ludo_royale/features/progression/application/meta_support.dart';
import 'package:ludo_royale/features/social/domain/report_models.dart';
import 'package:ludo_royale/features/social/domain/social_models.dart';
import 'package:ludo_royale/features/social/presentation/friends_screen.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';

import '../progression/meta_test_support.dart';

List<Map<String, dynamic>> _fourReports() => [
  reportJson('rep_1', status: 'submitted', ago: const Duration(minutes: 5)),
  reportJson(
    'rep_2',
    uid: 'u_neha4444rrrr',
    name: 'Neha',
    reason: 'offensive_name',
    status: 'reviewing',
    ago: const Duration(hours: 2),
  ),
  reportJson(
    'rep_3',
    uid: 'u_omar3333ssss',
    name: 'Omar',
    reason: 'leaving_or_stalling',
    status: 'action_taken',
    game: 'snakes_ladders',
    ago: const Duration(hours: 30),
  ),
  reportJson(
    'rep_4',
    uid: 'u_lina2222tttt',
    name: 'Lina',
    reason: 'abusive_behavior',
    status: 'dismissed',
    ago: const Duration(days: 9),
  ),
];

void main() {
  setUpAll(() async => initializeDateFormatting());

  group('report models', () {
    test('parse reports, statuses, reasons and the limit', () {
      final s = ReportsState.fromJson(
        reportsJson(
          reports: _fourReports(),
          remaining: 0,
          resetsAt: kMetaNowMs + 1000,
        ),
      );
      expect(s.reports.map((r) => r.status), [
        ReportStatus.submitted,
        ReportStatus.reviewing,
        ReportStatus.actionTaken,
        ReportStatus.dismissed,
      ]);
      expect(s.reports[1].reason, ReportReason.offensiveName);
      expect(s.reports[2].game, 'snakes_ladders');
      expect(s.limit.exhausted, isTrue);
      expect(s.limit.resetsAt, kMetaNowMs + 1000);
      // Unknown values from a newer server degrade gracefully.
      expect(ReportStatus.parse('escalated'), ReportStatus.submitted);
      expect(ReportReason.parse('spam'), ReportReason.other);
    });

    test('a player counts as reported for 24 h (or after a 409)', () {
      final s = ReportsState.fromJson(reportsJson(reports: _fourReports()));
      expect(s.reportedRecently('u_zaid1111aaaa', kMetaNowMs), isTrue);
      expect(s.reportedRecently('u_omar3333ssss', kMetaNowMs), isFalse);
      expect(s.block('u_x').reportedRecently('u_x', kMetaNowMs), isTrue);
    });

    test('friends lists: server counts, limit and fallbacks', () {
      final server = FriendsLists.fromJson(
        friendsJson(onlineCount: 3, friendCount: 20, maxFriends: 20),
      );
      expect(server.onlineCount, 3);
      expect(server.friendCount, 20);
      expect(server.atFriendLimit, isTrue);
      expect(server.statusOf('u_kabir9999qqqq'), FriendStatus.incoming);
      expect(server.statusOf('u_ravi2345abcd'), FriendStatus.friend);
      expect(server.statusOf('u_nobody'), FriendStatus.none);

      final legacy = FriendsLists.fromJson(friendsJson());
      expect(legacy.onlineCount, 1);
      expect(legacy.friendCount, 2);
      expect(legacy.maxFriends, 20);
      expect(legacy.atFriendLimit, isFalse);
      // Local changes fall back to counting.
      expect(server.remove('u_ravi2345abcd').friendCount, 1);
    });
  });

  group('Reported tab', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    testWidgets('lists my reports with reasons, dates and status chips', (
      tester,
    ) async {
      env.backend.json(
        'GET',
        '/reports',
        reportsJson(reports: _fourReports(), remaining: 1),
      );
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'reported'),
      );
      expect(find.text('Reports left today: 1 of 2'), findsOneWidget);
      expect(byKeyString('reports-reset'), findsNothing);

      final statuses = {
        'rep_1': ('Zaid', 'Cheating', 'Submitted', 'submitted'),
        'rep_2': ('Neha', 'Offensive name', 'Under review', 'reviewing'),
        'rep_3': ('Omar', 'Leaving or stalling', 'Action taken', 'actionTaken'),
        'rep_4': (
          'Lina',
          'Harassment or abusive chat',
          'Dismissed',
          'dismissed',
        ),
      };
      for (final MapEntry(key: id, value: v) in statuses.entries) {
        await scrollTo(tester, byKeyString('report-$id'));
        final tile = byKeyString('report-$id');
        Finder inTile(Finder f) => find.descendant(of: tile, matching: f);
        expect(inTile(find.text(v.$1)), findsOneWidget);
        expect(inTile(find.text(v.$2)), findsOneWidget);
        // Text + icon + tint: never color alone.
        expect(inTile(find.text(v.$3)), findsOneWidget);
        expect(inTile(byKeyString('report-status-${v.$4}')), findsOneWidget);
      }
      // Relative and absolute dates.
      expect(find.text('Ludo · 5 min ago'), findsOneWidget);
      expect(find.text('Ludo · 2 h ago'), findsOneWidget);
      expect(find.text('Snakes & Ladders · Yesterday'), findsOneWidget);
      expect(find.text('Ludo · Oct 12'), findsOneWidget);
      expect(env.backend.calls('GET', '/reports'), hasLength(1));
    });

    testWidgets('empty state', (tester) async {
      env.backend.json('GET', '/reports', reportsJson());
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'reported'),
      );
      expect(find.text('No reports'), findsOneWidget);
      expect(find.text('Reports left today: 2 of 2'), findsOneWidget);
    });

    testWidgets('no reports left: shows when they come back', (tester) async {
      env.backend.json(
        'GET',
        '/reports',
        reportsJson(
          reports: _fourReports().take(2).toList(),
          remaining: 0,
          resetsAt: kMetaNowMs + const Duration(hours: 3).inMilliseconds,
        ),
      );
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'reported'),
      );
      expect(find.text('Reports left today: 0 of 2'), findsOneWidget);
      final reset = tester.widget<Text>(byKeyString('reports-reset')).data!;
      expect(reset, startsWith('You can report again at 3:00'));
    });

    testWidgets('pull to refresh reloads my reports', (tester) async {
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'reported'),
      );
      env.backend.json(
        'GET',
        '/reports',
        reportsJson(reports: [reportJson('rep_9', status: 'reviewing')]),
      );
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 500),
        1200,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settleRoute(tester);
      expect(env.backend.calls('GET', '/reports'), hasLength(2));
      expect(find.text('Under review'), findsOneWidget);
    });

    testWidgets('deep link /friends?tab=reported opens the tab', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/friends?tab=reported',
        routes: [
          GoRoute(
            path: '/friends',
            builder: (_, s) =>
                FriendsScreen(initialTab: s.uri.queryParameters['tab']),
          ),
        ],
      );
      addTearDown(router.dispose);
      env.backend.json('GET', '/reports', reportsJson());
      await pumpMeta(tester, env, fakes, const SizedBox(), router: router);
      expect(find.text('No reports'), findsOneWidget);
      // The selected pill is scrolled into view, not left past the edge.
      await tester.pump();
      final screen = tester.getRect(find.byType(FriendsScreen));
      final pill = tester.getRect(find.text('Reported').first);
      expect(pill.left, greaterThanOrEqualTo(screen.left));
      expect(pill.right, lessThanOrEqualTo(screen.right));
      router.go('/friends?tab=requests');
      await settleRoute(tester);
      expect(find.text('Received'), findsOneWidget);
      router.go('/friends?tab=reported');
      await settleRoute(tester);
      expect(find.text('No reports'), findsOneWidget);
    });

    testWidgets('fits 320×640 in Arabic (RTL) at 1.35× text', (tester) async {
      env.backend.json(
        'GET',
        '/reports',
        reportsJson(
          reports: _fourReports(),
          remaining: 0,
          resetsAt: kMetaNowMs + 3600000,
        ),
      );
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'reported'),
        locale: const Locale('ar'),
        size: Viewports.small,
        textScale: 1.35,
      );
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('قيد المراجعة'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(Scaffold).first)),
        TextDirection.rtl,
      );
    });
  });

  group('Friends tab presence', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    testWidgets('"Online now (N)" uses the server count, then offline', (
      tester,
    ) async {
      env.backend.json('GET', '/friends', friendsJson(onlineCount: 1));
      await pumpMeta(tester, env, fakes, const FriendsScreen());
      expect(find.text('Online now (1)'), findsOneWidget);
      expect(find.text('Offline (1)'), findsOneWidget);
      final online = tester.getTopLeft(byKeyString('friend-u_ravi2345abcd'));
      final offlineHeader = tester.getTopLeft(byKeyString('offline-header'));
      final offline = tester.getTopLeft(byKeyString('friend-u_meera7788wxyz'));
      expect(online.dy, lessThan(offlineHeader.dy));
      expect(offlineHeader.dy, lessThan(offline.dy));
    });

    testWidgets('falls back to counting online friends', (tester) async {
      env.backend.json(
        'GET',
        '/friends',
        friendsJson(
          friends: [
            friendJson('u_ravi2345abcd', 'Ravi', online: true),
            friendJson('u_asha1111bbbb', 'Asha', online: true),
          ],
        ),
      );
      await pumpMeta(tester, env, fakes, const FriendsScreen());
      expect(find.text('Online now (2)'), findsOneWidget);
      expect(byKeyString('offline-header'), findsNothing);
    });

    testWidgets('refreshes every 30 s only while visible, and on resume', (
      tester,
    ) async {
      final c = await pumpMeta(tester, env, fakes, const FriendsScreen());
      int gets() => env.backend.calls('GET', '/friends').length;
      final start = gets();

      await tester.pump(const Duration(seconds: 29));
      await flush(tester);
      expect(gets(), start, reason: 'not before 30 s');
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(gets(), start + 1);
      await tester.pump(FriendsScreen.autoRefreshInterval);
      await flush(tester);
      expect(gets(), start + 2);

      // Covered by another screen: no polling.
      final nav = Navigator.of(tester.element(find.byType(FriendsScreen)));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('other')),
        ),
      );
      await settleRoute(tester);
      final covered = gets();
      await tester.pump(const Duration(seconds: 95));
      await flush(tester);
      expect(gets(), covered);

      // Back on screen: refreshed right away, then every 30 s again.
      nav.pop();
      await settleRoute(tester);
      expect(gets(), covered + 1);

      // App in the background: no polling; resuming refreshes.
      final lifecycle = c.read(appLifecycleProvider);
      lifecycle.emit(AppLifecycleState.paused);
      final paused = gets();
      await tester.pump(const Duration(seconds: 65));
      await flush(tester);
      expect(gets(), paused);
      lifecycle.emit(AppLifecycleState.resumed);
      await flush(tester);
      expect(gets(), paused + 1);
    });

    testWidgets('online updates from a refresh move friends between '
        'sections', (tester) async {
      await pumpMeta(tester, env, fakes, const FriendsScreen());
      expect(find.text('Online now (1)'), findsOneWidget);
      env.backend.json(
        'GET',
        '/friends',
        friendsJson(
          friends: [
            friendJson('u_ravi2345abcd', 'Ravi', online: true),
            friendJson('u_meera7788wxyz', 'Meera', online: true),
          ],
          onlineCount: 2,
        ),
      );
      await tester.pump(FriendsScreen.autoRefreshInterval);
      await flush(tester);
      expect(find.text('Online now (2)'), findsOneWidget);
      expect(byKeyString('offline-header'), findsNothing);
    });
  });

  group('friend limit', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    testWidgets('header shows Friends N/max', (tester) async {
      await pumpMeta(tester, env, fakes, const FriendsScreen());
      expect(find.text('Friends 2/20'), findsOneWidget);
      expect(find.text('2/20'), findsOneWidget); // tab pill
      expect(byKeyString('friend-limit-note'), findsNothing);
    });

    const note = 'You can have up to 20 friends — remove one to add more.';

    testWidgets('at 20/20 the header explains the limit; add by code is '
        'disabled', (tester) async {
      env.backend.json(
        'GET',
        '/friends',
        friendsJson(friendCount: 20, maxFriends: 20),
      );
      await pumpMeta(tester, env, fakes, const FriendsScreen());
      expect(find.text('Friends 20/20'), findsOneWidget);
      expect(find.text(note), findsOneWidget);

      await tester.tap(byKeyString('add-friend'));
      await settleRoute(tester);
      expect(find.text(note), findsWidgets);
      await tester.enterText(
        byKeyString('friend-code-field'),
        'u_zzzz9999yyyy',
      );
      await tester.tap(byKeyString('send-friend-request'));
      await settleRoute(tester);
      expect(env.backend.calls('POST', '/friends/requests'), isEmpty);
    });

    testWidgets('at 20/20 accepting a request is disabled', (tester) async {
      env.backend.json(
        'GET',
        '/friends',
        friendsJson(friendCount: 20, maxFriends: 20),
      );
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'requests'),
      );
      expect(find.text(note), findsOneWidget);
      await tester.tap(byKeyString('accept-u_kabir9999qqqq'));
      await flush(tester);
      expect(
        env.backend.calls('POST', '/friends/requests/u_kabir9999qqqq/accept'),
        isEmpty,
      );
    });

    testWidgets('at 20/20 adding a recent opponent is disabled', (
      tester,
    ) async {
      env.backend.json(
        'GET',
        '/friends',
        friendsJson(friendCount: 20, maxFriends: 20),
      );
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'recent'),
      );
      expect(find.text(note), findsOneWidget);
      await tester.tap(byKeyString('recent-add-u_zaid1111aaaa'));
      await flush(tester);
      expect(env.backend.calls('POST', '/friends/requests'), isEmpty);
    });

    testWidgets('a 422 friend_limit from the server is explained', (
      tester,
    ) async {
      env.backend.on(
        'POST',
        '/friends/requests',
        (_) => FakeResponse.error(422, 'friend_limit'),
      );
      await pumpMeta(
        tester,
        env,
        fakes,
        const FriendsScreen(initialTab: 'recent'),
      );
      await tester.tap(byKeyString('recent-add-u_zaid1111aaaa'));
      await flush(tester);
      expect(
        find.text(
          'You can have up to 20 friends. Remove a friend to add someone new.',
        ),
        findsOneWidget,
      );
    });

    test('friend_limit wording follows the server maximum', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      const e = ApiException(code: 'friend_limit', status: 422);
      expect(
        metaErrorMessage(l10n, e, maxFriends: 30),
        'You can have up to 30 friends. Remove a friend to add someone new.',
      );
      expect(
        metaErrorMessage(
          l10n,
          const ApiException(
            code: 'friend_limit',
            status: 422,
            details: {'maxFriends': 25},
          ),
          maxFriends: 30,
        ),
        contains('25 friends'),
      );
    });
  });
}
