import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/core/analytics/analytics_providers.dart';
import 'package:ludo_royale/core/audio_haptics/reduced_motion.dart';
import 'package:ludo_royale/core/localization/language_controller.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/core/realtime/realtime_providers.dart';
import 'package:ludo_royale/core/theme/app_theme.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/progression/application/meta_support.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

export '../../helpers/fake_backend.dart';
export '../../helpers/harness.dart';
export '../../helpers/screen_harness.dart'
    show Viewports, setViewportSize, scrollThrough;

/// Records the meta analytics events (on top of the core recorder).
class MetaAnalytics extends RecordingAnalytics {
  @override
  void missionViewed() => events.add('mission_viewed');
  @override
  void missionCompleted(String period) =>
      events.add('mission_completed:$period');
  @override
  void missionRewardClaimed(String period) =>
      events.add('mission_reward_claimed:$period');
  @override
  void cosmeticUnlocked(String kind, String rarity) =>
      events.add('cosmetic_unlocked:$kind:$rarity');
  @override
  void cosmeticEquipped(String kind) => events.add('cosmetic_equipped:$kind');
  @override
  void collectionViewed() => events.add('collection_viewed');
  @override
  void coinPackPurchased({
    required String pack,
    required double value,
    required String currency,
  }) => events.add('coin_pack_purchased:$pack:$value:$currency');
}

/// Push streams + deterministic keys for meta tests.
class MetaFakes {
  final progression = StreamController<ProgressionUpdatedEvent>.broadcast();
  final wallet = StreamController<WalletUpdatedEvent>.broadcast();
  final social = StreamController<ServerEvent>.broadcast();
  final MetaAnalytics analytics = MetaAnalytics();
  int _keys = 0;

  /// Keys handed out by the Idempotency-Key factory, in order.
  final List<String> issuedKeys = [];

  List<Override> get overrides => [
    progressionUpdatesProvider.overrideWith((ref) => progression.stream),
    walletUpdatesProvider.overrideWith((ref) => wallet.stream),
    socialEventsProvider.overrideWith((ref) => social.stream),
    idempotencyKeyFactoryProvider.overrideWithValue(() {
      final k = 'idem-key-${++_keys}';
      issuedKeys.add(k);
      return k;
    }),
  ];

  Future<void> close() async {
    await progression.close();
    await wallet.close();
    await social.close();
  }
}

/// Signs in as a guest (level 4, 520 XP, 10 lakh coins, 50 diamonds).
Future<void> signIn(ProviderContainer c) async {
  await c.read(sessionControllerProvider.notifier).continueAsGuest();
}

// --------------------------------------------------------------- missions

Map<String, dynamic> missionJson(
  String id, {
  String game = 'any',
  int progress = 0,
  int target = 1,
  int coins = 500,
  int diamonds = 0,
  int xp = 30,
  List<Map<String, dynamic>> items = const [],
  bool? completed,
  bool claimed = false,
}) => {
  'id': id,
  'title': 'Server $id',
  'description': 'Server description',
  'game': game,
  'progress': progress,
  'target': target,
  'reward': {'coins': coins, 'diamonds': diamonds, 'xp': xp, 'items': items},
  'completed': completed ?? progress >= target,
  'claimed': claimed,
};

Map<String, dynamic> itemRef(String id, String kind, String rarity) => {
  'id': id,
  'kind': kind,
  'name': id,
  'rarity': rarity,
};

