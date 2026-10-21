# CLAUDE.md

Guidance for Claude Code (and engineers) working in this repository.

Ludo Royale: online multiplayer Ludo (classic + quick) and Snakes & Ladders.
Four independent projects — never mix their code or dependencies:

| Dir | Stack | Module / package |
|---|---|---|
| `frontend/` | Flutter 3.44 / Dart 3.12, Riverpod 3, go_router 18 | `ludo_royale` |
| `backend/` | Go 1.27, PostgreSQL 16, Redis 7 | `ludoroyale` |
| `bot-play/` | Go 1.27 (separate module) | `ludoroyale/botplay` |
| `monitoring/` | Prometheus 3, Alertmanager, node_exporter + Telegram ops bot in Go 1.27 (`monitoring/ops-bot`, separate module; gonum/plot charts, go-pdf/fpdf PDFs) | `ludoroyale/opsbot` |

`website/` — Ludo Royale pages for sungamestudio.com (static, deployed by hand; not
part of the app or backend). See `website/README.md`; regenerate
`website/ludo-royale/legal/index.html` with `website/build_legal_page.py` whenever
`backend/config/legal/open-source-notices.html` changes.

Start with `README.md` and `docs/architecture.html`. Contracts are the source
of truth: `docs/websocket-protocol.md`, `docs/rest-api.md`,
`docs/app-version-policy.md`, `docs/cosmetics-catalog.md`,
`backend/docs/game-rules.md`, `backend/docs/redis-keys.md`.

## Non-negotiable rules

- **No Firebase Authentication** (or Firestore, Realtime DB, Remote Config).
  Firebase is used in Flutter for **Analytics only**, behind the gate in
  `frontend/lib/core/analytics/` (consent + server `actorType == "human"`).
  bot-play and the backend never use Firebase.
- **The Go backend is authoritative** for dice (`crypto/rand`), legal moves,
  turns, winners, wallets, XP and rewards. Flutter only renders and animates
  server-confirmed events. Never trust client-supplied ids, balances or
  results.
- **PostgreSQL boundaries (user-approved):** `wallet.wallets` holds balances
  only; `identity.auth_identities` maps providers → accounts;
  `progression.*` holds XP, missions/claims, inventory, loadout, friendships,
  player reports (metadata only) and idempotency receipts. **Do not add
  tables** (no match history, ledger or profile tables) without asking. Live
  game state lives in Redis only — enforced by
  `backend/tests/schema_guard_test.go` (table allowlist + no gameplay-state columns).
- **Protocol changes must update both sides and the docs** in the same
  change: Go (`backend/internal/protocol`, `internal/rooms`), Flutter
  (`frontend/lib/core/protocol`, `core/realtime`), bot-play
  (`bot-play/internal/connection`), and `docs/websocket-protocol.md`.
- **Never commit secrets.** `.env`, `frontend/config/firebase.json`, keystores
  and service accounts are gitignored; examples use placeholders. Public OAuth
  client ids and package ids are fine. The repo is public.

## Commands

```bash
# Backend (needs PostgreSQL + Redis; see backend/.env.example)
cd backend
go build ./... && go vet ./...
go test -race ./...                                   # unit tests
TEST_DATABASE_URL=postgres://…/ludo_royale_test?sslmode=disable \
TEST_REDIS_ADDR=127.0.0.1:6379 go test -race ./...    # + e2e tests in tests/
go run golang.org/x/vuln/cmd/govulncheck@latest ./...
set -a; . ./.env; set +a; go run ./cmd/server         # :8080, metrics 127.0.0.1:9090

# bot-play
cd bot-play && go test -race ./...
BOT_SERVICE_KEY=… go run ./cmd/bot-play --config configs/environments/development.yaml --profiles configs/profiles.yaml

# Frontend
cd frontend
dart run tool/merge_arb.dart && flutter gen-l10n      # after any .arb change
flutter analyze && flutter test
BACKEND_URL=http://localhost:8080 flutter test test/integration/   # live contract test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080        # Android emulator
flutter run --dart-define=API_BASE_URL=http://localhost:8080 \
  --dart-define-from-file=config/firebase.json                     # iOS simulator (+ analytics)

# Load / compression matrix (development only)
cd bot-play && BACKEND_BIN=… BOTPLAY_BIN=… BACKEND_ENV_FILE=… BOT_SERVICE_KEY=… \
  python3 scripts/loadtest_matrix.py --bots 1000

# Monitoring + Telegram ops bot (secrets only in the gitignored monitoring/.env)
cd monitoring/ops-bot && gofmt -l . && go vet ./... && go test -race ./...
cd monitoring && promtool test rules prometheus/tests/alerts_test.yml
cd monitoring && cp .env.example .env && docker compose up -d --build   # Prometheus :9095, Alertmanager :9093, bot :9097
TELEGRAM_DRY_RUN=true DRY_RUN_DIR=./dry-run go run ./cmd/ops-bot --run-status-now   # in monitoring/ops-bot, no token needed
```

Integration tests flush Redis logical DB 13 (backend e2e) and use DB 14
(progression tests) plus the `ludo_royale_test` database — never point them at
real data.

