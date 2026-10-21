import 'package:flutter/services.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_models.dart';
import '../data/provider_credential.dart';
import 'identity_provider_client.dart';

/// Facebook via flutter_facebook_auth 7. On iOS the SDK may return a Limited
/// Login OIDC token (sent with our nonce); otherwise a classic access token.
/// Shown only when `FACEBOOK_ENABLED=true` (the native app id must also be
/// configured, see README).
class FacebookIdentityClient implements IdentityProviderClient {
  FacebookIdentityClient({required this._config});

  final AppConfig _config;

  @override
  LinkedProvider get provider => LinkedProvider.facebook;

  @override
  bool get isAvailable => _config.facebookAvailable;

  @override
  Future<ProviderCredential?> obtainCredential() async {
    if (!isAvailable) {
      throw const IdentityProviderException(IdentityFailure.notConfigured);
    }
    final nonce = Nonce.generateRaw(24);
    final LoginResult result;
    try {
      result = await FacebookAuth.instance.login(
        permissions: const ['public_profile'],
        nonce: nonce,
      );
    } on MissingPluginException {
      // The native SDK did not register (no app id configured).
      throw const IdentityProviderException(IdentityFailure.notConfigured);
    } on PlatformException catch (e) {
      throw IdentityProviderException(IdentityFailure.failed, e.code);
    }
    switch (result.status) {
      case LoginStatus.cancelled:
        return null;
      case LoginStatus.operationInProgress:
        return null;
      case LoginStatus.failed:
        final msg = (result.message ?? '').toLowerCase();
        throw IdentityProviderException(
          msg.contains('network') || msg.contains('connection')
              ? IdentityFailure.network
              : IdentityFailure.failed,
        );
      case LoginStatus.success:
        final token = result.accessToken;
        if (token is LimitedToken) {
          return FacebookCredential.limited(
            idToken: token.tokenString,
            nonce: token.nonce.isNotEmpty ? token.nonce : nonce,
          );
        }
        if (token != null && token.tokenString.isNotEmpty) {
          return FacebookCredential.classic(accessToken: token.tokenString);
        }
        throw const IdentityProviderException(IdentityFailure.failed);
    }
  }

  @override
  Future<void> signOut() async {
    if (!isAvailable) return;
    try {
      await FacebookAuth.instance.logOut();
    } catch (_) {}
  }
}
