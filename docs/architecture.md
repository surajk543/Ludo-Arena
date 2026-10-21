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
[PostgreSQL on the hot path](#postgresql-on-the-hot-path) and [Security](#security).

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
| 10 | [Deployment and configuration](architecture.html#deployment) | Target topology (pending), local dev, [environment variables by name](architecture.html#env-vars), identifiers |
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

## PostgreSQL on the hot path

Gameplay (rolls, moves, turns, timers, chat, presence) never touches
PostgreSQL: live state is in Redis only. These are the remaining PostgreSQL
calls on latency-sensitive paths and how each one is handled:

| Path | PostgreSQL call | Handling | Why |
|---|---|---|---|
| Sign-up (guest, device guest, first provider sign-in) | wallet + identity rows (one transaction) | synchronous | the account must exist before tokens are issued |
| | progression row (`progression.Bootstrap`) | **asynchronous**: bounded background queue (`server.Core.Async`: 4 workers, 1,024 jobs, 10 s per job; full queue = dropped and counted) | every progression read and write creates the row lazily, so a late, failed or dropped bootstrap is harmless |
| | progression summary in the sign-up response | **skipped**: an account created by this request has the starter summary by definition | |
| `matchmaking.join`, `room.create`, `room.join`, `practice.start` | seat summary (level, title, loadout) | **Redis cache** `seat:{userId}` (1 h), PostgreSQL only on a miss; looked up concurrently with the join's other checks (not for `practice.start`) | |
| | wallet pre-check (`checkFunds`, one primary-key read) | synchronous | UX guard so a player who cannot pay never waits in a lobby; the authoritative check is `DebitAll` at start + `removeBroke` |
| Lobby fills, host starts | `wallet.DebitAll` (+ refunds) | synchronous | all-or-nothing before the game starts ([settlement guarantees](#wallet-settlement-guarantees)) |
| `chat.emote` (non-starter emote) | inventory ownership | **Redis set** `emotes:{userId}` (1 h); overlaps the room load | |
| Game end | payout credit, match record (XP, missions, unlocks) | asynchronous `sched` jobs with bounded retries | |
| REST (`/me`, wallet, missions/claims, collection/purchases, social, leaderboards) | reads and writes | synchronous | the response is the database result |

**Invalidation rules** (always *after* the PostgreSQL commit):

- `seat:{userId}` and its fill lease are deleted (`progression.Service.InvalidateSeat`)
  by a level-up in a recorded match, a level-up from a mission claim, and every
  equip (including a reset to the starter item). Purchases and item grants
  change ownership, not the loadout, so they do not touch it. A miss takes a
  5 s lease atomically with the read and stores its PostgreSQL result only if
  the lease is still its own, so a fill that raced a commit can never store
  the old value. Anything new shown on a seat that is stored in PostgreSQL
  must call `InvalidateSeat` from its writer.
- `emotes:{userId}` gets every newly granted emote (purchase, mission/event
  reward, level milestone) added if the set exists. Inventory rows are never
  deleted, so a member is always a correct "owned"; a member missing from the
  set is confirmed in PostgreSQL and added, so a fill that raced a grant can
  never deny an owned emote. Starter emotes need no lookup.
- The TTLs only bound how long a *failed* invalidation can leave a seat
  stale; one hour outlasts a game, so the join after a game is usually a hit.
- Any Redis error falls back to PostgreSQL: a cache outage never fails a
  join or an emote. Metrics: `cache_lookups_total{cache,result}`
  (`hit`/`miss`/`verify`/`error`), `cache_write_errors_total{cache,op}`,
  `async_jobs_total{job,result}` (`ok`/`error`/`panic`/`dropped`/`abandoned`).

**Shutdown:** `App.Wait` (called by `cmd/server` after the HTTP server
stopped) drains queued background jobs for at most 5 s; jobs still queued
then are abandoned and counted (the lazily created rows make that harmless).

**Measured** (`backend/tests/hotpath_measure_test.go`: in-process, local
PostgreSQL 16 + Redis 7 on one laptop, 100 accounts × 20 rounds; medians of
the per-run p50/p95 over the quiet runs of 8 alternating before/after runs):

| Path | p50 before → after | p95 before → after | PostgreSQL statements per call |
|---|---|---|---|
| `POST /auth/guest` (new account) | 718 → 609 µs | 1,104 → 953 µs | 9 → 6 on the request path (0 progression) + 1 in the background |
| matchmaking join, warm | 362 → 318 µs | 430 → 408 µs | 3 → 1 (wallet pre-check only) |
| matchmaking join, first per account (cache fill) | 394 → 504 µs | 622 → 770 µs | 3 → 3 |
| owned emote, warm | 164 → 171 µs | 200 → 222 µs | 1 → 0 |
| 32 concurrent players: create room | 1,790 → 1,521 µs | 3,470 → 2,213 µs | 3 → 1 |
| 32 concurrent players: create + emote + leave | 8.7k → 9.6k rounds/s | | 4 → 1 per round |
| wallet pre-check alone / `DebitAll` (2 players) | 22 µs / 149 µs | 30 / 211 µs | 1 / 5 (unchanged) |

On one machine a Redis round trip (~58 µs) costs more than a loopback
PostgreSQL point read (~24 µs), so the single-call gains here come mostly
from overlapping lookups; the larger effect is fewer PostgreSQL statements and
pool checkouts per join (3 → 1) and per emote (1 → 0), which matters under
concurrency and with a remote database.

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
[../backend/docs/game-rules.md](../backend/docs/game-rules.md) ·
[../backend/docs/redis-keys.md](../backend/docs/redis-keys.md)
