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

## Guest persistence

A guest is the **device guest** — the same account, with the same id, coins,
diamonds, XP, collection and friends — until the player **links** it to
Google/Facebook/Apple (Save Progress) or **deletes** it. Two credentials
restore it, both only for guests: the guest secret (app secure storage) and
the device binding (below).

| Scenario | What happens |
|---|---|
| Guest signs out, taps **Play as guest** | Same guest: the app keeps the guest secret and the binding on sign-out (`POST /auth/guest/resume`, or `POST /auth/guest {"deviceId"}` → 200). There is no "forget this guest" any more; the sign-out dialog says progress stays on the device. Older app versions still drop their guest secret and call `DELETE /account/device`, which now keeps the binding, so they get the same guest back too (on devices with a device id). |
| App updated, or uninstalled and reinstalled on the same device | Same guest: restored on launch (`POST /auth/device/resume`) or by **Play as guest** (`POST /auth/guest {"deviceId"}` → 200). On iOS the keychain usually still holds the tokens and the guest secret as well. |
| Guest links a provider identity that has **no** game account yet | The guest becomes that provider account (same id and progress). In the same transaction its guest secret **and** device binding are deleted: the guest secret now answers 401, `POST /auth/device/resume` 404, and **Play as guest** on the device creates a **new** guest (201, new welcome grant). The saved account is reached only by signing in with the provider. |
| Guest tries to link a provider identity that **already** has its own account | 409 `identity_conflict`; nothing is merged, moved or lost. The guest stays the device guest (secret, binding, progress). If the player then chooses "Sign in to that account instead", the guest stays on the device: Settings → Switch back to guest, or sign out → **Play as guest**. |
| Guest deletes the account | Everything is erased, including both credentials; **Play as guest** creates a new guest. |
| Factory reset, new phone, or a build signed with another key | Not restorable without Save Progress (the device id changes). |

Linked accounts are never bound to a device (`PUT /account/device` → 409
`not_a_guest`), so a provider sign-in on a device never takes the device's
"Play as guest" slot. Guest credentials that an older server version left on a
linked account are ignored (guest resume 401, device resume 404) and such a
binding is released for the device's next guest. Verified by
`backend/tests/guest_persistence_test.go`.

## Device binding (restore after update or reinstall)

Secure storage (tokens, guest secret) does not reliably survive an uninstall
(Android deletes it; the iOS keychain normally keeps it). So that a guest's
coins, diamonds, XP, collection and friends come back after an app **update
or reinstall**, the guest account is bound to a platform device id.

| Platform | Device id the app sends | Survives | Changes on |
|---|---|---|---|
| Android 8.0+ (API ≥ 26) | `Settings.Secure.ANDROID_ID` — scoped to the app-signing key, user and device | app updates, uninstall + reinstall | factory reset; a build signed with a different key (debug vs release / Play App Signing) sees a different id |
| Android < 8 | nothing (ANDROID_ID is shared by every app there) | — | device binding not supported; such guests rely on the guest secret only |
| iOS | a random UUID the app creates once and keeps in the keychain | app updates, uninstall + reinstall on the same device | erasing the device; a new device (unless the keychain item is migrated, depending on the accessibility class the app uses) |

The app sends the id with its normal `X-App-Platform` header:

1. **No stored session** (fresh install, reinstall, lost secure storage):
   `POST /auth/device/resume {"deviceId"}` → 200 signs in to the device's
   guest with nothing lost; 404 `not_found` → the device has no guest (never
   bound, or its guest was linked or deleted).
2. **Continue as Guest**: `POST /auth/guest {"deviceId"}` → 200 if the device
   has a guest (that account, no new account, no second welcome grant, no
   `guestSecret`), else 201: a new guest **and** its device binding are
   created in **one transaction** (concurrent first calls for one device create
   exactly one account — `backend/tests/device_test.go:
   TestConcurrentDeviceGuestCreatesOneAccount`).
