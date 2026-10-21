import 'package:flutter/foundation.dart';

import '../../../core/network/api_models.dart';

/// A credential obtained from an identity provider SDK, exchanged with the Go
/// backend at `POST /auth/{provider}` or `POST /account/link/{provider}`.
/// Never persisted, logged or sent anywhere else.
@immutable
sealed class ProviderCredential {
  const ProviderCredential();

  LinkedProvider get provider;

  /// Request body for the backend.
  Map<String, dynamic> toJson();

  /// Path segment: `google` | `facebook` | `apple`.
  String get pathSegment => provider.name;
}

/// Google ID token (`aud` = the server client id).
final class GoogleCredential extends ProviderCredential {
  const GoogleCredential({required this.idToken});

  final String idToken;

  @override
  LinkedProvider get provider => LinkedProvider.google;

  @override
  Map<String, dynamic> toJson() => {'idToken': idToken};
}

/// Facebook classic access token, or a Limited Login OIDC token + nonce.
final class FacebookCredential extends ProviderCredential {
  const FacebookCredential.classic({required String this.accessToken})
    : idToken = null,
      nonce = null;

  const FacebookCredential.limited({
    required String this.idToken,
    required String this.nonce,
  }) : accessToken = null;

  final String? accessToken;
  final String? idToken;
  final String? nonce;

  @override
  LinkedProvider get provider => LinkedProvider.facebook;

  @override
  Map<String, dynamic> toJson() => accessToken != null
      ? {'accessToken': accessToken}
      : {'idToken': idToken, 'nonce': nonce};
}

/// Apple identity token + the raw nonce whose SHA-256 was sent to Apple.
/// Names are only provided by Apple on the very first authorization.
final class AppleCredential extends ProviderCredential {
  const AppleCredential({
    required this.identityToken,
    required this.rawNonce,
    this.givenName,
    this.familyName,
  });

  final String identityToken;
  final String rawNonce;
  final String? givenName;
  final String? familyName;

  @override
  LinkedProvider get provider => LinkedProvider.apple;

  @override
  Map<String, dynamic> toJson() => {
    'identityToken': identityToken,
    'rawNonce': rawNonce,
    if (givenName != null && givenName!.isNotEmpty) 'givenName': givenName,
    if (familyName != null && familyName!.isNotEmpty) 'familyName': familyName,
  };
}
