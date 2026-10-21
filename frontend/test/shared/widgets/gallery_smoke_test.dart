import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/realtime/realtime_status.dart';
import 'package:ludo_royale/core/theme/app_theme.dart';
import 'package:ludo_royale/core/time/server_clock.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';
import 'package:ludo_royale/shared/widgets/widgets.dart';

import 'widget_harness.dart';

/// Every shared widget on one scrolling page, using long localized strings.
class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayeredBackground(
      style: LayeredBackgroundStyle.hero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: BrandLogo(size: 72, showWordmark: true)),
            Row(
              children: [
                const Flexible(
                  child: BalanceChip(kind: BalanceKind.coins, value: 123456789),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: BalanceChip(kind: BalanceKind.diamonds, value: 1500),
                ),
                const Spacer(),
                IconCircleButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: l10n.commonBack,
                  onPressed: () {},
                  badgeCount: 120,
                  mirrorInRtl: true,
                ),
              ],
            ),
            PremiumButton(
              label: l10n.commonConnectionReplaced,
              icon: Icons.public_rounded,
              onPressed: () {},
            ),
            PremiumButton(
              label: l10n.commonOfflineHint,
              variant: PremiumButtonVariant.gold,
              onPressed: () {},
            ),
            SectionHeader(
              title: l10n.commonOfflineHint,
              actionLabel: l10n.commonSomethingWentWrong,
              onAction: () {},
            ),
            SurfaceCard(
              child: Row(
                children: [
                  const PlayerAvatar(
                    avatarIndex: 3,
                    frameId: 'frame_royal',
                    isBot: true,
                    seatColor: SeatColor.green,
                  ),
                  const SizedBox(width: 8),
                  const LevelBadge(level: 50),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: TitleChip(titleId: 'title_weekly_champion'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const GlassCard(
              child: XpProgressBar(current: 123456, total: 999999),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                EmoteIcon(emoteId: 'emote_laugh', size: 32),
                EmoteIcon(emoteId: 'emote_crown', size: 32),
                BadgeIcon(badgeId: 'badge_friendly', size: 32),
                CountdownRing(deadlineMs: 0, totalMs: 20000, size: 40),
              ],
            ),
            ConnectionIndicator(
              status: RealtimeStatus.replaced,
              onReconnect: () {},
            ),
            const SizedBox(height: 8),
            ChoiceChips<int>(
              options: [
                ChoiceOption(
                  value: 2,
                  label: l10n.commonPlayerCount(2),
                  caption: l10n.commonEntryFee('1,000'),
                ),
                ChoiceOption(value: 3, label: l10n.commonPlayerCount(3)),
                ChoiceOption(value: 4, label: l10n.commonPlayerCount(4)),
              ],
              value: 4,
              onChanged: (_) {},
            ),
            const RoyalDivider(),
            SizedBox(
              height: 320,
              child: EmptyState(
                title: l10n.commonNothingHereYet,
                message: l10n.commonOfflineHint,
              ),
            ),
            SizedBox(
              height: 320,
              child: ErrorState(
                message: l10n.commonOfflineHint,
                onRetry: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  final configs = <(String, ThemeMode, double)>[
    ('en', ThemeMode.light, 1.0),
    ('en', ThemeMode.dark, 1.0),
    ('ar', ThemeMode.light, 1.0),
    ('ar', ThemeMode.dark, 1.0),
    ('hi', ThemeMode.light, 1.0),
    ('hi', ThemeMode.dark, 1.3),
    ('ur', ThemeMode.dark, 1.0),
    ('id', ThemeMode.light, 1.3),
  ];

  for (final (code, mode, scale) in configs) {
    testWidgets('gallery renders at 320x640 [$code ${mode.name} x$scale]', (
      tester,
    ) async {
      setViewport(tester, const Size(320, 640));
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final clock = ServerClock(() => DateTime.fromMillisecondsSinceEpoch(0));
      await tester.pumpWidget(
        await buildHarness(
          const _Gallery(),
          locale: Locale(code),
          themeMode: mode,
          overrides: [serverClockProvider.overrideWithValue(clock)],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final direction = Directionality.of(
        tester.element(find.byType(_Gallery)),
      );
      expect(
        direction,
        code == 'ar' || code == 'ur' ? TextDirection.rtl : TextDirection.ltr,
      );

      // Scroll to the bottom to lay out everything.
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('LoadingState renders a localized message', (tester) async {
    setViewport(tester, const Size(320, 640));
    await tester.pumpWidget(
      await buildHarness(const LoadingState(), locale: const Locale('ar')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('جارٍ التحميل…'), findsOneWidget);
  });
}
