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

This file is a short overview. It also holds the two sections that code and
other docs link to by name: [Wallet settlement guarantees](#wallet-settlement-guarantees)
and [Security](#security).

## System in one paragraph

A Flutter app (Android/iOS, `com.ludoroyale.app`) talks to an **authoritative
Go backend** over HTTPS REST (`/api/v1`) and one WebSocket
(`GET /api/v1/ws`, protocol `ludo-royale.v1`). The backend owns dice
(`crypto/rand`), rules (Ludo classic/quick and Snakes & Ladders engines), room
state, turn timers, wallets, progression and sessions. Live state, timers,
sessions and cross-instance pub/sub live in **Redis**; durable data lives in
**PostgreSQL** schemas `wallet` (balances only), `identity` (provider →
account mappings) and `progression`. There are no match-history, ledger or
profile tables. Identity providers only prove identity: **Firebase
Authentication is not used**, and Firebase is in the app for consent-gated
Analytics only. A separate Go service, **bot-play**, plays as server-labelled
bots through the same protocol with room-scoped bot tokens.

## Sections of the HTML page

| # | Section | What it covers |
|---|---|---|
| 1 | [System architecture](architecture.html#architecture) | Context and backend layers, [who is authoritative for what](architecture.html#who-is-authoritative), [schema boundaries](architecture.html#schema-boundaries), Redis roles, [app-issued tokens](architecture.html#app-tokens) |
| 2 | [Google Sign-In](architecture.html#google-sign-in) | Nine-step sequence, Google Cloud project `ludo-royale-63887` and its Web / iOS / Android (debug) OAuth clients |
| 3 | [Guest login and Save Progress](architecture.html#guest-save-progress) | Guest creation and resume, linking, `identity_conflict` (no merge) and `provider_already_linked` |
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
| Welcome grant (1,000,000 coins, 50 diamonds) | Exactly once per account | Wallet and identity row inserted in one transaction; the `(provider, subject)` primary key serializes concurrent first sign-ins. Refresh, reconnect, guest resume and linking never grant again. | None known |
| Entry fees | All players charged or none; at most once per room round | `wallet.DebitAll` (one transaction, `SELECT … FOR UPDATE`); guard key `settle:fee:{room}:{round}` (24 h) taken with `SETNX` first; if the lobby changed before the room switched to playing, every charged player is credited back (`entry_fee_refund`) | If the process dies after the debit commits but before the room commit, the in-process refund does not run and is not retried; the guard key prevents a second charge. A failed refund credit is logged and counted in `wallet_settlement_failures_total{op="refund"}` but not retried. Neither case is repaired automatically (by design there is no ledger to reconcile against). |
| Payout (pot to the winner) | At most once — never twice | Scheduler job claims `settle:pay:{room}:{round}` with `SETNX` (7 d) **before** the PostgreSQL credit; on a credit error the claim is released and the job retried (attempt × 5 s, at most 10) | A crash between the claim and the PostgreSQL commit loses that payout (it is not retried). |
| Mission claims, purchases | Exactly once | Claim or inventory row and the wallet change in the same transaction (primary key); `Idempotency-Key` replays the stored response | None known |
| Maintenance | No settlement while active | Turn and fill timers are pushed forward; no auto-moves, forfeits, payouts or debits | — |

Rooms with a bot seat, practice rooms and load-test rooms charge **no entry
fee and pay no coins**. Coins and diamonds are virtual and non-redeemable.

## Security

- **Rate limits** (`backend/internal/ratelimit`, Redis fixed windows): sign-in
  30/min/IP · guest creation 10/h/IP · refresh 60/min/IP · app config
  120/min/IP · telemetry 60/min/IP · account linking 10/min/account ·
  WebSocket connects 30/min/account · room codes 10/min/account · matchmaking
  20/min/account · wallet operations 30/min/account · social 30/min/account ·
  bot service 600/min/IP. Per socket: 10 commands/s (burst 20); quick chat
  1 per 3 s and 10/min; invites 10/min; friend requests 60/h.
- **Tokens**: provider credentials are verified server-side (OIDC JWKS,
  Apple nonce, Facebook `debug_token`); emails never match or merge accounts.
  App access tokens are 15-minute HS256 JWTs checked against the live session;
  refresh tokens rotate with reuse detection. Only SHA-256 hashes of refresh
  tokens, guest secrets and the bot service key are stored.
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
