import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/progression_models.dart';

/// `GET /progression` (level, XP and level milestones).
class ProgressionApi {
  ProgressionApi(this._api);

  final ApiClient _api;

  /// Throws [ApiException].
  Future<ProgressionView> fetch() async =>
      ProgressionView.fromJson(await _api.get('/progression'));
}

final progressionApiProvider = Provider<ProgressionApi>(
  (ref) => ProgressionApi(ref.watch(apiClientProvider)),
);
