import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/network/api_client.dart';
import '../../../core/protocol/json_read.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Meta screens show an explicit error state with Retry instead of
/// Riverpod's automatic background retries.
Duration? noRetry(int retryCount, Object error) => null;

/// Creates a fresh `Idempotency-Key` (8–64 chars `[A-Za-z0-9-_.:]`).
/// Overridden in tests for deterministic keys.
final idempotencyKeyFactoryProvider = Provider<String Function()>((ref) {
  const uuid = Uuid();
  return () => uuid.v4();
});

/// Failures after which the SAME intent may be retried with the SAME
/// Idempotency-Key: the request may or may not have reached the server, so
/// a retry must either replay the stored result or execute exactly once.
bool isTransientFailure(ApiException e) =>
    e.isNetwork ||
    e.status >= 500 ||
    e.status == 429 ||
    e.code == 'request_in_progress' ||
    e.code == ClientErrorCodes.badResponse;

/// Where an error happened, to pick the most helpful message for
/// ambiguous codes like `not_found`.
enum MetaErrorContext { general, mission, friendCode, item }

/// Accepted-friends cap when neither the error nor the friends list says
/// otherwise.
const int kDefaultMaxFriends = 20;

/// Localized message for a meta-feature failure. Server English text is
/// never shown. [maxFriends] (from `GET /friends`) words `friend_limit`;
/// the error's own `details.maxFriends` / `details.max` wins.
String metaErrorMessage(
  AppLocalizations l10n,
  Object error, {
  MetaErrorContext context = MetaErrorContext.general,
  int? maxFriends,
}) {
  if (error is! ApiException) return l10n.errorGeneric;
  switch (error.code) {
    case 'cannot_friend_self':
      return l10n.metaErrorCannotFriendSelf;
    case 'friend_limit':
      final fromError = readIntOrNull(
        error.details['maxFriends'] ?? error.details['max'],
      );
      return l10n.metaErrorFriendLimit(
        fromError ?? maxFriends ?? kDefaultMaxFriends,
      );
    case 'request_in_progress':
      return l10n.metaErrorRequestInProgress;
    case 'idempotency_key_reused':
      return l10n.errorGeneric;
    case 'not_found':
      switch (context) {
        case MetaErrorContext.mission:
          return l10n.metaErrorMissionEnded;
        case MetaErrorContext.friendCode:
          return l10n.metaErrorUnknownFriendCode;
        case MetaErrorContext.item:
        case MetaErrorContext.general:
          break;
      }
  }
  return localizedErrorMessage(l10n, error.code, retryAfter: error.retryAfter);
}

/// Compact, calm duration: `2 d 5 h`, `5 h 12 min`, `12 min`.
String formatMetaDuration(AppLocalizations l10n, Duration d) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return l10n.metaDurationDaysHours(days, hours);
  if (d.inHours > 0) return l10n.metaDurationHoursMinutes(d.inHours, minutes);
  return l10n.metaDurationMinutes(minutes < 1 ? 1 : minutes);
}