Map<String, dynamic> missionsJson({
  List<Map<String, dynamic>>? daily,
  List<Map<String, dynamic>>? weekly,
  List<Map<String, dynamic>>? events,
  String dailyResetsAt = '2026-10-22T00:00:00Z',
}) => {
  'daily': {
    'periodKey': 'd2026-10-21',
    'resetsAtUtc': dailyResetsAt,
    'missions':
        daily ??
        [
          missionJson('daily_ludo_match', game: 'ludo', progress: 1, target: 1),
          missionJson('daily_play_two', progress: 1, target: 2, coins: 1000),
          missionJson('daily_win_one', coins: 2000, claimed: false),
        ],
  },
  'weekly': {
    'periodKey': 'w2026-W43',
    'resetsAtUtc': '2026-10-26T00:00:00Z',
    'missions':
        weekly ??
        [
          missionJson(
            'weekly_ten_matches',
            progress: 4,
            target: 10,
            coins: 2000,
            diamonds: 5,
            xp: 150,
            items: [
              itemRef('title_weekly_champion', 'title', 'epic'),
              itemRef('badge_friendly', 'badge', 'rare'),
            ],
          ),
        ],
  },
  'events':
      events ??
      [
        {
          'id': 'autumn_cup',
          'title': 'Autumn Cup',
          'description': 'Server event text',
          'periodKey': 'e-autumn_cup',
          'startsAtUtc': '2026-10-19T00:00:00Z',
          'endsAtUtc': '2026-11-02T00:00:00Z',
          'missions': [
            missionJson(
              'autumn_quick_ludo',
              game: 'ludo',
              progress: 2,
              target: 3,
              coins: 1000,
              items: [itemRef('dice_autumn', 'dice', 'rare')],
            ),
          ],
        },
      ],
};

Map<String, dynamic> claimJson(
  Map<String, dynamic> mission, {
  int coins = 1000500,
  int diamonds = 50,
  int level = 4,
  int xp = 550,
  int xpGained = 30,
  bool levelUp = false,
  List<Map<String, dynamic>> granted = const [],
}) => {
  'mission': {...mission, 'claimed': true, 'completed': true},
  'wallet': {'coins': coins, 'diamonds': diamonds},
  'progression': {
    'level': level,
    'xp': xp,
    'levelXp': level == 5 ? 700 : 450,
    'nextLevelXp': level == 5 ? 300 : 250,
    'xpGained': xpGained,
    'levelUp': levelUp,
  },
  'granted': granted,
};

// --------------------------------------------------------------- collection

/// (id, kind, rarity, acquisition)
const List<(String, String, String, Map<String, dynamic>)> kTestCatalog = [
  (
    'dice_classic',
    'dice',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'dice_neon',
    'dice',
    'rare',
    {'type': 'level', 'level': 5, 'label': 'Reach level 5'},
  ),
  (
    'dice_golden',
    'dice',
    'epic',
    {
      'type': 'purchase',
      'price': {'diamonds': 40},
      'label': '40 diamonds',
    },
  ),
  (
    'dice_autumn',
    'dice',
    'rare',
    {'type': 'event', 'label': 'Autumn Cup event reward'},
  ),
  (
    'token_classic',
    'token',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'token_gem',
    'token',
    'rare',
    {'type': 'level', 'level': 3, 'label': 'Reach level 3'},
  ),
  (
    'token_royal',
    'token',
    'epic',
    {'type': 'level', 'level': 10, 'label': 'Reach level 10'},
  ),
  (
    'token_crown',
    'token',
    'legendary',
    {
      'type': 'purchase',
      'price': {'coins': 150000},
      'label': '150,000 coins',
    },
  ),
  (
    'ludo_board_classic',
    'ludo_board',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'ludo_board_midnight',
    'ludo_board',
    'rare',
    {'type': 'level', 'level': 8, 'label': 'Reach level 8'},
  ),
  (
    'ludo_board_royal',
    'ludo_board',
    'epic',
    {
      'type': 'purchase',
      'price': {'diamonds': 30},
      'label': '30 diamonds',
    },
  ),
  (
    'snakes_board_classic',
    'snakes_board',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'snakes_board_jungle',
    'snakes_board',
    'rare',
    {'type': 'level', 'level': 6, 'label': 'Reach level 6'},
  ),
  (
    'snakes_board_candy',
    'snakes_board',
    'epic',
    {
      'type': 'purchase',
      'price': {'coins': 200000},
      'label': '200,000 coins',
    },
  ),
  (
    'trail_none',
    'trail',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'trail_sparkle',
    'trail',
    'rare',
    {'type': 'level', 'level': 7, 'label': 'Reach level 7'},
  ),
  (
    'trail_comet',
    'trail',
    'epic',
    {
      'type': 'purchase',
      'price': {'diamonds': 20},
      'label': '20 diamonds',
    },
  ),
  (
    'victory_confetti',
    'victory',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'victory_fireworks',
    'victory',
    'rare',
    {'type': 'level', 'level': 12, 'label': 'Reach level 12'},
  ),
  (
    'victory_crown',
    'victory',
    'epic',
    {
      'type': 'purchase',
      'price': {'diamonds': 40},
      'label': '40 diamonds',
    },
  ),
  (
    'frame_none',
    'frame',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'frame_bronze',
    'frame',
    'common',
    {'type': 'level', 'level': 2, 'label': 'Reach level 2'},
  ),
  (
    'frame_silver',
    'frame',
    'rare',
    {'type': 'level', 'level': 10, 'label': 'Reach level 10'},
  ),
  (
    'frame_gold',
    'frame',
    'epic',
    {'type': 'level', 'level': 20, 'label': 'Reach level 20'},
  ),
  (
    'frame_royal',
    'frame',
    'legendary',
    {
      'type': 'purchase',
      'price': {'diamonds': 60},
      'label': '60 diamonds',
    },
  ),
  (
    'title_rookie',
    'title',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'title_strategist',
    'title',
    'rare',
    {'type': 'level', 'level': 5, 'label': 'Reach level 5'},
  ),
  (
    'title_dice_master',
    'title',
    'epic',
    {'type': 'level', 'level': 15, 'label': 'Reach level 15'},
  ),
  (
    'title_royal',
    'title',
    'legendary',
    {'type': 'level', 'level': 30, 'label': 'Reach level 30'},
  ),
  (
    'title_weekly_champion',
    'title',
    'epic',
    {'type': 'mission', 'label': 'Weekly challenge reward'},
  ),
  (
    'badge_first_win',
    'badge',
    'common',
    {'type': 'mission', 'label': 'Win your first match'},
  ),
  (
    'badge_friendly',
    'badge',
    'rare',
    {'type': 'mission', 'label': 'Weekly challenge reward'},
  ),
  (
    'emote_wave',
    'emote',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'emote_thumbs',
    'emote',
    'common',
    {'type': 'starter', 'label': 'Starter item'},
  ),
  (
    'emote_laugh',
    'emote',
    'common',
    {'type': 'level', 'level': 3, 'label': 'Reach level 3'},
  ),
  (
    'emote_wow',
    'emote',
    'rare',
    {'type': 'level', 'level': 6, 'label': 'Reach level 6'},
  ),
  (
    'emote_crown',
    'emote',
    'epic',
    {
      'type': 'purchase',
      'price': {'diamonds': 10},
      'label': '10 diamonds',
    },
  ),
];

