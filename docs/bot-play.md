# bot-play — automated players

`bot-play/` is a standalone Go service (its own module, `ludoroyale/botplay`)
that runs automated players for Ludo Royale. Bots are **pure protocol
clients** of the Go backend: they use the same `ludo-royale.v1` WebSocket
protocol as the Flutter app, with server-issued bot session tokens.

**No Firebase or analytics.** bot-play contains no Firebase, Crashlytics,
Analytics or any other analytics SDK, and sends no telemetry anywhere except
its own Prometheus `/metrics` endpoint and structured logs. Bot status is
derived by the backend from the bot session token (`actorType: "bot"`), so
bot traffic is excluded from human analytics on the server side.

Related contracts: [`websocket-protocol.md`](websocket-protocol.md) (§10 Bot
clients), [`rest-api.md`](rest-api.md) (Bot service),
[`../backend/docs/game-rules.md`](../backend/docs/game-rules.md),
[`app-version-policy.md`](app-version-policy.md).

---

## 1. Responsibilities

| bot-play does | bot-play never does |
|---|---|
| Obtain controller tokens with the service key and serve backend assignments | Generate dice, decide legality, compute turns or winners |
| Create bot sessions, connect, keep a local copy of room state | Mutate Redis/PostgreSQL or call wallet/progression/social/account APIs |
| Roll when it is its turn; choose among the **server-listed** legal Ludo tokens | Claim outcomes, send results, or send a "bot" flag |
| Resync on gaps/hash mismatches, reconnect with backoff | Chat, create/join rooms by code, or act outside its assigned room |
| Leave, revoke its session, shut down gracefully | Run load tests against production |

The backend is authoritative. If bot-play's local view is wrong, it asks for a
snapshot (`game.request_sync`); the server's events are always what it applies.

## 2. Architecture

```
            +-------------------- bot-play process ----------------------+
            |  config.Store (atomic.Pointer) <- Watcher (mtime poll, HUP) |
            |                                                              |
 REST  <----|  client (controller JWT cache)                               |
 /bot/*     |    ^           ^              ^                              |
            |    |           |              |                              |
            |  assignment   fill loop     load-test loop (ramp, churn)    |
            |  long-poll    (public_fill)  (loadtest)                      |
            |     \           |             /                              |
            |      +---> Service: admission, population reconciler,       |
            |            token buckets, maintenance back-off, shutdown    |
            |                    |  one goroutine per bot                  |
            |                    v                                         |
 WS    <----|  Bot: session -> connection (reader + writer goroutines,    |
 /ws        |       bounded queue, heartbeat) -> RoomState reducer        |
            |       -> strategy (think time, Ludo evaluator) -> commands  |
            |                                                              |
            |  health: /healthz /readyz /metrics (127.0.0.1:9091)          |
            +--------------------------------------------------------------+
```

Package map: `internal/config` (schema, defaults, validation, load-test
guard, reload), `internal/profiles`, `internal/client` (REST), 
`internal/connection` (WS transport, protocol types, reducer, FNV-1a hash),
`internal/ludo` (geometry + evaluator), `internal/snakes_ladders` (geometry
only), `internal/strategy` (think time, move choice), `internal/matchmaking`
(fill planner, load-test mix), `internal/runner` (controller + bot game loop),
`internal/health`, `internal/metrics` (Prometheus + load-test report).

Each bot runs on its own goroutine; all of its game state is owned by that
goroutine (no locks on room state). Its WebSocket has exactly one reader and
one writer goroutine, a bounded outbound queue (`connection.outbound_queue_size`)
and the client heartbeat (`{"t":"ping"}` every 15 s, dead after 10 s without
`pong`). Every loop honours context cancellation.

## 3. How bot-play connects (auth and admission)

### 3.1 Calls made (exact)

REST (base `connection.backend_http_url`, e.g. `http://localhost:8080/api/v1`;
REST calls send `User-Agent: bot-play/<version>` and no `X-App-*` headers —
the bot endpoints are not version-gated):

