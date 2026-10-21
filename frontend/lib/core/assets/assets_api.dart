import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../protocol/json_read.dart';

/// Most paths one `POST /assets/sign` accepts.
const int kMaxSignPaths = 50;

/// `POST /assets/sign` response: short-lived signed GET URLs by path.
///
/// Signed URLs are bearer secrets for their lifetime: never log them, show
/// them or send them to analytics.
@immutable
class SignedAssetUrls {
  const SignedAssetUrls({required this.urls, required this.expiresAt});

  factory SignedAssetUrls.fromJson(Map<String, dynamic> j) {
    final raw = readMap(j['urls']);
    return SignedAssetUrls(
      urls: Map.unmodifiable({
        for (final e in raw.entries)
          if (e.value is String && (e.value as String).startsWith('http'))
            e.key: e.value as String,
      }),
      expiresAt: readInt(j['expiresAt']),
    );
  }

  /// Signed URL per requested path. Paths the server does not know are
  /// omitted (never signed).
  final Map<String, String> urls;

  /// Unix ms (server clock) after which the URLs stop working.
  final int expiresAt;
}

/// Asset REST endpoints.
class AssetsApi {
  AssetsApi(this._api);

  final ApiClient _api;

  /// `POST /assets/sign` for 1..[kMaxSignPaths] [paths]. Throws
  /// [ApiException] (`assets_unavailable` when storage is not configured,
  /// `bad_request`).
  Future<SignedAssetUrls> sign(List<String> paths) async {
    assert(paths.isNotEmpty && paths.length <= kMaxSignPaths);
    final json = await _api.post('/assets/sign', body: {'paths': paths});
    return SignedAssetUrls.fromJson(json);
  }
}