const Map<String, String> kStarterLoadout = {
  'dice': 'dice_classic',
  'token': 'token_classic',
  'ludo_board': 'ludo_board_classic',
  'snakes_board': 'snakes_board_classic',
  'frame': 'frame_none',
  'title': 'title_rookie',
  'victory': 'victory_confetti',
  'trail': 'trail_none',
};

Map<String, dynamic> collectionItemJson(
  String id, {
  required bool owned,
  required Map<String, String> loadout,
}) {
  final e = kTestCatalog.firstWhere((c) => c.$1 == id);
  return {
    'id': e.$1,
    'kind': e.$2,
    'name': e.$1,
    'description': 'Server description',
    'rarity': e.$3,
    'owned': owned,
    'equipped': loadout[e.$2] == e.$1,
    'acquisition': e.$4,
  };
}

/// Level-4 account: starters + frame_bronze, token_gem, emote_laugh.
Map<String, dynamic> collectionJson({
  Set<String> extraOwned = const {},
  Map<String, String> loadout = const {},
}) {
  final lo = {...kStarterLoadout, ...loadout};
  const levelOwned = {'frame_bronze', 'token_gem', 'emote_laugh'};
  return {
    'items': [
      for (final e in kTestCatalog)
        collectionItemJson(
          e.$1,
          owned:
              e.$4['type'] == 'starter' ||
              levelOwned.contains(e.$1) ||
              extraOwned.contains(e.$1),
          loadout: lo,
        ),
    ],
    'loadout': lo,
  };
}

// --------------------------------------------------------------- social

Map<String, dynamic> friendJson(
  String uid,
  String name, {
  String status = 'friend',
  bool online = false,
  int level = 7,
  int avatar = 5,
  String title = 'title_strategist',
}) => {
  'uid': uid,
  'name': name,
  'avatar': avatar,
  'level': level,
  'title': title,
  'online': online,
  'status': status,
};

