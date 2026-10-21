import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/realtime/realtime_status.dart';
import 'package:ludo_royale/core/time/server_clock.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import 'widget_harness.dart';

void main() {
  group('CountdownRing', () {
    testWidgets('counts down from the server-clock deadline', (tester) async {
      var now = DateTime.fromMillisecondsSinceEpoch(1000000);
      final clock = ServerClock(() => now);
      // Server is 5 s ahead of the device.
      clock.sample(1000000 + 5000);
      await tester.pumpWidget(
        await buildHarness(
          const CountdownRing(
            deadlineMs: 1000000 + 5000 + 20000,
            totalMs: 20000,
          ),
          overrides: [serverClockProvider.overrideWithValue(clock)],
        ),
      );
      expect(find.text('20s'), findsOneWidget);
      expect(find.bySemanticsLabel('20 seconds left'), findsOneWidget);

      now = now.add(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('5s'), findsOneWidget);

      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('0s'), findsOneWidget);
      // Ticker stopped: the tree settles.
      await tester.pumpAndSettle();
    });

    testWidgets('renders a child instead of seconds', (tester) async {
      final clock = ServerClock(() => DateTime.fromMillisecondsSinceEpoch(0));
      await tester.pumpWidget(
        await buildHarness(
          const CountdownRing(deadlineMs: 0, totalMs: 20000, child: Text('A')),
          overrides: [serverClockProvider.overrideWithValue(clock)],
        ),
      );
      expect(find.text('A'), findsOneWidget);
    });
  });

  group('ConnectionIndicator', () {
    testWidgets('shows every status label', (tester) async {
      for (final entry in {
        RealtimeStatus.connected: 'Online',
        RealtimeStatus.connecting: 'Connecting…',
        RealtimeStatus.reconnecting: 'Reconnecting…',
        RealtimeStatus.offline: 'Offline',
        RealtimeStatus.replaced: 'This game is open somewhere else',
      }.entries) {
        await tester.pumpWidget(
          await buildHarness(ConnectionIndicator(status: entry.key)),
        );
        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('replaced → Reconnect calls back', (tester) async {
      var reconnects = 0;
      await tester.pumpWidget(
        await buildHarness(
          ConnectionIndicator(
            status: RealtimeStatus.replaced,
            onReconnect: () => reconnects++,
            compact: true,
          ),
        ),
      );
      await tester.tap(find.text('Reconnect'));
      expect(reconnects, 1);
    });

    testWidgets('follows realtimeStatusProvider when no status is given', (
      tester,
    ) async {
      await tester.pumpWidget(
        await buildHarness(const ConnectionIndicator(compact: true)),
      );
      expect(find.bySemanticsLabel('Connection: Connecting…'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConnectionIndicator)),
      );
      container
          .read(realtimeStatusProvider.notifier)
          .set(RealtimeStatus.connected);
      await tester.pump();
      expect(find.bySemanticsLabel('Connection: Online'), findsOneWidget);
    });
  });

  group('ChoiceChips', () {
    testWidgets('selects options and marks the selection', (tester) async {
      var value = 4;
      await tester.pumpWidget(
        await buildHarness(
          StatefulBuilder(
            builder: (context, setState) => ChoiceChips<int>(
              options: const [
                ChoiceOption(value: 2, label: '2 players'),
                ChoiceOption(value: 3, label: '3 players'),
                ChoiceOption(
                  value: 4,
                  label: '4 players',
                  caption: 'Entry 1,000',
                ),
              ],
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      await tester.tap(find.text('2 players'));
      await tester.pumpAndSettle();
      expect(value, 2);
      expect(
        tester.getSemantics(find.bySemanticsLabel('2 players')),
        isSemantics(isSelected: true, isButton: true),
      );
    });
  });

  group('Overlays', () {
    testWidgets('AppDialog returns the tapped action value', (tester) async {
      String? result;
      await tester.pumpWidget(
        await buildHarness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await AppDialog.show<String>(
                  context,
                  title: 'Leave match?',
                  message: 'You will forfeit.',
                  actions: const [
                    AppDialogAction(label: 'Stay', value: 'stay'),
                    AppDialogAction(
                      label: 'Leave',
                      value: 'leave',
                      variant: PremiumButtonVariant.danger,
                    ),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Leave match?'), findsOneWidget);
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(result, 'leave');
      expect(find.text('Leave match?'), findsNothing);
    });

    testWidgets('AppDialog with canPop false ignores back', (tester) async {
      await tester.pumpWidget(
        await buildHarness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AppDialog.show<void>(
                context,
                title: 'Blocking',
                canPop: false,
                actions: const [AppDialogAction(label: 'OK')],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Blocking'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Blocking'), findsNothing);
    });

    testWidgets('AppBottomSheet shows title, content and closes', (
      tester,
    ) async {
      await tester.pumpWidget(
        await buildHarness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AppBottomSheet.show<void>(
                context,
                title: 'Play Online',
                builder: (_) => const Text('sheet body'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Play Online'), findsOneWidget);
      expect(find.text('sheet body'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('sheet body'), findsNothing);
    });

    testWidgets('AppToast shows a floating message', (tester) async {
      await tester.pumpWidget(
        await buildHarness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  AppToast.show(context, 'Copied!', kind: ToastKind.success),
              child: const Text('toast'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('toast'));
      await tester.pump();
      expect(find.text('Copied!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('ConfettiBurst plays once and settles', (tester) async {
    var play = false;
    await tester.pumpWidget(
      await buildHarness(
        StatefulBuilder(
          builder: (context, setState) => Stack(
            children: [
              TextButton(
                onPressed: () => setState(() => play = true),
                child: const Text('go'),
              ),
              Positioned.fill(child: ConfettiBurst(play: play)),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
