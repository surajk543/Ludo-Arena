import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/theme/app_theme.dart';
import 'package:ludo_arena/features/progression/presentation/widgets/pill_tabs.dart';

Widget _host(int selected, {String? trailing}) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: MetaPillTabs<int>(
            selected: selected,
            onSelected: (_) {},
            pills: [
              for (var i = 0; i < 6; i++)
                MetaPill(
                  value: i,
                  label: 'Tab number $i',
                  trailing: i == 0 ? trailing : null,
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position;

void main() {
  testWidgets('the selected pill starts in view and follows width changes', (
    tester,
  ) async {
    await tester.pumpWidget(_host(5));
    await tester.pump();
    final row = tester.getRect(find.byType(MetaPillTabs<int>));
    var pill = tester.getRect(find.text('Tab number 5'));
    expect(pill.right, lessThanOrEqualTo(row.right));

    // A count appears on the first pill (wider row): still in view.
    await tester.pumpWidget(_host(5, trailing: '12/20'));
    await tester.pump();
    pill = tester.getRect(find.text('Tab number 5'));
    expect(pill.right, lessThanOrEqualTo(row.right));
  });

  testWidgets('a manual scroll is kept when the content updates', (
    tester,
  ) async {
    await tester.pumpWidget(_host(5));
    await tester.pump();
    expect(_position(tester).pixels, greaterThan(0));

    await tester.drag(find.byType(Scrollable), const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);

    await tester.pumpWidget(_host(5, trailing: '3/20'));
    await tester.pump();
    expect(_position(tester).pixels, 0, reason: 'no jump back');

    // Selecting another pill reveals it again.
    await tester.pumpWidget(_host(4, trailing: '3/20'));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, greaterThan(0));
  });
}
