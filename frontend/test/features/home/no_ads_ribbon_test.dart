import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/home/presentation/home_screen.dart';
import 'package:ludo_royale/features/home/presentation/widgets/home_header.dart';
import 'package:ludo_royale/features/home/presentation/widgets/no_ads_ribbon.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

/// Home plus stub pages for the header's destinations.
GoRouter _router() => GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
    for (final p in [AppRoutes.settings, AppRoutes.linkAccount])
      GoRoute(
        path: p,
        builder: (_, state) => Scaffold(body: Text('AT ${state.uri}')),
      ),
  ],
);

Future<void> _pumpHome(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  Size size = Viewports.phone,
  double textScale = 1.0,
}) async {
  final env = await TestEnv.create();
  env.routeHappyPath(); // a guest: Save Progress and Settings both show
  await pumpScreen(
    tester,
    env,
    const SizedBox(),
    router: _router(),
    locale: locale,
    themeMode: themeMode,
    size: size,
    textScale: textScale,
    prepare: (c) =>
        c.read(sessionControllerProvider.notifier).continueAsGuest(),
  );
}

Rect _card(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(HomeHeader),
    matching: find.byType(SurfaceCard),
  ),
);

/// Perpendicular distance from the card's top-end corner to the nearest
/// point of a header action's 40 dp circle (found by its tooltip).
double _clearance(WidgetTester tester, String tooltip, {required bool rtl}) {
  final card = _card(tester);
  final c = tester.getCenter(find.byTooltip(tooltip));
  final fromEnd = rtl ? c.dx - card.left : card.right - c.dx;
  return (fromEnd + c.dy - card.top) / math.sqrt2 - 20;
}

void main() {
  // The real label faces, so widths below are what users see (the default
  // test font draws every glyph as a 1 em square).
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final (family, file) in const [
      ('Fredoka', 'Fredoka-Bold'),
      ('Baloo2', 'Baloo2-Bold'),
      ('BalooBhaijaan2', 'BalooBhaijaan2-Bold'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$file.ttf'));
      await loader.load();
    }
  });

  const configs = <(Locale, ThemeMode, Size, double)>[
    (Locale('en'), ThemeMode.light, Viewports.phone, 1.0),
    (Locale('en'), ThemeMode.dark, Viewports.small, 1.35),
    (Locale('ar'), ThemeMode.light, Viewports.small, 1.35),
    (Locale('ar'), ThemeMode.dark, Viewports.phone, 1.0),
  ];

  for (final (locale, mode, size, scale) in configs) {
    final rtl = locale.languageCode == 'ar';
    final tag =
        '${locale.languageCode} ${mode.name} '
        '@${size.width.toInt()}x${size.height.toInt()} x$scale';

    testWidgets('ribbon sits on the header\'s end corner, clear of the '
        'actions ($tag)', (tester) async {
      final l10n = lookupAppLocalizations(locale);
      await _pumpHome(
        tester,
        locale: locale,
        themeMode: mode,
        size: size,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);

      // Announced once, as a plain (non-interactive) statement.
      final ribbon = find.byType(NoAdsRibbon);
      expect(ribbon, findsOneWidget);
      final label = find.bySemanticsLabel(l10n.homeNoAdsRibbon);
      expect(label, findsOneWidget);
      final data = tester.getSemantics(label).getSemanticsData();
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      // Top-right in LTR, mirrored to top-left in RTL (the "end" corner,
      // where the header's actions are).
      final card = _card(tester);
      final rect = tester.getRect(ribbon);
      // (Inside the card's 1 dp border.)
      expect(rect.top - card.top, moreOrLessEquals(1));
      expect(
        rtl ? rect.left - card.left : card.right - rect.right,
        moreOrLessEquals(1),
      );
      expect(rect.size, const Size.square(NoAdsRibbon.reach));

      // Both 40 dp action circles stay clear of the band.
      for (final tooltip in [
        l10n.homeSettingsTooltip,
        l10n.homeSaveProgressTooltip,
      ]) {
        expect(
          _clearance(tester, tooltip, rtl: rtl),
          greaterThan(NoAdsRibbon.innerEdge + 3),
          reason: tooltip,
        );
      }

      // The band never takes pointer events: a hit test on its centre
      // reaches the card below and nothing inside the ribbon.
      final mid =
          (NoAdsRibbon.innerEdge - NoAdsRibbon.thickness / 2) / math.sqrt2;
      final bandCenter = Offset(
        rtl ? rect.left + mid : rect.right - mid,
        rect.top + mid,
      );
      final ribbonObjects = tester
          .renderObjectList(
            find.descendant(
              of: ribbon,
              matching: find.byWidgetPredicate((_) => true),
            ),
          )
          .toSet();
      final hits = tester
          .hitTestOnBinding(bandCenter)
          .path
          .map((e) => e.target);
      expect(hits.where(ribbonObjects.contains), isEmpty);
    });

    testWidgets('Settings and Save Progress still navigate ($tag)', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(locale);
      for (final (tooltip, route) in [
        (l10n.homeSettingsTooltip, AppRoutes.settings),
        (l10n.homeSaveProgressTooltip, AppRoutes.linkAccount),
      ]) {
        await _pumpHome(
          tester,
          locale: locale,
          themeMode: mode,
          size: size,
          textScale: scale,
        );
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
        expect(find.text('AT $route'), findsOneWidget, reason: tooltip);
      }
    });
  }

  // In every language, at the default and the largest text scale on the
  // smallest phone, the label stays inside the visible band and readable.
  for (final code in ['en', 'hi', 'ur', 'id', 'ar']) {
    for (final scale in [1.0, 1.35]) {
      testWidgets('ribbon label fits the band ($code @320x640 x$scale)', (
        tester,
      ) async {
        final locale = Locale(code);
        await _pumpHome(
          tester,
          locale: locale,
          size: Viewports.small,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        final text = find.descendant(
          of: find.byType(NoAdsRibbon),
          matching: find.text(lookupAppLocalizations(locale).homeNoAdsRibbon),
        );
        expect(text, findsOneWidget);

        // What is painted: the Text box times any FittedBox shrink.
        final raw = tester.getSize(text);
        final box = tester.getSize(
          find.ancestor(of: text, matching: find.byType(FittedBox)),
        );
        final shrink = math.min(1.0, box.width / raw.width);
        final w = raw.width * shrink;
        final h = raw.height * shrink;
        final fontSize = tester.widget<Text>(text).style!.fontSize! * shrink;

        // Capped text scale (10 sp × ≤ 1.2); English never shrinks.
        expect(fontSize, lessThanOrEqualTo(12.0001));
        if (code == 'en') {
          expect(fontSize, moreOrLessEquals(10 * scale.clamp(1, 1.2)));
        }
        // A w × h label centred on the band fits inside the card corner when
        // w + h ≤ 2 × midline, and inside the band when h ≤ thickness.
        expect(w + h, lessThanOrEqualTo(2 * NoAdsRibbon.midline));
        expect(h, lessThanOrEqualTo(NoAdsRibbon.thickness));
        // Long translations shrink, but stay readable (real fonts loaded).
        expect(fontSize, greaterThanOrEqualTo(8), reason: code);
      });
    }
  }
}
