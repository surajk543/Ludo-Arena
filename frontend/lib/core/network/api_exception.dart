import 'package:flutter/foundation.dart';

/// Client-side pseudo error codes (never sent by the server). They share the
/// `errors` localization area with server codes.
abstract final class ClientErrorCodes {
  /// No connectivity / DNS / socket failure.
  static const network = 'network_error';

  /// Connect/send/receive timeout.
  static const timeout = 'timeout';

  /// The response was not the expected JSON.
  static const badResponse = 'bad_response';

  /// The user cancelled a provider sign-in sheet (handled silently).
  static const cancelled = 'cancelled';

  /// The realtime connection is not open.
  static const notConnected = 'not_connected';

  /// Anything else.
  static const unknown = 'unknown';
}

/// Typed failure for REST calls, mapped from
/// `{"error":{"code","message","details"}}`.
@immutable
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.status,
    this.message = '',
    this.details = const {},
    this.retryAfter,
  });

  /// Server error code (`identity_conflict`, `maintenance`, …) or a
  /// [ClientErrorCodes] value.
  final String code;

  /// HTTP status; 0 for transport failures.
  final int status;

  /// Server-provided English text. Show the localized text for [code]
  /// instead; this is for logs only.
  final String message;
  final Map<String, dynamic> details;

  /// Parsed `Retry-After` on 429.
  final Duration? retryAfter;

  const ApiException.network([String message = ''])
    : this(code: ClientErrorCodes.network, status: 0, message: message);

  const ApiException.timeout()
    : this(code: ClientErrorCodes.timeout, status: 0);

  bool get isNetwork =>
      code == ClientErrorCodes.network || code == ClientErrorCodes.timeout;
  bool get isUnauthorized => status == 401;
  bool get isPolicyBlock => code == 'update_required' || code == 'maintenance';

  @override
  String toString() => 'ApiException($status, $code)';
}