3. **Existing guests** (created before device binding or without a device id):
   `PUT /account/device {"deviceId"}` binds the current device to the
   signed-in guest. It is idempotent; a device bound to **another** guest
   answers 409 `identity_conflict` and is never moved; a different device
   already bound to this guest is **replaced** (one device per account); a
   linked account answers 409 `not_a_guest`. Link and bind of one account are
   serialized (advisory lock), so a linked account never keeps a binding.
4. `DELETE /account/device` (204, not version-gated) **keeps** the binding.
   The current app never calls it; app versions before guest persistence call
   it on a guest sign-out ("forget this guest") and drop their guest secret —
   because the binding stays, their next "Play as guest" with the device id is
   still the same guest. A binding ends only with linking or deletion.

Every sign-in through these endpoints is a normal human sign-in and replaces
the account's previous session (see "One active device per account").

**What is stored.** One `identity.auth_identities` row with the internal
provider `device` and

```
subject = hex(HMAC-SHA256(k, platform + ":" + lowercase(deviceId)))
k       = HMAC-SHA256(PUBLIC_ID_KEY, "ludo-arena/device-id/v1")   # domain-separated
```

Changing the label would act like rotating `PUBLIC_ID_KEY` and orphan every
stored binding. The raw device
id is never stored or logged, and the same id on Android and iOS gives
different subjects. `PRIMARY KEY (provider, subject)` gives one
account per device; `UNIQUE (user_id, provider)` one device per account.
`device` is internal: it is never listed in `linkedProviders`, never counts as
linked (an account with only guest + device is still `isGuest: true` and is
offered Save Progress) and cannot be linked through `/account/link/{provider}`.
Rotating `PUBLIC_ID_KEY` orphans every device binding (guests stay reachable
through their guest secret while the app still holds it).

**Validation.** `deviceId`: 16–64 characters `[A-Za-z0-9-]`, compared
case-insensitively; the known-bad Android id `9774d56d682e549c` and values of
one repeated character (all zeros, hyphens ignored) are rejected (400
`bad_request`). The platform must be `android` or `ios` (400 otherwise).

**Privacy and security.** The device identifier is used **only** to restore
the account on the same device: the backend never logs it, never passes it to
analytics and never shows it to other players; the app must not send it
anywhere else either (analytics parameters never carry ids). It acts as a
bearer restore credential for the device's **guest** (never for a linked
account):

- **iOS:** a random UUID v4 (122 random bits) the app generated, in the app's
  own keychain item (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no
  shared access group): other apps cannot read it, it is not restored to
  another device, and keychain items survive an uninstall on the same device.
- **Android 8+:** ANDROID_ID is 64 bits, unique per (app-signing key, user,
  device): another app (different key) on the same phone sees a different
  value, and other devices cannot derive it. Unlike a server-issued secret it
  is not random per install, so anything that can run code **inside** this
  app's process (its own SDKs) or a rooted device can read it — the same reach
  as the app's secure storage, which holds the guest secret and tokens anyway.
- Guessing is impractical: ≥ 2^64 candidates per device, sign-in endpoints
  rate limited per IP (`/auth/device/resume` 30/min, `/auth/guest` 10/h), and
  only the HMAC is stored, so a database leak does not reveal device ids.

Android Auto Backup stays **off** (`android:allowBackup="false"`,
`data_extraction_rules.xml` excludes everything): Keystore-encrypted secure
storage cannot be restored on another device anyway, and backing up the guest
secret in plain form would put a bearer credential into the cloud backup.
Save Progress (linking Google/Apple/Facebook) remains the way to keep an
account across devices, factory resets and app-signing changes.

## Save Progress (linking)

`POST /api/v1/account/link/{google|facebook|apple}` (authenticated) verifies
the credential exactly like sign-in and inserts the identity for the **current
account id**. Coins, diamonds, XP and the collection are untouched; no welcome
grant is issued.

