# REST API — `/api/v1`

Base URL: `https://<host>/api/v1` (local: `http://localhost:8080/api/v1`).
All bodies are JSON (`Content-Type: application/json`). Times are unix
milliseconds unless the field name ends in `Utc` (ISO-8601 UTC string).

## Common request headers

| Header | Required on | Notes |
|---|---|---|
| `X-App-Platform` | every endpoint except `/healthz`, `/readyz`, `/metrics`, Apple callback | `android` \| `ios` |
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
| 400 | `bad_request`, `client_version_required`, `environment_mismatch` |
| 401 | `unauthorized`, `invalid_credential`, `refresh_reused`, `session_replaced` |
| 403 | `forbidden` |
| 404 | `not_found`, `invalid_code`, `room_not_found` |
| 409 | `identity_conflict`, `provider_already_linked`, `already_owned`, `already_claimed`, `already_friends`, `already_reported`, `request_in_progress` |
| 422 | `not_completed`, `insufficient_funds`, `item_locked`, `cannot_friend_self`, `friend_limit`, `cannot_report_self`, `cannot_report_bot`, `not_in_room`, `idempotency_key_reused` |
| 426 | `update_required` (details = policy) |
| 429 | `rate_limited`, `report_limit` (`Retry-After` header; `report_limit` details = `Limit`) |
| 503 | `maintenance` (details = policy), `provider_unavailable` |

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
  "displayName": "Asha",
  "avatar": 3,
  "isGuest": true,
  "linkedProviders": ["guest"],        // subset of guest|google|facebook|apple (never the internal device binding)
  "level": 4, "xp": 520, "levelXp": 450, "nextLevelXp": 250,   // progress = (xp - levelXp) / nextLevelXp
  "title": "title_rookie",
  "loadout": {"dice": "dice_classic", "token": "token_classic", "ludo_board": "ludo_board_classic",
              "snakes_board": "snakes_board_classic", "frame": "frame_none", "title": "title_rookie",
              "victory": "victory_confetti"}
}
```

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

### Profile & wallet

| Method & path | Response |
|---|---|
| `GET /me` | `{"user": User, "wallet": Wallet}` |
| `GET /wallet` | `Wallet` |

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

**Idempotency-Key** (claim, purchase): 8–64 characters `[A-Za-z0-9-_.:]`,
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
insufficient balance changes nothing.

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
| `GET /leaderboards/friends` | – | `{"periodKey":"w2026-W43","entries":[{"uid","name","avatar","level","weeklyXp","rank","isMe"}]}` |

**Friend**: `{"uid","name","avatar","level","title","online","status":"friend|incoming|outgoing|none"}`

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

## Player reports

Authenticated humans, version gated. Rate limits per account: `POST` 20/min,
`GET` 120/min (separate from the daily report limit). Stored in PostgreSQL
(`progression.player_reports`: report metadata only, no game state).

| Method & path | Body | Response |
|---|---|---|
| `POST /reports` | `{"uid":"u_3f9a1c2b7d","roomId":"r_k3m9x2","reason":"cheating"}` | 201 `{"report":Report,"limit":Limit}` |
| `GET /reports` | – | `{"reports":[Report],"limit":Limit}` — my reports, newest first, at most 100 |

`reason`: `cheating` \| `offensive_name` \| `abusive_behavior` \|
`leaving_or_stalling` \| `other`.

**Report**: `{"id","player":{"uid","name","avatar","level"},"reason","game","roomId","status":"submitted|reviewing|action_taken|dismissed","createdAt","updatedAt"}`
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
| 422 | `cannot_report_bot` | the seat is a bot (or not a human account) |
| 422 | `not_in_room` | the caller or the reported player does not hold a seat in that room (forfeited / left seats count) |
| 404 | `not_found` | `uid` is not seated and is no player at all |
| 409 | `already_reported` | the caller already reported this player in the last 24 h |
| 429 | `report_limit` | the caller already filed `perDay` reports in the last 24 h; `Retry-After` header and `details` = `Limit` (`details.resetsAt`) |

Both 24 h rules are rolling windows enforced atomically per reporter (a
burst of concurrent reports stores at most `perDay`). Rejected attempts are
not stored and do not count. The reported player is not notified.

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
| `GET /admin/reports?status=submitted&limit=50` | – | `{"reports":[AdminReport]}` newest first; `status` optional (one of the four statuses), `limit` 1–200 (default 50); else 400 |
| `PATCH /admin/reports/{id}` | `{"status":"reviewing","note":"…"}` (at least one; `note` ≤ 1000 chars, `""` clears it) | `{"report":AdminReport}`; 400 `bad_request`, 404 `not_found` (unknown id) |

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

## Health & metrics

`GET /healthz` (liveness), `GET /readyz` (PostgreSQL + Redis reachable),
`GET /metrics` (Prometheus; served on `METRICS_ADDR`, internal only).
