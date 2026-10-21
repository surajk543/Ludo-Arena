import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/protocol/json_read.dart';
import '../domain/report_models.dart';

/// Player report REST endpoints.
class ReportsApi {
  ReportsApi(this._api);

  final ApiClient _api;

  /// `GET /reports`: my reports (newest first) and today's allowance.
  /// Throws [ApiException].
  Future<ReportsState> list() async =>
      ReportsState.fromJson(await _api.get('/reports'));

  /// `POST /reports`. Throws [ApiException] (`already_reported` 409,
  /// `report_limit` 429 with `details.resetsAt`, `cannot_report_self`,
  /// `cannot_report_bot`, `not_in_room` 422, `not_found` /
  /// `room_not_found` 404, `bad_request` 400).
  Future<(PlayerReport, ReportLimit)> submit({
    required String uid,
    required String roomId,
    required ReportReason reason,
  }) async {
    final json = await _api.post(
      '/reports',
      body: {'uid': uid, 'roomId': roomId, 'reason': reason.wire},
    );
    return (
      PlayerReport.fromJson(readMap(json['report'])),
      ReportLimit.fromJson(readMap(json['limit'])),
    );
  }
}

final reportsApiProvider = Provider<ReportsApi>(
  (ref) => ReportsApi(ref.watch(apiClientProvider)),
);
