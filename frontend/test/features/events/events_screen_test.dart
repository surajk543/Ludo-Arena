import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:ludo_royale/features/events/presentation/events_screen.dart';
import 'package:ludo_royale/features/events/presentation/widgets/event_card.dart';
import 'package:ludo_royale/l10n/generated/app_localizations_en.dart';

import '../progression/meta_test_support.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());

  late TestEnv env;
  late MetaFakes fakes;

  setUp(() async {
    env = await TestEnv.create();
    env.routeHappyPath();
    routeMeta(env);
    fakes = MetaFakes();
  });
  tearDown(() => fakes.close());

  test('event window is shown in local dates', () {
    final start = DateTime.utc(2026, 10, 19).toLocal();
    final end = DateTime.utc(2026, 11, 2).toLocal();
    expect(
      eventWindowText(AppLocalizationsEn(), const Locale('en'), start, end),
      '${DateFormat.MMMd('en').format(start)} – '
      '${DateFormat.MMMd('en').format(end)}',
    );
  });

  testWidgets('shows the running event, its rules and missions', (
    tester,
  ) async {
    await pumpMeta(tester, env, fakes, const EventsScreen());
    expect(find.text('Autumn Cup'), findsOneWidget);
    expect(
      find.text(
        'Celebrate the season with Quick Ludo and win the Autumn Leaf dice.',
      ),
      findsOneWidget,
    );
    expect(find.text('How it works'), findsOneWidget);
    expect(find.textContaining('at least 3 moves'), findsOneWidget);
    await scrollTo(tester, find.text('Autumn Sprint'));
    expect(find.text('Complete 3 Quick Ludo matches.'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('no running events: calm empty state', (tester) async {
    env.backend.json('GET', '/missions', missionsJson(events: const []));
    await pumpMeta(tester, env, fakes, const EventsScreen());
    expect(find.text('No events right now'), findsOneWidget);
    expect(find.text('Go to missions'), findsOneWidget);
  });
}
