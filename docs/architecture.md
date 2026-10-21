# Ludo Royale — Architecture (companion)

The full system documentation, with 38 diagrams, is the standalone page
**[architecture.html](architecture.html)**. Open it directly in a browser
(`open docs/architecture.html`, or double-click it), or serve the folder:

```bash
cd docs && python3 -m http.server 8000   # then visit http://localhost:8000/architecture.html
```

It needs no network access: diagrams are rendered by the bundled Mermaid 12.2.0
in [`assets/mermaid.min.js`](assets/mermaid.min.js)
([license](assets/MERMAID-LICENSE.txt)). If that file is missing, each diagram
falls back to its Mermaid source. The page has light/dark themes, a sticky
section index, and per-diagram *Actual size* / *Source* buttons; append
`?render=all` to the URL to render every diagram at once (for printing).

This file is a short overview. It also holds the sections that code and
other docs link to by name: [Wallet settlement guarantees](#wallet-settlement-guarantees),
[Security](#security) and [Observability](#observability-live-player-counts).

## System in one paragraph

A Flutter app (Android/iOS, `com.ludoroyale.app`) talks to an **authoritative
Go backend** over HTTPS REST (`/api/v1`) and one WebSocket
(`GET /api/v1/ws`, protocol `ludo-royale.v1`). The backend owns dice
(`crypto/rand`), rules (Ludo classic/quick and Snakes & Ladders engines), room
state, turn timers, wallets, progression and sessions. Live state, timers,
sessions and cross-instance pub/sub live in **Redis**; durable data lives in
**PostgreSQL** schemas `wallet` (balances only), `identity` (provider →
account mappings, plus the internal `device` binding that restores an account
after an app update or reinstall) and `progression`. There are no match-history, ledger or
profile tables. Identity providers only prove identity: **Firebase
Authentication is not used**, and Firebase is in the app for consent-gated
Analytics only. A separate Go service, **bot-play**, plays as server-labelled
bots through the same protocol with room-scoped bot tokens.

## Monitoring and alerting

The fourth project, [`monitoring/`](../monitoring/README.md), runs Prometheus
(scraping every backend instance's `METRICS_ADDR`, bot-play and node_exporter
on each host), Alertmanager and a Telegram **ops bot** (separate Go module
`ludoroyale/opsbot`). The bot reads only the Prometheus API (plus, optionally,
the Play Console bulk reports in Cloud Storage and the GA4 Data API) and sends:
an hourly PDF status (real players vs bots in game and online, rooms, lobby,
matches, new accounts, DAU, CPU / RAM / disk per host, process memory, firing
alerts, 24-hour charts), a daily KPI PDF for yesterday (accounts, DAU/WAU,
matches by game and mode, human-only vs bot-filled, peaks, matchmaking wait,
5xx, settlement failures, Play installs/uninstalls, GA4 first_open/app_remove,
30-day trends), and every alert enriched with the current CPU, RAM and player
counts. Alert thresholds live in one file
(`monitoring/prometheus/rules/thresholds.yml`); the bot token and Google keys
come only from the environment. Cluster-wide gauges are combined with `max`
(every instance reports the same value); per-instance gauges are summed.

## Sections of the HTML page

| # | Section | What it covers |
|---|---|---|
| 1 | [System architecture](architecture.html#architecture) | Context and backend layers, [who is authoritative for what](architecture.html#who-is-authoritative), [schema boundaries](architecture.html#schema-boundaries), Redis roles, [app-issued tokens](architecture.html#app-tokens) |
| 2 | [Google Sign-In](architecture.html#google-sign-in) | Nine-step sequence, Google Cloud project `ludo-royale-63887` and its Web / iOS / Android (debug) OAuth clients |
| 3 | [Guest login and Save Progress](architecture.html#guest-save-progress) | Guest creation and resume, linking, `identity_conflict` (no merge) and `provider_already_linked`, [device binding](architecture.html#device-binding) (restore after update / reinstall) |
| 4 | [Wallet, fees and payouts](architecture.html#wallet) | Exactly-once welcome grant, all-or-nothing entry fees, at-most-once payout, [settlement guarantees](architecture.html#wallet-settlement-guarantees) |
| 5 | [Online multiplayer Ludo](architecture.html#ludo-online) | Matchmaking → room → WebSocket → server dice → Redis CAS commit → ordered fan-out → client reducer |
| 6 | [Snakes & Ladders](architecture.html#snakes-ladders) | Turn flow, snakes/ladders, exact-100 rule |
| 7 | [Private rooms](architecture.html#private-rooms) | 6-character codes from a 32-symbol alphabet, preview, join, host start, bots, lifecycle and expiry |
| 8 | [Reconnection](architecture.html#reconnection) | Backoff with jitter, `connection.ready.activeRoomId`, `game.state`, version/hash reconciliation, close codes incl. `4409` |
| 9 | [Light / dark theme](architecture.html#theme) | Selection → SharedPreferences → restore before first frame → ThemeExtensions |
| 10 | [Deployment and configuration](architecture.html#deployment) | Target topology (pending), local dev, [monitoring and alerting](architecture.html#monitoring) (Prometheus, Alertmanager, Telegram ops bot), [environment variables by name](architecture.html#env-vars), identifiers |
| 11 | [App version management](architecture.html#app-version) | Startup policy check, force/optional update, maintenance lifecycle, enforcement (426/503, 4426/4503), reload |
| 12 | [WebSocket performance](architecture.html#websocket-performance) | permessage-deflate boundaries, deltas vs snapshots, slow-consumer handling, metrics, [measured results](architecture.html#measured-load-test-results) |
| 13 | [Progression and engagement](architecture.html#progression) | Rematch, match records → missions/XP, levels, cosmetics, exactly-once claims, engagement principles |
| 14 | [bot-play](architecture.html#bot-play) | Relationship, authentication and admission, turn decisions, hot reload, scaling, load-test isolation |
| 15 | [Analytics](architecture.html#analytics) | Human-only, consent-gated Firebase path vs bot traffic; HyperLogLog active users |
| 16 | [Localization](architecture.html#localization) | ARB fragments → `merge_arb.dart` → `gen-l10n`, RTL for ar/ur (boards stay LTR), localized policy texts |
| 17 | [Security and testing](architecture.html#security-testing) | Trust boundaries, controls, test suites per project |
| 18 | [Status](architecture.html#status) | Implemented vs pending |

## Wallet settlement guarantees

Every wallet change is a single PostgreSQL transaction on `wallet.wallets`
(balances can never go negative), so no partial update can exist. The
boundary between PostgreSQL and the Redis room state is not transactional;
these are the exact guarantees and failure windows
(`backend/internal/rooms/game.go`, `backend/internal/rooms/scheduler.go`):

| Operation | Guarantee | Mechanism | Known failure window |
|---|---|---|---|
| Welcome grant (default 1,000,000 coins, 50 diamonds; live from `welcome` in the app-policy file) | Exactly once per account | Amounts read once per new account; wallet and identity row inserted in one transaction; the `(provider, subject)` primary key serializes concurrent first sign-ins. Refresh, reconnect, guest and device resume, device binding and linking never grant again; concurrent first `/auth/guest` calls with one `deviceId` create one account; a config change never alters existing wallets. | None known |
| Entry fees | All players charged or none; at most once per room round | `wallet.DebitAll` (one transaction, `SELECT … FOR UPDATE`); guard key `settle:fee:{room}:{round}` (24 h) taken with `SETNX` first; if the lobby changed before the room switched to playing, every charged player is credited back (`entry_fee_refund`) | If the process dies after the debit commits but before the room commit, the in-process refund does not run and is not retried; the guard key prevents a second charge. A failed refund credit is logged and counted in `wallet_settlement_failures_total{op="refund"}` but not retried. Neither case is repaired automatically (by design there is no ledger to reconcile against). |
| Payout (pot to the winner) | At most once — never twice | Scheduler job claims `settle:pay:{room}:{round}` with `SETNX` (7 d) **before** the PostgreSQL credit; on a credit error the claim is released and the job retried (attempt × 5 s, at most 10) | A crash between the claim and the PostgreSQL commit loses that payout (it is not retried). |
| Mission claims, purchases | Exactly once | Claim or inventory row and the wallet change in the same transaction (primary key); `Idempotency-Key` replays the stored response | None known |
| Maintenance | No settlement while active | Turn and fill timers are pushed forward; no auto-moves, forfeits, payouts or debits | — |

Entry fees are flat per player — **Ludo 100,000 coins, Snakes & Ladders
50,000 coins** by default — and are set live by `entryFees` in the
per-environment app-policy file (hot-reloaded; `ENTRY_FEE_*` and the built-in
defaults are fallbacks). A room keeps the fee it was created with, so a change
only applies to new rooms (`docs/app-version-policy.md` → Entry fees).
Rooms with a bot seat, practice rooms and load-test rooms charge **no entry
fee and pay no coins**. Coins and diamonds are virtual and non-redeemable.

## Security

- **Rate limits** (`backend/internal/ratelimit`, Redis fixed windows): sign-in
  30/min/IP · guest creation 10/h/IP · refresh + logout 60/min/IP · app config
  120/min/IP · telemetry 60/min/IP · account linking 10/min/account ·
  WebSocket connects 30/min/account · room codes 10/min/account · matchmaking
  20/min/account · wallet operations 30/min/account · social 30/min/account ·
  device bind/unbind 10/min/account (linking budget) · device resume 30/min/IP
  (sign-in budget) ·
  bot service 600/min/IP. Per socket: 10 commands/s (burst 20); quick chat
  1 per 3 s and 10/min; invites 10/min; friend requests 60/h.
- **Tokens**: provider credentials are verified server-side (OIDC JWKS,
  Apple nonce, Facebook `debug_token`); emails never match or merge accounts.
  App access tokens are 15-minute HS256 JWTs checked against the live session;
  refresh tokens rotate with reuse detection. **One active device per
  account**: each sign-in atomically revokes the account's previous human
  session (`usess:{userId}` pointer, `sessrep:{sid}` tombstone), whose device
  gets `401 session_replaced` and has its WebSocket closed at once with
  `4401`; bot sessions are exempt. Only SHA-256 hashes of refresh
  tokens, guest secrets and the bot service key are stored. Device ids are
  stored only as `HMAC-SHA256(k, platform:deviceId)` (k derived from
  `PUBLIC_ID_KEY`) and used only to restore the account on that device
  ([authentication.md](authentication.md#device-binding-restore-after-update-or-reinstall)).
- **Validation**: strict JSON (unknown fields rejected); WebSocket text frames
  only, ≤ 4096 bytes after decompression, known message types, seat / phase /
  `turnSeq` checks, de-duplicated message ids.
- **Network and secrets**: TLS at the load balancer; PostgreSQL and Redis on a
  private network only; secrets only via environment or a secret manager;
  production startup refuses `RATE_LIMIT_DISABLED`, `BOT_LOADTEST_ENABLED`,
  provider endpoint overrides and any dice source other than `crypto/rand`. Version headers are a compatibility policy, not
  proof of a genuine binary.

Details and diagrams: [architecture.html#security-testing](architecture.html#security-testing).

## Observability: live player counts

The backend serves Prometheus metrics on `METRICS_ADDR` (`GET /metrics`,
internal network only; transport metrics are listed in
[architecture.html#ws-metrics](architecture.html#ws-metrics)). How many people
and bots are playing right now is answered by four **cluster-wide** gauges.
Every instance exports the same values, so aggregate them with `max`, never
`sum`:

| Metric | Labels | Meaning |
|---|---|---|
| `players_in_game` | `actor` = `human` \| `bot` | Seats in rooms with status `playing` whose player has not forfeited (left or timed out). Load-test bots count as `bot`. |
| `rooms_in_game` | `game` = `ludo` \| `snakes_ladders`, `mode` = `public` \| `private` \| `practice` | Rooms with status `playing` (load-test rooms are `public`). Every combination is exported, 0 included. |
| `players_in_lobby` | `actor` | Seats in rooms with status `lobby`: public matchmaking, private rooms before the host starts, practice rooms waiting for bots. Requested bots that have not taken their seat are not counted. |
| `game_stats_refreshed_timestamp_seconds` | — | Unix time of the last successful recount. |

`ws_connections_active{actor}` stays **per instance** (open WebSockets on that
process): `sum` it across instances. Rooms in the rematch window (`finished`)
appear in neither the game nor the lobby gauges.

How the counts stay correct with several instances
(`backend/internal/rooms/stats.go`, keys in
[redis-keys.md](../backend/docs/redis-keys.md#live-game-counts)): every room
commit atomically updates the room's entry in the Redis index
`idx:rooms:live` (status, game, mode, human and bot seats, tagged with the
room revision), so the index cannot drift from room state. Every
`GAME_STATS_INTERVAL` (default 15 s, jittered) one instance — the holder of the
`stats:game:lease` lease — recounts the index in bounded batches, prunes
entries of expired rooms, verifies each entry's revision against the room
(reading the room itself when they differ, e.g. during a rolling deploy),
publishes the gauges and caches the result in `stats:game`; the other
instances publish that cached result. Values are at most about two
intervals old; if the lease holder crashes, another instance takes over
within about three intervals (at once on a graceful shutdown). Rooms last
written by an instance without the index (only during the rolling deploy
that introduces it) are counted from their next commit. A recount of 20,000
live rooms takes ≈ 48 ms (≈ 2 µs of Redis time per room).

```promql
max by (actor) (players_in_game)                    # playing now, humans vs bots
max by (game, mode) (rooms_in_game)
max by (actor) (players_in_lobby)
sum by (actor) (ws_connections_active)              # connected now
time() - max(game_stats_refreshed_timestamp_seconds) > 120   # alert: recount stuck
```

## Pending (not yet implemented or configured)

Facebook app and credentials; Apple Developer configuration; release signing
SHA-1 / Play App Signing; App Store and Play listings (store URLs are empty, so
the app shows "not yet available in the store"); Firebase DebugView
verification on a device; production infrastructure. The Flutter play and
meta screens are implemented (`feature_routes.dart` spreads `playRoutes` and
`metaRoutes`) and covered by widget tests; a hands-on play-through on physical
devices is still pending. See
[architecture.html#status](architecture.html#status).

## Related documents

[websocket-protocol.md](websocket-protocol.md) ·
[rest-api.md](rest-api.md) ·
[authentication.md](authentication.md) ·
[app-version-policy.md](app-version-policy.md) ·
[progression.md](progression.md) ·
[cosmetics-catalog.md](cosmetics-catalog.md) ·
[bot-play.md](bot-play.md) ·
[deployment.md](deployment.md) ·
[performance.md](performance.md) ·
[../monitoring/README.md](../monitoring/README.md) ·
[../backend/docs/game-rules.md](../backend/docs/game-rules.md) ·
[../backend/docs/redis-keys.md](../backend/docs/redis-keys.md)