| # | Call | Auth header | Body | Used for |
|---|---|---|---|---|
| 1 | `POST /bot/controller/token` | `Authorization: Bot-Service <BOT_SERVICE_KEY>` | – | Controller JWT; refreshed at 80 % of its lifetime (≥ 30 s before `expiresAt`), and once on any 401 |
| 2 | `GET /bot/assignments?wait=<1..25>` | `Bearer <controller JWT>` | – | Long-poll; only while practice/public_fill is configured **and** there is headroom. `{"maintenance":true}` in the body is treated like 503 |
| 3 | `GET /bot/lobbies` | controller | – | Public fill planning (every `poll_interval_ms`); also the readiness probe when idle. `publicFillEnabled:false` pauses fill |
| 4 | `POST /bot/lobbies/{roomId}/fill` | controller | `{"count":n}` | Public fill. Accepts `{"assignments":[…]}` (documented) or `{"requested":n}` (assignments then arrive via #2). 409 → cooldown; 403 → pause 60 s |
| 5 | `POST /bot/sessions` | controller | `{"assignmentId","name","profile"}` or `{"mode":"loadtest","name"}` | Bot access token (≤ 2 h), `uid`, `roomId`. No `bot` field is ever sent |
| 6 | `DELETE /bot/sessions/{uid}` | controller | – | Always on bot exit (also during shutdown, with a fresh 5 s context); 404 = already revoked |

WebSocket (`connection.backend_ws_url`, e.g. `ws://localhost:8080/api/v1/ws`):

```
Authorization: Bearer <bot accessToken>
Sec-WebSocket-Protocol: ludo-royale.v1
Sec-WebSocket-Extensions: permessage-deflate; client_no_context_takeover; server_no_context_takeover
X-App-Platform: bot
X-App-Version: <bot-play version, e.g. 1.0.0>      X-App-Build: <build>
X-Reconnect: 1                                      (only when replacing a dropped connection)
```

Commands sent (payloads contain exactly these fields; the backend decodes
strictly):

| Command | Payload | When |
|---|---|---|
| `ping` | – | every `ping_interval_seconds` |
| `game.request_sync` | `{"roomId"}` (or `{}` when unknown) | after every `connection.ready`; on gap, hash mismatch, `stale_state`/`invalid_phase`/`illegal_move`, unconfirmed action, or stall |
| `game.roll_dice` | `{"roomId","turnSeq"}` | own turn, phase `awaiting_roll`, `dice == 0`, once per `(turnSeq, phase)` |
| `game.make_move` | `{"roomId","turnSeq","token"}` | own turn, phase `awaiting_move`, **≥ 2** legal tokens (one legal token is applied by the server) |
| `room.leave` | `{"roomId"}` | game finished (= rematch declined), forfeited, retiring now, lobby timeout |
| `matchmaking.join` | `{"game","variant","capacity"}` | load-test bots only |
| `matchmaking.cancel` | `{}` | load-test bots leaving a lobby that has not started |
| `game.rematch` | `{"roomId","accept":true}` | only with `bots.accept_rematch: true` (practice/private); if refused, the bot leaves |

Message ids are `m1, m2, …` per bot and stay unique across reconnects (the
server de-duplicates `(userId, id)` for 2 minutes).

### 3.2 Assignment flow (practice, private, public fill)

1. The backend creates an assignment (`practice.start`, `room.add_bot`, or a
   fill request) and queues it.
2. bot-play receives it via the long-poll (or inline in the fill response)
   and **admits** it only if: not shutting down; `bots.enabled`; the kind's
   mode is configured (`practice`/`private` → `practice`, `public_fill` →
   `public_fill`); the game is enabled in `bots.games`; not expired; not a
   duplicate; active < `min(target_active_bots, max_concurrent_bots)`; and the
   game is under `per_game_max`. Otherwise it is dropped (metric
   `assignments_rejected_total{reason}`) and expires on the backend.
3. Session creation is rate limited (`max_room_joins_per_second`) and
   retried (bounded) on 5xx/429; 4xx (`assignment_not_found`,
   `room_unavailable`) ends the bot.
4. Dial (global `max_connection_attempts_per_second` limiter), read
   `connection.ready` (records negotiated compression and server clock
   offset), send `game.request_sync`, then play.
5. On `game.finished` the bot leaves (declines the rematch), closes with
   1000, and revokes its session.

### 3.3 State reconciliation

For every event carrying `roomId` and `v`: `v <= local.v` → ignore;
`v == local.v + 1` → apply the documented reducer, then compare `h` with the
locally computed FNV-1a of the canonical string (mismatch → resync);
`v > local.v + 1` → resync, buffer nothing. Snapshots (`room.updated`,
`game.started`, `game.state`) replace local state when `room.v >= local.v`.
No commands are sent while a sync is pending. If the server's turn deadline
passed more than 2 s ago and no newer event arrived, the bot resyncs once for
that state version (covers a lost last event).

### 3.4 Decisions and timing

* Think time = profile `think_time_ms`, clamped into `bots.think_time`
  (`randomize: false` → midpoint), **capped at 40 % of the time left** before
  the server's `turn.deadline` (server clock offset from `connection.ready`).
* Per-bot command token bucket `limits.max_actions_per_second_per_bot`.
* `rate_limited` → exponential, jittered slowdown (retry when `retry: true`);
  `not_your_turn` → wait; `stale_state`/`invalid_phase`/`illegal_move` →
  resync; `not_in_room`/`room_not_found`/`room_closed` → room over;
  `maintenance` → back off; `unauthorized` → exit.
* A command not confirmed by its authoritative event (`game.dice_result` /
  `game.move_applied`) within `action_confirm_timeout_ms` triggers a resync.

### 3.5 Connection failures

| Signal | Behaviour |
|---|---|
| Upgrade 401 / close 4401 | Session invalid/expired → exit (session revoked) |
| Upgrade 503 / close 4503 / `error maintenance` | Global maintenance back-off (`maintenance_backoff_seconds` ±20 %), new work paused, then each bot reconnects after an extra random delay in `[0, maintenance_backoff]` |
| Upgrade 429 / close 4429 | Reconnect after ≥ 10 s (or `Retry-After`) |
| Upgrade 400 / 426, close 4426 | Bug/policy → exit, logged as error (bots are exempt from version policy) |
| Close 4409 | Replaced → never auto-reconnect; exit |
| 1001, 1006, 1008, 4400, 4508, pong timeout, queue overflow | Reconnect with `X-Reconnect: 1`, full-jitter backoff `random(0, min(max, base·2^(n-1)))`, per-bot budget `max_reconnect_attempts_per_minute`, `reconnect_max_attempts`; attempts reset after `reconnect_reset_seconds` up; then resync and verify (`v` not regressed, hash matches) |

## 4. Modes

### practice (`bots.modes: [practice]`)
Serves assignment kinds `practice` (a human sent `practice.start` with N bots)
and `private` (the host used `room.allow_bots` + `room.add_bot`).

### public_fill (`bots.modes: [public_fill]`, combinable with practice)
Matchmaking assistance. Every `poll_interval_ms` bot-play lists lobbies and
requests a fill for a lobby only when **all** hold:

* `bots.enabled`, `public_matchmaking.enabled`, the game enabled in both
  `bots.games` and `public_matchmaking.per_game` (and the backend does not
  report `publicFillEnabled: false`);
* `fill_after_seconds <= waitingMs/1000 < maximum_wait_seconds`;
* `humans >= minimum_humans`;
* `pendingBots == 0` and no request for that room within
  `refill_cooldown_seconds` (failed requests count too).

`count = min(capacity − humans − bots − pendingBots, max_bots_per_room − bots,
service headroom, per-game headroom)`; oldest lobbies first. The backend
re-validates (open lobby, capacity, `BOT_MAX_PER_ROOM`,
`BOT_PUBLIC_FILL_ENABLED`). Rooms with a bot are played with entry fee 0 and
no payout (backend rule).

### loadtest (`bots.modes: [loadtest]`, exclusive)
Development/preproduction traffic generation (also WebSocket compression and
concurrency benchmarks). See §8.

## 5. Configuration reference

Files: one YAML config (`--config`) and `profiles.yaml` (`--profiles`).
Every key is optional (defaults below); unknown keys are rejected. The only
environment input is **`BOT_SERVICE_KEY`** (32–256 characters, no whitespace;
never read from files, never logged). `[R]` = restart required (a reload that
changes it is rejected and the previous config stays active).

### app
| Key | Default | Range / values | Notes |
|---|---|---|---|
| `name` | `bot-play` | 1–64 chars | log field |
| `environment` | `development` | `development`, `preprod` (`preproduction` alias), `production` | [R]; selects caps and guards |
| `log_level` | `info` | debug, info, warn, error | applied on reload |
| `log_format` | `json` | json, text | [R] (fixed at startup) |
| `reload_poll_seconds` | 5 | 0–3600 | 0 = SIGHUP only |

### connection
| Key | Default | Range | Notes |
|---|---|---|---|
| `backend_http_url` | `http://localhost:8080/api/v1` | http(s) URL | [R]; production requires https |
| `backend_ws_url` | `ws://localhost:8080/api/v1/ws` | ws(s) URL | [R]; production requires wss |
| `connect_timeout_ms` | 5000 | 100–60000 | dial + wait for `connection.ready` |
| `request_timeout_ms` | 5000 | 100–60000 | per REST call (long-poll adds the wait) |
| `assignment_wait_seconds` | 20 | 1–25 | long-poll `wait` (backend max 25) |
| `reconnect_enabled` | true | | |
| `reconnect_max_attempts` | 8 | 0–100 | consecutive failures before a bot gives up |
| `reconnect_backoff_base_ms` | 500 | 10–60000 | full jitter |
| `reconnect_backoff_max_ms` | 30000 | 10–300000, ≥ base | |
| `reconnect_reset_seconds` | 30 | 1–3600 | uptime that resets the attempt counter |
| `maintenance_backoff_seconds` | 30 | 1–3600 | pause + reconnect spread after 503/4503 |
| `ping_interval_seconds` | 15 | 1–60 | |
| `pong_timeout_seconds` | 10 | 1–60 | |
| `outbound_queue_size` | 64 | 8–4096 | overflow closes and reconnects |
| `read_limit_bytes` | 1048576 | 4096–16 MiB | inbound message limit (after decompression) |
| `action_confirm_timeout_ms` | 5000 | 200–60000 | unconfirmed command / sync → resync / reconnect after 3 |
| `readiness_stale_seconds` | 60 | 5–3600 | `/readyz` fails when the backend was not reached within this |

### bots
| Key | Default | Range | Notes |
|---|---|---|---|
| `enabled` | true | | false: no new assignments/fills, cancel load-test matchmaking, running games finish (or leave per policy), no reconnects |
| `modes` | `[practice]` | practice, public_fill, loadtest | loadtest exclusive and [R] |
| `games.{ludo,ludo_quick,snakes_ladders}` | true | | missing key = true |
| `target_active_bots` | 50 | 0–max_concurrent | admission cap for practice/public_fill |
| `max_concurrent_bots` | 100 | 1–env cap (dev 10000, preprod 5000, **prod 500**) | hard cap, never exceeded |
| `per_game_max.{game}` | unset (= max_concurrent) | 0–max_concurrent | |
| `max_bots_per_room` | 3 | 1–3 | fill never asks for more |
| `max_room_joins_per_second` | 5 | >0–1000 | token bucket (session creation, `matchmaking.join`) |
| `max_connection_attempts_per_second` | 10 | >0–1000 | global dial token bucket (reconnect-storm guard) |
| `lobby_wait_timeout_seconds` | 90 | 5–600 | leave a lobby that has not started |
| `accept_rematch` | false | | practice/private only; falls back to leaving if refused |
| `public_matchmaking.enabled` | false | | runtime switch |
| `public_matchmaking.per_game.{game}` | false | | missing key = false (opt-in) |
| `public_matchmaking.poll_interval_ms` | 2000 | 100–60000 | ±10 % jitter |
| `public_matchmaking.fill_after_seconds` | 15 | 0–300 | |
| `public_matchmaking.minimum_humans` | 1 | 1–3 | |
| `public_matchmaking.maximum_wait_seconds` | 27 | 1–600, > fill_after | skip lobbies about to start/time out (backend default 30 s) |
| `public_matchmaking.refill_cooldown_seconds` | 10 | 1–600 | |
| `think_time.min_ms` / `max_ms` | 300 / 6000 | 0–15000, min ≤ max | clamp for profile think time |
| `think_time.randomize` | true | | false = midpoint |
| `behavior.default_profile` | `balanced` | must exist | resolved at every decision |
| `behavior.random_seed` | 0 | int64 | 0 = random; else per-bot seed `seed + id·φ` (reproducible) |
| `behavior.disconnect_simulation_enabled` | false | | |
| `behavior.disconnect_probability` | 0 | 0–0.2 | per own action |
| `identity.display_name_prefix` | `Bot` | ≤ 12 chars | requested name `"<prefix> <name>"`; the backend strips a leading `Bot` word from the seat name (so `Bot Asha` is shown as `Asha`) and limits it to 20 runes |
| `identity.names_pool` | built-in 16 names | 1–16 chars each | |
| `shutdown.graceful_timeout_seconds` | 60 | 1–3600 | |
| `shutdown.policy` | `finish_games` | finish_games, leave_now | leave_now forfeits running games |

### limits
| Key | Default | Range |
|---|---|---|
| `max_actions_per_second_per_bot` | 4 | >0–20 |
| `max_reconnect_attempts_per_minute` | 6 | 1–120 |

### loadtest (never valid in `production`)
| Key | Default | Range | Notes |
|---|---|---|---|
| `enabled` | false | | [R]; required for `modes: [loadtest]` |
| `allowed_hosts` | `[localhost, 127.0.0.1]` | hostnames or `*.suffix` | [R]; both backend URLs must match |
| `forbidden_hosts` | `[]` | same | [R]; a match always refuses |
| `target_connections` | 100 | 1–max_concurrent | population target (reloadable) |
| `ramp_per_second` | 10 | >0–1000 | new bots per second |
| `duration_seconds` | 600 | 1–86400 | then drain + report |
| `game_mix` | `{ludo: 50, ludo_quick: 25, snakes_ladders: 25}` | weights ≥ 0, sum > 0 | |
| `capacity_mix` | `{2: 40, 3: 20, 4: 40}` | keys 2–4 | |
| `think_time_ms` | `{min: 200, max: 1500}` | 0–15000 | replaces profile think time |
| `churn_per_minute` | 0 | 0–100000 | forced disconnect + reconnect events per minute (Poisson) across the population |
| `slow_reader_fraction` | 0 | 0–1 | bots that read slowly |
| `slow_reader_delay_ms` | 250 | 0–10000 | delay per inbound message |
| `malformed_message_rate` | 0 | 0–0.5 | chance per action of also sending an invalid message |
| `report_path` | `loadtest-report.json` | | [R] |

### metrics
| Key | Default | Notes |
|---|---|---|
| `enabled` | true | [R] |
| `listen_addr` | `127.0.0.1:9091` | [R]; `/healthz`, `/readyz`, `/metrics` — keep internal |

Shipped files: `bot-play/configs/config.example.yaml` (every key documented),
`configs/environments/{development,preprod,production}.yaml`,
`configs/loadtest.example.yaml`, `configs/profiles.yaml`. Validate with
`bot-play --config <file> --profiles configs/profiles.yaml --validate`.

## 6. Profiles

`profiles.yaml` defines named profiles (`beginner`, `balanced`, `advanced`).
Each has `think_time_ms {min,max}` and Ludo `weights`:

| Weight | Feature (per server-listed legal token) |
|---|---|
| `enter_from_base` | 1 if the token leaves base |
| `capture_opponent` | number of opponent tokens sent to base (non-safe track square shared with other non-forfeited colours) |
| `reach_safe_square` | 1 if the token ends on a safe square (start/star squares or home column) from an unsafe one |
| `progress_toward_home` | destination progress / 56 |
| `complete_home` | 1 if the token reaches home (56) |
| `escape_danger` | bonus (0.5–1 by progress at risk) for leaving a square an opponent could hit with 1–6 |
| `avoid_danger` | penalty (0.5–1) for landing 1–6 squares ahead of an opponent on a non-safe square |
| `random_jitter` | seeded uniform noise in `[-w, +w]` |

Ties: higher destination progress, then lower token index. The evaluator
(`internal/ludo`) uses the documented geometry (absolute index
`(13·colour + progress) mod 52`, safe squares 0/8/13/21/26/34/39/47, home
column 51–55) **only to score** tokens the server already listed; it is
non-authoritative and never adds a token or predicts dice. Snakes & Ladders
has no choices — bots only roll; profiles affect only think time there.

## 7. Operating the service

### Starting practice bots (development)
1. Backend: set `BOT_SERVICE_KEY_SHA256` = hex SHA-256 of your key; restart.
2. `export BOT_SERVICE_KEY=…` (32–256 chars, e.g. `openssl rand -hex 32`).
3. `go run ./cmd/bot-play --config configs/environments/development.yaml --profiles configs/profiles.yaml`
4. In the app start a practice game; bots appear with the BOT badge
   (server-side `players[].bot`).

### Enabling / disabling public fill per game (no restart)
Edit the config file:
```yaml
bots:
  modes: [practice, public_fill]   # public_fill must be configured (no restart needed to add it)
  public_matchmaking:
    enabled: true
    per_game: {ludo: true, ludo_quick: false, snakes_ladders: true}
```
then wait ≤ `reload_poll_seconds` or `kill -HUP <pid>`. Check
`config_reloads_total{result="success"}` and the "config reloaded" log line.
The backend must also have `BOT_PUBLIC_FILL_ENABLED=true`. To stop fills for
one game set its `per_game` entry to `false`; to stop all, `enabled: false`.

### Reload semantics
Config and profiles are re-read on SIGHUP and on mtime/size change. The whole
new pair is parsed and validated; if invalid (or a [R] key changed) it is
rejected, logged, counted in `config_reload_failures_total`, and the last
valid config stays active. Valid configs are swapped atomically:

| Change | Takes effect |
|---|---|
| lower `target_active_bots` / `loadtest.target_connections` | excess bots finish their current game then exit (immediately with `shutdown.policy: leave_now`); load-test bots not in a game exit now; seated assignment bots still play their game |
| lower `max_concurrent_bots` | no new bots until under the limit (plus the target rule above) |
| profile/weights/`default_profile` | next decision point |
| think time | next scheduled action |
| `bots.enabled: false` | stop new assignments/fills, cancel load-test matchmaking, running games finish (or leave per policy), no reconnects; seated assignment bots still play their game |
| `modes` (practice ↔ public_fill), `games`, `per_game`, `public_matchmaking.*` | future sessions / next poll |
| rate limits, `log_level` | immediately |

### Shutdown
SIGINT/SIGTERM: stop polling/filling/spawning; `finish_games` lets bots finish
their game, `leave_now` leaves immediately; after
`graceful_timeout_seconds` remaining bots leave; sessions are always revoked
(`DELETE /bot/sessions/{uid}`); then the process exits 0. Exit codes: 1 runtime
error, 2 configuration, 3 load test refused.

## 8. Safe simulations and load tests

Guards — **all** must hold or bot-play refuses (exit code 3, reason in the log):

1. `app.environment` ∈ {development, preprod} (validation also rejects
   `loadtest.enabled` / `modes: [loadtest]` in production);
2. `loadtest.enabled: true` and `bots.modes: [loadtest]`;
3. CLI flag `--i-understand-this-is-a-load-test`;
4. both backend URL hosts match `loadtest.allowed_hosts` and none match
   `loadtest.forbidden_hosts`;
5. the backend accepts load-test sessions (it refuses when `APP_ENV=production`
   or `BOT_LOADTEST_ENABLED=false`; bot-play stops immediately with
   `load test refused (backend_refused)`).

Step by step:
1. Backend (dev/preprod): `BOT_LOADTEST_ENABLED=true`, service key hash set.
   For compression benchmarks also set `WS_COMPRESSION` /
   `WS_COMPRESSION_THRESHOLD` as needed.
2. Copy `configs/loadtest.example.yaml`; set hosts, `target_connections`,
   `ramp_per_second`, `duration_seconds`, mixes, churn, slow readers,
   malformed rate, `report_path`.
3. Validate: `bot-play --config lt.yaml --profiles configs/profiles.yaml --validate --i-understand-this-is-a-load-test`.
4. Run with the flag; watch `/metrics` (`bots_active`, `action_latency_seconds`,
   `state_hash_mismatches_total`, `bot_connection_failures_total`).
5. Lower `loadtest.target_connections` at runtime to ramp down; SIGTERM to stop
   early (report is still written).

Each load-test bot creates a load-test session, loops `matchmaking.join` with
the configured game/capacity mix, plays, leaves, and re-joins; sessions close
to expiry are retired and replaced. Churn drops a random connection
(Poisson, `churn_per_minute`) and verifies the resync after reconnecting.

Report (`report_path`, JSON): `startedAt`, `finishedAt`, `durationSeconds`,
`environment`, `backendHost`, `targetConnections`, `finalTargetConnections`,
`peakConnections`, `successfulSessions`, `failedSessions`, `gamesStarted` /
`gamesFinished` per game, `actionsTotal`, `actionsPerSecond`, `actionsByType`,
`latencyMs` per action (`count`, `p50`, `p95`, `p99`, `max`; actions roll,
move, sync, join), `errorsByCode`, `resyncs` (excluding the initial sync after
each connect), `resyncsByReason`, `hashMismatches` (must be 0),
`reconnectAttempts`, `reconnectSuccesses`, `reconnectSuccessRate`,
`reconnectResyncVerification`, `bytesReceived` (after decompression),
`compression` (negotiated/none), `connectionFailures`, `malformedSent`.

## 9. Monitoring and troubleshooting

Endpoints (`metrics.listen_addr`): `/healthz` (process alive), `/readyz`
(200 when the controller token is valid, the backend was reached within
`readiness_stale_seconds` and no maintenance back-off is active; otherwise 503
with a reason), `/metrics`.

Metrics (labels are small fixed sets — never ids):

| Metric | Labels |
|---|---|
| `bots_active` | game = ludo, ludo_quick, snakes_ladders, none |
| `bots_target` | – |
| `bot_connection_failures_total` | reason (dial_error, unauthorized, maintenance, rate_limited, bad_request, update_required, rejected, server_shutdown, policy_violation, protocol_violation, revoked, replaced, version, slow_consumer, abnormal, pong_timeout, queue_overflow, write_error, no_ready, normal, other) |
| `matchmaking_join_attempts_total` | – |
| `room_joins_total` | kind = practice, private, public_fill, loadtest |
| `game_actions_total` | type = roll, move, sync, leave, join, cancel, rematch |
| `invalid_action_responses_total` | code (documented error codes, else `other`) |
| `reconnects_total` | result = success, failure |
| `action_latency_seconds` (histogram) | action = roll, move, sync, join |
| `config_reloads_total` / `config_reload_failures_total` | result |
| `compression_negotiated_total` | result = negotiated, none |
| `ws_bytes_received_total` | – (payload bytes after decompression) |
| `state_resyncs_total` | reason (connect, reconnect, gap, hash_mismatch, stale_state, invalid_phase, illegal_move, action_timeout, sync_timeout, stalled, no_state, invalid, already_in_room) |
| `state_hash_mismatches_total`, `events_ignored_total{reason}` | |
| `assignments_received_total{kind}`, `assignments_rejected_total{reason}` | |
| `public_fill_requests_total{result}` | ok, conflict, forbidden, error |
| `bot_sessions_total{result}`, `games_started_total{game}`, `games_finished_total{game}` | |
| `controller_token_refreshes_total{result}`, `controller_ready` | |
| `bot_label_missing_total` | server did not mark the bot seat `bot:true` (contract issue) |
| `reconnect_resync_verifications_total{result}` | verified, failed, room_gone |
| `loadtest_malformed_sent_total{kind}` | |
| Go runtime + process collectors | |

Logs are structured (`log/slog`, JSON by default) with `bot_id`, `kind`,
`uid`, `room_id`, `assignment_id`. Tokens and the service key are never
logged (a `Secret` type redacts every formatting path, and a log hook redacts
any attribute named `*token`, `*key`, `*authorization`, `*secret`, …).

| Symptom | Check |
|---|---|
| `/readyz` 503 "controller token not valid" | `controller_token_refreshes_total{result="failure"}`; key mismatch with `BOT_SERVICE_KEY_SHA256`, key < 32 chars, backend unreachable |
| Practice games close with `bots_unavailable` | `assignments_rejected_total{reason}` (at_capacity, mode_disabled, game_disabled, game_at_capacity), `bots.enabled`, target/max |
| No public fills | `bots.modes` includes public_fill, `public_matchmaking.enabled`, `per_game`, backend `BOT_PUBLIC_FILL_ENABLED`, lobby age vs `fill_after/maximum_wait`, `public_fill_requests_total` |
| Many resyncs / hash mismatches | `state_resyncs_total{reason}`, `state_hash_mismatches_total` (a non-zero rate means the canonical hash rules diverged — compare with game-rules.md) |
| Reconnect storms | `bot_connection_failures_total{reason}`, lower `max_connection_attempts_per_second`, raise `maintenance_backoff_seconds` |
| Bots time out on turns | `action_latency_seconds`, `limits.max_actions_per_second_per_bot`, think time vs `TURN_SECONDS` |

## 10. Deployment and rollback

* Image: `docker build -t bot-play:<ver> --build-arg VERSION=<ver> --build-arg BUILD=<n> bot-play`
  (static binary, distroless `nonroot`, configs under `/app/configs`).
* Provide `BOT_SERVICE_KEY` from the secret store; mount environment configs
  if they differ from the image. Keep port 9091 cluster-internal; use
  `/healthz` for liveness, `/readyz` for readiness.
* Set the orchestrator's termination grace period above
  `bots.shutdown.graceful_timeout_seconds` (production default 300 s) so
  bots can finish their games.
* Run one replica unless you size `target_active_bots` per replica; every
  replica long-polls the same assignment queue (each assignment is handed out
  once).
* Rollback: deploy the previous image (or previous config file + SIGHUP).
  Emergency stop without a deploy: set `bots.enabled: false` (running games
  finish) or scale to zero (SIGTERM drain). Backend-side kill switches:
  `BOT_PUBLIC_FILL_ENABLED=false`, unset `BOT_SERVICE_KEY_SHA256`.

## 11. Security and limitations

* **Service key.** Only from `BOT_SERVICE_KEY` (32–256 chars, no whitespace);
  the backend stores only its SHA-256. It is used for exactly one call
  (`POST /bot/controller/token`) and never logged. **Rotation:** generate a new
  key, update `BOT_SERVICE_KEY_SHA256` on the backend and `BOT_SERVICE_KEY` for
  bot-play, and restart both (rolling); controller tokens issued with the old
  key expire within 15 minutes. The backend accepts one key at a time, so
  expect a brief gap of controller-token failures during rotation.
* **Scope.** Controller tokens only reach `/bot/*`. Bot session tokens are
  scoped to one room (or the load-test pool), expire within 2 hours, and can
  only roll, move, sync and leave (load-test bots: also matchmaking and
  rematch). Bots cannot touch wallets, progression, collection, social or
  account APIs, chat, or join by code.
* **Labelling.** Bots never send a bot flag; the backend derives
  `players[].bot` and `actorType: "bot"` from the session, and the protocol
  always marks bot seats `bot: true`. bot-play counts
  `bot_label_missing_total` if a snapshot ever shows its own seat as non-bot.
  Display names carry **no** bot label: the backend strips a leading `Bot`
  word (any case, followed by a space, `-`, `_`, `:` or `.`) from the
  requested name and falls back to a neutral first name (never "Bot") when
  nothing is left. The app shows no bot tag or badge — a UI choice; the
  server still treats bots as bots everywhere (no wallets, fees or payouts,
  no XP or analytics, cannot be friended or reported: `cannot_report_bot`),
  and the app simply does not offer those actions on `bot: true` seats.
* **Integrity.** All game logic is server-side. The evaluator is advisory;
  a wrong estimate only produces a weaker move.
* **Limitations.** Bots cannot follow a public rematch into a new private
  room (sessions are room-scoped), so they decline rematches (leave). With
  `accept_rematch: true` the current backend refuses `game.rematch` from
  assignment bots; bot-play then leaves immediately. An event lost right
  before the bot's own turn is only detected by the next event or the stall
  check (deadline + 2 s), so the server may auto-act once in that case.

## 12. Backend contract notes

bot-play implements the documented contract and tolerates these differences
observed in the backend implementation:

* `POST /bot/lobbies/{roomId}/fill` may return `{"requested": n}` instead of
  `{"assignments": […]}`; the assignments then come through
  `GET /bot/assignments`.
* `GET /bot/lobbies` may include `publicFillEnabled`; `false` pauses fills.
* `GET /bot/assignments` may answer `200 {"assignments":[],"maintenance":true}`;
  treated as maintenance.
* Roll/move commands are acknowledged with `ack`; bot-play waits for the
  authoritative event instead. The backend pushes `game.state` after
  `connection.ready`; bot-play's own `game.request_sync` is then redundant but
  harmless.
* A Ludo roll with exactly one legal token is announced as
  `game.dice_result {phase: awaiting_move, legal: [t]}` and applied by the
  server; bot-play only sends `game.make_move` with ≥ 2 legal tokens.

## 13. Tests

```sh
cd bot-play && go test -race ./...
```

Unit tests cover parsing/validation, secrets redaction, the load-test guard,
reload rollback, the reducer and hash vectors, the Ludo evaluator, think-time
caps, fill planning and the REST client. Integration tests (`bot-play/tests`)
run the real service against an in-process fake backend (`tests/fakebackend`:
bot REST endpoints + the WebSocket protocol with an independent Ludo/Snakes
engine and hash) covering full games, multiple bots per match, Snakes,
duplicate/out-of-order/gap/hash-mismatch handling, reconnects, 4409,
maintenance, error codes, capacity and per-game limits, enable/disable,
reload rollback, public fill (both fill response shapes), graceful shutdown
policies, auth headers and log redaction, rematch fallback, and load tests
(guards, ramp, scale-down, churn, malformed messages, slow readers, report).
