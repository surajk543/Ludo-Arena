# App Version & Maintenance Policy

The Go backend decides — per environment and per platform — whether a Flutter
client may use online services. No Firebase Remote Config is involved; the
policy lives in a validated JSON file loaded by the backend
(`backend/internal/apppolicy`). Changing it never requires a new app release.
The same file also carries live economy settings: the coin **entry fees** per
game ([Entry fees](#entry-fees)) and the new-account **welcome grant**
([Welcome grant](#welcome-grant)).

## Modes and precedence

Evaluated for `(platform, installedVersion, installedBuild)` at request time:

1. **`maintenance`** — global or platform maintenance is active (manual switch,
   flag file, or a scheduled window covering *now*).
   *Exception:* if the platform policy sets `securityCritical: true` and the
   client is below the minimum, `force_update` wins.
2. **`force_update`** — `(installedVersion, installedBuild) < (minimumSupportedVersion, minimumSupportedBuild)`.
3. **`optional_update`** — `(installedVersion, installedBuild) < (latestVersion, latestBuild)`.
4. **`normal`** — otherwise.

### Version comparison

Versions are 1–4 dot-separated non-negative integers (`1.10.0 > 1.9.0`,
`1.2 == 1.2.0`). Pre-release/metadata suffixes (`-beta`, `+5`) are rejected as
invalid. Comparison is on the tuple `(version, build)`: the build number only
matters when versions are equal. A minimum build of `0` means "any build".
Invalid or missing client version data → HTTP 400 `client_version_required`
on gated endpoints (the client should treat that as a bug, not an update).

## Enforcement

| Surface | maintenance | force_update | optional_update / normal |
|---|---|---|---|
| `GET /api/v1/app/config` | 200 (mode=maintenance) | 200 (mode=force_update) | 200 |
| Auth endpoints, `/me`, wallet, progression, collection, social, rooms | 503 `maintenance` | 426 `update_required` | allowed |
| WebSocket upgrade (`/api/v1/ws`) | 503 | 426 | allowed |
| Live WebSocket commands | `error maintenance`, then close `4503` | `error update_required`, then close `4426` | allowed (never disconnected for an optional update) |
| `/healthz`, `/readyz`, `/metrics`, Apple callback | allowed | allowed | allowed |

Error `details` contain the evaluated policy (same fields as
`GET /app/config`), including `storeUrl` and `minimumSupportedVersion`.

Version headers are a **compatibility policy, not proof of a genuine
binary**: a modified client can lie about its version. Authorization and game
integrity checks are independent of the version gate.

### Running matches during maintenance

Maintenance **pauses** matches; it does not end them:

- Game commands are rejected; connected clients are closed with `4503`.
- Turn deadlines and lobby fill timers are pushed forward while maintenance is
  active, so no auto-moves, forfeits, payouts or wallet debits happen.
- Room state stays in Redis (TTL refreshed). When maintenance ends, each
  running game's current turn gets a fresh full deadline; players reconnect and
  receive `game.state`.
- Wallet operations are single PostgreSQL transactions, so no partial update
  can be left behind by a maintenance transition.

## Configuration file

`APP_POLICY_FILE` (e.g. `backend/config/app-policy.production.json`).
`APP_ENV` must equal the file's `environment` or startup fails.

```json
{
  "configVersion": 3,
  "environment": "production",
  "entryFees": {"ludo": 100000, "snakes_ladders": 50000},
  "welcome": {"coins": 1000000, "diamonds": 50},
  "maintenance": {
    "enabled": false,
    "message": "We're upgrading the game servers.",
    "windows": [
      {"startsAtUtc": "2026-11-02T01:00:00Z", "endsAtUtc": "2026-11-02T02:00:00Z",
       "message": "Scheduled maintenance"}
    ]
  },
  "platforms": {
    "android": {
      "minimumSupportedVersion": "1.0.0", "minimumSupportedBuild": 1,
      "latestVersion": "1.0.0", "latestBuild": 1,
      "storeUrl": "https://play.google.com/store/apps/details?id=com.ludoarena.app",
      "forceUpdateTitle": "Update required",
      "forceUpdateMessage": "This version is no longer supported. Update to keep playing.",
      "optionalUpdateTitle": "A new version is available",
      "optionalUpdateMessage": "",
      "optionalUpdateReminderHours": 24,
      "securityCritical": false,
      "maintenance": {"enabled": false, "message": ""}
    },
    "ios": { "...": "same shape; storeUrl must be an apps.apple.com URL or empty" }
  }
}
```

Validation (startup and every reload; an invalid file is rejected as a whole
and the previous policy stays active):

- `environment` ∈ `development|preproduction|production` and equals `APP_ENV`.
- Both `android` and `ios` present; versions valid; `latest ≥ minimum`.
- `storeUrl`: empty (shown as "update not yet available in the store") or
  `https://play.google.com/...` for Android / `https://apps.apple.com/...` for
  iOS. An Android URL in the iOS section (or vice versa) is rejected.
- Window `endsAtUtc > startsAtUtc`; messages ≤ 500 chars.
- `entryFees` (optional): keys only `ludo` and `snakes_ladders`; values whole
  coins in `0..100000000` (no fractions, strings, exponents or `null`).
- `welcome` (optional): keys only `coins` (`0..1000000000`) and `diamonds`
  (`0..1000000`); whole numbers only.

### Entry fees

`entryFees` sets the flat coin entry fee each player pays when a game starts.
The shipped policy files for every environment use **Ludo 100,000** and
**Snakes & Ladders 50,000**. Precedence, per game:

1. `entryFees.<game>` in this file (live; hot-reloaded with the rest of the
   policy);
2. `ENTRY_FEE_LUDO` / `ENTRY_FEE_SNAKES` (environment, read at startup; same
   `0..100000000` range);
3. built-in defaults: 100,000 / 50,000.

`GET /api/v1/app/config` returns the live values as `entryFees` on every
request; the app shows them and re-reads them whenever it re-fetches the
policy (app resume, at most every 30 s).

What a change affects:

- **New rooms only.** The fee is copied onto a room when it is created
  (public lobby, private room, or the new room of a public rematch) and stays
  with that room for all its rounds (private-room rematches keep it). Rooms
  already in a lobby or playing are never re-priced; their `entryFee` and pot
  are unchanged.
- Public matchmaking only seats a player in an open lobby whose fee equals the
  current fee, so the price shown before **Find match** is the price charged.
  Lobbies opened at an older fee keep their players and start or time out
  normally.
- Practice rooms and load-test rooms stay free. Rooms with bots charge every
  seat, bots included (`backend/docs/game-rules.md` "Coins with bots").
- An invalid value (negative, too large, unknown game) rejects the whole file;
  the previous policy and fees stay active and the error is logged.

### Welcome grant

`welcome` sets the one-time grant every **new** account receives (guest or
provider sign-in). The shipped policy files use **1,000,000 coins (10 lakh)
and 50 diamonds**. Precedence, per amount:

1. `welcome.coins` / `welcome.diamonds` in this file (live; hot-reloaded);
2. `WELCOME_COINS` / `WELCOME_DIAMONDS` (environment, read at startup; same
   ranges);
3. built-in defaults: 1,000,000 coins, 50 diamonds.

The amounts are read once per account creation, immediately before the
transaction that inserts the wallet and the first identity, so the grant stays
exactly-once (see `docs/authentication.md`). A change applies to accounts
created afterwards only: existing wallets are never re-granted, topped up or
reduced, and refresh, guest resume, linking and reconnects never grant.
`GET /api/v1/app/config` reports the live amounts as `welcome`. An invalid
value rejects the whole file and keeps the last good policy.

### Reload

The backend re-reads the file on `SIGHUP` and whenever its modification time
changes (checked every `APP_POLICY_POLL_SECONDS`, default 5 s). Each accepted
reload is swapped in atomically and logged with `configVersion` and a SHA-256
of the file; rejected reloads are logged with the validation error.

### Operator procedures

- **Enable maintenance (emergency, fastest):** create the flag file
  `APP_MAINTENANCE_FLAG_FILE` (e.g. `touch /etc/ludo-arena/MAINTENANCE`).
  Its first line (optional) is used as the message. Remove the file to end
  maintenance. Takes effect within the poll interval on every instance.
- **Enable maintenance (planned):** add a window to `maintenance.windows` or set
  `maintenance.enabled: true`, bump `configVersion`, deploy the file, `kill -HUP`.
- **Force update:** raise `minimumSupportedVersion`/`Build` for the platform.
- **Optional update:** raise `latestVersion`/`Build` and set the message.
- **Change entry fees:** edit `entryFees` (e.g.
  `{"ludo": 150000, "snakes_ladders": 75000}`), bump `configVersion`, deploy
  the file; it is picked up within the poll interval (or `kill -HUP`) on every
  instance. Confirm with `GET /api/v1/app/config` and the
  `app policy loaded … entryFees=…` log line.
- **Change the welcome grant:** edit `welcome` (e.g.
  `{"coins": 1500000, "diamonds": 75}`), bump `configVersion`, deploy the
  file. New accounts get it once the file is picked up; existing accounts keep
  what they have. Confirm with `GET /api/v1/app/config` (`welcome`).
- **Preproduction vs production:** separate files
  (`app-policy.preproduction.json`, `app-policy.production.json`), selected by
  `APP_POLICY_FILE` and checked against `APP_ENV`.

There is no HTTP admin API for changing the policy.

## Client behaviour (Flutter)

Startup state machine: `initializing → checkingPolicy → (maintenance |
forceUpdate | optionalUpdatePrompt → ) restoringSession → loadingWallet →
ready`. No home/game route is reachable before `ready`.

- The policy is re-fetched on app resume (throttled to once per 30 s, always
  when the current screen is maintenance/force-update/unreachable), and whenever
  a REST call returns 426/503 or the WebSocket closes with 4426/4503.
- Force update: full-screen, no dismiss, back button disabled; **Update Now**
  opens `storeUrl` (or shows "not yet available" + Retry when empty).
- Optional update: dialog with **Update Now** / **Later**; shown at most once per
  launch and not again for `optionalUpdateReminderHours` after **Later** (per
  `latestVersion`); never shown during a match.
- Maintenance: full-screen with message, optional "estimated end" (labelled as
  an estimate), Retry, automatic re-check every 30 s.
- Unreachable backend: "Can't reach the game service" + Retry. The last
  successfully received policy is cached (SharedPreferences) only to show
  context; it never grants access.
