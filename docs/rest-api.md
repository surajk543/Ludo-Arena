# REST API — `/api/v1`

Base URL: `https://<host>/api/v1` (local: `http://localhost:8080/api/v1`).
All bodies are JSON (`Content-Type: application/json`). Times are unix
milliseconds unless the field name ends in `Utc` (ISO-8601 UTC string).

## Common request headers

| Header | Required on | Notes |
|---|---|---|
| `X-App-Platform` | every endpoint except `/healthz`, `/readyz`, `/metrics`, `/legal/open-source`, Apple callback | `android` \| `ios` |
| `X-App-Version` | same | e.g. `1.4.0` (1–4 numeric dot-separated components) |
| `X-App-Build` | same | positive integer build number |
| `Authorization` | protected endpoints | `Bearer <accessToken>` |
| `Idempotency-Key` | purchase / claim endpoints | 8–64 chars; replays return the original result |

Every endpoint behind the version gate answers **426** (`update_required`) or
**503** (`maintenance`) when the app policy blocks the client — see
[`app-version-policy.md`](app-version-policy.md).

## Error shape

```json
{"error": {"code": "identity_conflict", "message": "Human readable text", "details": {}}}
```

| HTTP | Typical codes |
|---|---|
| 400 | `bad_request`, `client_version_required`, `environment_mismatch`, `invalid_name` (details = `{"reason"}`), `confirmation_required` (`DELETE /account`) |
| 401 | `unauthorized`, `invalid_credential`, `refresh_reused`, `session_replaced` |
| 403 | `forbidden` |
| 404 | `not_found`, `invalid_code`, `room_not_found` |
| 409 | `identity_conflict`, `provider_already_linked`, `already_owned`, `already_claimed`, `already_friends`, `already_reported`, `request_in_progress` |
| 422 | `not_completed`, `insufficient_funds`, `item_locked`, `cannot_friend_self`, `friend_limit`, `cannot_report_self`, `not_in_room`, `idempotency_key_reused` |
| 426 | `update_required` (details = policy) |
| 429 | `rate_limited`, `report_limit` (`Retry-After` header; `report_limit` details = `Limit`) |
| 503 | `maintenance` (details = policy), `provider_unavailable`, `assets_unavailable` |

---

## App policy

### `GET /app/config`

Public (rate limited per IP). Query: `platform`, `version`, `build`,
`environment` (or the `X-App-*` headers). Never blocked by the gate itself.

```json
{
  "configVersion": 3,
  "environment": "production",
  "platform": "android",
  "mode": "normal",                      // normal | optional_update | force_update | maintenance
  "installedVersion": "1.2.0",
  "installedBuild": 120,
  "minimumSupportedVersion": "1.2.0",
  "minimumSupportedBuild": 120,
  "latestVersion": "1.4.0",
  "latestBuild": 140,
  "storeUrl": "https://play.google.com/store/apps/details?id=com.ludoroyale.app",
  "storeAvailable": true,
  "title": "Update available",
  "message": "New boards and smoother dice.",
  "optionalUpdateReminderHours": 24,
  "maintenance": {
    "enabled": false,
    "message": "",
    "startsAtUtc": null,
    "scheduledEndUtc": null
  },
  "rulesVersion": 1,
  "protocolVersion": 1,
  "entryFees": {"ludo": 100000, "snakes_ladders": 50000},
  "turnSeconds": 20,
  "welcome": {"coins": 1000000, "diamonds": 50},
  "serverTime": 1761022800000
}
```

`entryFees` are the live coin entry fees for **new** rooms (flat, per player),
read on every request: the app-policy file's `entryFees` (hot-reloaded), else
`ENTRY_FEE_LUDO` / `ENTRY_FEE_SNAKES`, else the defaults 100,000 / 50,000. A
room keeps the fee it was created with; the room snapshot's `entryFee` is what
that room charges (see `docs/app-version-policy.md` → Entry fees).

`welcome` is the live one-time grant for accounts created **from now on**:
the app-policy file's `welcome` (hot-reloaded), else `WELCOME_COINS` /
`WELCOME_DIAMONDS`, else 1,000,000 coins and 50 diamonds. Existing accounts
are never changed (see `docs/app-version-policy.md` → Welcome grant).

---

## Authentication (Go-owned; no Firebase)

All return **AuthResponse**:

```json
{
  "accessToken": "eyJ…",              // JWT, 15 min
  "accessTokenExpiresAt": 1761023700000,
  "refreshToken": "rt_…",             // opaque, 30 days, rotated on every use
  "refreshTokenExpiresAt": 1763614800000,
  "isNewUser": false,
  "user": User,
  "wallet": Wallet,
  "guestSecret": "gs_…"               // ONLY when POST /auth/guest creates a new account (store in secure storage)
}
```

