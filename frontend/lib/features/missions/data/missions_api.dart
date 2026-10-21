import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/mission_models.dart';

/// Missions REST endpoints.
class MissionsApi {
  MissionsApi(this._api);

  final ApiClient _api;

  /// `GET /missions`. Throws [ApiException].
  Future<MissionsBoard> fetch() async =>
      MissionsBoard.fromJson(await _api.get('/missions'));

  /// `POST /missions/{periodKey}/{missionId}/claim` with [idempotencyKey].
  /// Throws [ApiException] (`already_claimed`, `not_completed`, `not_found`,
  /// …).
  Future<ClaimResult> claim({
    required String periodKey,
    required String missionId,
    required String idempotencyKey,
  }) async {
    final json = await _api.post(
      '/missions/${Uri.encodeComponent(periodKey)}/'
      '${Uri.encodeComponent(missionId)}/claim',
      idempotencyKey: idempotencyKey,
    );
    return ClaimResult.fromJson(json);
  }
}

final missionsApiProvider = Provider<MissionsApi>(
  (ref) => MissionsApi(ref.watch(apiClientProvider)),
);
