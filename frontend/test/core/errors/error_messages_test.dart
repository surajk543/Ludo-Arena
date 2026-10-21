import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/errors/error_messages.dart';
import 'package:ludo_royale/core/network/api_exception.dart';
import 'package:ludo_royale/core/realtime/realtime_connection.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';

void main() {
  const wsCodes = [
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
  ];
  const restCodes = [
    'bad_request',
    'client_version_required',
    'environment_mismatch',
    'unauthorized',
    'invalid_credential',
    'refresh_reused',
    'forbidden',
    'not_found',
    'invalid_code',
    'identity_conflict',
    'provider_already_linked',
    'already_owned',
    'already_claimed',
    'already_friends',
    'not_completed',
    'insufficient_funds',
    'item_locked',
    'update_required',
    'rate_limited',
    'maintenance',
    'provider_unavailable',
    'internal',
  ];
  const clientCodes = [
    ClientErrorCodes.network,
    ClientErrorCodes.timeout,
    ClientErrorCodes.badResponse,
    ClientErrorCodes.cancelled,
    ClientErrorCodes.notConnected,
    RealtimeCommandException.timeoutCode,
  ];

  for (final locale in AppLocalizations.supportedLocales) {
    group('locale ${locale.languageCode}', () {
      final l10n = lookupAppLocalizations(locale);

      test('every known code has a specific, non-empty message', () {
        for (final code in {...wsCodes, ...restCodes, ...clientCodes}) {
          final text = localizedErrorMessage(l10n, code);
          expect(text, isNotEmpty, reason: code);
          expect(text, isNot(l10n.errorGeneric), reason: code);
          expect(isKnownErrorCode(code), isTrue, reason: code);
        }
      });

      test('unknown codes fall back to the generic message', () {
        expect(localizedErrorMessage(l10n, 'totally_new'), l10n.errorGeneric);
        expect(localizedErrorMessage(l10n, ''), l10n.errorGeneric);
        expect(
          localizedErrorMessage(l10n, ClientErrorCodes.unknown),
          l10n.errorGeneric,
        );
      });

      test('rate limit with Retry-After mentions the wait', () {
        final text = localizedErrorMessage(
          l10n,
          'rate_limited',
          retryAfter: const Duration(seconds: 7),
        );
        expect(text, contains('7'));
      });
    });
  }

  test('translations are real (not English copies)', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final code in [
      'not_your_turn',
      'identity_conflict',
      'network_error',
    ]) {
      for (final lang in ['hi', 'ur', 'ar', 'id']) {
        final other = lookupAppLocalizations(Locale(lang));
        expect(
          localizedErrorMessage(other, code),
          isNot(localizedErrorMessage(en, code)),
          reason: '$lang/$code',
        );
      }
    }
  });

  test('report codes have specific, translated messages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    const codes = [
      'already_reported',
      'report_limit',
      'cannot_report_self',
      'cannot_report_bot',
    ];
    for (final code in codes) {
      expect(isKnownErrorCode(code), isTrue, reason: code);
      expect(localizedErrorMessage(en, code), isNot(en.errorGeneric));
      // Players are never labelled as bots, not even in errors.
      expect(
        localizedErrorMessage(en, code).toLowerCase(),
        isNot(contains('bot')),
      );
      for (final lang in ['hi', 'ur', 'ar', 'id']) {
        final other = lookupAppLocalizations(Locale(lang));
        expect(
          localizedErrorMessage(other, code),
          isNot(localizedErrorMessage(en, code)),
          reason: '$lang/$code',
        );
      }
    }
  });

  test('retryable classification', () {
    expect(isRetryableCode('network_error'), isTrue);
    expect(isRetryableCode('bots_unavailable'), isTrue);
    expect(isRetryableCode('illegal_move'), isFalse);
    expect(isRetryableCode('identity_conflict'), isFalse);
  });
}
