import '../../l10n/generated/app_localizations.dart';

/// Every error code the app can localize: WebSocket protocol codes
/// (websocket-protocol.md §9), REST codes (rest-api.md) and client-side
/// pseudo codes (`ClientErrorCodes`, realtime `timeout`).
abstract final class KnownErrorCodes {
  static const Set<String> all = {
    'bad_request',
    'unknown_type',
    'rate_limited',
    'unauthorized',
    'update_required',
    'maintenance',
    'not_in_room',
    'room_not_found',
    'room_full',
    'room_in_progress',
    'room_closed',
    'already_in_room',
    'not_host',
    'not_enough_players',
    'players_not_ready',
    'not_your_turn',
    'invalid_phase',
    'illegal_move',
    'stale_state',
    'insufficient_funds',
    'invalid_code',
    'rematch_closed',
    'not_friends',
    'item_not_owned',
    'bots_unavailable',
    'bots_not_allowed',
    'internal',
    'client_version_required',
    'environment_mismatch',
    'invalid_credential',
    'refresh_reused',
    'session_replaced',
    'forbidden',
    'not_found',
    'identity_conflict',
    'provider_already_linked',
    'already_owned',
    'already_claimed',
    'already_friends',
    'not_completed',
    'item_locked',
    'provider_unavailable',
    'network_error',
    'timeout',
    'bad_response',
    'cancelled',
    'not_connected',
  };

  /// Codes for which retrying the same action later can succeed without the
  /// user changing anything.
  static const Set<String> retryable = {
    'rate_limited',
    'maintenance',
    'internal',
    'provider_unavailable',
    'network_error',
    'timeout',
    'bad_response',
    'not_connected',
    'stale_state',
    'bots_unavailable',
  };
}

/// Localized, user-facing text for an error [code]. Unknown codes map to a
/// generic message. Pass [retryAfter] (e.g. `ApiException.retryAfter`) to get
/// a precise rate-limit message.
///
/// ```dart
/// final text = localizedErrorMessage(AppLocalizations.of(context), e.code);
/// ```
String localizedErrorMessage(
  AppLocalizations l10n,
  String code, {
  Duration? retryAfter,
}) {
  if (code == 'rate_limited' &&
      retryAfter != null &&
      retryAfter.inSeconds > 0) {
    return l10n.errorRateLimitedRetry(retryAfter.inSeconds);
  }
  return switch (code) {
    'bad_request' => l10n.errorBadRequest,
    'unknown_type' => l10n.errorUnknownType,
    'rate_limited' => l10n.errorRateLimited,
    'unauthorized' => l10n.errorUnauthorized,
    'update_required' => l10n.errorUpdateRequired,
    'maintenance' => l10n.errorMaintenance,
    'not_in_room' => l10n.errorNotInRoom,
    'room_not_found' => l10n.errorRoomNotFound,
    'room_full' => l10n.errorRoomFull,
    'room_in_progress' => l10n.errorRoomInProgress,
    'room_closed' => l10n.errorRoomClosed,
    'already_in_room' => l10n.errorAlreadyInRoom,
    'not_host' => l10n.errorNotHost,
    'not_enough_players' => l10n.errorNotEnoughPlayers,
    'players_not_ready' => l10n.errorPlayersNotReady,
    'not_your_turn' => l10n.errorNotYourTurn,
    'invalid_phase' => l10n.errorInvalidPhase,
    'illegal_move' => l10n.errorIllegalMove,
    'stale_state' => l10n.errorStaleState,
    'insufficient_funds' => l10n.errorInsufficientFunds,
    'invalid_code' => l10n.errorInvalidCode,
    'rematch_closed' => l10n.errorRematchClosed,
    'not_friends' => l10n.errorNotFriends,
    'item_not_owned' => l10n.errorItemNotOwned,
    'bots_unavailable' => l10n.errorBotsUnavailable,
    'bots_not_allowed' => l10n.errorBotsNotAllowed,
    'internal' => l10n.errorInternal,
    'client_version_required' => l10n.errorClientVersionRequired,
    'environment_mismatch' => l10n.errorEnvironmentMismatch,
    'invalid_credential' => l10n.errorInvalidCredential,
    'refresh_reused' => l10n.errorRefreshReused,
    'session_replaced' => l10n.errorSessionReplaced,
    'forbidden' => l10n.errorForbidden,
    'not_found' => l10n.errorNotFound,
    'identity_conflict' => l10n.errorIdentityConflict,
    'provider_already_linked' => l10n.errorProviderAlreadyLinked,
    'already_owned' => l10n.errorAlreadyOwned,
    'already_claimed' => l10n.errorAlreadyClaimed,
    'already_friends' => l10n.errorAlreadyFriends,
    'not_completed' => l10n.errorNotCompleted,
    'item_locked' => l10n.errorItemLocked,
    'provider_unavailable' => l10n.errorProviderUnavailable,
    'network_error' => l10n.errorNetwork,
    'timeout' => l10n.errorTimeout,
    'bad_response' => l10n.errorBadResponse,
    'cancelled' => l10n.errorCancelled,
    'not_connected' => l10n.errorNotConnected,
    'unknown' => l10n.errorGeneric,
    _ => l10n.errorGeneric,
  };
}

/// Whether [code] is worth an automatic or "Retry" affordance.
bool isRetryableCode(String code) => KnownErrorCodes.retryable.contains(code);

/// Whether [code] is one of [KnownErrorCodes.all] (e.g. for bucketing
/// analytics parameters).
bool isKnownErrorCode(String code) => KnownErrorCodes.all.contains(code);
