import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/device/device_identity.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/token_manager.dart' show SessionEnd;
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../../shared/widgets/cosmetic_names.dart' show cosmeticRarity;
import '../../profile/domain/display_name.dart';
import '../../profile/progression.dart';
import '../../wallet/wallet_controller.dart';
import '../data/auth_api.dart';
import '../data/provider_credential.dart';
import '../identity/identity_providers.dart';

enum SessionStatus { unknown, signedOut, signedIn }

/// Why the user was signed out (for an explanatory banner on login).
enum SignOutReason {
  none,
  userAction,
  expired,

  /// The account signed in on another device (only one device at a time).
  /// The app never signs back in on its own after this (not even on the
  /// next launch) until the user signs in explicitly.
  replaced,
}

@immutable
class SessionState {
  const SessionState({
    this.status = SessionStatus.unknown,
    this.user,
    this.hasStoredGuest = false,
    this.signOutReason = SignOutReason.none,
  });

  final SessionStatus status;

  /// The signed-in user (server-provided; never trust client ids).
  final User? user;

  /// A guest secret is stored on this device (guest can be resumed).
  final bool hasStoredGuest;
  final SignOutReason signOutReason;

  bool get isSignedIn => status == SessionStatus.signedIn && user != null;
  bool get isGuest => user?.isGuest ?? false;

  /// "Switch back to guest" is offered when signed into a non-guest account
  /// and a guest secret is still stored on the device.
  bool get canSwitchBackToGuest => isSignedIn && !isGuest && hasStoredGuest;

  SessionState copyWith({
    SessionStatus? status,
    User? user,
    bool clearUser = false,
    bool? hasStoredGuest,
    SignOutReason? signOutReason,
  }) => SessionState(
    status: status ?? this.status,
    user: clearUser ? null : (user ?? this.user),
    hasStoredGuest: hasStoredGuest ?? this.hasStoredGuest,
    signOutReason: signOutReason ?? this.signOutReason,
  );
}

/// Result of the startup restore.
enum RestoreOutcome { restored, signedOut, networkError, policyBlocked }

/// Result of an explicit sign-in.
@immutable
sealed class AuthOutcome {
  const AuthOutcome();
}

final class AuthSucceeded extends AuthOutcome {
  const AuthSucceeded(this.user, {this.isNewUser = false});
  final User user;
  final bool isNewUser;
}

/// The user dismissed the provider sheet: handled silently.
final class AuthCancelled extends AuthOutcome {
  const AuthCancelled();
}

/// [code] is a REST/client error code (see `localizedErrorMessage`).
final class AuthFailed extends AuthOutcome {
  const AuthFailed(this.code);
  final String code;
}

/// Result of Save Progress (`POST /account/link/{provider}`).
@immutable
sealed class LinkOutcome {
  const LinkOutcome();
}

final class LinkSucceeded extends LinkOutcome {
  const LinkSucceeded(this.user, this.provider);
  final User user;
  final LinkedProvider provider;
}

final class LinkCancelled extends LinkOutcome {
  const LinkCancelled();
}

/// 409 `identity_conflict`: the provider identity already has its own
/// account. Nothing was merged or moved. [credential] can be used to sign
/// in to that account instead.
final class LinkConflict extends LinkOutcome {
  const LinkConflict(this.credential);
  final ProviderCredential credential;
  LinkedProvider get provider => credential.provider;
}

/// 409 `provider_already_linked`.
final class LinkAlreadyLinked extends LinkOutcome {
  const LinkAlreadyLinked(this.provider);
  final LinkedProvider provider;
}

final class LinkFailed extends LinkOutcome {
  const LinkFailed(this.code);
  final String code;
}

/// Result of a display-name change (`PATCH /me`).
@immutable
sealed class DisplayNameOutcome {
  const DisplayNameOutcome();
}

/// The server accepted the name; [user] carries it as normalized by the
/// server and is already the session's user.
final class DisplayNameChanged extends DisplayNameOutcome {
  const DisplayNameChanged(this.user);
  final User user;
}

