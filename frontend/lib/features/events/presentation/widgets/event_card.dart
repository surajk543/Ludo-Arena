import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/time/server_clock.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../missions/domain/mission_models.dart';
import '../../../missions/domain/mission_texts.dart';
import '../../../missions/presentation/widgets/reset_label.dart';

/// Event dates in local time, e.g. "Oct 19 – Nov 2" (the exact end time
/// is on the "Ends …" line).
String eventWindowText(
  AppLocalizations l10n,
  Locale locale,
  DateTime startLocal,
  DateTime endLocal,
) {
  final tag = metaDateTag(locale);
  return l10n.metaEventWindow(
    DateFormat.MMMd(tag).format(startLocal),
    DateFormat.MMMd(tag).format(endLocal),
  );
}

/// Hero card of a running event: title, description, window and a calm
/// "ends …" line.
class EventHeroCard extends ConsumerWidget {
  const EventHeroCard({super.key, required this.event});

  final EventSet event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final clock = ref.watch(serverClockProvider);
    final start = event.startsAtUtc;
    final end = event.endsAtUtc;
    final onHero = Colors.white;
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgAll,
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color(0xFFE0703A), Color(0xFFB8452E), Color(0xFF6E2A4F)],
        ),
        boxShadow: c.shadow(AppElevation.medium),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -12,
            top: -10,
            child: ExcludeSemantics(
              child: Icon(
                Icons.eco_rounded,
                size: 120,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: AppRadii.pillAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.celebration_rounded, size: 14, color: onHero),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          l10n.metaEventLiveBadge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.labelSmall?.copyWith(
                            color: onHero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  header: true,
                  child: Text(
                    MissionTexts.eventTitle(l10n, event),
                    style: context.textTheme.headlineSmall?.copyWith(
                      color: onHero,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  MissionTexts.eventDescription(l10n, event),
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: onHero.withValues(alpha: 0.92),
                  ),
                ),
                if (start != null && end != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _HeroLine(
                    icon: Icons.date_range_rounded,
                    text: eventWindowText(
                      l10n,
                      locale,
                      clock.toLocal(start.millisecondsSinceEpoch),
                      clock.toLocal(end.millisecondsSinceEpoch),
                    ),
                  ),
                ],
                if (end != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  PeriodResetLabel(
                    resetsAtUtc: end,
                    kind: ResetKind.event,
                    color: onHero.withValues(alpha: 0.92),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroLine extends StatelessWidget {
  const _HeroLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: Colors.white),
      const SizedBox(width: AppSpacing.xs + 2),
      Expanded(
        child: Text(
          text,
          style: context.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
      ),
    ],
  );
}

/// "How it works" — honest event rules (eligibility, claiming, end).
class EventRulesCard extends StatelessWidget {
  const EventRulesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final rules = [
      (Icons.flag_rounded, l10n.metaEventRuleComplete),
      (Icons.verified_rounded, l10n.metaEventRuleEligible),
      (Icons.redeem_rounded, l10n.metaEventRuleClaim),
      (Icons.event_busy_rounded, l10n.metaEventRuleEnd),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.lgAll,
        border: Border.all(
          color: c.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : c.outline.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.metaEventRulesTitle, style: context.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final (icon, text) in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: c.brand),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(text, style: context.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Empty-state art for "no events right now".
class EventEmptyIllustration extends StatelessWidget {
  const EventEmptyIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [c.goldSoft, c.goldSoft.withValues(alpha: 0)],
          ),
        ),
        child: Icon(Icons.event_available_rounded, size: 56, color: c.gold),
      ),
    );
  }
}
