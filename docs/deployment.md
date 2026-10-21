# Deployment & Local Development

Three independent projects, each with its own dependencies:

| Directory | Stack | Build | Config |
|---|---|---|---|
| `frontend/` | Flutter 3.44 / Dart 3.12 | `flutter build apk` / `flutter build ipa` | `--dart-define`s (public ids only) + gitignored `config/firebase.json` |
| `backend/` | Go 1.27 | `go build ./cmd/server` or `backend/Dockerfile` | environment variables (`backend/.env.example`), policy files in `backend/config/` |
| `bot-play/` | Go 1.27 (separate module) | `go build ./cmd/bot-play` or `bot-play/Dockerfile` | YAML in `bot-play/configs/` + env for the service key |

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
- Expose `METRICS_ADDR` only to the monitoring network.
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
