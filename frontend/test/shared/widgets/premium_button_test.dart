import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/audio_haptics/audio_service.dart';
import 'package:ludo_arena/shared/widgets/widgets.dart';

import 'widget_harness.dart';

void main() {
  testWidgets('prevents double submit while the future is pending', (
    tester,
  ) async {
    final completer = Completer<void>();
    var calls = 0;
    final audio = SilentAudioService();
    await tester.pumpWidget(
      await buildHarness(
        PremiumButton(
          label: 'Play',
          onPressed: () {
            calls++;
            return completer.future;
          },
        ),
        audio: audio,
      ),
    );

    await tester.tap(find.byType(PremiumButton));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(audio.played, [Sfx.uiTap]);

    await tester.tap(find.byType(PremiumButton));
    await tester.tap(find.byType(PremiumButton));
    await tester.pump();
    expect(calls, 1, reason: 'taps while pending are ignored');

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byType(PremiumButton));
    await tester.pump();
    expect(calls, 2);
    await tester.pumpAndSettle();
  });

  testWidgets('loading flag shows a spinner and blocks taps', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      await buildHarness(
        PremiumButton(label: 'Save', loading: true, onPressed: () => calls++),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(PremiumButton));
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('disabled when onPressed is null', (tester) async {
    final audio = SilentAudioService();
    await tester.pumpWidget(
      await buildHarness(
        const PremiumButton(label: 'Locked', onPressed: null),
        audio: audio,
      ),
    );
    await tester.tap(find.byType(PremiumButton), warnIfMissed: false);
    await tester.pump();
    expect(audio.played, isEmpty);
    final semantics = tester.getSemantics(find.byType(PremiumButton));
    expect(semantics.label, 'Locked');
  });

  testWidgets('all variants and sizes render with a 48dp target', (
    tester,
  ) async {
    await tester.pumpWidget(
      await buildHarness(
        SingleChildScrollView(
          child: Column(
            children: [
              for (final v in PremiumButtonVariant.values)
                for (final s in PremiumButtonSize.values)
                  PremiumButton(
                    label: '${v.name} ${s.name}',
                    variant: v,
                    size: s,
                    icon: Icons.play_arrow_rounded,
                    onPressed: () {},
                  ),
              Row(
                children: [
                  PremiumButton(
                    label: 'Inline',
                    expand: false,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    for (final e in find.byType(PremiumButton).evaluate()) {
      expect(
        tester.getSize(find.byWidget(e.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(tester.takeException(), isNull);
  });
}
