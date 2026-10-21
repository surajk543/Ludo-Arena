import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'provider_credential.dart';

/// Go-owned authentication + account endpoints (see docs/rest-api.md).
abstract interface class AuthApi {
  /// `POST /auth/guest`. Without [deviceId]: a new guest (201, incl.
  /// `guestSecret`). With [deviceId]: the device's guest (200, no
  /// `guestSecret`) or a new guest bound to the device (201).
  Future<AuthResponse> createGuest({String? deviceId});

  /// `POST /auth/guest/resume`. 401 `invalid_credential` once the guest was
  /// linked to a provider or deleted.
  Future<AuthResponse> resumeGuest(String guestSecret);

  /// `POST /auth/device/resume`: signs in to the device's guest (no
  /// `guestSecret`). 404 `not_found` when the device has no guest; never
  /// creates one.
  Future<AuthResponse> resumeDevice(String deviceId);

  /// `PUT /account/device`: binds [deviceId] to the current guest account.
  /// 409 `identity_conflict` when the device has another guest, 409
  /// `not_a_guest` for a linked account.
  Future<void> bindDevice(String deviceId);

  /// `POST /auth/{provider}`.
  Future<AuthResponse> signIn(ProviderCredential credential);

  /// `POST /auth/logout` (best effort). Revokes the session of
  /// [accessToken] when given (sent explicitly: the local session is being
  /// replaced or cleared at the same time), else of [refreshToken].
  Future<void> logout(String refreshToken, {String? accessToken});

  /// `GET /me`.
  Future<MeResponse> me();

  /// `PATCH /me` `{"displayName": …}` → the updated user + wallet. 400
  /// `invalid_name` (`details.reason`), 429 `rate_limited` (`Retry-After`).
  /// The server trims, collapses whitespace and NFC-normalizes the name.
  Future<MeResponse> updateDisplayName(String displayName);

  /// `POST /account/link/{provider}`.
  Future<MeResponse> link(ProviderCredential credential);

  /// `DELETE /account` `{"confirm":"DELETE"}` → 204: permanently deletes the
  /// current account (wallet, progress, items, friends, sign-in methods and
  /// device binding) and ends its session. 401 when the session or the
  /// account no longer exists; never version-gated.
  Future<void> deleteAccount();
}

/// The literal confirmation `DELETE /account` requires (never localized).
const deleteAccountConfirmation = 'DELETE';

class RestAuthApi implements AuthApi {
  RestAuthApi(this._api);

  final ApiClient _api;

  @override
  Future<AuthResponse> createGuest({String? deviceId}) async =>
      AuthResponse.fromJson(
        await _api.post(
          '/auth/guest',
          auth: false,
          body: {'deviceId': ?deviceId},
        ),
      );

  @override
  Future<AuthResponse> resumeDevice(String deviceId) async =>
      AuthResponse.fromJson(
        await _api.post(
          '/auth/device/resume',
          auth: false,
          body: {'deviceId': deviceId},
        ),
      );

  @override
  Future<void> bindDevice(String deviceId) async {
    await _api.put('/account/device', body: {'deviceId': deviceId});
  }

  @override
  Future<AuthResponse> resumeGuest(String guestSecret) async =>
      AuthResponse.fromJson(
        await _api.post(
          '/auth/guest/resume',
          auth: false,
          body: {'guestSecret': guestSecret},
        ),
      );

  @override
  Future<AuthResponse> signIn(ProviderCredential credential) async =>
      AuthResponse.fromJson(
        await _api.post(
          '/auth/${credential.pathSegment}',
          auth: false,
          body: credential.toJson(),
        ),
      );

  @override
  Future<void> logout(String refreshToken, {String? accessToken}) async {
    await _api.post(
      '/auth/logout',
      auth: false,
      bearer: accessToken,
      body: {'refreshToken': refreshToken},
    );
  }

  @override
  Future<MeResponse> me() async => MeResponse.fromJson(await _api.get('/me'));

  @override
  Future<MeResponse> updateDisplayName(String displayName) async =>
      MeResponse.fromJson(
        await _api.patch('/me', body: {'displayName': displayName}),
      );

  @override
  Future<void> deleteAccount() async {
    await _api.delete(
      '/account',
      body: const {'confirm': deleteAccountConfirmation},
    );
  }

  @override
  Future<MeResponse> link(ProviderCredential credential) async =>
      MeResponse.fromJson(
        await _api.post(
          '/account/link/${credential.pathSegment}',
          body: credential.toJson(),
        ),
      );
}

final authApiProvider = Provider<AuthApi>(
  (ref) => RestAuthApi(ref.watch(apiClientProvider)),
);
