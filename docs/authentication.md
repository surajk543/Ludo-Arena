# Authentication & Accounts

**Firebase Authentication is not used anywhere.** Identity providers (Google,
Facebook, Apple) only *prove who the user is*; the Go backend
(`backend/internal/auth`) creates and owns the application account and
session. Firebase is present in the Flutter app for **Analytics only**.

## Flow

1. The player taps *Continue with Google / Facebook / Apple* or *Continue as Guest*.
2. Flutter runs the provider SDK flow and obtains a provider credential
   (Google ID token; Apple identity token + raw nonce; Facebook Limited Login
   ID token + nonce, or a classic access token). Guests skip this step.
3. Flutter sends the credential to `POST /api/v1/auth/{provider}` (HTTPS).
4. Go verifies it with the provider's official mechanism:
   - **Google / Apple / Facebook Limited Login** — OIDC JWT verified by
     `coreos/go-oidc` against the provider's published JWKS: signature,
     issuer, expiry, non-empty subject; audience checked against the
     configured client ids (`GOOGLE_CLIENT_IDS`, `APPLE_AUDIENCES`,
     `FACEBOOK_APP_ID`); Apple: `nonce == sha256(rawNonce)`; Facebook Limited:
     `nonce` equality.
   - **Facebook classic tokens** — Graph API `debug_token` with the app access
     token (`FACEBOOK_APP_ID|FACEBOOK_APP_SECRET`): `is_valid`, matching
     `app_id`, `user_id`, expiry.
   Only the verified `(provider, subject)` is used to find the account. Emails
   are never used to match or merge accounts; client-supplied ids are ignored.
5. Go resolves `(provider, subject)` → internal account id in
   `identity.auth_identities`. If none exists it creates the account **and**
   its wallet (1,000,000 coins, 50 diamonds) in **one PostgreSQL transaction**
   (see "Exactly-once welcome grant").
6. Go issues the application session: a 15-minute HS256 access JWT (`sub` =
   account id, `sid` = session family, `knd`, `act` = actor type) and a
   30-day opaque refresh token. Only hashes of refresh tokens are stored
   (Redis).
7. Flutter stores the tokens in `flutter_secure_storage` and loads `/me` and
   the wallet.

## Guests

`POST /api/v1/auth/guest` creates an account with a random 256-bit **guest
secret** (returned once; stored only as SHA-256 as the `guest` identity
subject). The app keeps it in secure storage. `POST /auth/guest/resume`
signs the guest back in if the refresh token is lost or expired, so a guest
does not depend on Redis-held sessions surviving. Guest creation is rate
limited per IP (10/hour). A guest is never a Firebase anonymous user and never
just a locally generated id.

## Save Progress (linking)

`POST /api/v1/account/link/{google|facebook|apple}` (authenticated) verifies
the credential exactly like sign-in and inserts the identity for the **current
account id**. Coins, diamonds, XP and the collection are untouched; no welcome
grant is issued.

| Outcome | Response |
|---|---|
| Identity unused | 200, `user.isGuest=false`, same `user.id`, same wallet |
| Identity already linked to this account | 200 (idempotent) |
| Identity belongs to **another** account | 409 `identity_conflict` — nothing is merged or moved. The app offers "Sign in to that account instead" (calls `/auth/{provider}` with the same credential) or "Cancel". |
| This account already has a different identity of that provider | 409 `provider_already_linked` |

After linking, signing in with that provider on any device resolves to the same
account id and wallet.

## Sessions

| Item | Storage | Notes |
|---|---|---|
| Access token | client only | HS256, 15 min, verified on every request **and** checked against the live session family (`sess:{sid}`), so logout/revocation (including replacement by a sign-in on another device) is immediate |
| Refresh token | client (secure storage); server keeps `sha256` | Rotated on every use (`POST /auth/refresh`). Presenting an already-rotated token revokes the whole family (`refresh_reused`) |
| Guest secret | client (secure storage); server keeps `sha256` in `identity.auth_identities` | Durable guest recovery |
| Bot sessions | server-issued, room-scoped, ≤ 2 h | See `docs/bot-play.md`; bot status comes only from these tokens |

### One active device per account (last sign-in wins)

An account has **at most one live human session**. Every sign-in that issues
a session (`/auth/guest`, `/auth/guest/resume`, `/auth/{google,facebook,apple}`)
runs one Redis Lua script that creates the new family, points
`usess:{userId}` at it and **deletes the previous family** (if it was still
live), leaving a tombstone `sessrep:{oldSid}` (TTL = refresh TTL). Refresh
rotation keeps the same `sid` and slides the pointer. Linking does not create a
session and replaces nothing. Bot and bot-controller sessions never touch the
pointer; any number of them coexist.

The replaced device then sees, everywhere, the distinct error code
**`session_replaced`** (HTTP 401) instead of the generic one:

| Where | Replaced session | Other dead session (logout, reuse, expiry) |
|---|---|---|
| `POST /auth/refresh` | 401 `session_replaced` | 401 `invalid_credential` / `refresh_reused` |
| Authenticated REST (bearer) | 401 `session_replaced` | 401 `unauthorized` |
| WebSocket upgrade | 401 `session_replaced` | 401 `unauthorized` |
| Live WebSocket | closed **immediately** with `4401` ("session replaced") on whichever instance holds it | closed with `4401` by the 60 s re-check |