/// [code] is a REST/client error code (`invalid_name`, `rate_limited`,
/// `network_error`, …). [reason] is `details.reason` for `invalid_name`;
/// [retryAfter] the parsed `Retry-After` for `rate_limited`.
final class DisplayNameFailed extends DisplayNameOutcome {
  const DisplayNameFailed(this.code, {this.reason, this.retryAfter});
  final String code;
  final String? reason;
  final Duration? retryAfter;

  /// The rule the server says the name breaks (`invalid_name` only).
  DisplayNameProblem? get problem =>
      code == 'invalid_name' ? DisplayNameProblem.parse(reason) : null;
}

/// Owns the authenticated session. The Go backend owns identity: this
/// controller only exchanges provider credentials for backend sessions and
/// keeps tokens in secure storage (via [TokenManager]).
///
/// Device binding: when the device has an id ([DeviceIdentity]), each
/// human account it signs in to is bound to it (`PUT /account/device`,
/// once per account), so an update or reinstall lands back in the same
/// account (`POST /auth/device/resume`) with its coins and progress.
class SessionController extends Notifier<SessionState> {
  AuthApi get _api => ref.read(authApiProvider);
  SecureSessionStore get _store => ref.read(secureSessionStoreProvider);
  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  /// The account a `PUT /account/device` is in flight for.
  String? _bindingUid;

