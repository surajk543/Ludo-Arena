import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/theme/app_theme.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import 'widget_harness.dart';

class _Balance extends StatefulWidget {
  const _Balance();

  @override
  State<_Balance> createState() => _BalanceState();
}

class _BalanceState extends State<_Balance> {
  int value = 1000;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      BalanceChip(kind: BalanceKind.coins, value: value),
      BalanceChip(kind: BalanceKind.diamonds, value: 50, compact: false),
      TextButton(
        onPressed: () => setState(() => value = 1000000),
        child: const Text('credit'),
      ),
    ],
  );
}

void main() {
  testWidgets('BalanceChip counts up to the server-confirmed value', (
    tester,
  ) async {
    await tester.pumpWidget(await buildHarness(const _Balance()));
    expect(find.text('1,000'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);

    await tester.tap(find.text('credit'));
    await tester.pump(const Duration(milliseconds: 200));
    // Mid-animation: neither the old nor the final value.
    expect(find.text('10 Lakh'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('10 Lakh'), findsOneWidget);
    expect(find.bySemanticsLabel('Coins: 10,00,000'), findsOneWidget);
  });

  testWidgets('BalanceChip jumps straight to the value with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      await buildHarness(const _Balance(), disableAnimations: true),
    );
    await tester.tap(find.text('credit'));
    await tester.pump();
    expect(find.text('10 Lakh'), findsOneWidget);
  });

  testWidgets('PlayerAvatar renders all 12 avatars x 5 frames', (tester) async {
    await tester.pumpWidget(
      await buildHarness(
        SingleChildScrollView(
          child: Wrap(
            children: [
              for (var i = 0; i < 12; i++)
                for (final f in kAvatarFrameIds)
                  PlayerAvatar(
                    avatarIndex: i,
                    frameId: f,
                    size: 48,
                    seatColor: SeatColor.values[i % 4],
                    dimmed: i == 3,
                  ),
              const PlayerAvatar(avatarIndex: 25, frameId: 'frame_unknown'),
              const PlayerAvatar(avatarIndex: 1, size: 24),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(PlayerAvatar), findsNWidgets(62));
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatars announce only the player name', (tester) async {
    await tester.pumpWidget(
      await buildHarness(
        const PlayerAvatar(avatarIndex: 2, semanticLabel: 'Asha'),
        locale: const Locale('hi'),
      ),
    );
    expect(find.bySemanticsLabel('Asha'), findsOneWidget);
    expect(find.text('बॉट'), findsNothing);
  });

  testWidgets('Level, XP, title, emote and badge widgets render', (
    tester,
  ) async {
    await tester.pumpWidget(
      await buildHarness(
        const Column(
          children: [
            LevelBadge(level: 7),
            XpProgressBar(current: 70, total: 400),
            TitleChip(titleId: 'title_dice_master'),
            Row(
              children: [
                EmoteIcon(emoteId: 'emote_wave'),
                EmoteIcon(emoteId: 'emote_thumbs'),
                EmoteIcon(emoteId: 'emote_laugh'),
                EmoteIcon(emoteId: 'emote_wow'),
                EmoteIcon(emoteId: 'emote_crown'),
                EmoteIcon(emoteId: 'emote_future'),
              ],
            ),
            Row(
              children: [
                BadgeIcon(badgeId: 'badge_first_win'),
                BadgeIcon(badgeId: 'badge_friendly'),
                BadgeIcon(badgeId: 'badge_future'),
              ],
            ),
          ],
        ),
      ),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.text('70 / 400 XP'), findsOneWidget);
    expect(find.text('Dice Master'), findsOneWidget);
    expect(find.bySemanticsLabel('Emote: Wave'), findsOneWidget);
    expect(find.bySemanticsLabel('Badge: First Victory'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
