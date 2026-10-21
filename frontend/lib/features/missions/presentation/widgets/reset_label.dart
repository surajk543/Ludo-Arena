import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/time/server_clock.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../progression/application/meta_support.dart';

/// What resets at the given instant.
enum ResetKind { daily, weekly, event }

/// Locale tag usable by `DateFormat` (falls back to `en` when the locale's
/// date symbols are not loaded).
String metaDateTag(Locale locale) {
  try {
    return Intl.verifiedLocale(
          locale.languageCode,
          DateFormat.localeExists,
          onFailure: (_) => 'en',
        ) ??
        'en';
  } catch (_) {
    return 'en';
  }
}

/// Calm reset description in the user's LOCAL time, e.g.
/// "New missions at 5:30 AM · in 4 h 12 min". [resetsAtLocal] must already
/// be converted to local time; [remaining] is measured on the server clock.
String resetDescription(
  AppLocalizations l10n,
  Locale locale, {
  required ResetKind kind,
  required DateTime resetsAtLocal,
  required Duration remaining,
}) {
  final tag = metaDateTag(locale);
  final time = AppNumberFormat.time(resetsAtLocal, locale);
  final when = switch (kind) {
    ResetKind.daily => l10n.metaResetsDailyAt(time),
    ResetKind.weekly => l10n.metaResetsWeeklyAt(
      DateFormat.EEEE(tag).format(resetsAtLocal),
      time,
    ),
    ResetKind.event => l10n.metaEventEndsAt(
      '${DateFormat.MMMd(tag).format(resetsAtLocal)}, $time',
    ),
  };
  return l10n.metaWhenWithCountdown(when, formatMetaDuration(l10n, remaining));
}

/// "Resets …" line with a clock icon; refreshes every 30 s (no seconds, no
/// flashing — a calm reminder, not an urgency timer).
class PeriodResetLabel extends ConsumerStatefulWidget {
  const PeriodResetLabel({
    super.key,
    required this.resetsAtUtc,
    required this.kind,
    this.onElapsed,
    this.color,
  });

  final DateTime resetsAtUtc;
  final ResetKind kind;

  /// Text/icon color (defaults to the secondary text color).
  final Color? color;

  /// Called once when the reset time passes (e.g. to reload missions).
  final VoidCallback? onElapsed;

  @override
  ConsumerState<PeriodResetLabel> createState() => _PeriodResetLabelState();
}

class _PeriodResetLabelState extends ConsumerState<PeriodResetLabel> {
  Timer? _timer;
  bool _elapsedFired = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant PeriodResetLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetsAtUtc != widget.resetsAtUtc) _elapsedFired = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final clock = ref.watch(serverClockProvider);
    final ms = widget.resetsAtUtc.millisecondsSinceEpoch;
    final remaining = clock.remainingUntil(ms);
    if (remaining == Duration.zero && !_elapsedFired) {
      _elapsedFired = true;
      final cb = widget.onElapsed;
      if (cb != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) cb();
        });
      }
    }
    final text = resetDescription(
      l10n,
      Localizations.localeOf(context),
      kind: widget.kind,
      resetsAtLocal: clock.toLocal(ms),
      remaining: remaining,
    );
    return Row(
      children: [
        Icon(
          widget.kind == ResetKind.event
              ? Icons.event_rounded
              : Icons.schedule_rounded,
          size: 16,
          color: widget.color ?? c.textSecondary,
        ),
        const SizedBox(width: AppSpacing.xs + 2),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodySmall?.copyWith(color: widget.color),
          ),
        ),
      ],
    );
  }
}
