# bot-play

Automated players for Ludo Arena (Ludo + Snakes & Ladders). bot-play is a
separate Go service and a **pure protocol client** of the Go backend: the
backend owns dice, legal moves, state, turns, winners and wallets. Bots only
roll, choose among server-listed legal moves, and leave.

Full documentation: [`../docs/bot-play.md`](../docs/bot-play.md).

## Quick start (local)

Prerequisites: Go 1.27.3, a backend on `localhost:8080` started with
`BOT_SERVICE_KEY_SHA256` set to the SHA-256 (hex) of your key.

```sh
cd bot-play
export BOT_SERVICE_KEY="$(openssl rand -hex 32)"   # 32..256 chars; never put it in a file
# backend: BOT_SERVICE_KEY_SHA256=$(printf %s "$BOT_SERVICE_KEY" | shasum -a 256 | cut -d' ' -f1)

go run ./cmd/bot-play --config configs/environments/development.yaml \
                      --profiles configs/profiles.yaml
```

Then start a practice game from the app (or send `practice.start` over the
WebSocket); bot-play receives the assignment, seats the bots and plays.

| Command | Purpose |
|---|---|
| `go run ./cmd/bot-play --validate --config <file> --profiles configs/profiles.yaml` | Validate configuration and exit |
| `go run ./cmd/bot-play --version` | Print version/build |
| `kill -HUP <pid>` | Reload config + profiles (also automatic on file change) |
| `curl localhost:9091/healthz` / `/readyz` / `/metrics` | Health, readiness, Prometheus |
| `go test -race ./...` | All tests (uses an in-process fake backend) |

### Load test (development / preprod only)

```sh
BOT_SERVICE_KEY=... go run ./cmd/bot-play \
  --config configs/loadtest.example.yaml --profiles configs/profiles.yaml \
  --i-understand-this-is-a-load-test
```

Refused unless `app.environment` is `development`/`preprod`,
`loadtest.enabled: true`, the flag is passed, and the backend host is in
`loadtest.allowed_hosts` and not in `loadtest.forbidden_hosts`. The backend
also refuses load-test sessions in production. A JSON report is written to
`loadtest.report_path`.

### Docker

```sh
docker build -t bot-play:1.0.0 --build-arg VERSION=1.0.0 --build-arg BUILD=1 .
docker run --rm -e BOT_SERVICE_KEY -p 127.0.0.1:9091:9091 bot-play:1.0.0 \
  --config /app/configs/environments/preprod.yaml --profiles /app/configs/profiles.yaml
```

Multi-stage build, static binary, `gcr.io/distroless/static-debian12:nonroot`.

## Layout

```
cmd/bot-play/            entrypoint (flags, signals, wiring)
internal/config/         YAML schema, defaults, validation, load-test guard, hot reload
internal/profiles/       profiles.yaml (think time + Ludo weights)
internal/client/         REST client for /api/v1/bot/* (controller token, assignments, lobbies, sessions)
internal/connection/     WebSocket transport, protocol types, versioned state reducer + FNV-1a hash
internal/ludo/           Ludo geometry + non-authoritative move evaluator
internal/snakes_ladders/ Snakes & Ladders geometry (roll-only; no strategy)
internal/strategy/       think-time policy and move choice
internal/matchmaking/    public-fill planner, load-test game/capacity mix
internal/runner/         controller, population reconciler, bot lifecycle and game loop
internal/health/         /healthz /readyz /metrics server
internal/metrics/        Prometheus metrics + load-test report
configs/                 example, profiles, per-environment configs
tests/                   integration tests + in-process fake backend
```

No Firebase or analytics SDKs are used anywhere in bot-play.
