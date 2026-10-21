# Deployment & Local Development

Four independent projects, each with its own dependencies:

| Directory | Stack | Build | Config |
|---|---|---|---|
| `frontend/` | Flutter 3.44 / Dart 3.12 | `flutter build apk` / `flutter build ipa` | `--dart-define`s (public ids only) + gitignored `config/firebase.json` |
| `backend/` | Go 1.27 | `go build ./cmd/server` or `backend/Dockerfile` | environment variables (`backend/.env.example`), policy files in `backend/config/` |
| `bot-play/` | Go 1.27 (separate module) | `go build ./cmd/bot-play` or `bot-play/Dockerfile` | YAML in `bot-play/configs/` + env for the service key |
| `monitoring/` | Prometheus 3, Alertmanager, node_exporter; ops bot in Go 1.27 (separate module) | `monitoring/docker-compose.yml`; `go build ./cmd/ops-bot` or `monitoring/ops-bot/Dockerfile` | env (`monitoring/.env.example`), targets and thresholds in `monitoring/prometheus/` |

Backend secrets (`JWT_SIGNING_KEY`, `PUBLIC_ID_KEY`, `FACEBOOK_APP_SECRET`,
database/Redis passwords, the bot service key) are provided only through the
environment or a secret manager — never in the Flutter app or in Git.

## Local development

```bash
# 1. Dependencies (Docker) — or use any local PostgreSQL 16 + Redis 7
cd backend && docker compose up -d

# 2. Backend
cp .env.example .env   # edit the CHANGE_ME values
set -a && . ./.env && set +a
go run ./cmd/server    # applies migrations, serves :8080, metrics on 127.0.0.1:9090

# 3. Flutter (Android emulator reaches the host at 10.0.2.2)
cd ../frontend
dart run tool/merge_arb.dart && flutter gen-l10n
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 \
            --dart-define=APP_ENV=development \
            --dart-define-from-file=config/firebase.json   # optional (analytics)
```

## Tests

```bash
cd backend
go test -race ./...                       # unit tests (engines, policy, progression…)
TEST_DATABASE_URL=postgres://…/ludo_royale_test TEST_REDIS_ADDR=127.0.0.1:6379 \
  go test -race ./...                     # + end-to-end integration tests (tests/)

cd ../frontend && flutter analyze && flutter test
cd ../bot-play && go test -race ./...
cd ../monitoring/ops-bot && go test -race ./...
cd .. && promtool test rules prometheus/tests/alerts_test.yml
```

Integration tests use a dedicated test database and Redis logical DB 13/14,
which they flush.

## Production checklist

- TLS terminates at the load balancer (WebSocket upgrade allowed, idle timeout
  > 60 s); set `TRUSTED_PROXY_HOPS` accordingly; `PUBLIC_URL` = https URL.
- PostgreSQL and Redis on a private network only (never public), with backups:
  PostgreSQL PITR covering schemas `wallet`, `identity`, `progression`
  together; Redis AOF `everysec` + RDB, `noeviction`.
- `APP_ENV=production`, `APP_POLICY_FILE=…/app-policy.production.json`,
  `APP_MAINTENANCE_FLAG_FILE` on a path operators can create quickly
  (e.g. a mounted volume). `BOT_LOADTEST_ENABLED` must be `false` (startup
  refuses otherwise).
- Expose `METRICS_ADDR` only to the monitoring network. Live player counts
  (`players_in_game`, `rooms_in_game`, `players_in_lobby`) are cluster-wide
  and identical on every instance — aggregate with `max`; `ws_connections_active`
  is per instance — aggregate with `sum`. Alert when
  `time() - max(game_stats_refreshed_timestamp_seconds) > 120` (recount every
  `GAME_STATS_INTERVAL`, default 15 s). See
  [architecture.md](architecture.md#observability-live-player-counts).
- Monitoring and alerting: run the `monitoring/` stack (Prometheus,
  Alertmanager, node_exporter on every host, Telegram ops bot) on the same
  private network. List every backend instance's `METRICS_ADDR`, bot-play's
  metrics address and each host's node_exporter in
  `monitoring/prometheus/targets/*.yml`; use `docker-compose.host.yml` on Linux
  so node_exporter reads the real host; keep ≥ 31 days of Prometheus retention
  for the 30-day trends. Prometheus (9095), Alertmanager (9093), the ops bot
  (9097) and all metrics ports stay private; the bot needs outbound HTTPS to
  `api.telegram.org` (and Google APIs for Play/GA4 KPIs). The Telegram token
  and the optional Google service-account key come only from the environment
  or a secret store. Setup: [monitoring/README.md](../monitoring/README.md).
- Run ≥ 2 instances; any instance can serve any player (state + timers in
  Redis, events via Redis pub/sub). Rolling deploys: instances close
  WebSockets with `1001`; clients reconnect and resync.
- Graceful shutdown: SIGTERM → stop accepting, close sockets, drain HTTP (20 s).

## Release signing (Android)

The project currently signs release builds with the debug key (Flutter
default). Before publishing: create an upload keystore (kept outside Git,
referenced from an untracked `android/key.properties`), enable Play App
Signing, and add the **Play App Signing SHA-1** and upload-key SHA-1 as
additional Android OAuth clients in Google Cloud (`docs/authentication.md`).

## App policy operations

See `docs/app-version-policy.md` (force/optional update, maintenance windows,
emergency flag file, reload with `kill -HUP`).