| Outcome | Response |
|---|---|
| Identity unused | 200, `user.isGuest=false`, same `user.id`, same wallet. In the same transaction the account's guest secret and device binding are deleted (`linkedProviders` no longer lists `guest`): it is no longer the device guest — see "Guest persistence" |
| Identity already linked to this account | 200 (idempotent) |
| Identity belongs to **another** account | 409 `identity_conflict` — nothing is merged or moved. The app offers "Sign in to that account instead" (calls `/auth/{provider}` with the same credential) or "Cancel". |
| This account already has a different identity of that provider | 409 `provider_already_linked` |

After linking, signing in with that provider on any device resolves to the same
account id and wallet; "Play as guest" on the device starts a new guest.

## Sessions

| Item | Storage | Notes |
|---|---|---|
| Access token | client only | HS256, 15 min, verified on every request **and** checked against the live session family (`sess:{sid}`), so logout/revocation (including replacement by a sign-in on another device) is immediate |
| Refresh token | client (secure storage); server keeps `sha256` | Rotated on every use (`POST /auth/refresh`). Presenting an already-rotated token revokes the whole family (`refresh_reused`) |
| Guest secret | client (secure storage); server keeps `sha256` in `identity.auth_identities` | Durable guest recovery, kept on sign-out; deleted when the guest is linked or deleted |
| Device binding | client sends the platform device id; server keeps only an HMAC (provider `device`) in `identity.auth_identities` | Restore the device's guest after sign-out, app update or reinstall on the same device (see "Guest persistence", "Device binding") |
| Bot sessions | server-issued, room-scoped, ≤ 2 h | See `docs/bot-play.md`; bot status comes only from these tokens |

### One active device per account (last sign-in wins)

An account has **at most one live human session**. Every sign-in that issues
a session (`/auth/guest`, `/auth/guest/resume`, `/auth/device/resume`,
`/auth/{google,facebook,apple}`)
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

## Deleting an account

Required by Google Play and the App Store for apps with accounts. In the app:
**Settings → Delete account** (guests and linked accounts alike). The app
explains what is deleted, requires an explicit "I understand" confirmation,
then calls:

```
DELETE /api/v1/account
Authorization: Bearer <human access token>
{"confirm":"DELETE"}            → 204 No Content
```

`confirm` is the literal `DELETE` (never localized; anything else → 400
`confirmation_required`). Bots and bot controllers → 403. Not version-gated
(like logout: deleting must work on any app version and during a force
update). Rate limited **5 per hour per account**, wrong confirmations included
(429 `rate_limited`). A second call with the same, now dead, token → 401
`unauthorized`; so does the loser of two concurrent calls. Any 5xx means
nothing was deleted. Implementation: `backend/internal/account`.

**Order of operations**

1. **Active room.** The account leaves its room exactly like `room.leave`: a
   lobby seat is released, a game in progress is **forfeited** and continues
   for the other players (entry fees are not refunded — the rules of leaving
   a game are unchanged), a finished room's rematch is declined.
2. **PostgreSQL, one transaction.** It locks the account's
   `progression.player_progress` row and then its `wallet.wallets` row (the
   lock order of every progression write, so it cannot deadlock with a claim,
   purchase, equip or match record) and deletes, table by table:
   `progression.player_reports` filed **by** the account and filed
   **against** it, `progression.friendships` on **both** sides (accepted and
   pending, sent and received), `mission_progress`, `mission_claims`,
   `match_receipts`, `inventory`, `loadout`, `purchases` (coin pack records),
   `player_progress` (XP, level,
   chosen display name, public id), every `identity.auth_identities` row
   (guest secret hash, **device binding**, Google/Facebook/Apple subjects)
   and finally `wallet.wallets` (coins, diamonds). Concurrent deletions of
   one account serialize on those locks: exactly one commits, the others find
   no account (401). A failure rolls everything back.
