import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/protocol/json_read.dart';
import '../../../core/time/server_clock.dart';
import '../../progression/application/meta_support.dart';
import '../data/reports_api.dart';
import '../domain/report_models.dart';

/// Result of `POST /reports`.
@immutable
sealed class ReportOutcome {
  const ReportOutcome();
}

/// The server stored the report.
final class ReportSubmitted extends ReportOutcome {
  const ReportSubmitted(this.report, this.limit);
  final PlayerReport report;
  final ReportLimit limit;
}

/// 409 `already_reported`: this player was reported in the last 24 h.
final class ReportAlreadyReported extends ReportOutcome {
  const ReportAlreadyReported();
}

/// 429 `report_limit`: today's reports are used up until [limit].resetsAt.
final class ReportLimitReached extends ReportOutcome {
  const ReportLimitReached(this.limit);
  final ReportLimit limit;
}

/// Any other failure (`cannot_report_self`, `cannot_report_bot`,
/// `not_in_room`, `room_not_found`, network, …).
final class ReportFailed extends ReportOutcome {
  const ReportFailed(this.error);
  final ApiException error;
}

/// A report for the same player is already being sent.
final class ReportIgnored extends ReportOutcome {
  const ReportIgnored();
}

/// My reports and the daily allowance (`GET /reports`), plus submitting new
/// reports from a match.
class ReportsController extends AsyncNotifier<ReportsState> {
  final Set<String> _inFlight = {};

  ReportsApi get _api => ref.read(reportsApiProvider);

  @override
  Future<ReportsState> build() => _api.list();

  Future<void> refresh() async {
    try {
      final next = await _api.list();
      if (!ref.mounted) return;
      // Keep 409-confirmed players blocked until the list shows them.
      final blocked = state.value?.blockedUids ?? const {};
      state = AsyncData(next.copyWith(blockedUids: blocked));
    } catch (e, s) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, s);
      rethrow;
    }
  }

  bool isBusy(String uid) => _inFlight.contains(uid);

  /// Reports [uid] (a human opponent in [roomId]) for [reason].
  Future<ReportOutcome> submit({
    required String uid,
    required String roomId,
    required ReportReason reason,
  }) async {
    if (!_inFlight.add(uid)) return const ReportIgnored();
    try {
      final (report, limit) = await _api.submit(
        uid: uid,
        roomId: roomId,
        reason: reason,
      );
      ref.read(analyticsServiceProvider).playerReported(reason.wire);
      _update((s) => s.add(report, limit));
      return ReportSubmitted(report, limit);
    } on ApiException catch (e) {
      switch (e.code) {
        case 'already_reported':
          _update((s) => s.block(uid));
          return const ReportAlreadyReported();
        case 'report_limit':
          final limit = _exhaustedLimit(e);
          _update((s) => s.copyWith(limit: limit));
          return ReportLimitReached(limit);
      }
      return ReportFailed(e);
    } finally {
      _inFlight.remove(uid);
    }
  }

  /// The allowance after a 429: none left until `details.resetsAt` (or
  /// `Retry-After` from now).
  ReportLimit _exhaustedLimit(ApiException e) {
    final current = state.value?.limit ?? const ReportLimit();
    var resetsAt = readIntOrNull(e.details['resetsAt']);
    final retry = e.retryAfter;
    if (resetsAt == null && retry != null && retry > Duration.zero) {
      resetsAt = ref.read(serverClockProvider).nowMs() + retry.inMilliseconds;
    }
    return ReportLimit(
      perDay: current.perDay,
      remaining: 0,
      resetsAt: resetsAt ?? current.resetsAt,
    );
  }

  void _update(ReportsState Function(ReportsState) apply) {
    if (!ref.mounted) return;
    state = AsyncData(apply(state.value ?? const ReportsState()));
  }
}

final reportsProvider = AsyncNotifierProvider<ReportsController, ReportsState>(
  ReportsController.new,
  isAutoDispose: true,
  retry: noRetry,
);
