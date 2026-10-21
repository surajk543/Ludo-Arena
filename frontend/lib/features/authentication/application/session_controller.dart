import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/token_manager.dart' show SessionEnd;
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../../shared/widgets/cosmetic_names.dart' show cosmeticRarity;
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
  /// The app never signs back in on its own after this.
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

/// Owns the authenticated session. The Go backend owns identity: this
/// controller only exchanges provider credentials for backend sessions and
/// keeps tokens in secure storage (via [TokenManager]).
class SessionController extends Notifier<SessionState> {
  AuthApi get _api => ref.read(authApiProvider);
  SecureSessionStore get _store => ref.read(secureSessionStoreProvider);
  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

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

  /// Startup restore: stored refresh token → `/auth/refresh`; if that is
  /// rejected and the last session was a guest with a stored secret →
  /// `/auth/guest/resume`; else signed out. Never counted as a login.
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
      await _adopt(r);
      if (revokePrevious && previous != null) unawaited(_revoke(previous));
      _analytics.loginSucceeded(method);
      return AuthSucceeded(r.user, isNewUser: r.isNewUser);
    } on ApiException catch (e) {
      _analytics.loginFailed(method);
      return AuthFailed(e.code);
    }
  }

  /// "Play as guest": resumes the guest stored on this device if any,
  /// otherwise creates a new guest account.
  Future<AuthOutcome> continueAsGuest() async {
    _analytics.loginStarted(LoginMethod.guest);
    try {
      final secret = await _store.readGuestSecret();
      if (secret != null) {
        try {
          final r = await _api.resumeGuest(secret);
          await _adopt(r);
          _analytics.guestLoginSucceeded();
          return AuthSucceeded(r.user);
        } on ApiException catch (e) {
          if (!_isCredentialRejected(e)) rethrow;
          await _store.clearGuestSecret();
        }
      }
      final r = await _api.createGuest();
      await _adopt(r);
      _analytics.guestLoginSucceeded();
      return AuthSucceeded(r.user, isNewUser: true);
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
      await _adopt(r);
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

  /// Signs out. [forgetGuest] also deletes the guest secret (only after the
  /// user confirmed losing an unsaved guest account).
  Future<void> logout({required bool forgetGuest}) async {
    final tokens = ref.read(tokenManagerProvider);
    final previous = _currentTokens();
    if (previous != null) unawaited(_revoke(previous));
    await tokens.clear();
    for (final c in ref.read(identityProviderClientsProvider).values) {
      unawaited(c.signOut());
    }
    if (forgetGuest) await _store.clearGuestSecret();
    await _store.writeLastSessionWasGuest(false);
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

  Future<void> _adopt(AuthResponse r, {bool persistTokens = true}) async {
    if (persistTokens) await ref.read(tokenManagerProvider).adopt(r);
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
      // Signed in on another device: never sign back in automatically.
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