3. **Redis** (after the commit; best effort, idempotent — a failure is logged
   and a retry with a still-live session repeats it): every human session is
   revoked (`sess:{sid}` with its current `rt:{hash}`, `usess:{userId}`; no
   `sessrep:` tombstone, so refresh answers 401 `invalid_credential` and REST
   / WebSocket upgrades 401 `unauthorized`); the live WebSocket is closed at
   once with **`4401` and reason `account deleted`** on whichever instance
   holds it (control message `{"ctl":"deleted"}` on `ev:user:{userId}`); a
   room joined in the meantime is left again; then `profile:{userId}`,
   `pubid:{publicId}`, `namechg:{userId}`, `seat:{userId}` (+ lease),
   `emotes:{userId}`, `presence:{userId}`, `botfr:{userId}` (pending friend
   requests to bots), `recent:{userId}` **and** the
   account's entry in every recent opponent's `recent:{otherId}`, its member
   in the last five weekly leaderboards `lb:xp:{week}`, its member in the
   operator statistics (`online:humans`, the hourly play per game
   `ptg:{game}:{hour}`), and its per-account
   rate-limit counters (`rl:{rule}:{userId}:{window}`, incl. the report
   limiters) are deleted. Match records that finish later never re-add a
   deleted account to anyone's recent players, and a payout owed to a
   deleted winner is skipped.

Metric: `account_deletions_total{result}` with `deleted`, `already_deleted`
(lost a concurrent race), `bad_confirm` and `error` (nothing deleted).

**What remains** (no personal data, nothing that identifies the account):

| Data | Why / until |
|---|---|
| HyperLogLog active-user sketches `au:d:*`, `au:w:*` | Pseudonymous HMAC members that cannot be enumerated or removed; expire after 40 days |
| Prometheus counters (e.g. `account_deletions_total{result}`) | Aggregates without ids |
| `idem:{userId}:{key}` (cached claim/purchase responses), `dedup:{userId}:{msgId}`, `invite:{from}:{to}:{roomId}` | Short-lived keys that only the (revoked) account could read; expire within 24 h / 2 min / ≤ 30 min. They cannot be listed without a keyspace scan |
| Rotated refresh-token tombstones `rt:{hash}` → dead session id, older `sessrep:{sid}` tombstones | No account id; expire with the refresh TTL |
| Live rooms the account played in | Seat name/avatar copied at join time, until the room expires (≤ 3 h playing, ~10 min finished) |
| Server logs | The deletion is logged with row counts only (no account, public or provider id) |
| Backups / WAL archives | Until they rotate out (operator retention) |

**Player reports.** Reports **against** the deleted account are deleted too:
`player_reports.reported_id` is `NOT NULL REFERENCES wallet.wallets ON DELETE
CASCADE` (approved schema), and keeping them would need a schema change. The
account no longer exists, so there is nothing left to act on.

**After a deletion** the app forgets everything it held (tokens, guest
secret, device-binding marker, provider SDK session) and lands on the sign-in
screen with "Your account was deleted." — nothing is restored automatically,
not even on the next launch. Because the device binding and every provider
identity are gone, `POST /auth/device/resume` on that device answers 404, and
**Play as guest** on the same device or a Google/Facebook/Apple sign-in with
the same provider account creates a **new** account with a **new** welcome
grant. This is intended: everything of the old account, including its coins,
was deleted.

Verified by `backend/tests/account_delete_test.go`
(`TestDeleteAccountErasesEverything`, `TestDeleteAccountRequestRules`,
`TestConcurrentAccountDeletion`).

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
schema wallet:    wallets(user_id PK, coins BIGINT >= 0, diamonds BIGINT >= 0,
                          is_bot BOOLEAN NOT NULL DEFAULT FALSE)   -- migration 012
                  is_bot rows hold a bot persona's coins: never an account, no identity,
                  never deleted by DELETE /account (backend/docs/game-rules.md "Coins with bots")
schema identity:  auth_identities(provider, subject, user_id → wallet.wallets, created_at,
                                  PK(provider, subject), UNIQUE(user_id, provider))
                  provider ∈ guest | google | facebook | apple | device (internal, migration 004)