  @override
  SessionState build() {
    // Creating the ApiClient wires TokenManager.refreshCall (`/auth/refresh`).
    ref.read(apiClientProvider);
    final tokens = ref.read(tokenManagerProvider);
    final subs = <StreamSubscription<dynamic>>[
      tokens.onRefreshed.listen(_onTokensRefreshed),
      tokens.onExpired.listen((end) => unawaited(_onSessionExpired(end))),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    ref.listen<AsyncValue<ProgressionUpdatedEvent>>(
      progressionUpdatesProvider,
      (_, next) {
        final e = next.value;
        if (e != null) applyProgression(e);
      },
    );
    return const SessionState();
  }

  // ---------------------------------------------------------------- restore

  /// Startup restore, never counted as a login:
  /// 1. stored refresh token → `/auth/refresh`;
  /// 2. signed out by the user or by a sign-in on another device → stay
  ///    signed out until an explicit sign-in;
  /// 3. the last session was a guest with a stored secret →
  ///    `/auth/guest/resume` (installs from before device binding);
  /// 4. the device has an id → `/auth/device/resume` (an update or
  ///    reinstall lands back in the device's account; 404 → signed out);
  /// 5. else signed out.
  Future<RestoreOutcome> restore() async {
    final tokens = ref.read(tokenManagerProvider);
    await tokens.load();
    final guestSecret = await _store.readGuestSecret();
    _set(state.copyWith(hasStoredGuest: guestSecret != null));

    if (tokens.hasSession) {
      try {
        final r = await tokens.refreshNow();
        if (r != null) {
          await _adopt(r, persistTokens: false);
          return RestoreOutcome.restored;
        }
      } on ApiException catch (e) {
        if (e.isPolicyBlock) return RestoreOutcome.policyBlocked;
        return RestoreOutcome.networkError;
      }
      // Signed in on another device while this app was closed: tell the
      // user, and do not resume the guest (that would sign the other
      // device out in turn).
      if (tokens.lastEnd == SessionEnd.replaced) {
        await _store.writeLastSessionWasGuest(false);
        await _store.markSessionReplaced();
        _set(
          state.copyWith(
            status: SessionStatus.signedOut,
            clearUser: true,
            signOutReason: SignOutReason.replaced,
          ),
        );
        return RestoreOutcome.signedOut;
      }
    }

    // Signed out by the user, or from another device: resuming the guest or
    // the device's account would undo that (and sign the other device out).
    if (!await _store.readAutoSignInBlocked()) {
      if (guestSecret != null && await _store.readLastSessionWasGuest()) {
        try {
          final r = await _api.resumeGuest(guestSecret);
          await _adopt(r);
          return RestoreOutcome.restored;
        } on ApiException catch (e) {
          if (e.isPolicyBlock) return RestoreOutcome.policyBlocked;
          if (_isCredentialRejected(e)) {
            await _store.clearGuestSecret();
            _set(state.copyWith(hasStoredGuest: false));
          } else {
            return RestoreOutcome.networkError;
          }
        }
      }

      final deviceId = await _deviceId();
      if (deviceId != null) {
        try {
          final r = await _api.resumeDevice(deviceId);
          await _store.writeDeviceBoundUid(r.user.uid);
          await _adopt(r);
          return RestoreOutcome.restored;
        } on ApiException catch (e) {
          if (e.isPolicyBlock) return RestoreOutcome.policyBlocked;
          // 404: no account on this device yet → login screen.
          if (!_isDefinitiveRejection(e)) return RestoreOutcome.networkError;
        }
      }
    }
    _set(
      state.copyWith(
        status: SessionStatus.signedOut,
        clearUser: true,
        signOutReason: SignOutReason.none,
      ),
    );
    return RestoreOutcome.signedOut;
  }

  // ---------------------------------------------------------------- sign-in

  /// Explicit sign-in with Google / Facebook / Apple.
  Future<AuthOutcome> signIn(LinkedProvider provider) async {
    final method = _method(provider);
    _analytics.loginStarted(method);
    final ProviderCredential? credential;
    try {
      credential = await _obtain(provider);
    } on IdentityProviderException catch (e) {
      _analytics.loginFailed(method);
      return AuthFailed(_identityFailureCode(e.failure));
    }
    if (credential == null) return const AuthCancelled();
    return _exchange(credential, method);
  }

  /// Signs in with an already obtained [credential] — used after a Save
  /// Progress conflict ("Sign in to that account"). The guest secret stays
  /// on the device so the user can switch back from Settings.
  Future<AuthOutcome> signInWithCredential(ProviderCredential credential) {
    final method = _method(credential.provider);
    _analytics.loginStarted(method);
    return _exchange(credential, method, revokePrevious: true);
  }

  Future<AuthOutcome> _exchange(
    ProviderCredential credential,
    LoginMethod method, {
    bool revokePrevious = false,
  }) async {
    final previous = _currentTokens();
    try {
      final r = await _api.signIn(credential);
      await _adopt(r, explicit: true);
      if (revokePrevious && previous != null) unawaited(_revoke(previous));
      _analytics.loginSucceeded(method);
      return AuthSucceeded(r.user, isNewUser: r.isNewUser);
    } on ApiException catch (e) {
      _analytics.loginFailed(method);
      return AuthFailed(e.code);
    }
  }

  /// "Play as guest": resumes the guest stored on this device if any,
  /// otherwise `POST /auth/guest` — with the device id the server returns
  /// the device's account (200) or a new guest bound to the device (201).
  Future<AuthOutcome> continueAsGuest() async {
    _analytics.loginStarted(LoginMethod.guest);
    try {
      final secret = await _store.readGuestSecret();
      if (secret != null) {
        try {
          final r = await _api.resumeGuest(secret);
          await _adopt(r, explicit: true);
          _analytics.guestLoginSucceeded();
          return AuthSucceeded(r.user);
        } on ApiException catch (e) {
          if (!_isCredentialRejected(e)) rethrow;
          await _store.clearGuestSecret();
        }
      }
      final deviceId = await _deviceId();
      final r = await _api.createGuest(deviceId: deviceId);
      // Either way the device is now bound to this account.
      if (deviceId != null) await _store.writeDeviceBoundUid(r.user.uid);
      await _adopt(r, explicit: true);
      _analytics.guestLoginSucceeded();
      return AuthSucceeded(r.user, isNewUser: r.isNewUser);
    } on ApiException catch (e) {
      _analytics.loginFailed(LoginMethod.guest);
      return AuthFailed(e.code);
    }
  }

  /// Settings → "Switch back to guest".
  Future<AuthOutcome> switchBackToGuest() async {
    final secret = await _store.readGuestSecret();
    if (secret == null) return const AuthFailed('not_found');
    final previous = _currentTokens();
    try {
      final r = await _api.resumeGuest(secret);
      await _adopt(r, explicit: true);
      if (previous != null) unawaited(_revoke(previous));
      return AuthSucceeded(r.user);
    } on ApiException catch (e) {
      if (_isCredentialRejected(e)) {
        await _store.clearGuestSecret();
        _set(state.copyWith(hasStoredGuest: false));
        return const AuthFailed('not_found');
      }
      return AuthFailed(e.code);
    }
  }

  // ---------------------------------------------------------------- linking

  /// Save Progress: links [provider] to the CURRENT account.
  Future<LinkOutcome> link(LinkedProvider provider) async {
    final ProviderCredential? credential;
    try {
      credential = await _obtain(provider);
    } on IdentityProviderException catch (e) {
      return LinkFailed(_identityFailureCode(e.failure));
    }
    if (credential == null) return const LinkCancelled();
    try {
      final me = await _api.link(credential);
      // A linked account is no longer resumed with the guest secret on
      // launch (that would sign out the account's other device).
      await _store.writeLastSessionWasGuest(me.user.isGuest);
      _adoptProfile(me);
      _analytics.accountLinkSucceeded(_method(provider));
      return LinkSucceeded(me.user, provider);
    } on ApiException catch (e) {
      if (e.code == 'identity_conflict') return LinkConflict(credential);
      if (e.code == 'provider_already_linked') {
        return LinkAlreadyLinked(provider);
      }
      return LinkFailed(e.code);
    }
  }

  // ---------------------------------------------------------------- profile

  /// `GET /me` → user + wallet. Throws [ApiException].
  Future<void> refreshMe() async => _adoptProfile(await _api.me());

  /// Changes the display name (`PATCH /me`). The server validates and
  /// normalizes it; on success the returned user replaces the session's
  /// user, so every screen showing the name updates at once. Never throws.
  Future<DisplayNameOutcome> updateDisplayName(String displayName) async {
    if (!state.isSignedIn) return const DisplayNameFailed('unauthorized');
    try {
      final me = await _api.updateDisplayName(displayName);
      // Not for an account that was left while the request was in flight.
      if (state.user?.uid == me.user.uid) {
        ref.read(walletControllerProvider.notifier).setFromServer(me.wallet);
        updateUser(me.user);
        _analytics.displayNameChanged();
      }
      return DisplayNameChanged(me.user);
    } on ApiException catch (e) {
      final reason = e.details['reason'];
      return DisplayNameFailed(
        e.code,
        reason: reason is String ? reason : null,
        retryAfter: e.retryAfter,
      );
    }
  }

  /// Lets feature screens (e.g. the Collection Room after equipping) push
  /// an updated server user.
  void updateUser(User user) {
    if (!state.isSignedIn) return;
    _set(state.copyWith(user: user));
  }

  /// Applies an equipped-loadout change returned by the server.
  void applyLoadout(Loadout loadout) {
    final u = state.user;
    if (u == null) return;
    updateUser(u.copyWith(loadout: loadout, title: loadout.title));
  }

  /// Applies `progression.updated` (server-authoritative XP/level).
  void applyProgression(ProgressionUpdatedEvent e) {
    final u = state.user;
    if (u == null) return;
    _set(
      state.copyWith(
        user: u.copyWith(
          xp: e.xp,
          level: e.level,
          levelXp: LevelMath.levelStart(e.level),
          nextLevelXp: LevelMath.toNext(e.level),
        ),
      ),
    );
    if (e.levelUp) _analytics.levelUp(e.level);
    for (final id in e.unlocked) {
      _analytics.cosmeticUnlocked(catalogKindOf(id), catalogRarityOf(id));
    }
  }

  // ---------------------------------------------------------------- logout

  /// Signs out. [forgetGuest] also deletes the guest secret and unbinds the
  /// device from the account (only after the user confirmed losing an
  /// unsaved guest account; otherwise the device would restore it). The app
  /// does not sign in on its own again until the user signs in.
  Future<void> logout({required bool forgetGuest}) async {
    final tokens = ref.read(tokenManagerProvider);
    // Needs the still-valid session, so before the revoke (an expiring
    // access token may be refreshed here: read the tokens after it).
    if (forgetGuest) await _unbindDevice();
    final previous = _currentTokens();
    if (previous != null) unawaited(_revoke(previous));
    await tokens.clear();
    for (final c in ref.read(identityProviderClientsProvider).values) {
      unawaited(c.signOut());
    }
    if (forgetGuest) await _store.clearGuestSecret();
    await _store.writeLastSessionWasGuest(false);
    await _store.markSignedOut();
    final hasGuest = await _store.readGuestSecret() != null;
    _signedOut(SignOutReason.userAction, hasStoredGuest: hasGuest);
  }

  // ---------------------------------------------------------------- internals

  Future<ProviderCredential?> _obtain(LinkedProvider provider) {
    final client = ref.read(identityProviderClientsProvider)[provider];
    if (client == null || !client.isAvailable) {
      throw const IdentityProviderException(IdentityFailure.notConfigured);
    }
    return client.obtainCredential();
  }

  /// [explicit]: the user signed in (not a restore), which lifts the block
  /// on automatic sign-in set by a sign-out.
  Future<void> _adopt(
    AuthResponse r, {
    bool persistTokens = true,
    bool explicit = false,
  }) async {
    if (persistTokens) await ref.read(tokenManagerProvider).adopt(r);
    if (explicit) await _store.clearAutoSignInBlock();
    await _store.writeLastSessionWasGuest(r.user.isGuest);
    if (r.guestSecret != null && r.guestSecret!.isNotEmpty) {
      await _store.writeGuestSecret(r.guestSecret!);
    }
    final hasGuest = await _store.readGuestSecret() != null;
    ref.read(walletControllerProvider.notifier).setFromServer(r.wallet);
    _analytics.setActorType(r.user.actorType);
    _set(
      SessionState(
        status: SessionStatus.signedIn,
        user: r.user,
        hasStoredGuest: hasGuest,
      ),
    );
    unawaited(_bindDevice(r.user));
  }

  /// The device id, or null (no id on this platform/version, or it could
  /// not be read). Never logged.
  Future<String?> _deviceId() async {
    try {
      return await ref.read(deviceIdentityProvider).deviceId();
    } catch (_) {
      return null;
    }
  }

  /// Best effort, once per account: binds this device to [user]'s account
  /// so a reinstall restores it. Also migrates accounts created before
  /// device binding. A 409 `identity_conflict` (the device already belongs
  /// to another account, which keeps it) is final and silent; other
  /// failures are retried after the next sign-in or launch.
  Future<void> _bindDevice(User user) async {
    if (!user.isHuman || _bindingUid == user.uid) return;
    _bindingUid = user.uid;
    try {
      final deviceId = await _deviceId();
      if (deviceId == null) return;
      if (await _store.readDeviceBoundUid() == user.uid) return;
      try {
        await _api.bindDevice(deviceId);
      } on ApiException catch (e) {
        if (e.code != 'identity_conflict') return;
      }
      // Not for an account that was left meanwhile.
      if (state.user?.uid == user.uid) {
        await _store.writeDeviceBoundUid(user.uid);
      }
    } catch (_) {
      // Best effort.
    } finally {
      if (_bindingUid == user.uid) _bindingUid = null;
    }
  }

  /// Best effort `DELETE /account/device` with the current session.
  Future<void> _unbindDevice() async {
    if (!ref.read(tokenManagerProvider).hasSession) return;
    if (await _deviceId() == null) return;
    try {
      await _api.unbindDevice().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best effort: signing out must not depend on the network.
    } finally {
      await _store.clearDeviceBoundUid();
    }
  }

  void _adoptProfile(MeResponse me) {
    ref.read(walletControllerProvider.notifier).setFromServer(me.wallet);
    _analytics.setActorType(me.user.actorType);
    if (state.status == SessionStatus.signedIn) {
      _set(state.copyWith(user: me.user));
    }
  }

  void _onTokensRefreshed(AuthResponse r) {
    if (!state.isSignedIn) return;
    ref.read(walletControllerProvider.notifier).setFromServer(r.wallet);
    _set(state.copyWith(user: r.user));
  }

  Future<void> _onSessionExpired(SessionEnd end) async {
    if (!state.isSignedIn) return;
    final secret = await _store.readGuestSecret();
    if (end == SessionEnd.replaced) {
      // Signed in on another device: never sign back in automatically, not
      // even on the next launch (the guest secret stays for an explicit
      // "Play as guest").
      await _store.writeLastSessionWasGuest(false);
      await _store.markSessionReplaced();
      _signedOut(SignOutReason.replaced, hasStoredGuest: secret != null);
      return;
    }
    // A guest whose refresh token died can be resumed silently.
    if (state.isGuest && secret != null) {
      try {
        await _adopt(await _api.resumeGuest(secret));
        return;
      } on ApiException catch (e) {
        if (_isCredentialRejected(e)) await _store.clearGuestSecret();
      }
    }
    final hasGuest = await _store.readGuestSecret() != null;
    _signedOut(SignOutReason.expired, hasStoredGuest: hasGuest);
  }

  void _signedOut(SignOutReason reason, {required bool hasStoredGuest}) {
    ref.read(walletControllerProvider.notifier).clear();
    _analytics.setActorType(null);
    _set(
      SessionState(
        status: SessionStatus.signedOut,
        hasStoredGuest: hasStoredGuest,
        signOutReason: reason,
      ),
    );
  }

  /// The session being left, for a best-effort revoke. The access token is
  /// only sent while still valid; the server falls back to the refresh token.
  ({String refresh, String? access})? _currentTokens() {
    final tokens = ref.read(tokenManagerProvider);
    final refresh = tokens.refreshToken;
    if (refresh == null) return null;
    final access = tokens.accessValidFor(const Duration(seconds: 5))
        ? tokens.accessToken
        : null;
    return (refresh: refresh, access: access);
  }

  Future<void> _revoke(({String refresh, String? access}) session) async {
    try {
      await _api.logout(session.refresh, accessToken: session.access);
    } catch (_) {
      // Best effort: the session expires server-side anyway.
    }
  }

  void _set(SessionState s) {
    if (ref.mounted) state = s;
  }

  static bool _isCredentialRejected(ApiException e) =>
      e.status == 401 || e.status == 403 || e.status == 404;

  /// A 4xx answer that a retry would not change (unlike network failures,
  /// 5xx, 408 and 429).
  static bool _isDefinitiveRejection(ApiException e) =>
      e.status >= 400 && e.status < 500 && e.status != 408 && e.status != 429;

  static LoginMethod _method(LinkedProvider p) => switch (p) {
    LinkedProvider.google => LoginMethod.google,
    LinkedProvider.facebook => LoginMethod.facebook,
    LinkedProvider.apple => LoginMethod.apple,
    LinkedProvider.guest => LoginMethod.guest,
  };

  static String _identityFailureCode(IdentityFailure f) => switch (f) {
    IdentityFailure.notConfigured => 'provider_unavailable',
    IdentityFailure.network => ClientErrorCodes.network,
    IdentityFailure.failed => ClientErrorCodes.unknown,
  };
}

/// Slot/kind of a catalog item id (`ludo_board_royal` → `ludo_board`).
String catalogKindOf(String itemId) {
  for (final k in const ['ludo_board', 'snakes_board']) {
    if (itemId.startsWith('${k}_')) return k;
  }
  final i = itemId.indexOf('_');
  return i > 0 ? itemId.substring(0, i) : itemId;
}

/// Rarity of a catalog item (docs/cosmetics-catalog.md), `common` if unknown.
String catalogRarityOf(String itemId) => cosmeticRarity(itemId).name;

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
