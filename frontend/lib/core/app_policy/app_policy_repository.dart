import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/app_info.dart';
import '../network/api_client.dart';
import '../storage/preferences_store.dart';
import 'app_policy.dart';

export 'app_policy.dart';

/// Fetches the evaluated policy for this install.
abstract interface class AppPolicyRepository {
  /// `GET /app/config`. Throws [ApiException] (network/timeout/…) when the
  /// service can't be reached.
  Future<AppPolicy> fetch({required String locale});
}

class RestAppPolicyRepository implements AppPolicyRepository {
  RestAppPolicyRepository({
    required this._api,
    required this._info,
    required this._config,
  });

  final ApiClient _api;
  final AppInfo _info;
  final AppConfig _config;

  @override
  Future<AppPolicy> fetch({required String locale}) async {
    final json = await _api.get(
      '/app/config',
      auth: false,
      query: {
        'platform': _info.platform,
        'version': _info.version,
        'build': '${_info.build}',
        'environment': _config.environment.name,
        'locale': locale,
      },
    );
    return AppPolicy.fromJson(json);
  }
}

/// Last successfully received policy, cached in SharedPreferences for
/// display context only (e.g. on the "can't reach" screen). It NEVER grants
/// access: the gate always requires a fresh fetch.
class PolicyCache {
  PolicyCache(this._prefs);

  final PreferencesStore _prefs;

  AppPolicy? read() {
    final raw = _prefs.getString(PrefKeys.cachedPolicy);
    if (raw == null) return null;
    try {
      return AppPolicy.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AppPolicy policy) =>
      _prefs.setString(PrefKeys.cachedPolicy, jsonEncode(policy.toJson()));
}

final appPolicyRepositoryProvider = Provider<AppPolicyRepository>(
  (ref) => RestAppPolicyRepository(
    api: ref.watch(apiClientProvider),
    info: ref.watch(appInfoProvider),
    config: ref.watch(appConfigProvider),
  ),
);

final policyCacheProvider = Provider<PolicyCache>(
  (ref) => PolicyCache(ref.watch(preferencesStoreProvider)),
);
