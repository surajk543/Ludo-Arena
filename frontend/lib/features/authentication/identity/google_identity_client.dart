import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_models.dart';
import '../data/provider_credential.dart';
import 'identity_provider_client.dart';

/// Google via google_sign_in 7 (`initialize` once, then `authenticate`).
class GoogleIdentityClient implements IdentityProviderClient {
  GoogleIdentityClient({required this._config, required this._platform});

  final AppConfig _config;
  final String _platform;
  Future<void>? _init;

  @override
  LinkedProvider get provider => LinkedProvider.google;

  @override
  bool get isAvailable => _config.googleEnabledFor(_platform);

  Future<void> _ensureInitialized() => _init ??= GoogleSignIn.instance
      .initialize(
        clientId: _platform == 'ios' ? _config.googleIosClientId : null,
        serverClientId: _config.googleServerClientId,
      )
      .catchError((Object e) {
        _init = null;
        throw e;
      });

  @override
  Future<ProviderCredential?> obtainCredential() async {
    if (!isAvailable) {
      throw const IdentityProviderException(IdentityFailure.notConfigured);
    }
    try {
      await _ensureInitialized();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const IdentityProviderException(IdentityFailure.notConfigured);
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const IdentityProviderException(
          IdentityFailure.failed,
          'no id token',
        );
      }
      return GoogleCredential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
          return null;
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw IdentityProviderException(
            IdentityFailure.notConfigured,
            e.code.name,
          );
        default:
          throw IdentityProviderException(IdentityFailure.failed, e.code.name);
      }
    } on PlatformException catch (e) {
      final network = e.code.toLowerCase().contains('network');
      throw IdentityProviderException(
        network ? IdentityFailure.network : IdentityFailure.failed,
        e.code,
      );
    } on MissingPluginException {
      throw const IdentityProviderException(IdentityFailure.notConfigured);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (_init != null) await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