## Where things live

- `backend/internal/server` — the real wiring (`server.go`, `extensions.go`); tests use it too.
- `backend/internal/rooms` — room engine: Lua CAS commit + ordered publish (`store.go`), matchmaking/private/practice (`lobby.go`, `bots.go`), turns/finish (`game.go`), rematch, scheduler (`sched` ZSET timers), WS command dispatch (`commands.go`).
- `backend/internal/websocket` — gateway: compression, bounded queues with snapshot coalescing, heartbeats, rate limits, pub/sub fan-out.
- `backend/internal/{auth,identity,wallet,apppolicy,progression,social,analytics}`.
- `backend/config/` — app policy per environment, `catalog.json`, `missions.json`.
- `frontend/lib/core/` — config, network (Dio + refresh), protocol (models, reducer, FNV hash), realtime (socket, `ActiveRoomController`), analytics, theme, localization.
- `frontend/lib/features/` — feature folders; routes are registered in `lib/app/feature_routes.dart` via `play_routes.dart` and `meta_routes.dart`, except the five bottom-navigation tabs (Home, Games, Missions, Friends, Profile), which are one `StatefulShellRoute` in `lib/app/shell/main_shell.dart` (switch tabs with `context.go`, never push them).
- `frontend/lib/shared/game_visuals/`, `features/{ludo,snakes_ladders}/presentation/board/` — board, dice, token and cosmetic renderers.
- `monitoring/` — Prometheus scrape targets (`prometheus/targets/`), alert thresholds in one file (`prometheus/rules/thresholds.yml`), alert rules + promtool tests, Alertmanager routing to the ops bot. `monitoring/ops-bot/internal/` — `report` (PromQL + text), `pdfreport` + `charts` (PDF/PNG), `telegram` (429 retry, token redaction), `alertmanager` (webhook + dedupe), `google` (Play CSV in GCS, GA4 Data API), `schedule`. See `monitoring/README.md`.

## Gotchas (learned the hard way)

- **WebSocket message ids must be unique per user for ≥ 2 minutes across
  connections** (server de-duplication). The app uses a random per-connection
  prefix + counter; test clients must too, or commands are silently acked as
  duplicates.
- **Ludo single legal move:** when `game.dice_result` has exactly one legal
  token, the server applies the move itself. Clients only send
  `game.make_move` when `legal.length >= 2` (`ActiveRoomState.canMove`).
- **Deltas carry `v` and `h`.** Event `h` is the FNV-1a hash of the
  client-visible state *after that event* (see game-rules.md "State hash");
  intermediate events use `HashAt(prevTurnSeq, seat)` on the server. Any
  reducer change must keep the hash test vectors passing on both sides.
- **Instance control messages on `ev:user:*` must never reach clients**; the
  gateway forwards only payloads starting with `{"t":` (the Go e2e client fails
  on any frame without a type).
- `ludo.Roll` never auto-applies a move; the room service calls `Move` when
  there is exactly one legal token.
- Per-connection command limit is 10/s (burst 20); bots and tests that act
  instantly need a small think delay.
- Anti-farming: matches shorter than `PROGRESSION_MIN_MATCH_DURATION`
  (30 s default, ≥ 10 s in production) earn no XP; e2e tests set it to `0s`.
- `RATE_LIMIT_DISABLED` and `BOT_LOADTEST_ENABLED` are refused in production.
- Compression: deltas (~150 B) are sent uncompressed below
  `WS_COMPRESSION_THRESHOLD` (1024); no-context-takeover is the default because
  context takeover costs ~1 MB per connection (see `docs/performance.md`).
- iOS uses CocoaPods (not SwiftPM), deployment target 15.0, arm64-only
  simulator builds. Google Sign-In on Android needs each machine's debug SHA-1
  registered in Google Cloud project `ludo-royale-63887`.

- Monitoring: cluster-wide gauges (`players_in_game`, `rooms_in_game`,
  `players_in_lobby`, `active_users_estimate`) are reported identically by
  every backend instance — aggregate them with `max`, never `sum`;
  `ws_connections_active` is per instance (sum). The Telegram bot token lives
  only in `monitoring/.env` / the secret store and is redacted from errors.

## Conventions

- **Localization:** never edit `frontend/lib/l10n/app_*.arb` directly. Add keys
  to `lib/l10n/parts/<area>/{en,hi,ur,id,ar}.arb` (prefix keys by area, real
  translations in all five), then run `merge_arb` + `gen-l10n`. Arabic/Urdu
  are RTL; boards stay LTR.
- Every user-visible Flutter string goes through `AppLocalizations`; every
  error shown to users maps from a stable server code
  (`core/errors/error_messages.dart`).
- Go: `gofmt`, `go vet`, table-driven tests; e2e tests in `backend/tests` use
  the production wiring. Flutter: `flutter analyze` must be clean.
- Analytics events only after server confirmation, through the typed
  catalogue; no ids, names, codes or tokens in parameters.
- Commits: conventional commit messages; work on a branch and open a PR into
  `master` (the default branch).
