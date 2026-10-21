import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/features/progression/presentation/widgets/pill_tabs.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import 'widget_harness.dart';

/// Separate taps are further apart than the UI gesture window.
Future<void> nextGesture(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 300));

void main() {
  testWidgets('pill tabs: one tab sound per change, none for the current tab', (
    tester,
  ) async {
    final audio = SilentAudioService();
    var selected = 'a';
    await tester.pumpWidget(
      await buildHarness(
        StatefulBuilder(
          builder: (context, setState) => MetaPillTabs<String>(
            pills: const [
              MetaPill(value: 'a', label: 'Daily'),
              MetaPill(value: 'b', label: 'Weekly'),
            ],
            selected: selected,
            onSelected: (v) => setState(() => selected = v),
          ),
        ),
        audio: audio,
      ),
    );
    await tester.tap(find.text('Weekly'));
    await nextGesture(tester);
    expect(audio.played, [Sfx.uiTab]);
    await tester.tap(find.text('Weekly'));
    await nextGesture(tester);
    expect(audio.played, [Sfx.uiTab], reason: 'already selected');
    await tester.tap(find.text('Daily'));
    await nextGesture(tester);
    expect(audio.played, [Sfx.uiTab, Sfx.uiTab]);
  });

  testWidgets('cards and icon buttons click only when tappable; rebuilds '
      'never play', (tester) async {
    final audio = SilentAudioService();
    var taps = 0;
    await tester.pumpWidget(
      await buildHarness(
        Column(
          children: [
            SurfaceCard(onTap: () => taps++, child: const Text('Tile')),
            const SurfaceCard(child: Text('Static')),
            IconCircleButton(
              icon: Icons.settings,
              tooltip: 'Settings',
              onPressed: () => taps++,
            ),
            const IconCircleButton(
              icon: Icons.lock,
              tooltip: 'Locked',
              onPressed: null,
            ),
          ],
        ),
        audio: audio,
      ),
    );
    await tester.tap(find.text('Static'));
    await tester.tap(find.byTooltip('Locked'), warnIfMissed: false);
    await nextGesture(tester);
    expect(audio.played, isEmpty);

    await tester.tap(find.text('Tile'));
    await nextGesture(tester);
    await tester.tap(find.byTooltip('Settings'));
    await nextGesture(tester);
    expect(taps, 2);
    expect(audio.played, [Sfx.uiTap, Sfx.uiTap]);

    // Rebuilds and frames alone never make a sound.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(audio.played, hasLength(2));
  });

  testWidgets('dialogs: the open sound replaces the click; an action closes '
      'silently; dismissing plays the close sound', (tester) async {
    final audio = SilentAudioService();
    await tester.pumpWidget(
      await buildHarness(
        Builder(
          builder: (context) => PremiumButton(
            label: 'Leave',
            onPressed: () {
              AppDialog.show<bool>(
                context,
                title: 'Leave the room?',
                actions: const [
                  AppDialogAction(label: 'Stay', value: false),
                  AppDialogAction(label: 'Leave now', value: true),
                ],
              );
            },
          ),
        ),
        audio: audio,
      ),
    );
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(audio.played, [Sfx.uiOpen]);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(audio.played, [Sfx.uiOpen, Sfx.uiTap]);

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5)); // barrier
    await tester.pumpAndSettle();
    expect(audio.played, [Sfx.uiOpen, Sfx.uiTap, Sfx.uiOpen, Sfx.uiClose]);
  });

  testWidgets('a failure toast sounds once; a success toast stays quiet', (
    tester,
  ) async {
    final audio = SilentAudioService();
    await tester.pumpWidget(
      await buildHarness(
        Builder(
          builder: (context) => Column(
            children: [
              PremiumButton(
                label: 'Fail',
                onPressed: () => AppToast.show(
                  context,
                  'Something failed',
                  kind: ToastKind.error,
                ),
              ),
              PremiumButton(
                label: 'Copy',
                onPressed: () =>
                    AppToast.show(context, 'Copied', kind: ToastKind.success),
              ),
            ],
          ),
        ),
        audio: audio,
      ),
    );
    await tester.tap(find.text('Fail'));
    await nextGesture(tester);
    expect(audio.played, [Sfx.uiError], reason: 'error wins over the click');
    await tester.tap(find.text('Copy'));
    await nextGesture(tester);
    expect(audio.played, [Sfx.uiError, Sfx.uiTap]);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('choice chips: a sound per change, none for the current value', (
    tester,
  ) async {
    final audio = SilentAudioService();
    var value = 4;
    await tester.pumpWidget(
      await buildHarness(
        StatefulBuilder(
          builder: (context, setState) => ChoiceChips<int>(
            value: value,
            onChanged: (v) => setState(() => value = v),
            options: const [
              ChoiceOption(value: 2, label: 'Two'),
              ChoiceOption(value: 4, label: 'Four'),
            ],
          ),
        ),
        audio: audio,
      ),
    );
    await tester.tap(find.text('Four'));
    await nextGesture(tester);
    expect(audio.played, isEmpty);
    await tester.tap(find.text('Two'));
    await nextGesture(tester);
    expect(audio.played, [Sfx.uiTab]);
    expect(value, 2);
  });
}
