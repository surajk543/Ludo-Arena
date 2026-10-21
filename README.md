# Ludo Royale

Multiplayer **Ludo** (classic and Quick) and **Snakes & Ladders** for Android
and iOS. A Flutter app talks to an **authoritative Go backend** (REST +
WebSocket) backed by PostgreSQL and Redis; a separate Go service,
**bot-play**, provides clearly labelled bot players. The server owns dice,
rules, room state, timers, wallets and progression — clients only send intents
and render server-confirmed results. A fourth project, **monitoring**, runs
Prometheus and Alertmanager plus a Telegram ops bot that sends PDF status
reports, daily KPIs and enriched alerts.

## [System Architecture and Flow Diagrams](docs/architecture.html)

**[docs/architecture.html](docs/architecture.html)** is the main system
documentation: 18 sections and 38 diagrams covering architecture, sign-in,
wallets, gameplay, private rooms, reconnection, deployment, app version policy,
WebSocket performance, progression, bot-play, analytics, localization,
security, testing and project status. It is fully self-contained (Mermaid is
bundled in `docs/assets/`), so it works offline:

- **Open the file directly** in a browser: `open docs/architecture.html`
  (macOS), `xdg-open docs/architecture.html` (Linux), or double-click it.
- **Or serve it locally**:
  ```bash
  cd docs && python3 -m http.server 8000
  # then browse to http://localhost:8000/architecture.html
  ```

A short Markdown companion is in [docs/architecture.md](docs/architecture.md).

## Features

- **Two games, four modes**: Ludo (classic, and Quick with 2 tokens) and Snakes
  & Ladders; public matchmaking, private rooms with 6-character codes, practice
  against bots, and consent-based rematches. 2–4 players.
- **Server-authoritative play**: `crypto/rand` dice, Go rule engines, versioned
  delta events with a state hash, server-side turn timers and auto-moves, and
  reconnect-and-resync from snapshots.
- **Accounts without Firebase Auth**: Google Sign-In (configured), guest play
  with Save Progress (account linking, never merging), guests restored after
  an app update or reinstall through a device binding (only an HMAC of the
  device id is stored), app-issued access and refresh tokens. Apple and Facebook are implemented but pending configuration.
- **Virtual wallet**: 1,000,000 coins + 50 diamonds granted exactly once per
  account; all-or-nothing flat entry fees (Ludo 100,000, Snakes & Ladders
  50,000); at-most-once payouts. The welcome grant and entry fees are set live
  in the per-environment app-policy file. Coins are virtual and non-redeemable.
- **Progression**: XP and 50 levels, daily/weekly missions and events,
  exactly-once reward claims, a cosmetic-only Collection Room, friends, invites
  and a weekly friends leaderboard. No loot boxes, no punitive streaks.
- **Operations**: backend-controlled force/optional update and maintenance
  mode (hot-reloaded policy files), negotiated WebSocket compression with
  bounded queues, Prometheus metrics, privacy-conscious analytics (human,
  consented players only), and a Telegram ops bot: hourly PDF status (real
  players vs bots, CPU / RAM per host, charts), a daily KPI report (Google
  Play installs / uninstalls, Firebase Analytics, 30-day trends) and alerts
  enriched with CPU, RAM and player counts.
- **App**: light/dark themes, five languages (English, Hindi, Urdu, Arabic,
  Indonesian) with RTL support.

## Repository structure

```
frontend/   Flutter app (Android/iOS): lib/app, lib/core/{analytics,app_policy,realtime,protocol,
            localization,theme,network,...}, lib/features/*, l10n.yaml, tool/merge_arb.dart
backend/    Go backend (module "ludoroyale"): cmd/server, internal/{server,httpapi,websocket,auth,
            identity,wallet,rooms,game/ludo,game/snakes_ladders,apppolicy,progression,social,
            analytics,...}, migrations/, config/ (app policy, catalog, missions), docs/, tests/
bot-play/   Go bot service (separate module "ludoroyale/botplay"): cmd/bot-play, internal/*,
            configs/, tests/
monitoring/ Prometheus (targets, rules/thresholds.yml, alert rule tests), Alertmanager,
            docker-compose.yml, and ops-bot/ (separate Go module "ludoroyale/opsbot"):
            Telegram status / daily KPI PDFs and enriched alerts
docs/       Architecture page and contracts (REST, WebSocket, auth, app policy, progression,
            bot-play, deployment, performance, cosmetics)
```

## Quick start

### Backend (`backend/`, Go 1.27, PostgreSQL 16, Redis 7)