```

No profile, email or provider-profile columns are stored. Provider names and
avatars are presentation data cached in Redis (`profile:{userId}`) and
regenerated if lost. A name the player chose (`PATCH /me`) is stored in
`progression.player_progress.display_name` and always wins: provider
sign-ins and linking never overwrite it ([rest-api.md](rest-api.md#changing-the-display-name)).

## Rate limits (Redis fixed windows, per IP or per account)

Sign-in (incl. device resume) 30/min/IP · guest creation (incl. `/auth/guest`
with a `deviceId`) 10/h/IP · refresh and logout 60/min/IP · linking and device
bind/unbind 10/min/account · WebSocket connects 30/min/account · room codes 10/min/account
· matchmaking 20/min/account · account deletion 5/h/account · app config 120/min/IP.

## Provider configuration

### Google (configured)

Google Cloud project `ludo-royale-63887` (Google Auth Platform: External,
**In production** since 2026-10-26: basic scopes only and no logo, so no
Google verification; branding home page `https://sungamestudio.com/ludo-arena`,
privacy policy `/ludo-arena/privacy/`, authorized domain `sungamestudio.com`).
OAuth clients:

| Client | Purpose | Identifier |
|---|---|---|
| Web application "Ludo Arena Backend (server client ID)" | `serverClientId` in the app; the `aud` the backend accepts (`GOOGLE_CLIENT_IDS`) | `124893613050-93on2291jjunnk5u95lcpk15pk6vgr6c.apps.googleusercontent.com` |
| iOS "Ludo Arena iOS" | iOS sign-in (`GIDClientID`, reversed id as URL scheme) | `124893613050-etb8okpenf0il17tmb33pr3cet8s9jba.apps.googleusercontent.com` |
| Android "Ludo Arena Android (debug)" | package `com.sungamestudio.ludoarena` + **debug** SHA-1 `7D:A8:67:75:85:7F:BA:77:64:E4:5C:C3:70:A2:68:DE:10:56:82:20` | `124893613050-nur1fbncr3muucgh0mccibgp6vo36bjr.apps.googleusercontent.com` |
| Android "Ludo Arena Android (Play app signing)" | package `com.sungamestudio.ludoarena` + **Play app signing** SHA-1 `B5:48:E8:65:81:D7:A2:9D:00:B8:50:A9:E9:4C:3A:32:82:5A:06:9B` (installs from Google Play) | `124893613050-0tco9t36svsvu2c3g7deps61t4mmk2ei.apps.googleusercontent.com` |
| Android "Ludo Arena Android (upload key)" | package `com.sungamestudio.ludoarena` + **upload key** SHA-1 `6A:6E:F5:50:C9:CD:EF:D5:2F:3D:0E:11:07:AB:A1:D4:3A:A9:96:CA` (release APKs installed outside Play) | `124893613050-k3jfeen9m0dndl845nghno6jh6nk8aaa.apps.googleusercontent.com` |

The Android package (`com.sungamestudio.ludoarena`, Google Play) differs from
the iOS bundle id (`com.ludoarena.app`). Client ids are public identifiers.
The web client's secret is not used (ID token verification needs none) and is
not stored anywhere in this repository.

Adding a logo or a sensitive scope to the consent screen would require
Google's verification; keep it to basic scopes.

### Apple (not yet configured — needs an Apple Developer account)

Enable *Sign in with Apple* for App ID `com.ludoarena.app` (the iOS bundle
id); for Android create a Services ID and register the return URL
`{PUBLIC_URL}/api/v1/auth/apple/callback`; set `APPLE_AUDIENCES` to the bundle
id and Services ID. The callback redirects to the Android package
`APPLE_ANDROID_PACKAGE` (default `com.sungamestudio.ludoarena`); it is
documented in `rest-api.md`.

### Facebook (not yet configured — needs a Meta app)

Create a Meta app with Facebook Login (Android key hashes for package
`com.sungamestudio.ludoarena`, iOS bundle id `com.ludoarena.app`), set
`FACEBOOK_APP_ID` (public) and
`FACEBOOK_APP_SECRET` (server secret, env/secret manager only). Until then the
app hides the Facebook button (`FACEBOOK_ENABLED=false`) and the backend
answers `503 provider_unavailable`.
