import 'dart:ui';

import 'package:intl/intl.dart';

import '../../../core/localization/number_format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/time/server_clock.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../missions/presentation/widgets/reset_label.dart' show metaDateTag;
import '../../progression/application/meta_support.dart';
import '../domain/report_models.dart';

/// Localized texts for player reports.
abstract final class ReportText {
  static String reason(AppLocalizations l10n, ReportReason r) => switch (r) {
    ReportReason.cheating => l10n.socialReasonCheating,
    ReportReason.offensiveName => l10n.socialReasonOffensiveName,
    ReportReason.abusiveBehavior => l10n.socialReasonAbusiveBehavior,
    ReportReason.leavingOrStalling => l10n.socialReasonLeavingOrStalling,
    ReportReason.other => l10n.socialReasonOther,
  };

  static String status(AppLocalizations l10n, ReportStatus s) => switch (s) {
    ReportStatus.submitted => l10n.socialStatusSubmitted,
    ReportStatus.reviewing => l10n.socialStatusReviewing,
    ReportStatus.actionTaken => l10n.socialStatusActionTaken,
    ReportStatus.dismissed => l10n.socialStatusDismissed,
  };

  /// "3:30 PM" today, otherwise "22 Oct 2026, 3:30 PM" (local time).
  static String resetTime(
    Locale locale,
    ServerClock clock,
    int resetsAtServerMs,
  ) {
    final at = clock.toLocal(resetsAtServerMs);
    final now = clock.toLocal(clock.nowMs());
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay
        ? AppNumberFormat.time(at, locale)
        : AppNumberFormat.dateTime(at, locale);
  }

  /// "You've used today's 2 reports. You can report again at 3:30 PM."
  static String limitReached(
    AppLocalizations l10n,
    Locale locale,
    ServerClock clock,
    ReportLimit limit,
  ) {
    final at = limit.resetsAt;
    if (at == null || at <= 0) return l10n.socialReportLimitLater(limit.perDay);
    return l10n.socialReportLimitAt(limit.perDay, resetTime(locale, clock, at));
  }

  /// "Just now", "12 min ago", "3 h ago", "Yesterday", then a date.
  static String relative(
    AppLocalizations l10n,
    Locale locale,
    ServerClock clock,
    int serverMs,
  ) {
    final ago = Duration(milliseconds: clock.nowMs() - serverMs);
    if (ago.inMinutes < 1) return l10n.socialJustNow;
    if (ago.inHours < 1) return l10n.socialMinutesAgo(ago.inMinutes);
    if (ago.inHours < 24) return l10n.socialHoursAgo(ago.inHours);
    final at = clock.toLocal(serverMs);
    final now = clock.toLocal(clock.nowMs());
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (today.difference(day).inDays == 1) return l10n.socialYesterday;
    final tag = metaDateTag(locale);
    return at.year == now.year
        ? DateFormat.MMMd(tag).format(at)
        : DateFormat.yMMMd(tag).format(at);
  }

  /// Message for a failed `POST /reports` (server English never shown).
  static String error(AppLocalizations l10n, ApiException e) =>
      switch (e.code) {
        'already_reported' => l10n.socialAlreadyReported,
        'cannot_report_self' => l10n.socialErrorCannotReportSelf,
        'cannot_report_bot' => l10n.socialErrorCannotReportBot,
        'not_in_room' => l10n.socialErrorNotInRoom,
        'room_not_found' => l10n.socialErrorRoomNotFound,
        'not_found' => l10n.socialErrorPlayerNotFound,
        _ => metaErrorMessage(l10n, e),
      };
}