Map<String, dynamic> friendsJson({
  List<Map<String, dynamic>>? friends,
  List<Map<String, dynamic>>? incoming,
  List<Map<String, dynamic>>? outgoing,
  int? onlineCount,
  int? friendCount,
  int? maxFriends,
}) => {
  'onlineCount': ?onlineCount,
  'friendCount': ?friendCount,
  'maxFriends': ?maxFriends,
  'friends':
      friends ??
      [
        friendJson('u_ravi2345abcd', 'Ravi', online: true),
        friendJson(
          'u_meera7788wxyz',
          'Meera',
          level: 12,
          title: 'title_rookie',
        ),
      ],
  'incoming':
      incoming ??
      [friendJson('u_kabir9999qqqq', 'Kabir', status: 'incoming', level: 3)],
  'outgoing':
      outgoing ??
      [friendJson('u_sara5555pppp', 'Sara', status: 'outgoing', level: 9)],
};

/// Fixed server "now" of the meta tests (FakeClock start).
int get kMetaNowMs => DateTime(2026, 10, 21, 12).millisecondsSinceEpoch;

Map<String, dynamic> reportJson(
  String id, {
  String uid = 'u_zaid1111aaaa',
  String name = 'Zaid',
  String reason = 'cheating',
  String status = 'submitted',
  String game = 'ludo',
  Duration ago = const Duration(hours: 2),
}) => {
  'id': id,
  'player': {'uid': uid, 'name': name, 'avatar': 4, 'level': 6},
  'reason': reason,
  'game': game,
  'roomId': 'r_$id',
  'status': status,
  'createdAt': kMetaNowMs - ago.inMilliseconds,
  'updatedAt': kMetaNowMs - ago.inMilliseconds,
};

Map<String, dynamic> limitJson({int remaining = 2, int? resetsAt}) => {
  'perDay': 2,
  'remaining': remaining,
  'resetsAt': resetsAt,
};

Map<String, dynamic> reportsJson({
  List<Map<String, dynamic>> reports = const [],
  int remaining = 2,
  int? resetsAt,
}) => {
  'reports': reports,
  'limit': limitJson(remaining: remaining, resetsAt: resetsAt),
};

Map<String, dynamic> recentJson() => {
  'players': [
    friendJson('u_zaid1111aaaa', 'Zaid', status: 'none', level: 5),
    friendJson('u_ravi2345abcd', 'Ravi', status: 'friend'),
  ],
};

Map<String, dynamic> leaderboardJson({bool alone = false}) => {
  'periodKey': 'w2026-W43',
  'entries': alone
      ? [
          {
            'uid': 'u_guest1',
            'name': 'Asha',
            'avatar': 3,
            'level': 4,
            'weeklyXp': 120,
            'rank': 1,
            'isMe': true,
          },
        ]
      : [
          {
            'uid': 'u_meera7788wxyz',
            'name': 'Meera',
            'avatar': 5,
            'level': 12,
            'weeklyXp': 640,
            'rank': 1,
            'isMe': false,
          },
          {
            'uid': 'u_guest1',
            'name': 'Asha',
            'avatar': 3,
            'level': 4,
            'weeklyXp': 320,
            'rank': 2,
            'isMe': true,
          },
          {
            'uid': 'u_ravi2345abcd',
            'name': 'Ravi',
            'avatar': 8,
            'level': 7,
            'weeklyXp': 320,
            'rank': 2,
            'isMe': false,
          },
        ],
};

// --------------------------------------------------------------- progression