```bash
cd backend
docker compose up -d                 # local PostgreSQL 16 + Redis 7.4 on 127.0.0.1
                                     # (or use your own local PostgreSQL and Redis)
cp .env.example .env                 # then replace every CHANGE_ME placeholder
set -a && . ./.env && set +a
go run ./cmd/server                  # applies migrations, API on :8080, metrics on 127.0.0.1:9090
```

`docker-compose.yml` is for local development only. Never commit `.env` or real
secrets.

### Flutter app (`frontend/`, Flutter 3.44 / Dart 3.12)

```bash
cd frontend
flutter pub get
dart run tool/merge_arb.dart && flutter gen-l10n     # merge ARB fragments, generate localizations
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 \
            --dart-define=APP_ENV=development
            # optional analytics: --dart-define-from-file=config/firebase.json
```

`10.0.2.2` reaches the host from the Android emulator (use
`http://localhost:8080` on the iOS simulator). Firebase is used for Analytics
only; to enable it, copy `config/firebase.example.json` to the gitignored
`config/firebase.json` and fill in your own Firebase app values.

### bot-play (`bot-play/`, optional)

```bash
cd bot-play
export BOT_SERVICE_KEY="$(openssl rand -hex 32)"     # 32–256 chars; environment only, never a file
# Backend: set BOT_SERVICE_KEY_SHA256 to the hex SHA-256 of that key and restart it:
#   printf '%s' "$BOT_SERVICE_KEY" | shasum -a 256
go run ./cmd/bot-play --config configs/environments/development.yaml \
                      --profiles configs/profiles.yaml
```

Modes (`bots.modes` in the YAML config): `practice` (practice games and
host-added bots in private rooms), `public_fill` (optional matchmaking
assistance, also requires `BOT_PUBLIC_FILL_ENABLED=true` on the backend) and
`loadtest` (development/preprod only; requires `loadtest.enabled`, allowed
hosts and the `--i-understand-this-is-a-load-test` flag; refused by a
production backend). Validate a config with `--validate`. See
[docs/bot-play.md](docs/bot-play.md).

### Monitoring and Telegram ops bot (`monitoring/`, optional)

```bash
cd monitoring
cp .env.example .env          # TELEGRAM_BOT_TOKEN (from @BotFather) + TELEGRAM_CHAT_IDS; never commit .env
docker compose up -d --build  # Prometheus 127.0.0.1:9095, Alertmanager :9093, ops bot :9097
```

Every hour (`STATUS_INTERVAL`) the bot sends a PDF status report, every day at
`DAILY_REPORT_AT` (default 09:00 `Asia/Kolkata`) yesterday's KPI report, and
every Alertmanager alert as a short message with the current CPU, RAM and
players playing. Thresholds are in `monitoring/prometheus/rules/thresholds.yml`.
Setup of the Telegram bot, Google Play reports and GA4 access, and production
notes: [monitoring/README.md](monitoring/README.md).

## Testing

```bash
# Backend: unit tests with the race detector
cd backend && go test -race ./...
# Backend: + end-to-end integration tests against a dedicated test PostgreSQL and Redis
#          (they flush their Redis DB; never point them at real data)
TEST_DATABASE_URL=postgres://…/ludo_royale_test TEST_REDIS_ADDR=127.0.0.1:6379 go test -race ./...

# Flutter
cd frontend && flutter analyze && flutter test
# Flutter: contract test of the app's protocol code against a running backend
BACKEND_URL=http://localhost:8080 flutter test test/integration/

# bot-play (uses an in-process fake backend)
cd bot-play && go test -race ./...

# Monitoring: ops bot (fake Prometheus / Telegram / Google APIs) and alert rules
cd monitoring/ops-bot && go test -race ./...
cd monitoring && promtool test rules prometheus/tests/alerts_test.yml
```

## Configuration overview (names only)