The live socket is kicked through a control message on the user's pub/sub
channel (`ev:user:{userId}`, `{"ctl":"revoke","sid":"<oldSid>"}`, never
forwarded to clients); each gateway instance closes only the connection
authenticated with that `sid`. Clients already refresh on `4401`; a
`session_replaced` refresh result means: show "Your account was signed in on
another device", clear the local session and go to the sign-in screen
**without** automatically signing in again (a guest resume would take the
account back and kick the other device).

### Logout

`POST /auth/logout` ends the session with **either** credential: a valid
`Authorization: Bearer <access>` identifies it; otherwise (no, expired or
invalid bearer) the body `{"refreshToken"}` does — but only the family's
**current** refresh token revokes (an old, rotated one is ignored and is not
treated as reuse). The answer is `204` whether or not a session was found;
`400` for a malformed body; `401` only when neither credential is present.
Logout clears `usess:{userId}` only if it still names that session and never
writes a `sessrep:` tombstone, so a logged-out session reads as plainly
revoked (`invalid_credential` / `unauthorized`), never `session_replaced`.
Long-lived WebSockets re-check their session every 60 s and close with `4401`
once revoked.

## Exactly-once welcome grant

```
BEGIN;
  INSERT INTO wallet.wallets (user_id, coins, diamonds) VALUES ($new, 1000000, 50);
  INSERT INTO identity.auth_identities (provider, subject, user_id) VALUES ($p, $s, $new)
    ON CONFLICT (provider, subject) DO NOTHING RETURNING user_id;
  -- no row returned => another request created the account: ROLLBACK (wallet discarded)
COMMIT;
```

Concurrent first sign-ins for the same identity serialize on the
`(provider, subject)` primary key: exactly one transaction commits; the others
roll back and read the winner's account. Verified by
`backend/tests/auth_test.go: TestConcurrentFirstLoginProvisionsOnce` (20
concurrent requests → 1 identity row, 1 wallet).

**Amounts are configurable live** (default 1,000,000 coins / 10 lakh and 50
diamonds). Each new account reads the grant once, just before its
transaction, in this order: `welcome` in the per-environment app-policy file
(`{"coins": 1000000, "diamonds": 50}`, hot-reloaded on `SIGHUP` or file change;
see `docs/app-version-policy.md` → Welcome grant) > `WELCOME_COINS` /
`WELCOME_DIAMONDS` > built-in defaults. A change applies only to accounts
created afterwards; existing accounts are never re-granted or adjusted, and
refresh, guest resume, linking and reconnects never grant. `GET /app/config`
reports the live amounts (`welcome`). Verified by
`backend/tests/welcome_test.go: TestWelcomeGrantLiveFromPolicy` (new amounts
for the next account, existing account unchanged, 12 concurrent first logins →
one grant of the configured amount).

## Storage (approved design)

```
schema wallet:    wallets(user_id PK, coins BIGINT >= 0, diamonds BIGINT >= 0)
schema identity:  auth_identities(provider, subject, user_id → wallet.wallets, created_at,
                                  PK(provider, subject), UNIQUE(user_id, provider))
```

No profile, email or provider-profile columns are stored. Display names and
avatars are presentation data cached in Redis (`profile:{userId}`) and
regenerated if lost.

## Rate limits (Redis fixed windows, per IP or per account)

Sign-in 30/min/IP · guest creation 10/h/IP · refresh and logout 60/min/IP · linking
10/min/account · WebSocket connects 30/min/account · room codes 10/min/account
· matchmaking 20/min/account · app config 120/min/IP.

## Provider configuration

### Google (configured)

Google Cloud project `ludo-royale-63887` (Google Auth Platform: External,
Testing mode, test user added). OAuth clients:

| Client | Purpose | Identifier |
|---|---|---|
| Web application "Ludo Royale Backend (server client ID)" | `serverClientId` in the app; the `aud` the backend accepts (`GOOGLE_CLIENT_IDS`) | `124893613050-93on2291jjunnk5u95lcpk15pk6vgr6c.apps.googleusercontent.com` |
| iOS "Ludo Royale iOS" | iOS sign-in (`GIDClientID`, reversed id as URL scheme) | `124893613050-etb8okpenf0il17tmb33pr3cet8s9jba.apps.googleusercontent.com` |
| Android "Ludo Royale Android (debug)" | package `com.ludoroyale.app` + **debug** SHA-1 `7D:A8:67:75:85:7F:BA:77:64:E4:5C:C3:70:A2:68:DE:10:56:82:20` | `124893613050-nur1fbncr3muucgh0mccibgp6vo36bjr.apps.googleusercontent.com` |

Client ids are public identifiers. The web client's secret is not used (ID
token verification needs none) and is not stored anywhere in this repository.

**Still required for production:** add the release keystore / Play App
Signing SHA-1 as another Android client; move the consent screen out of
Testing (verification) before public launch; add more test users as needed.

### Apple (not yet configured — needs an Apple Developer account)

Enable *Sign in with Apple* for App ID `com.ludoroyale.app`; for Android create
a Services ID and register the return URL
`{PUBLIC_URL}/api/v1/auth/apple/callback`; set `APPLE_AUDIENCES` to the bundle
id and Services ID. The callback endpoint is documented in `rest-api.md`.

### Facebook (not yet configured — needs a Meta app)

Create a Meta app with Facebook Login (Android key hashes for package
`com.ludoroyale.app`, iOS bundle id), set `FACEBOOK_APP_ID` (public) and
`FACEBOOK_APP_SECRET` (server secret, env/secret manager only). Until then the
app hides the Facebook button (`FACEBOOK_ENABLED=false`) and the backend
answers `503 provider_unavailable`.
