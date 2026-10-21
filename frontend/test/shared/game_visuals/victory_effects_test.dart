import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:ludo_royale/shared/game_visuals/effects/level_up_burst.dart';
import 'package:ludo_royale/shared/game_visuals/effects/victory_overlay.dart';
import 'package:ludo_royale/shared/game_visuals/game_palette.dart';

Widget wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Directionality(
      textDirection: textDirection,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

Future<void> pumpFor(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

void main() {
  test('VictoryStyles.resolve falls back to confetti', () {
    expect(VictoryStyles.resolve(VictoryStyles.crown), VictoryStyles.crown);
    expect(VictoryStyles.resolve('victory_unknown'), VictoryStyles.confetti);
    expect(VictoryStyles.resolve(null), VictoryStyles.confetti);
  });

  test('durations', () {
    expect(
      VictoryEffectPainter.durationFor(),
      const Duration(milliseconds: 2900),
    );
    expect(
      VictoryEffectPainter.durationFor(reducedMotion: true),
      const Duration(milliseconds: 1200),
    );
  });

  group('VictoryEffectPainter', () {
    for (final id in [...VictoryStyles.all, 'victory_unknown']) {
      for (final reduced in [false, true]) {
        test('$id (reduced: $reduced) paints at 0, 0.5 and 1', () {
          for (final palette in [GamePalette.light, GamePalette.dark]) {
            for (final p in [0.0, 0.1, 0.3, 0.5, 0.75, 0.9, 1.0]) {
              final painter = VictoryEffectPainter(
                victoryId: id,
                color: palette.green,
                progress: AlwaysStoppedAnimation<double>(p),
                palette: palette,
                reducedMotion: reduced,
              );
              final recorder = ui.PictureRecorder();
              final canvas = Canvas(recorder);
              painter.paint(canvas, const Size(360, 640));
              painter.paint(canvas, const Size(280, 280));
              painter.paint(canvas, Size.zero);
              recorder.endRecording().dispose();
              expect(
                painter.shouldRepaint(
                  VictoryEffectPainter(
                    victoryId: id,
                    color: palette.red,
                    progress: AlwaysStoppedAnimation<double>(p),
                    palette: palette,
                  ),
                ),
                isTrue,
              );
            }
          }
        });
      }
    }
  });

  group('VictoryOverlay', () {
    for (final id in VictoryStyles.all) {
      for (final reduced in [false, true]) {
        testWidgets('$id (reduced: $reduced) renders and calls onDone once', (
          tester,
        ) async {
          for (final brightness in Brightness.values) {
            for (final size in [280.0, 420.0]) {
              var done = 0;
              await tester.pumpWidget(
                wrap(
                  SizedBox.square(
                    dimension: size,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(color: Colors.teal),
                        ),
                        VictoryOverlay(
                          key: UniqueKey(),
                          victoryId: id,
                          color: const Color(0xFF3E63DD),
                          reducedMotion: reduced,
                          onDone: () => done++,
                        ),
                      ],
                    ),
                  ),
                  brightness: brightness,
                  textDirection: size > 300
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                ),
              );
              expect(
                tester.getSize(find.byType(VictoryOverlay)),
                Size.square(size),
              );
              final total = VictoryEffectPainter.durationFor(
                reducedMotion: reduced,
              );
              await pumpFor(tester, total - const Duration(milliseconds: 200));
              expect(done, 0);
              await pumpFor(tester, const Duration(milliseconds: 400));
              expect(done, 1);
              await pumpFor(tester, const Duration(milliseconds: 500));
              expect(done, 1);
              expect(tester.hasRunningAnimations, isFalse);
              expect(tester.takeException(), isNull);
            }
          }
        });
      }
    }

    testWidgets('does not block taps underneath', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          SizedBox.square(
            dimension: 300,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                  ),
                ),
                const VictoryOverlay(
                  victoryId: VictoryStyles.crown,
                  color: Colors.red,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tapAt(tester.getCenter(find.byType(VictoryOverlay)));
      expect(taps, 1);
      await pumpFor(tester, const Duration(seconds: 3));
    });

    testWidgets('onDone is not called after dispose', (tester) async {
      var done = 0;
      await tester.pumpWidget(
        wrap(
          SizedBox.square(
            dimension: 300,
            child: VictoryOverlay(
              victoryId: VictoryStyles.fireworks,
              color: Colors.red,
              onDone: () => done++,
            ),
          ),
        ),
      );
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.pumpWidget(wrap(const SizedBox()));
      await pumpFor(tester, const Duration(seconds: 3));
      expect(done, 0);
    });

    testWidgets('exposes a localized live-region label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          const SizedBox.square(
            dimension: 300,
            child: VictoryOverlay(
              victoryId: VictoryStyles.confetti,
              color: Colors.green,
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Victory celebration'), findsOneWidget);
      await pumpFor(tester, const Duration(seconds: 3));
      handle.dispose();
    });
  });

  group('LevelUpBurst', () {
    for (final reduced in [false, true]) {
      testWidgets(
        'plays, shows its child and calls onDone (reduced: $reduced)',
        (tester) async {
          for (final brightness in Brightness.values) {
            var done = 0;
            await tester.pumpWidget(
              wrap(
                LevelUpBurst(
                  key: UniqueKey(),
                  size: 180,
                  reducedMotion: reduced,
                  onDone: () => done++,
                  child: const Text('12'),
                ),
                brightness: brightness,
              ),
            );
            expect(find.text('12'), findsOneWidget);
            expect(
              tester.getSize(find.byType(LevelUpBurst)),
              const Size.square(180),
            );
            await pumpFor(
              tester,
              const Duration(milliseconds: 600),
              step: const Duration(milliseconds: 50),
            );
            expect(done, 0);
            await pumpFor(tester, const Duration(milliseconds: 800));
            expect(done, 1);
            expect(tester.hasRunningAnimations, isFalse);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }

    testWidgets('uses a custom color and has a semantics label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(const LevelUpBurst(color: Colors.purple)));
      expect(find.bySemanticsLabel('Level up'), findsOneWidget);
      await pumpFor(tester, const Duration(milliseconds: 1400));
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  });
}
