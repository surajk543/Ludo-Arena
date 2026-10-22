import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_arena/features/collection/presentation/collection_screen.dart';
import 'package:ludo_arena/features/events/presentation/events_screen.dart';
import 'package:ludo_arena/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:ludo_arena/features/missions/presentation/missions_screen.dart';
import 'package:ludo_arena/features/progression/presentation/progression_screen.dart';
import 'package:ludo_arena/features/social/presentation/friends_screen.dart';

import 'meta_test_support.dart';

/// Every meta screen × light/dark × en/ar (RTL)/hi at 360×740 and 320×640
/// (plus 1.3× text in some passes) lays out without overflow, and RTL
/// locales render right-to-left.
void main() {
  setUpAll(() async => initializeDateFormatting());

  const mid = Size(360, 740);
  const small = Viewports.small;
  final configs = <(Locale, ThemeMode, Size, double)>[
    (const Locale('en'), ThemeMode.light, mid, 1.0),
    (const Locale('en'), ThemeMode.dark, small, 1.0),
    (const Locale('ar'), ThemeMode.light, mid, 1.0),
    (const Locale('ar'), ThemeMode.dark, small, 1.3),
    (const Locale('hi'), ThemeMode.light, small, 1.0),
    (const Locale('hi'), ThemeMode.dark, mid, 1.3),
    (const Locale('ur'), ThemeMode.light, small, 1.0),
    (const Locale('id'), ThemeMode.dark, small, 1.3),
  ];

  final screens = <String, Widget Function()>{
    'missions': () => const MissionsScreen(),
    'events': () => const EventsScreen(),
    'collection': () => const CollectionScreen(),
    'collection-titles': () => const CollectionScreen(initialKind: 'title'),
    'friends': () => const FriendsScreen(),
    'friends-requests': () => const FriendsScreen(initialTab: 'requests'),
    'friends-recent': () => const FriendsScreen(initialTab: 'recent'),
    'friends-reported': () => const FriendsScreen(initialTab: 'reported'),
    'leaderboard': () => const LeaderboardScreen(),
    'level-road': () => const ProgressionScreen(),
  };

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final (locale, mode, size, scale) in configs) {
      final label =
          '$name ${locale.languageCode} ${mode.name} '
          '${size.width.toInt()}x${size.height.toInt()} x$scale';
      testWidgets(label, (tester) async {
        final env = await TestEnv.create();
        env.routeHappyPath();
        routeMeta(env);
        final fakes = MetaFakes();
        addTearDown(fakes.close);
        await pumpMeta(
          tester,
          env,
          fakes,
          build(),
          locale: locale,
          themeMode: mode,
          size: size,
          textScale: scale,
        );
        await scrollThrough(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final rtl = locale.languageCode == 'ar' || locale.languageCode == 'ur';
        expect(
          Directionality.of(tester.element(find.byType(Scaffold).first)),
          rtl ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }
  }

  testWidgets('collection item sheet and purchase dialog fit 320×640 in ar', (
    tester,
  ) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    routeMeta(env);
    final fakes = MetaFakes();
    addTearDown(fakes.close);
    await pumpMeta(
      tester,
      env,
      fakes,
      const CollectionScreen(initialItemId: 'dice_golden'),
      locale: const Locale('ar'),
      size: small,
      textScale: 1.3,
    );
    await settleRoute(tester);
    expect(byKeyString('buy'), findsOneWidget);
    await tester.ensureVisible(byKeyString('buy'));
    await tester.tap(byKeyString('buy'));
    await settleRoute(tester);
    expect(tester.takeException(), isNull);
  });
}