Map<String, dynamic> progressionJson({int level = 4, int xp = 520}) {
  const milestones = {
    2: [('frame_bronze', 'frame', 'common')],
    3: [('token_gem', 'token', 'rare'), ('emote_laugh', 'emote', 'common')],
    5: [('dice_neon', 'dice', 'rare'), ('title_strategist', 'title', 'rare')],
    6: [
      ('snakes_board_jungle', 'snakes_board', 'rare'),
      ('emote_wow', 'emote', 'rare'),
    ],
    7: [('trail_sparkle', 'trail', 'rare')],
    8: [('ludo_board_midnight', 'ludo_board', 'rare')],
    10: [('frame_silver', 'frame', 'rare'), ('token_royal', 'token', 'epic')],
    12: [('victory_fireworks', 'victory', 'rare')],
    15: [('title_dice_master', 'title', 'epic')],
    20: [('frame_gold', 'frame', 'epic')],
    30: [('title_royal', 'title', 'legendary')],
  };
  return {
    'level': level,
    'xp': xp,
    'levelXp': 450,
    'nextLevelXp': 250,
    'maxLevel': 50,
    'title': 'title_rookie',
    'milestones': [
      for (final e in milestones.entries)
        {
          'level': e.key,
          'rewards': [for (final r in e.value) itemRef(r.$1, r.$2, r.$3)],
          'reached': level >= e.key,
        },
    ],
  };
}

/// Registers every meta GET route with happy-path data.
void routeMeta(TestEnv env) {
  env.backend
    ..json('GET', '/missions', missionsJson())
    ..json('GET', '/collection', collectionJson())
    ..json('GET', '/friends', friendsJson())
    ..json('GET', '/social/recent', recentJson())
    ..json('GET', '/leaderboards/friends', leaderboardJson())
    ..json(
      'GET',
      '/reports',
      reportsJson(
        // Older than 24 h: both of today's reports are still available.
        reports: [
          reportJson(
            'rep_a',
            status: 'reviewing',
            ago: const Duration(hours: 26),
          ),
          reportJson(
            'rep_b',
            uid: 'u_neha4444rrrr',
            name: 'Neha',
            reason: 'other',
            status: 'action_taken',
            ago: const Duration(days: 3),
          ),
        ],
      ),
    )
    ..json('GET', '/progression', progressionJson());
}

/// Lets queued microtasks and the fake HTTP adapter complete, then pumps.
Future<void> flush(WidgetTester tester, [int frames = 3]) async {
  await tester.runAsync(() => settle(40));
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a route / sheet / dialog transition finish (and HTTP complete).
Future<void> settleRoute(WidgetTester tester) async {
  await flush(tester);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the page's vertical scrollable until [finder] is built and
/// visible.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.pump();
}

/// Tag for widget finders.
Finder byKeyString(String key) => find.byKey(ValueKey(key));

/// Container for [env] where meta analytics are recorded by [fakes] and the
/// realtime pushes come from [fakes]' controllers.
ProviderContainer metaContainer(
  TestEnv env,
  MetaFakes fakes, {
  List<Override> extra = const [],
}) {
  final replaced = {
    analyticsServiceProvider,
    progressionUpdatesProvider,
    walletUpdatesProvider,
    socialEventsProvider,
  };
  final c = ProviderContainer(
    overrides: [
      ...env.overrides.where((o) => !replaced.contains(o.origin)),
      analyticsServiceProvider.overrideWithValue(fakes.analytics),
      ...fakes.overrides,
      ...extra,
    ],
    retry: (_, _) => null,
  );
  addTearDown(c.dispose);
  return c;
}

/// Pumps [screen] (or [router]) in the real theme / l10n stack, signed in,
/// with meta fakes. Mirrors `pumpScreen` from the core harness.
Future<ProviderContainer> pumpMeta(
  WidgetTester tester,
  TestEnv env,
  MetaFakes fakes,
  Widget screen, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  Size size = Viewports.phone,
  double textScale = 1.0,
  bool signedIn = true,
  List<Override> extra = const [],
  GoRouter? router,
  TransitionBuilder? shell,
}) async {
  setViewportSize(tester, size);
  final container = metaContainer(env, fakes, extra: extra);
  if (signedIn) {
    await tester.runAsync(() async {
      await signIn(container);
      await settle();
    });
  }
  await tester.runAsync(
    () => container.read(languageControllerProvider.notifier).setLocale(locale),
  );
  Widget wrap(BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: true,
      textScaler: TextScaler.linear(textScale),
    ),
    child: ReducedMotionScope(
      child: shell != null
          ? shell(context, child ?? const SizedBox())
          : child ?? const SizedBox(),
    ),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: router != null
          ? MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: themeMode,
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
              builder: wrap,
            )
          : MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: themeMode,
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: wrap,
              home: screen,
            ),
    ),
  );
  await flush(tester);
  return container;
}
