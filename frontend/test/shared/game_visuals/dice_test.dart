import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/l10n/generated/app_localizations.dart';
import 'package:ludo_arena/shared/game_visuals/dice/dice_controller.dart';
import 'package:ludo_arena/shared/game_visuals/dice/dice_skins.dart';
import 'package:ludo_arena/shared/game_visuals/dice/dice_view.dart';

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

/// Pumps frames in small steps so the painter runs throughout the tumble.
Future<void> pumpFor(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 50),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

void main() {
  group('DiceSkins / DiceStyle', () {
    test('resolve falls back to classic for unknown ids', () {
      expect(DiceSkins.resolve('dice_neon'), DiceSkins.neon);
      expect(DiceSkins.resolve('dice_unknown'), DiceSkins.classic);
      expect(DiceSkins.resolve(null), DiceSkins.classic);
      expect(
        DiceStyle.resolve('nope', brightness: Brightness.dark).id,
        DiceSkins.classic,
      );
    });

    test('every skin resolves in light and dark', () {
      for (final id in DiceSkins.all) {
        for (final b in Brightness.values) {
          final style = DiceStyle.resolve(id, brightness: b);
          expect(style.id, id);
        }
      }
      expect(
        DiceStyle.resolve(DiceSkins.autumn, brightness: Brightness.light).motif,
        DiceMotif.autumnLeaves,
      );
      expect(
        DiceStyle.resolve(
          DiceSkins.neon,
          brightness: Brightness.light,
          accent: Colors.pink,
        ).edgeGlow,
        Colors.pink,
      );
    });
  });

  group('DiceController without a view', () {
    test('roll applies the value immediately and completes', () async {
      final controller = DiceController();
      int? settled;
      controller.onSettle = (v) => settled = v;
      await controller.roll(5);
      expect(controller.value, 5);
      expect(controller.rolling, isFalse);
      expect(settled, 5);
      expect(controller.angleX, DiceController.baseAngleX(5));
      expect(controller.angleY, DiceController.baseAngleY(5));
      controller.dispose();
    });

    test('show snaps and cancel keeps the value', () {
      final controller = DiceController(initialValue: 2);
      expect(controller.value, 2);
      controller.show(6);
      expect(controller.value, 6);
      expect(controller.angleY, DiceController.baseAngleY(6));
      controller.beginRoll();
      expect(controller.rolling, isTrue);
      controller.cancel();
      expect(controller.rolling, isFalse);
      expect(controller.value, 6);
      controller.dispose();
    });

    test('initial value is clamped', () {
      expect(DiceController(initialValue: 9).value, 6);
      expect(DiceController(initialValue: 0).value, 1);
    });
  });

  group('DiceView animation', () {
    testWidgets('roll tumbles and settles exactly on the server value', (
      tester,
    ) async {
      final controller = DiceController();
      var tumbleStarts = 0;
      int? settled;
      controller.onTumbleStart = () => tumbleStarts++;
      controller.onSettle = (v) => settled = v;
      await tester.pumpWidget(wrap(DiceView(controller: controller)));

      var done = false;
      controller.roll(4).then((_) => done = true);
      await tester.pump();
      expect(controller.rolling, isTrue);
      expect(tumbleStarts, 1);
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(done, isFalse);
      expect(controller.rolling, isTrue);
      await pumpFor(tester, const Duration(milliseconds: 700));
      await tester.pump();
      expect(done, isTrue);
      expect(controller.rolling, isFalse);
      expect(controller.value, 4);
      expect(settled, 4);
      expect(controller.angleX, DiceController.baseAngleX(4));
      expect(controller.angleY, DiceController.baseAngleY(4));
      expect(controller.angleZ, 0);
      expect(controller.hop, 0);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('beginRoll spins and a later roll settles smoothly', (
      tester,
    ) async {
      final controller = DiceController(initialValue: 1);
      await tester.pumpWidget(wrap(DiceView(controller: controller)));
      controller.beginRoll();
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(controller.rolling, isTrue);
      expect(controller.hop, greaterThan(0));
      final midX = controller.angleX;
      expect(midX, isNot(0));

      var done = false;
      controller.roll(6).then((_) => done = true);
      await pumpFor(tester, const Duration(milliseconds: 950));
      await tester.pump();
      expect(done, isTrue);
      expect(controller.rolling, isFalse);
      expect(controller.value, 6);
      expect(controller.angleY, DiceController.baseAngleY(6));
    });

    testWidgets(
      'beginRoll without a server value returns to the previous one',
      (tester) async {
        final controller = DiceController(initialValue: 3);
        await tester.pumpWidget(wrap(DiceView(controller: controller)));
        controller.beginRoll();
        await pumpFor(tester, const Duration(milliseconds: 4200));
        await pumpFor(tester, const Duration(milliseconds: 1000));
        expect(controller.rolling, isFalse);
        expect(controller.value, 3);
        expect(tester.hasRunningAnimations, isFalse);
      },
    );

    testWidgets('show snaps mid-roll and completes the pending roll', (
      tester,
    ) async {
      final controller = DiceController();
      await tester.pumpWidget(wrap(DiceView(controller: controller)));
      var done = false;
      controller.roll(3).then((_) => done = true);
      await pumpFor(tester, const Duration(milliseconds: 200));
      controller.show(5);
      await tester.pump();
      expect(done, isTrue);
      expect(controller.value, 5);
      expect(controller.rolling, isFalse);
      expect(controller.angleX, DiceController.baseAngleX(5));
    });

    testWidgets('a second roll supersedes the first', (tester) async {
      final controller = DiceController();
      await tester.pumpWidget(wrap(DiceView(controller: controller)));
      var first = false;
      var second = false;
      controller.roll(2).then((_) => first = true);
      await pumpFor(tester, const Duration(milliseconds: 200));
      controller.roll(5).then((_) => second = true);
      await tester.pump();
      expect(first, isTrue);
      await pumpFor(tester, const Duration(milliseconds: 1100));
      expect(second, isTrue);
      expect(controller.value, 5);
    });

    testWidgets('reduced motion pops quickly to the value', (tester) async {
      final controller = DiceController();
      await tester.pumpWidget(
        wrap(DiceView(controller: controller, reducedMotion: true)),
      );
      var done = false;
      controller.roll(2).then((_) => done = true);
      await pumpFor(tester, const Duration(milliseconds: 320));
      expect(done, isTrue);
      expect(controller.value, 2);
      expect(controller.popScale, 1);
      expect(controller.opacity, 1);
    });

    testWidgets('removing the view completes a pending roll', (tester) async {
      final controller = DiceController();
      await tester.pumpWidget(wrap(DiceView(controller: controller)));
      var done = false;
      controller.roll(6).then((_) => done = true);
      await pumpFor(tester, const Duration(milliseconds: 100));
      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pump();
      expect(done, isTrue);
      expect(controller.value, 6);
      // Rolling without a view now resolves instantly.
      await controller.roll(1);
      expect(controller.value, 1);
    });
  });

  group('DiceView rendering', () {
    for (final skin in [...DiceSkins.all, 'dice_unknown']) {
      testWidgets('$skin renders in light/dark, LTR/RTL at several sizes', (
        tester,
      ) async {
        for (final brightness in Brightness.values) {
          for (final dir in TextDirection.values) {
            for (final size in [48.0, 72.0, 120.0]) {
              final controller = DiceController(initialValue: 3);
              await tester.pumpWidget(
                wrap(
                  DiceView(
                    controller: controller,
                    skin: skin,
                    size: size,
                    enabled: true,
                    accent: skin == DiceSkins.neon ? Colors.purpleAccent : null,
                  ),
                  brightness: brightness,
                  textDirection: dir,
                ),
              );
              expect(tester.getSize(find.byType(DiceView)), Size.square(size));
              // Exercise every face mid-tumble.
              final future = controller.roll(1 + (size ~/ 24) % 6);
              await pumpFor(
                tester,
                const Duration(milliseconds: 1100),
                step: const Duration(milliseconds: 90),
              );
              await future;
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(wrap(const SizedBox()));
              controller.dispose();
            }
          }
        }
      });
    }
  });

  group('DiceView interaction', () {
    testWidgets('semantics label carries the value and rolling state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = DiceController(initialValue: 5);
      await tester.pumpWidget(
        wrap(DiceView(controller: controller, enabled: true, onTap: () {})),
      );
      expect(find.bySemanticsLabel(RegExp('Dice showing 5')), findsOneWidget);
      controller.roll(2);
      await tester.pump();
      expect(find.bySemanticsLabel('Dice rolling'), findsOneWidget);
      await pumpFor(tester, const Duration(milliseconds: 1200));
      expect(find.bySemanticsLabel(RegExp('Dice showing 2')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('semantics use the active locale', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = DiceController(initialValue: 4);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('id'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Center(child: DiceView(controller: controller)),
        ),
      );
      expect(find.bySemanticsLabel('Dadu menunjukkan 4'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('tap only fires when enabled and not rolling', (tester) async {
      final controller = DiceController();
      var taps = 0;
      Widget build({required bool enabled}) => wrap(
        DiceView(controller: controller, enabled: enabled, onTap: () => taps++),
      );

      await tester.pumpWidget(build(enabled: false));
      await tester.tap(find.byType(DiceView));
      await tester.pumpAndSettle();
      expect(taps, 0);

      await tester.pumpWidget(build(enabled: true));
      await tester.tap(find.byType(DiceView));
      await tester.pump();
      expect(taps, 1);

      controller.roll(3);
      await tester.pump();
      await tester.tap(find.byType(DiceView), warnIfMissed: false);
      await tester.pump();
      expect(taps, 1);
      await pumpFor(tester, const Duration(milliseconds: 1200));
      await tester.tap(find.byType(DiceView));
      await tester.pump();
      expect(taps, 2);
    });

    testWidgets('ready pulse only runs while enabled and idle', (tester) async {
      final controller = DiceController();
      await tester.pumpWidget(wrap(DiceView(controller: controller)));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(
        wrap(DiceView(controller: controller, enabled: true)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
        wrap(DiceView(controller: controller, enabled: false)),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      // Reduced motion: static ring, no ticker.
      await tester.pumpWidget(
        wrap(
          DiceView(controller: controller, enabled: true, reducedMotion: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('swapping controllers re-attaches the ticker', (tester) async {
      final a = DiceController(initialValue: 1);
      final b = DiceController(initialValue: 2);
      await tester.pumpWidget(wrap(DiceView(controller: a)));
      await tester.pumpWidget(wrap(DiceView(controller: b)));
      var done = false;
      b.roll(4).then((_) => done = true);
      await tester.pump();
      expect(done, isFalse, reason: 'b animates through the view ticker');
      await pumpFor(tester, const Duration(milliseconds: 1200));
      expect(done, isTrue);
      // a is detached: instant.
      await a.roll(6);
      expect(a.value, 6);
    });
  });
}