**User**

```json
{
  "id": "6f1d…",                       // internal account id (only ever sent to its owner)
  "uid": "u_3f9a1c2b7d",               // public id shown to others / friend code
  "actorType": "human",                // server-determined: "human" | "bot" (analytics gate)
  "displayName": "Asha",              // chosen name (PATCH /me) if any, else provider name, else "Player XXXX"
  "avatar": 3,
  "isGuest": true,
  "linkedProviders": ["guest"],        // subset of guest|google|facebook|apple (never the internal device binding)
  "level": 4, "xp": 520, "levelXp": 450, "nextLevelXp": 250,   // progress = (xp - levelXp) / nextLevelXp
  "title": "title_rookie",
  "loadout": {"dice": "dice_classic", "token": "token_classic", "ludo_board": "ludo_board_classic",
              "snakes_board": "snakes_board_classic", "frame": "frame_none", "title": "title_rookie",
              "victory": "victory_confetti"},
  "picture": {"id": "pp_wolf", "format": "image", "path": "profile_pictures/image/wolf.png"}   // PlayerPicture or null
}
```

**PlayerPicture** (public, also on friends, leaderboard rows, report
targets and WebSocket seats): `{"id":"pp_wolf","format":"image|lottie","path":"profile_pictures/image/wolf.png"}`
or `null` (the built-in avatar `avatar` is shown). `path` names an object in
the private asset bucket; get a download URL with
[`POST /assets/sign`](#store-profile-pictures). The equipped picture is not
part of `loadout`.

**Wallet**: `{"coins": 1000000, "diamonds": 50}`

| Method & path | Body | Notes |
|---|---|---|
| `POST /auth/guest` | empty, `{}` or `{"deviceId"}` | Without `deviceId`: 201, creates account + wallet (1,000,000 coins, 50 diamonds) + guest credential. With `deviceId` (see [Device binding](#device-binding-restore-after-update-or-reinstall)): **200** `isNewUser:false`, no `guestSecret` — signed in to the account already bound to this device (guest or linked; no new account, no second welcome grant); or **201** `isNewUser:true` + `guestSecret` — new guest created and bound to the device in one transaction. 400 `bad_request` for an invalid `deviceId`. Rate limited per IP (guest-creation budget). |
| `POST /auth/guest/resume` | `{"guestSecret"}` | Signs a guest back in after the refresh token was lost or expired. |
| `POST /auth/device/resume` | `{"deviceId"}` | Signs in to the account bound to this device (guest or linked): 200, `isNewUser:false`, no `guestSecret`. **404 `not_found`** if no account is bound. Never creates an account. 400 `bad_request` for an invalid `deviceId`. Rate limited per IP (sign-in budget). |
| `POST /auth/google` | `{"idToken"}` | Google ID token; `aud` must be a configured Google client id. |
| `POST /auth/facebook` | `{"accessToken"}` or `{"idToken","nonce"}` | Classic token (validated with Graph `debug_token`) or Limited Login OIDC token. |
| `POST /auth/apple` | `{"identityToken","rawNonce","givenName"?,"familyName"?}` | Nonce: `sha256(rawNonce)` must equal the token's `nonce`. |
| `POST /auth/apple/callback` | form post from Apple | Android web flow only: redirects to `intent://callback?…#Intent;package=com.ludoroyale.app;scheme=signinwithapple;end`. Not version-gated. |
| `POST /auth/refresh` | `{"refreshToken"}` | Rotates (same session). Re-use of an old refresh token revokes the whole session (`refresh_reused`). 401 `session_replaced` if the session was ended by a sign-in on another device; `invalid_credential` for other dead sessions. |
| `POST /auth/logout` | `{"refreshToken"}` | Not version-gated; rate limited per IP (shares the refresh budget). `Authorization: Bearer` is **optional**: a valid access token identifies the session; otherwise (absent, expired, invalid) the body's refresh token does, and only the session's *current* refresh token revokes (a rotated one is ignored, not treated as reuse). Always 204 for a well-formed request, whether or not a session was found; 400 malformed body; 401 when neither credential is present. Never produces `session_replaced`. |

**One live session per account.** Every sign-in above (guest, guest resume,
device resume / guest with a bound device, Google/Facebook/Apple) ends the
account's previous session (last sign-in
wins; see [`authentication.md`](authentication.md)). The replaced session
then gets **401 `session_replaced`** from `/auth/refresh` and from every
authenticated endpoint (instead of `invalid_credential` / `unauthorized`), and
its WebSocket is closed with `4401`. Clients show "signed in on another
device" and go to sign-in without re-authenticating automatically.

### Account linking (Save Progress)

`POST /account/link/{provider}` — `provider` ∈ `google|facebook|apple`,
authenticated, same body as the provider login.

- 200 `{"user","wallet"}` — identity linked to **this** account; account id,
  coins, diamonds, XP and collection unchanged; no welcome bonus.
- 409 `identity_conflict` — the provider identity already belongs to another
  account. `details`: `{"provider":"google"}`. Nothing is merged or moved. The
  client offers "Sign in to that account instead" (calls `POST /auth/{provider}`
  with the same credential) or "Cancel".
- 409 `provider_already_linked` — this account already has a different
  identity of that provider.

`device` is not a provider here: `POST /account/link/device` is 404 (use
`PUT /account/device`).

### Device binding (restore after update or reinstall)

A device binding lets the app restore its account after an app update or a
reinstall, when secure storage (tokens, guest secret) may be gone. The client
sends a platform-scoped device id (Android ≥ 8: `Settings.Secure.ANDROID_ID`;
iOS: a random UUID kept in the keychain) together with the usual
`X-App-Platform`. The server stores only
`hex(HMAC-SHA256(k, platform + ":" + lowercase(deviceId)))` — never the raw id;
see [`authentication.md`](authentication.md#device-binding-restore-after-update-or-reinstall).
One device → one account, one device per account. The binding is internal: it
never appears in `linkedProviders`, and an account with only guest + device is
still `isGuest:true` (needs Save Progress).

**Validation** (all device endpoints): `deviceId` is a string of 16–64
characters `[A-Za-z0-9-]`, compared case-insensitively; the known-bad Android
id `9774d56d682e549c` and values made of one repeated character (e.g. all
zeros, hyphens ignored) are rejected → 400 `bad_request`. The platform is
`X-App-Platform`; anything but `android` / `ios` is rejected by the version
gate → 400 `client_version_required`. The same `deviceId` on `android` and
`ios` is two different devices.

| Method & path | Auth | Body | Responses |
|---|---|---|---|
| `POST /auth/guest` | none | `{"deviceId"}` | 200 sign-in to the bound account / 201 new guest bound to the device (see the table above) |
| `POST /auth/device/resume` | none | `{"deviceId"}` | 200 AuthResponse / 404 `not_found` |
| `PUT /account/device` | human | `{"deviceId"}` | **200 `{}`**: bound to the caller's account. Idempotent if already bound to the caller. If the caller had a different device bound, that binding is **replaced** (moved to a new phone). **409 `identity_conflict`** (no `details`) if the device is bound to **another** account — it is never moved. Rate limited 10/min/account (shared with linking). |
| `DELETE /account/device` | human | — | **204**, idempotent: removes the caller's device binding (e.g. "forget this guest" on logout). The account itself is untouched. Like logout, **not version-gated**. Rate limited 10/min/account (shared with linking). |

### Deleting the account

`DELETE /account` — app: **Settings → Delete account**. Permanently deletes
the caller's account and everything tied to it; see
[`authentication.md` → Deleting an account](authentication.md#deleting-an-account)
for exactly what is deleted and what remains.

| | |
|---|---|
| Auth | Human access token only (`Authorization: Bearer`); bot and bot-controller tokens → **403** `forbidden` |
| Body | Exactly `{"confirm":"DELETE"}` — the literal `DELETE`, never localized. Missing, different (e.g. `"delete"`) or extra fields → **400** `confirmation_required` (nothing deleted) |
| Success | **204**, no body. The account leaves its active room (a game in progress is forfeited and continues for the others), every PostgreSQL row of it is deleted in one transaction (wallet, all sign-in identities incl. the device binding, XP/level/display name, missions and claims, receipts, inventory, loadout, friendships on both sides, reports filed by and against it), every session is revoked and its WebSocket is closed with `4401` reason `account deleted` |
| Afterwards | The same token (or the loser of two concurrent calls) → **401** `unauthorized`; refresh → 401 `invalid_credential`; `POST /auth/device/resume` on that device → 404; `POST /auth/guest {"deviceId"}` there or a provider sign-in with the same provider account → a **new** account with a new welcome grant |
| Errors | 401 `unauthorized` / `session_replaced`, 403 `forbidden`, 429 `rate_limited` (5 requests/h/account, wrong confirmations included; `Retry-After`), 5xx = nothing was deleted (retry) |
| Gate | **Not version-gated** (works on every app version, like logout); `X-App-*` headers optional |

### Profile & wallet

| Method & path | Response |
|---|---|
| `GET /me` | `{"user": User, "wallet": Wallet}` |
| `PATCH /me` | Body `{"displayName": "…"}` → 200 `{"user": User, "wallet": Wallet}` (same as `GET /me`, with the new name). See [Changing the display name](#changing-the-display-name). |
| `GET /wallet` | `Wallet` |

### Changing the display name

`PATCH /me` with `{"displayName": "Asha Verma"}`. Authenticated **humans
only** (bot and bot-controller tokens → 403 `forbidden`); version gated. The
body must contain exactly `displayName` as a string: a missing or `null`
value, another type or any unknown field → 400 `bad_request`.

The server is authoritative and stores the **normalized** name: Unicode NFC,
leading/trailing whitespace removed, every internal whitespace run collapsed
to one space (case is kept). The response carries the stored form.

Rules, checked in this order → **400 `invalid_name`** with
`details.reason`:

| `details.reason` | Rule |
|---|---|
| `too_short` | fewer than 3 characters (Unicode code points, after normalization) |
| `too_long` | more than 16 characters |
| `invalid_characters` | only Unicode letters, combining marks (Mn/Mc, e.g. Hindi matras, Arabic harakat; directly after a letter, at most 4 in a row), decimal digits, space, `_`, `.`, `-`; at least one letter. Rejected: emoji and other symbols, punctuation, control and format characters (zero-width joiner/space, bidi controls), enclosing marks (keycaps), variation selectors, invisible fillers (e.g. U+3164). |
| `reserved` | after lower-casing, removing spaces/`_`/`.`/`-`, folding look-alikes (`0→o`, `1→i`, `4→a`, `ａ→a`, Cyrillic `а→a`, …) and accents: starts with `bot` (bots are shown as "Bot …"), or contains `admin`, `moderator`, `support`, `official`, `system`, `ludoroyale` (also "Ludo Royale") |
| `inappropriate` | contains an entry of the server blocklist (same folding; a starting list in English and Hindi/Urdu, Indonesian and Arabic transliterations that operators extend: `backend/internal/profile/blocklist.txt`) |

Example: `{"error":{"code":"invalid_name","message":"This name is reserved. Please choose another one.","details":{"reason":"reserved"}}}`.
Clients localize from `details.reason`, not from `message`.

**Limit:** at most `NAME_CHANGES_PER_DAY` (default **3**) successful
changes per account per **rolling 24 h** → **429 `rate_limited`** with a
`Retry-After` header (seconds until the oldest change leaves the window) and
`details` `{"reason":"name_change_limit","limit":3}`. Not counted: setting
the current name again (200, no-op), invalid names, and pinning the name
currently shown (provider or generated name) as the chosen one. The route also
has the usual abuse limit of 20 requests/min/account (429 `rate_limited`
without `details`).

**Where the name applies:** the chosen name is stored in PostgreSQL and
always wins over provider names — later Google/Facebook/Apple sign-ins,
linking and guest/device sign-ins never overwrite it (accounts that never
chose a name keep the provider's or a generated name, as before). Friends
lists, the friends leaderboard, recent players, friend-request and invite
pushes, room previews (`hostName`) and **rooms joined afterwards** show the
new name. Seats in rooms that were already open or playing keep the name the
player joined with (room snapshots are not rewritten).

### Rooms

| Method & path | Response |
|---|---|
| `GET /rooms/code/{code}` | `{"game","variant","capacity","players","status","entryFee","hostName"}`; 404 `invalid_code`. Rate limited 10/min/user. Joining happens over WebSocket (`room.join`). |

---

## Progression

XP and levels: `nextLevelXp(level) = 100 + 50 × (level − 1)` XP from `level` to
`level + 1`; max level 50. XP sources (server-side only): completed eligible
match 20, win bonus 15, match with a friend 5, mission rewards.

Field meaning (here and in `User`): `levelXp` = total XP at which the current
level started (`100(L−1) + 25(L−1)(L−2)`), `nextLevelXp` = XP needed to go
from the current level to the next (the formula above). Progress bar =
`(xp − levelXp) / nextLevelXp`. Example: level 4 → `levelXp` 450,
`nextLevelXp` 250 (level 5 at 700 XP; the `User` example above shows the
level-5 threshold 700 instead). At level 50 XP keeps growing, `levelXp` stays
63,700 and `nextLevelXp` 2,550 (show "MAX"; the bar clamps full).

Eligible match (anti-farming): the player did not forfeit, made ≥ 3 own
rolls/moves, and the match lasted ≥ 30 s. Bots never earn XP. Details:
[`progression.md`](progression.md).

All routes below: authenticated humans, version gated. Rate limits per
account: reads 120/min, claims and purchases 30/min, loadout 60/min.

| Method & path | Body | Response |
|---|---|---|
| `GET /progression` | – | `{"level","xp","levelXp","nextLevelXp","maxLevel":50,"title","milestones":[{"level","rewards":[ItemRef],"reached"}]}` |
| `GET /missions` | – | `{"daily": MissionSet, "weekly": MissionSet, "events": [EventSet]}` |
| `POST /missions/{periodKey}/{missionId}/claim` | – (`Idempotency-Key`) | `{"mission": Mission, "wallet": Wallet, "progression": {"level","xp","levelXp","nextLevelXp","xpGained","levelUp"}, "granted": [ItemRef]}`; 404 `not_found` (not a mission of a current period), 409 `already_claimed`, 422 `not_completed` |

**ItemRef**: `{"id":"frame_bronze","kind":"frame","name":"Bronze Ring","rarity":"common"}`

**MissionSet**: `{"periodKey":"d2026-10-21","resetsAtUtc":"2026-10-22T00:00:00Z","missions":[Mission]}`

**EventSet**: `{"id":"autumn_cup","title","description","periodKey":"e-autumn_cup","startsAtUtc","endsAtUtc","missions":[Mission]}` (only running events are listed)

**Mission**: `{"id","title","description","game":"any|ludo|snakes_ladders","progress","target","reward":{"coins","diamonds","xp","items":[ItemRef]},"completed","claimed"}`

Period keys: daily `dYYYY-MM-DD`, weekly `wYYYY-Www` (ISO week), event
`e-{eventId}`. Daily missions (3, the same for everyone that day) reset at
00:00 UTC; weekly challenges reset Monday 00:00 UTC; event missions end at
`endsAtUtc`. Only current periods can be claimed — an unclaimed reward of a
past period is gone. Missed periods never reset XP, level or collection.

A claim credits the wallet, XP and items in one transaction, exactly once.
`granted` lists every item newly added to the collection (reward items plus
level milestones reached through the reward XP). After a claim the server
pushes `wallet.updated` (`reason: "mission"`, when coins/diamonds changed) and
`progression.updated`. Finished matches push `progression.updated` with the
changed missions.

**Idempotency-Key** (claim, Collection and Store purchases): 8–64 characters `[A-Za-z0-9-_.:]`,
scoped to the account. A successful response is stored for 24 h and replayed
byte-for-byte (header `Idempotent-Replayed: true`, no second credit or push).
Errors are not stored. A concurrent request with the same key waits for the
first (409 `request_in_progress` after 5 s). Reusing a key on a different
endpoint → 422 `idempotency_key_reused`; a malformed key → 400.

## Collection Room

| Method & path | Body | Response |
|---|---|---|
| `GET /collection` | – | `{"items":[CollectionItem],"loadout":Loadout}` (all catalog items, catalog order) |
| `PUT /collection/loadout` | `{"slot":"dice","itemId":"dice_neon"}` | `{"loadout"}`; 422 `item_locked` (not owned), 404 `not_found` (unknown item), 400 `bad_request` (unknown slot or item kind ≠ slot). `"itemId": null` or `""` resets the slot to its starter item. |
| `POST /collection/items/{itemId}/purchase` | – (`Idempotency-Key`) | `{"item": CollectionItem, "wallet": Wallet}`; 409 `already_owned`, 422 `insufficient_funds` / `item_locked` (not a `purchase` item), 404 `not_found`. Pushes `wallet.updated` (`reason: "purchase"`). |

**CollectionItem**: `{"id","kind":"dice|token|ludo_board|snakes_board|frame|title|badge|emote|victory|trail","name","description","rarity":"common|rare|epic|legendary","owned","equipped","acquisition":{"type":"starter|level|mission|purchase|event","level"?,"price"?:{"coins"?,"diamonds"?},"label"}}`

Slots: `dice, token, ludo_board, snakes_board, frame, title, victory, trail`.
Emotes and badges are owned, not equipped. Every item is cosmetic only.
A purchase debits the fixed price and adds the item in one transaction; an
insufficient balance changes nothing. The app shows this one list in two
places: the **Collection Room** (owned items plus `level`/`mission`/`event`
items still to earn) and the **Shop** (`purchase` items not owned yet) — see
[`cosmetics-catalog.md` → Collection vs Shop](cosmetics-catalog.md#collection-vs-shop-app).

## Store (profile pictures)

Profile pictures (Lottie animations and PNG images) bought with **diamonds**
and owned **forever**; the owner applies any picture they own. The app
calls this the **Shop** (`/shop`; its old `/store` route redirects); the API
paths keep `/store`. Catalogue,
storage and privacy model: [`cosmetics-catalog.md`](cosmetics-catalog.md#profile-pictures).

All routes: authenticated humans, version gated. Rate limits per account:
list 120/min (shared with progression reads), purchase 30/min (shared with
claims and purchases), apply 60/min (shared with the loadout), sign 120/min.

| Method & path | Body | Response |
|---|---|---|
| `GET /store/profile-pictures?filter=&excludeOwned=&limit=&cursor=` | – | `{"items":[ProfilePicture],"nextCursor":"…"\|null,"total":160,"equipped":"pp_x"\|null}` |
| `POST /store/profile-pictures/{id}/purchase` | – (`Idempotency-Key`) | `{"item": ProfilePicture, "wallet": Wallet}`; 409 `already_owned`, 422 `insufficient_funds`, 404 `not_found` (unknown or retired picture). Pushes `wallet.updated` (`reason: "purchase"`, `delta.diamonds` = −price). |
| `PUT /me/profile-picture` | `{"id":"pp_x"}` or `{"id":null}` | `{"equipped": ProfilePicture\|null}`; 422 `item_locked` (not owned), 404 `not_found` (unknown id), 400 `bad_request` (missing `id`, `""`, wrong type, unknown field). `null` = back to the built-in avatar. |
| `POST /assets/sign` | `{"paths":["profile_pictures/…", …]}` (1–50) | `{"urls":{"<path>":"https://…"},"expiresAt":1792588328065}`; 400 `bad_request` (0 or > 50 paths, empty or > 255-character path), 503 `assets_unavailable` (asset storage not configured on this server). |

**ProfilePicture**: `{"id":"pp_wolf","name":"Wolf","format":"image|lottie","path":"profile_pictures/image/wolf.png","price":{"diamonds":10},"owned":false,"equipped":false}`

**List**: `filter` = `all` (default) \| `animated` (Lottie) \| `static`
(images) \| `owned`; `excludeOwned` = `true` \| `false` (default `false`)
leaves out every picture the caller owns (with `all`, `animated`, `static`);
`limit` 1–50 (default 24); order `sort_order`, then `id`. `cursor` is the
previous page's opaque `nextCursor` (`null` on the last page); paging
continues after the last item seen, so rows added or retired — or pictures
bought — meanwhile never repeat or skip an item. `total` = items matching the
filter and `excludeOwned` (for the caller). `equipped` = the caller's
equipped picture id (also when `excludeOwned` leaves its item out). Retired
pictures (`active = false`) are listed only to their owners (so never with
`excludeOwned=true`). Any other `filter`/`limit`/`cursor`, an
`excludeOwned` other than `true`/`false`, or `filter=owned` with
`excludeOwned=true` → 400 `bad_request`. The app's **Shop** lists
`excludeOwned=true` (only pictures not owned yet); the **Collection**'s
Pictures category and the Profile picker list `filter=owned`.

**Purchase** — like the Collection purchase: one transaction locks the
progression row, then adds the inventory row and debits the wallet (same
lock order), so a picture is paid **exactly once** even under concurrent
requests (the others get 409 `already_owned`); an insufficient balance
changes nothing. The price charged is the catalogue row's price at that
moment. `Idempotency-Key` works as for claims (below): a replay returns the
original body with `Idempotent-Replayed: true` and no second debit or push.

**Apply** takes effect for **rooms joined afterwards** (seats already taken
keep the picture they joined with), `GET /me` and every list at once. A
retired picture the caller owns can still be applied.

**Sign** returns SigV4 query-presigned GET URLs for the private bucket, valid
`ASSET_URL_TTL` (default **10 minutes**; `expiresAt` = unix ms). Only paths
that some catalogue row names are signed; any other path is silently left
out of `urls` (never an error, never signed). Duplicates are signed once.
Download each URL once and keep the file (objects are immutable:
`Cache-Control: private, max-age=31536000, immutable`); never cache the URL
itself. Signed URLs are never logged by the server.

## Social

Authenticated humans, version gated. Rate limits per account: reads 120/min,
writes 30/min, new friend requests 60/hour.

| Method & path | Body | Response |
|---|---|---|
| `GET /friends` | – | `{"friends":[Friend],"incoming":[Friend],"outgoing":[Friend],"onlineCount":3,"friendCount":12,"maxFriends":20}` (friends: online first, then by name; requests: newest first). `onlineCount` = accepted friends online now, `friendCount` = accepted friends, `maxFriends` = the cap (`FRIENDS_MAX`) |
| `POST /friends/requests` | `{"friendCode":"u_3f9a1c2b7d"}` | 201 `{"friend"}`; auto-accepts if they already requested you (`status: "friend"`); repeating a pending request returns it again (`status: "outgoing"`). 404 `not_found` (unknown code), 409 `already_friends`, 422 `cannot_friend_self`, 422 `friend_limit` (you **or** they already have `maxFriends` friends, or a pending-request cap is reached) |
| `POST /friends/requests/{uid}/accept` | – | `{"friend"}`; 404 `not_found` (no pending request from `uid`), 422 `friend_limit` (either side has `maxFriends` friends); accepting an existing friend returns it |
| `DELETE /friends/{uid}` | – | 204 (removes friend or declines/cancels request; no-op if none); 404 `not_found` for an unknown uid |
| `GET /social/recent` | – | `{"players":[Friend]}` last 20 human opponents (14 days), newest first |
| `GET /leaderboards/friends` | – | `{"periodKey":"w2026-W43","entries":[{"uid","name","avatar","picture","level","weeklyXp","rank","isMe"}]}` |

**Friend**: `{"uid","name","avatar","picture","level","title","online","status":"friend|incoming|outgoing|none"}`
(`picture` = PlayerPicture or `null`; also in friend requests and
`GET /social/recent`)

- Friend codes are the public uid, case-insensitive. Limits: `FRIENDS_MAX`
  accepted friends (default **20**), 100 pending sent, 100 pending received.
  A new friendship (request, auto-accept or accept) is refused with
  `friend_limit` when **either** player is at the cap, atomically (two
  concurrent accepts cannot both take the last slot). Pending requests may
  outnumber free slots; the cap is checked again on acceptance. Accounts
  already above the cap keep their friends but cannot add more.
- `online` is only reported for accepted friends (always `false` otherwise).
- No response ever contains another player's account id, email or provider
  id.
- Leaderboard: you plus your accepted friends, ranked by XP gained this ISO
  week (Monday 00:00 UTC; matches and mission rewards); equal XP share a rank.
- A new request pushes `social.friend_request` to the recipient. Invites are
  sent over WebSocket (`room.invite`, friends only, 10/min per sender).
- Bots look like people: the code of a bot seat the caller can see (in their
  room) is accepted like a person's — same checks and limits (it counts
  toward the 100 pending sent), `201` `status: "outgoing"`, listed under
  `outgoing`, cancellable with `DELETE /friends/{uid}`. A bot never accepts;
  its pending request disappears after 72 h.

## Player reports

Authenticated humans, version gated. Rate limits per account: `POST` 20/min,
`GET` 120/min (separate from the daily report limit). Stored in PostgreSQL
(`progression.player_reports`: report metadata only, no game state). Any
seated opponent can be reported, bots included: a bot is reported exactly
like a person (same errors, limits and response, listed by `GET /reports`)
and is kept out of the operator queue.

| Method & path | Body | Response |
|---|---|---|
| `POST /reports` | `{"uid":"u_3f9a1c2b7d","roomId":"r_k3m9x2","reason":"cheating"}` | 201 `{"report":Report,"limit":Limit}` |
| `GET /reports` | – | `{"reports":[Report],"limit":Limit}` — my reports, newest first, at most 100 |

`reason`: `cheating` \| `offensive_name` \| `abusive_behavior` \|
`leaving_or_stalling` \| `other`.

**Report**: `{"id","player":{"uid","name","avatar","picture","level"},"reason","game","roomId","status":"submitted|reviewing|action_taken|dismissed","createdAt","updatedAt"}`
(`player` is the reported player's public profile; reporter ids and operator
notes are never returned).

**Limit**: `{"perDay":2,"remaining":1,"resetsAt":1792588328065}` — `perDay` =
`REPORTS_PER_DAY` (default 2); `resetsAt` (unix ms) is when `remaining` next
goes up (the oldest report of the rolling 24 h window leaves it), `null` when
no report is counted.

`POST /reports` errors, in check order:

| HTTP | Code | When |
|---|---|---|
| 400 | `bad_request` | malformed body, unknown field, unknown `reason`, malformed `uid`/`roomId` |
| 422 | `cannot_report_self` | `uid` is the caller |
| 404 | `room_not_found` | the room no longer exists (rooms are kept while playing and ≈ 10.5 min after the game ends) |
| 422 | `not_in_room` | the caller or the reported player does not hold a seat in that room (forfeited / left seats count) |
| 404 | `not_found` | `uid` is not seated and is no player at all |
| 409 | `already_reported` | the caller already reported this player in the last 24 h |
| 429 | `report_limit` | the caller already filed `perDay` reports in the last 24 h; `Retry-After` header and `details` = `Limit` (`details.resetsAt`) |

Both 24 h rules are rolling windows enforced atomically per reporter (a
burst of concurrent reports stores at most `perDay`). Rejected attempts are
not stored and do not count. The reported player is not notified.
(`422 cannot_report_bot` is no longer returned; older apps may still map it.)

### Operator API (private network only)

Not for the app. **Not version gated**, no user token: header
`X-Admin-Key: <key>` is compared in constant time with
`ADMIN_API_KEY_SHA256` (hex sha256 of the key). When that variable is unset
both routes answer **404** `not_found`; a missing or wrong key answers
**401** `unauthorized`. Rate limited 60/min per client IP (checked before the
key). Expose `/api/v1/admin/*` only on the private network (block it at the
public proxy).

| Method & path | Body | Response |
|---|---|---|
| `GET /admin/reports?status=submitted&limit=50` | – | `{"reports":[AdminReport]}` newest first; `status` optional (one of the four statuses), `limit` 1–200 (default 50); else 400. Reports against bots are not listed |
| `PATCH /admin/reports/{id}` | `{"status":"reviewing","note":"…"}` (at least one; `note` ≤ 1000 chars, `""` clears it) | `{"report":AdminReport}`; 400 `bad_request`, 404 `not_found` (unknown id or a report against a bot) |

**AdminReport**: `{"id","reporter":{"uid","name"},"reported":{"uid","name"},"reason","roomId","game","status","note":null,"createdAt","updatedAt","reportedStats":{"total","open","reporters"}}`
— `reportedStats` counts every report against the reported player (`open` =
`submitted` + `reviewing`; `reporters` = distinct reporters). Account ids are
never returned.

## Telemetry (privacy-conscious, aggregate only)

`POST /telemetry/events` — `{"events":[{"kind":"client_error|hash_mismatch|reconnect_success|reconnect_failure","count":1}]}`
→ 202 `{"accepted": <entries counted>}`. Only increments aggregate counters; no
identifiers or free text stored.

No authentication; version gated (X-App-* headers); rate limited 60/min per
IP; body ≤ 2 KiB. 1–8 entries (else 400); unknown fields → 400. Each entry
counts at most 20 (larger counts are capped, so clients should send
`min(count, 20)`); unknown kinds and counts < 1 are ignored.

## Bot service (`bot-play` only)

Service-to-service endpoints, **not** version-gated, disabled unless
`BOT_SERVICE_KEY_SHA256` is configured. They never touch wallets.

| Method & path | Auth | Body | Response |
|---|---|---|---|
| `POST /bot/controller/token` | `Authorization: Bot-Service <key>` | – | `{"token","expiresAt"}` controller JWT (scope `bot_controller`, 15 min) |
| `GET /bot/assignments?wait=20` | controller JWT | – | Long-poll. `{"assignments":[{"id","roomId","game","variant","kind":"practice\|private\|public_fill","expiresAt"}]}`; each assignment is handed out once. During maintenance: `{"assignments":[],"maintenance":true}` |
| `GET /bot/lobbies` | controller JWT | – | `{"lobbies":[{"roomId","game","variant","capacity","humans","bots","pendingBots","waitingMs"}],"publicFillEnabled":bool}` open public lobbies |
| `POST /bot/lobbies/{roomId}/fill` | controller JWT | `{"count":2}` | `{"requested":2}` — the assignments are delivered through `GET /bot/assignments`; 409 when the lobby changed, is full, or already has pending bots; 403 when public fill is disabled |
| `POST /bot/sessions` | controller JWT | `{"assignmentId","name","profile"}` or `{"mode":"loadtest","name"}` | `{"accessToken","expiresAt","uid","roomId"}` — seats the bot (assignment) or scopes it to the isolated load-test pool. Load-test sessions are refused when `APP_ENV=production` or `BOT_LOADTEST_ENABLED` is false. The display name is `name` sanitized (≤ 20 runes) with any leading `Bot` label stripped (empty → a neutral first name); bots are identified by `players[].bot`, never by their name. |
| `DELETE /bot/sessions/{uid}` | controller JWT | – | 204, revokes the bot session (bot leaves its room) |

## Legal notices (outside `/api/v1`)

`GET /legal/open-source` (also `HEAD`) serves the static open-source notices
page — the same file published at `https://sungamestudio.com/ludo-royale/legal/`,
which the app's Settings → About → "Legal notices" entry opens by default.
This route is an optional fallback (apps built with
`--dart-define=LEGAL_NOTICES_URL=<api>/legal/open-source`). No authentication, no `X-App-*` headers and no version gate
or maintenance block (a plain browser request); rate-limited to 60/min per
client IP (`429 rate_limited`). The body is the file at `LEGAL_NOTICES_FILE`
(default `config/legal/open-source-notices.html`, generated by
`frontend/tool/export_oss_notices.dart`), read at startup and on `SIGHUP`;
while it is missing the route answers `404 not_found` (JSON error shape).

Response headers: `Content-Type: text/html; charset=utf-8`,
`Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
`X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
`Cache-Control: public, max-age=3600`, `Last-Modified`, a strong `ETag`
(`If-None-Match` → `304`) and `Vary: Accept-Encoding` (gzip-encoded when the
client accepts it).

## Health & metrics

`GET /healthz` (liveness), `GET /readyz` (PostgreSQL + Redis reachable),
`GET /metrics` (Prometheus; served on `METRICS_ADDR`, internal only).
