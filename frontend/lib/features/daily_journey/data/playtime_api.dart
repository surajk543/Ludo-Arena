import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/protocol/protocol.dart';

/// `GET /playtime` (today's server-counted playtime).
class PlaytimeApi {
  PlaytimeApi(this._api);

  final ApiClient _api;

  /// Today's playtime, or null while the server has daily playtime disabled
  /// (404 `not_found`). Throws [ApiException] for other failures.
  Future<Playtime?> fetch() async {
    try {
      return Playtime.fromJson(await _api.get('/playtime'));
    } on ApiException catch (e) {
      if (e.status == 404 && e.code == 'not_found') return null;
      rethrow;
    }
  }
}

final playtimeApiProvider = Provider<PlaytimeApi>(
  (ref) => PlaytimeApi(ref.watch(apiClientProvider)),
);
