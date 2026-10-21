import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/localization/number_format.dart';
import 'package:ludo_royale/core/settings/app_settings.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/features/settings/presentation/number_system_picker.dart';
import 'package:ludo_royale/shared/widgets/balance_chip.dart';

import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

/// A balance chip (compact and exact-or-words) next to a button that opens
/// the Number format sheet, wired like the app root.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const BalanceChip(kind: BalanceKind.coins, value: 1234567),
        const BalanceChip(
          kind: BalanceKind.coins,
          value: 1000000,
          compact: false,
        ),
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => NumberSystemSheet.show(ctx),
            child: const Text('open'),
          ),
        ),
      ],
    ),
  );
}

void main() {
  tearDown(() => AppNumberFormat.preferredSystem = null);

  Future<(TestEnv, ProviderContainer)> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    final env = await TestEnv.create();
    env.routeHappyPath();
    final c = await pumpScreen(tester, env, const _Host(), locale: locale);
    return (env, c);
  }

  testWidgets('picking International in the sheet reformats balance chips '
      'at once, persists and reports settings_changed', (tester) async {
    final (env, c) = await pump(tester);
    expect(find.text('12.34 Lakh'), findsOneWidget);
    expect(find.text('10 Lakh'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Each option shows a live example; Indian (the default) is selected.
    expect(find.text('1,00,000 · 10 Lakh'), findsOneWidget);
    expect(find.text('100,000 · 1M'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('numberSystem.indian'))),
      isSemantics(isSelected: true, isButton: true),
    );

    await tester.tap(find.text('International'));
    await tester.pumpAndSettle();
    expect(find.text('100,000 · 1M'), findsNothing, reason: 'sheet closed');
    expect(find.text('1.23M'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('12.34 Lakh'), findsNothing);
    expect(
      c.read(preferencesStoreProvider).getString(PrefKeys.numberSystem),
      'international',
    );
    expect(
      env.analytics.events,
      contains('settings_changed:international_numbers:true'),
    );

    // Back to Indian (e.g. from Settings): every chip follows.
    await c
        .read(settingsControllerProvider.notifier)
        .setNumberSystem(NumberSystem.indian);
    await tester.pump();
    expect(find.text('12.34 Lakh'), findsOneWidget);
    expect(find.text('10 Lakh'), findsOneWidget);
  });

  testWidgets('other locales switch their own words and separators', (
    tester,
  ) async {
    final (_, c) = await pump(tester, locale: const Locale('hi'));
    expect(find.text('12.34 लाख'), findsOneWidget);
    await c
        .read(settingsControllerProvider.notifier)
        .setNumberSystem(NumberSystem.international);
    await tester.pump();
    expect(find.text('1.23 मिलियन'), findsOneWidget);
    expect(find.text('1 मिलियन'), findsOneWidget);
  });

  testWidgets('id defaults to international and can switch to Indian', (
    tester,
  ) async {
    final (env, c) = await pump(tester, locale: const Locale('id'));
    expect(find.text('1,23 jt'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('1.00.000 · 10 lakh'), findsOneWidget);
    expect(find.text('100.000 · 1 jt'), findsOneWidget);
    await tester.tap(find.text('India'));
    await tester.pumpAndSettle();
    expect(find.text('12,34 lakh'), findsOneWidget);
    expect(
      c.read(settingsControllerProvider).numberSystem,
      NumberSystem.indian,
    );
    expect(
      env.analytics.events,
      contains('settings_changed:international_numbers:false'),
    );
  });
}