| Project | Configuration |
|---|---|
| backend | Environment variables (template: `backend/.env.example`): `APP_ENV`, `HTTP_ADDR`, `METRICS_ADDR`, `PUBLIC_URL`, `TRUSTED_PROXY_HOPS`, `DATABASE_URL`, `REDIS_ADDR`, `REDIS_PASSWORD`, `REDIS_TLS`, `JWT_SIGNING_KEY`, `PUBLIC_ID_KEY`, `ACTIVE_USER_KEY`, `GOOGLE_CLIENT_IDS`, `APPLE_AUDIENCES`, `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET`, `APP_POLICY_FILE`, `APP_MAINTENANCE_FLAG_FILE`, gameplay timers and fallback fees (`TURN_SECONDS`, `ENTRY_FEE_LUDO`, …), WebSocket (`WS_COMPRESSION`, `WS_COMPRESSION_THRESHOLD`, `WS_OUTBOUND_QUEUE`, …), bots (`BOT_SERVICE_KEY_SHA256`, `BOT_PUBLIC_FILL_ENABLED`, `BOT_LOADTEST_ENABLED`, …). Policy and content files in `backend/config/`; the live entry fees (default Ludo 100,000 / Snakes & Ladders 50,000 coins) and welcome grant (default 1,000,000 coins, 50 diamonds) are `entryFees` / `welcome` in `backend/config/app-policy.<env>.json`, hot-reloaded without a restart (`ENTRY_FEE_*` / `WELCOME_*` are fallbacks). |
| frontend | `--dart-define`s: `API_BASE_URL`, `APP_ENV`, `GOOGLE_SERVER_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`, `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI`, `FACEBOOK_ENABLED`; optional `--dart-define-from-file=config/firebase.json` (gitignored). |
| bot-play | YAML in `bot-play/configs/` (`config.example.yaml`, `environments/*.yaml`, `loadtest.example.yaml`, `profiles.yaml`) + the `BOT_SERVICE_KEY` environment variable. |
| monitoring | Environment variables (template: `monitoring/.env.example`): `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_IDS`, `ENV_NAME`, `TZ_NAME`, `STATUS_INTERVAL`, `DAILY_REPORT_AT`, `REPORT_FORMAT`, `ALERT_FORMAT`, `ALERT_DEDUPE_WINDOW`, `PROM_URL`, `WEBHOOK_BEARER_TOKEN`, `PLAY_REPORTS_BUCKET`, `GA4_PROPERTY_ID`, `GOOGLE_APPLICATION_CREDENTIALS`, …; scrape targets in `monitoring/prometheus/targets/`, thresholds in `monitoring/prometheus/rules/thresholds.yml`, alert timing in `monitoring/alertmanager/alertmanager.yml`. |

Secrets (`JWT_SIGNING_KEY`, `PUBLIC_ID_KEY`, `ACTIVE_USER_KEY`,
`FACEBOOK_APP_SECRET`, database/Redis passwords, `BOT_SERVICE_KEY`,
`TELEGRAM_BOT_TOKEN`, Google service-account keys) come only
from the environment or a secret manager — never from Git or the app. The full
list with groups is in [the architecture page](docs/architecture.html#env-vars).

## Documentation

| Document | Contents |
|---|---|
| [docs/architecture.html](docs/architecture.html) | System architecture and flow diagrams (start here) |
| [docs/architecture.md](docs/architecture.md) | Markdown overview, wallet settlement guarantees, security |
| [docs/websocket-protocol.md](docs/websocket-protocol.md) | Realtime protocol `ludo-royale.v1` |
| [docs/rest-api.md](docs/rest-api.md) | REST API `/api/v1` |
| [docs/authentication.md](docs/authentication.md) | Accounts, sessions, providers |
| [docs/app-version-policy.md](docs/app-version-policy.md) | Force/optional update and maintenance |
| [docs/progression.md](docs/progression.md) | XP, missions, Collection Room, social, analytics |
| [docs/cosmetics-catalog.md](docs/cosmetics-catalog.md) | Cosmetic item ids |
| [docs/bot-play.md](docs/bot-play.md) | Bot service design and operations |
| [docs/deployment.md](docs/deployment.md) | Local development and production checklist |
| [docs/performance.md](docs/performance.md) | WebSocket compression and load-test measurements |
| [backend/docs/game-rules.md](backend/docs/game-rules.md) | Game rules, board geometry, state hash |
| [backend/docs/redis-keys.md](backend/docs/redis-keys.md) | Redis key layout |
| [bot-play/README.md](bot-play/README.md) | bot-play quick start |

## Status / pending items

Implemented: the Go backend (auth, guest and linking, wallet, rooms, both
engines, scheduler, app policy, progression, social, analytics, metrics),
bot-play, and the Flutter app (app gate and policy screens, login and Save
Progress, home, profile, settings, wallet, realtime client and state reducer,
board renderers, themes, localization, analytics gate). The Flutter play
screens (matchmaking, practice, private rooms, match, results/rematch) and meta
screens (missions, events, collection, friends, leaderboard, level road) are
implemented and covered by widget tests; a hands-on play-through on physical
devices is still pending.

Pending:

- **Facebook Login**: needs a Meta app and credentials (button hidden until then).
- **Sign in with Apple**: needs Apple Developer configuration.
- **Release signing**: release keystore / Play App Signing SHA-1 and the
  matching Android OAuth client.
- **Store listings**: App Store and Google Play; store URLs are empty, so the
  app shows "not yet available in the store" on update prompts.
- **Firebase Analytics**: DebugView verification on a real device.
- **Production infrastructure**: load balancer, managed PostgreSQL/Redis,
  secrets and monitoring (target design in
  [docs/deployment.md](docs/deployment.md)).
