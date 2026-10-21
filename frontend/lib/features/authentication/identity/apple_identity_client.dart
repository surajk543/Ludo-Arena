import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_models.dart';
import '../data/provider_credential.dart';
import 'identity_provider_client.dart';

/// Sign in with Apple: native on iOS; on Android via Apple's web flow when
/// `APPLE_SERVICE_ID` and `APPLE_REDIRECT_URI` are configured (the backend's
/// `/auth/apple/callback` redirects back into the app).
class AppleIdentityClient implements IdentityProviderClient {
  AppleIdentityClient({required this._config, required this._platform});

  final AppConfig _config;
  final String _platform;

  @override
  LinkedProvider get provider => LinkedProvider.apple;

  @override
  bool get isAvailable => _config.appleEnabledFor(_platform);

  @override
  Future<ProviderCredential?> obtainCredential() async {
    if (!isAvailable) {
      throw const IdentityProviderException(IdentityFailure.notConfigured);
    }
    final rawNonce = Nonce.generateRaw();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.fullName],
        nonce: Nonce.sha256Hex(rawNonce),
        webAuthenticationOptions: _platform == 'android'
            ? WebAuthenticationOptions(
                clientId: _config.appleServiceId,
                redirectUri: Uri.parse(_config.appleRedirectUri),
              )
            : null,
      );
      final token = credential.identityToken;
      if (token == null || token.isEmpty) {
        throw const IdentityProviderException(
          IdentityFailure.failed,
          'no identity token',
        );
      }
      return AppleCredential(
        identityToken: token,
        rawNonce: rawNonce,
        givenName: credential.givenName,
        familyName: credential.familyName,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw IdentityProviderException(IdentityFailure.failed, e.code.name);
    } on SignInWithAppleNotSupportedException {
      throw const IdentityProviderException(IdentityFailure.notConfigured);
    } on SignInWithAppleException catch (e) {
      throw IdentityProviderException(IdentityFailure.failed, '$e');
    } on PlatformException catch (e) {
      throw IdentityProviderException(IdentityFailure.failed, e.code);
    } on MissingPluginException {
      throw const IdentityProviderException(IdentityFailure.notConfigured);
    }
  }

  /// Apple has no SDK-side session to clear.
  @override
  Future<void> signOut() async {}
}
