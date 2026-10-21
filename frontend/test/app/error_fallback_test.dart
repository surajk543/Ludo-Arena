import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/app/error_fallback.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';

class _Boom extends StatelessWidget {
  const _Boom();

  @override
  Widget build(BuildContext context) =>
      throw StateError('FlutterError: secret stack detail');
}

Widget _app({Locale locale = const Locale('en'), Widget? home}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Column(
      children: [
        const Text('above'),
        SizedBox(height: 200, child: home ?? const _Boom()),
      ],
    ),
  ),
);

List<String> _texts(WidgetTester tester) => [
  for (final e in find.byType(RichText).evaluate())
    (e.widget as RichText).text.toPlainText(),
];

/// Runs [body] with the fallback installed as in a release build; restores
/// the framework builder before the test ends (flutter_test verifies it).
Future<void> _inRelease(Future<void> Function() body) async {
  final original = ErrorWidget.builder;
  try {
    installErrorWidget(release: true);
    await body();
  } finally {
    ErrorWidget.builder = original;
  }
}

void main() {
  testWidgets('release builds show the branded, localized fallback', (
    tester,
  ) async {
    await _inRelease(() async {
      await tester.pumpWidget(_app());
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());

      expect(find.byType(AppErrorFallback), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(find.text('above'), findsOneWidget);
      for (final t in _texts(tester)) {
        expect(t, isNot(contains('Flutter')));
        expect(t, isNot(contains('secret')));
        expect(t, isNot(contains('StateError')));
      }
    });
  });

  testWidgets('the fallback follows the app language', (tester) async {
    await _inRelease(() async {
      await tester.pumpWidget(_app(locale: const Locale('hi')));
      await tester.pump();
      tester.takeException();
      expect(find.text('कुछ गड़बड़ हो गई।'), findsOneWidget);
    });
  });

  testWidgets('works without any app scaffolding (English, LTR)', (
    tester,
  ) async {
    await _inRelease(() async {
      await tester.pumpWidget(const _Boom());
      tester.takeException();
      expect(find.text('Something went wrong.'), findsOneWidget);
    });
  });

  testWidgets('debug builds keep the framework error widget', (tester) async {
    final original = ErrorWidget.builder;
    installErrorWidget(release: false);
    expect(identical(ErrorWidget.builder, original), isTrue);
    await tester.pumpWidget(_app());
    await tester.pump();
    tester.takeException();
    expect(find.byType(AppErrorFallback), findsNothing);
    expect(find.byType(ErrorWidget), findsOneWidget);
  });
}
