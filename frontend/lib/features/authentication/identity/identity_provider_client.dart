import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../../core/network/api_models.dart';
import '../data/provider_credential.dart';

/// Why acquiring a provider credential failed (cancellation is NOT an error:
/// [IdentityProviderClient.obtainCredential] returns `null`).
enum IdentityFailure {
  /// SDK not configured in this build (missing client id / app id).
  notConfigured,

  /// No connectivity while talking to the provider.
  network,

  /// Anything else reported by the SDK.
  failed,
}

class IdentityProviderException implements Exception {
  const IdentityProviderException(this.failure, [this.detail = '']);

  final IdentityFailure failure;

  /// Diagnostic only — never shown or logged with credentials.
  final String detail;

  @override
  String toString() => 'IdentityProviderException($failure)';
}

/// Acquires a credential from one identity provider's native SDK. The Go
/// backend validates it and owns the session; nothing here talks to Firebase.
abstract interface class IdentityProviderClient {
  LinkedProvider get provider;

  /// Whether the provider is configured/supported on this platform/build.
  bool get isAvailable;

  /// Runs the provider's sign-in UI. Returns `null` when the user cancelled
  /// (handled silently). Throws [IdentityProviderException] on failure.
  Future<ProviderCredential?> obtainCredential();

  /// Clears the provider SDK's own session (best effort, never throws).
  Future<void> signOut();
}

/// Nonce helpers (Apple / Facebook Limited Login).
abstract final class Nonce {
  static final Random _random = Random.secure();

  /// 32 random bytes, base64url without padding.
  static String generateRaw([int bytes = 32]) {
    final data = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64Url.encode(data).replaceAll('=', '');
  }

  /// Lower-case hex SHA-256 of [raw] (what Apple receives and embeds).
  static String sha256Hex(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();
}
