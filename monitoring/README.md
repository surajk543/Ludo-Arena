# Ludo Arena monitoring and Telegram ops bot

The fourth independent project of the repository (next to `frontend/`,
`backend/` and `bot-play/`). It never shares code or dependencies with them;
it reads their Prometheus metrics and, for the per-player lists of `/live`
and `/playtime`, the backend's operator API.

- **Prometheus** scrapes every backend instance, bot-play, node_exporter
  (host CPU / RAM / disk) and the ops bot, and evaluates the alert rules.
- **Alertmanager** groups alerts and sends them to the ops bot's webhook.
- **ops-bot** (`ops-bot/`, Go module `ludoarena/opsbot`) posts to Telegram:
  - an **hourly status report** (PDF with charts, or text),
  - a **daily KPI report** for yesterday (PDF with 30-day trends, or text),
    including Google Play installs/uninstalls and Firebase Analytics,
  - **alerts** (firing and resolved) enriched with the current CPU %, RAM %
    and players playing (real players vs bots),
  - on-demand PDF reports from the configured chats and channels: `/live`
    (real players online now, 24 h chart and peak), `/playtime` (top players
    by minutes per game, 24 h), `/metrics` (CPU, RAM, PostgreSQL connections,
    24 h), plus `/status`, `/digest` and `/help`.

```
                         private network only (never public)
 ┌──────────────┐ scrape ┌────────────┐ alerts ┌──────────────┐ webhook ┌──────────┐ HTTPS ┌──────────┐
 │ backend ×N   │◀───────│ Prometheus │───────▶│ Alertmanager │────────▶│ ops-bot  │──────▶│ Telegram │
 │ :9090        │        │ :9090      │        │ :9093        │         │ :9097    │       │ Bot API  │
 │ bot-play     │◀───────│ rules/     │◀───────────────────────────────│ PromQL   │       └──────────┘
 │ :9091        │        │ targets/   │        query API (status,       │ charts,  │──────▶ Google Cloud Storage
 │ node_exporter│◀───────│            │        reports, enrichment)     │ PDF      │       (Play reports), GA4 Data API
 │ :9100        │        └────────────┘                                 └──────────┘
 └──────────────┘
```

## Layout

| Path | What |
|---|---|
| `docker-compose.yml` | Prometheus, Alertmanager, node_exporter, ops-bot (ports bound to 127.0.0.1) |
| `docker-compose.host.yml` | Linux servers: lets node_exporter read the real host |
| `prometheus/prometheus.yml` | Scrape jobs `backend`, `bot-play`, `node`, `ops-bot` |
| `prometheus/targets/*.yml` | Scrape targets (file service discovery; dev defaults point at the Docker host) |
| `prometheus/rules/thresholds.yml` | **All alert thresholds, in one place** |
| `prometheus/rules/alerts.yml` | Alert rules (severity, summary, description, `for:` durations) |
| `prometheus/tests/alerts_test.yml` | `promtool test rules` unit tests for the alerts |
| `alertmanager/alertmanager.yml` | Routing to the ops bot, group/repeat intervals, inhibitions |
| `.env.example` | ops bot configuration template (copy to the gitignored `.env`) |
| `ops-bot/` | The bot: `cmd/ops-bot`, `cmd/fake-telegram` (local testing), `internal/*`, `Dockerfile` |

## Quick start (local, against the dev backend)

Prerequisites: the backend running with metrics on `127.0.0.1:9090`
(optional: bot-play on `127.0.0.1:9091`).

```bash
cd monitoring
cp .env.example .env     # set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_IDS (see below)
docker compose up -d --build
open http://127.0.0.1:9095/targets     # Prometheus; Alertmanager on :9093
curl -s http://127.0.0.1:9097/healthz  # ops bot
docker compose exec ops-bot /app/ops-bot --run-status-now     # one status report now
docker compose exec ops-bot /app/ops-bot --run-digest-now     # yesterday's daily report now
```

On Linux, Docker containers cannot reach services bound to the host's
`127.0.0.1`: run the backend with `METRICS_ADDR=0.0.0.0:9090` behind a host
firewall, or point `prometheus/targets/backend.yml` at an address the
containers can reach. On macOS, the node-exporter container measures Docker's
VM; to see the Mac, run `node_exporter` natively and use
`host.docker.internal:9100` in `prometheus/targets/node.yml`.

### Without Telegram or Docker

- `TELEGRAM_DRY_RUN=true` (and `DRY_RUN_DIR=./dry-run`) logs messages and
  writes the PDFs to a directory instead of sending them.
- `go run ./cmd/fake-telegram --out ./fake-telegram-out` (in `ops-bot/`) is a
  fake Bot API that records every message and saves every document; point the
  bot at it with `TELEGRAM_API_URL=http://127.0.0.1:9098` and any token of the
  form `123:abc…` (`--fail-first-429` exercises the retry path). Queue a
  command for the bot with
  `curl -X POST '127.0.0.1:9098/inject?chat=<chat id>&text=/live'` (add
  `&channel=1` for a channel post); the PDF lands in the output directory.
- The Prometheus, Alertmanager and node_exporter release binaries work the
  same way as the containers (`prometheus --config.file=prometheus/prometheus.yml`).

## Telegram setup (you do this; never share the token)

1. In Telegram, open **@BotFather** → `/newbot` → choose a name and a username
   ending in `bot`. BotFather replies with the **bot token**. Put it only in
   `monitoring/.env` (gitignored) or your secret manager — never in Git, an
   issue, a chat or a screenshot. If it leaks, `/revoke` it in BotFather.
2. Find the **chat id** (before starting the ops bot — once it runs it
   consumes the updates itself):
   - Personal chat: send any message to your new bot, then open
     `https://api.telegram.org/bot<TOKEN>/getUpdates` in your own browser and
     read `message.chat.id` (a positive number).
   - Group: add the bot to the group, send `/help@<your_bot>` in the group,
     and read the (negative) `chat.id` from the same `getUpdates` page.
   - Channel: add the bot as an administrator with **Post messages** and use
     `@channelname` (or the numeric `-100…` id). Commands typed in the
     channel arrive as channel posts and are answered in the channel.
3. Set `TELEGRAM_CHAT_IDS` (comma-separated for several chats). Only these
   chats receive reports and may use the commands; messages from other chats
   are ignored. At start the bot publishes its command menu (`setMyCommands`),
   so typing `/` in a private chat or group lists the commands.
4. Use one bot per environment (or `TELEGRAM_COMMANDS=false` on all but one):
   two processes polling the same token get HTTP 409 from Telegram.

## What the reports contain

**Hourly status** (`STATUS_INTERVAL`, default `1h`; file
`ludo-arena-status-2026-10-21-1700-IST.pdf`, caption e.g. `production ·
Playing: 1,234 players · 456 bots · CPU 41% · RAM 63%`):
real players and bots in game, real players and bots online (WebSocket),
rooms in game by game, players waiting in lobby, matches started in the last
hour (human-only vs with bots) and finished, new accounts in the last hour,
DAU estimate, CPU / RAM / disk per host, memory and CPU of every backend and
bot-play process, scrape health, firing alerts. The PDF adds 24-hour charts:
players in game (real vs bots), CPU % and RAM % per host, matches started per
hour by game.

**Daily KPI report** (`DAILY_REPORT_AT`, default `09:00` in `TZ_NAME`; file
`ludo-arena-daily-2026-10-20.pdf`) for yesterday's local calendar day: new
accounts by provider, sign-ins, DAU / WAU (HyperLogLog estimates per UTC
day / week), matches started / finished by game and mode, human-only vs
bot-filled matches, abandons by reason, peak concurrent real players and bots
(in game and online), matchmaking wait (average and p95) and outcomes, HTTP
5xx count, wallet settlement failures, client errors, peak CPU / RAM per host,
alerts that fired; then **Google Play** (latest available day: installs,
uninstalls, upgrades, active device installs, …) and **Firebase Analytics**
(first_open, app_remove, active and new users by platform). The PDF adds
30-day charts: installs vs uninstalls (Play), first_open vs app_remove (GA4),
DAU, matches per day by game, peak concurrent real players vs bots per day and
the daily peak CPU / RAM per host. A source that is not configured shows
"not configured" instead of failing the report; when Prometheus holds fewer
than 30 days the charts show what exists and say so.

**Bots in the numbers.** New accounts, sign-ins, DAU / WAU and every "real
players" figure count people only. Bots play for coins from their own wallets
(`wallet.wallets` rows flagged `is_bot`, never accounts; see
`backend/docs/game-rules.md` "Coins with bots"), which the backend watches
with `bot_wallet_recharges_total`, `bot_wallet_resets_total`,
`bot_coins_minted_total{reason}` and `bot_coins_removed_total{reason}` (per
instance: `sum`). They are not in the reports yet; to see how many coins bots
put into the economy per day, query
`sum(increase(bot_coins_minted_total[1d])) - sum(increase(bot_coins_removed_total[1d]))`.

**Alerts**: a short text message per Alertmanager notification (firing and
resolved), with summary, severity, instance, start time / duration, and the
current CPU %, RAM %, players playing and online (real vs bots).
`ALERT_FORMAT=pdf` sends a one-page PDF instead, with the last hour's players,
CPU and RAM charts. Identical notifications within `ALERT_DEDUPE_WINDOW` are
dropped; still-firing alerts repeat every `repeat_interval` (1 h). Telegram
rate limits are respected (`TELEGRAM_MIN_GAP` per chat; HTTP 429 waits for
`retry_after`).

## Commands (on demand)

| Command | Report |
|---|---|
| `/live` | **Live players** PDF (`ludo-arena-live-2026-10-27-1504-IST.pdf`): real players online now, how many play Ludo, Snakes & Ladders, wait for a match or sit in the lobby; peak and average online over the last 24 hours with a 1-minute chart (online, in a game, waiting) marking the peak; the first 100 online players with user id (`u_…`), name, account creation date ("new" when under a day old), what they play (game · mode) and how long they have been online. Players in a match come first, then the longest online |
| `/playtime` | **Playtime** PDF: minutes of active play per game over the last 24 hours (totals, players, average per player, top player, share), minutes per hour stacked by game, and the top 100 players of Ludo and of Snakes & Ladders with user id, name, joined date, minutes and share |
| `/metrics` | **Server metrics** PDF: CPU % and RAM % per host and the backend's PostgreSQL pool connections (open, in use, pool limit) over the last 24 hours, with now / average / peak (and when) |
| `/status`, `/digest` | The hourly status and yesterday's daily report, on demand |
| `/help` | The command list (also the answer to unknown commands) |

Bots and load tests are never listed or counted. The player lists and
playtime come from the backend's operator API
(`GET /api/v1/admin/ops/online` and `/ops/playtime`, `docs/rest-api.md`):
set `BACKEND_API_URL` and `BACKEND_ADMIN_KEY` in the ops bot and
`ADMIN_API_KEY_SHA256` (the hex sha256 of that key) on the backend. Without
them `/live` still shows the Prometheus counts and chart and says the list
is off. Playtime counts what the daily playtime rules count
(`docs/progression.md`): seated in a running match, app in the foreground,
not idle. CPU, RAM and online counts come from Prometheus; PostgreSQL from the
backend's `postgres_pool_connections{state}` and
`postgres_pool_max_connections` (per instance, summed). Names in scripts the
PDF font cannot draw (Devanagari, Arabic, …) are labelled, e.g.
`[Devanagari script]`; the user id next to them is exact.

How commands run:

- **Asynchronous**: the bot accepts a command and keeps polling; one worker
  generates and sends the reports, and Telegram shows "sending a file…"
  meanwhile. Up to 4 commands wait; more are refused with a short reply.
- **One report at a time**: commands and the scheduled reports share one
  generation slot.
- **Repeats are dropped**: the same command from the same chat within
  `COMMAND_DEDUPE_WINDOW` (30 s) of an accepted one is ignored (aliases count:
  `/daily` = `/digest`).
- **Deadline**: a report that is not generated within `COMMAND_REPORT_TIMEOUT`
  (30 s) is cancelled: its Prometheus and backend requests are aborted, the
  PDF renderer stops at its next section, the late result is discarded and
  the chat gets "⏱ /live was cancelled …". (Go cannot kill a goroutine; the
  next report starts only after the cancelled one has returned, so two never
  overlap.) Sending the document is not part of the 30 s.
- Results are counted in `opsbot_command_reports_total{command,result}`
  (`accepted`, `duplicate`, `busy`, `sent`, `failed`, `timeout`) and
  `opsbot_command_report_generation_seconds{command}`.

## Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | — (**secret**, required) | Bot token from @BotFather; never logged (redacted from errors) |
| `TELEGRAM_CHAT_IDS` | — (required) | Comma-separated chat ids / `@channel` |
| `TELEGRAM_COMMANDS` | `true` | Answer the commands (long polling) |
| `COMMAND_REPORT_TIMEOUT` | `30s` | A command's report is cancelled when not generated within this (minimum `5s`) |
| `COMMAND_DEDUPE_WINDOW` | `30s` | Drop the same command from the same chat within this; `0` disables |
| `BACKEND_API_URL` | empty | Backend REST base for the operator API, e.g. `http://127.0.0.1:8080` (`http://host.docker.internal:8080` from compose); empty turns the `/live` list and `/playtime` off |
| `BACKEND_ADMIN_KEY` | empty (**secret**; required with `BACKEND_API_URL`) | Sent as `X-Admin-Key`; the backend's `ADMIN_API_KEY_SHA256` is its sha256. Never logged |
| `TELEGRAM_MIN_GAP` | `3s` | Minimum gap between messages to one chat (`0` = none) |
| `TELEGRAM_DRY_RUN` / `DRY_RUN_DIR` | `false` / empty | Log instead of sending; write PDFs to the directory |
| `TELEGRAM_API_URL` | `https://api.telegram.org` | Only for tests (fake Bot API) |
| `ENV_NAME` | `development` | Shown in every header and caption |
| `TZ_NAME` | `Asia/Kolkata` | Time zone of headers, schedules and daily windows |
| `STATUS_INTERVAL` | `1h` | Status report period; `0` disables; minimum `1m` |
| `STATUS_ALIGN` | `true` | Run on clock multiples (every full hour) instead of N after start |
| `STATUS_ON_START` | `false` | Also send a status right after start |
| `DAILY_REPORT_AT` | `09:00` | Local time of the daily report; `off` disables |
| `REPORT_FORMAT` | `pdf` | `pdf` (document with charts) or `text` for status and daily reports |
| `ALERT_FORMAT` | `text` | `text` or `pdf` for alerts |
| `ALERT_DEDUPE_WINDOW` | `30m` | Keep below Alertmanager's `repeat_interval` |
| `TREND_DAYS` | `30` | Days in the daily report's trend charts (2–90) |
| `PROM_URL` / `PROM_TIMEOUT` | `http://127.0.0.1:9095` / `20s` | Prometheus API (`http://prometheus:9090` in compose) |
| `BACKEND_JOB` / `BOTPLAY_JOB` / `NODE_JOB` | `backend` / `bot-play` / `node` | Prometheus job names |
| `HTTP_ADDR` | `127.0.0.1:9097` | `/healthz`, `/metrics`, `POST /alertmanager` |
| `WEBHOOK_BEARER_TOKEN` | empty (**secret**, optional) | Require `Authorization: Bearer …` on the webhook |
| `PLAY_REPORTS_BUCKET` | empty | `gs://pubsite_prod_…` bucket of the Play Console bulk reports |
| `PLAY_PACKAGE_NAME` | `com.sungamestudio.ludoarena` | Package in the report file names |
| `GA4_PROPERTY_ID` | empty | GA4 property of the Firebase project (digits) |
| `GOOGLE_APPLICATION_CREDENTIALS` | empty | Path to a service-account JSON key (or use workload identity / `gcloud auth application-default login`) |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |

One-shot flags: `--validate`, `--run-status-now`, `--run-digest-now
[--digest-date YYYY-MM-DD]`.

## Alerts

Thresholds are in `prometheus/rules/thresholds.yml`; durations and texts in
`prometheus/rules/alerts.yml`.

| Alert | Condition (default threshold) | For | Severity |
|---|---|---|---|
| `BackendInstanceDown` | `up{job="backend"} == 0` | 1 m | critical |
| `BotPlayDown` | `up{job="bot-play"} == 0` | 2 m | warning |
| `NodeExporterDown` | host metrics missing | 5 m | warning |
| `HostCPUHigh` | host CPU > **85 %** | 5 m | warning |
| `HostMemoryHigh` | host RAM in use > **90 %** | 5 m | warning |
| `HostDiskFull` | data filesystem > **90 %** full | 5 m | warning |
| `ProcessMemoryHigh` | backend / bot-play RSS > **2 GiB** | 10 m | warning |
| `HTTP5xxRateHigh` | 5xx > **2 %** of requests and > **0.05/s** | 5 m | critical |
| `WalletSettlementFailures` | any entry-fee / refund / payout failure in 15 min | — | critical |
| `WebSocketSlowConsumers` | slow-consumer events > **30/min** | 5 m | warning |
| `MatchmakingWaitHigh` | p95 matchmaking wait > **45 s** (per game) | 10 m | warning |
| `GameStatsStale` | `time() - game_stats_refreshed_timestamp_seconds` > **120 s** while the backend is up | 2 m | warning |

`promtool test rules prometheus/tests/alerts_test.yml` checks the rules.

## Changing intervals and thresholds

- **Status every 30 minutes**: `STATUS_INTERVAL=30m`; disable with `0`.
  Restart the ops bot (`docker compose up -d ops-bot`).
- **Daily report time**: `DAILY_REPORT_AT=08:30` (24 h, `TZ_NAME`), or `off`.
- **A threshold**: edit `prometheus/rules/thresholds.yml`, then
  `curl -X POST http://127.0.0.1:9095/-/reload`.
- **Alert repeat / grouping**: `repeat_interval`, `group_interval`,
  `group_wait` in `alertmanager/alertmanager.yml`, then
  `curl -X POST http://127.0.0.1:9093/-/reload`.
- **Text instead of PDF**: `REPORT_FORMAT=text`; PDF alerts: `ALERT_FORMAT=pdf`.

## Google KPIs (optional)

Both sources use Application Default Credentials. Create one service account
in the Google Cloud project (e.g. `ludo-royale-63887`), create a JSON key,
save it as `monitoring/secrets/ops-bot.json` (gitignored; mounted read-only at
`/secrets`) and set `GOOGLE_APPLICATION_CREDENTIALS=/secrets/ops-bot.json`.
On Google Cloud, prefer an attached service account (no key file).

**Google Play installs / uninstalls** (Play Console bulk reports; they lag
1–2 days, so the report shows the latest available day and its date):

1. Play Console → **Download reports** → **Statistics** → copy the **Cloud
   Storage URI** (`gs://pubsite_prod_rev_…`); set `PLAY_REPORTS_BUCKET` to it.
2. Play Console → **Users and permissions** → **Invite new users** → the
   service account's e-mail → account permission **View app information and
   download bulk reports (read only)**. Access can take up to a day.
3. The bot reads `stats/installs/installs_<PLAY_PACKAGE_NAME>_<YYYYMM>_overview.csv`
   (UTF-16 CSV, columns matched by name). Reports exist only once the app is
   published and has installs.

**Firebase Analytics (GA4)**: in Google Analytics → Admin → **Property
access management**, add the service account's e-mail as **Viewer**; copy the
numeric **Property ID** (Admin → Property settings) into `GA4_PROPERTY_ID`;
enable the **Google Analytics Data API** in the Cloud project. The report
uses `first_open` (installs, both platforms), `app_remove` (uninstalls,
Android only), active and new users by platform. The app sends analytics only
for consenting human players, and GA4 needs up to 24–48 h to finish
processing a day.

## Production notes

- On the production VPS the stack runs without Docker, as systemd services
  next to the backend: `deploy/scripts/monitoring-setup.sh` installs and
  updates it (`deploy/README.md` §6.7).
- Run the stack next to the backend on the **private network**; scrape
  targets are private addresses (`prometheus/targets/*.yml`, or mount another
  directory with `PROM_TARGETS_DIR`). Metrics ports (9090, 9091, 9100),
  Prometheus (9095), Alertmanager (9093) and the ops bot (9097) are never
  exposed publicly; the compose file binds them to 127.0.0.1. The ops bot
  needs outbound HTTPS to `api.telegram.org` (and Google APIs if enabled).
- Use `docker-compose.host.yml` on Linux so node_exporter reports the real
  host, and run node_exporter on every backend host.
- Keep at least 31 days of Prometheus retention (`PROM_RETENTION`, default
  `45d`) for the 30-day trends.
- Set `WEBHOOK_BEARER_TOKEN` and the matching `credentials_file` in
  `alertmanager.yml` when Alertmanager and the bot are not on an isolated
  network. Keep `.env` and `secrets/` out of Git.
- `/live` and `/playtime` call the backend's operator API over the private
  network (nginx answers 404 for `/api/v1/admin/` publicly). Generate a key
  (`openssl rand -hex 32`), put it in `BACKEND_ADMIN_KEY` here and its sha256
  (`printf %s "$KEY" | sha256sum`) in the backend's `ADMIN_API_KEY_SHA256`.
  From the compose stack on Linux the backend must listen where the container
  can reach it (see "Quick start"); `host.docker.internal` is mapped for the
  ops bot.
- The backend's cluster gauges (`players_in_game`, `rooms_in_game`,
  `players_in_lobby`, `game_stats_refreshed_timestamp_seconds`) are reported
  identically by every instance, so the bot combines them with `max`;
  `ws_connections_active` is per instance and summed. Until a backend exports
  the gauges, those values show `n/a`.
- `matches_completed_total` has no human/bot label, so finished matches are
  not split by mix; load-test matches are excluded from started counts.

## Development

```bash
cd monitoring/ops-bot
gofmt -l . && go vet ./... && go test -race ./...
OPSBOT_SAMPLE_DIR=/tmp go test ./internal/pdfreport -run WriteSamples   # sample PDFs from fixtures
cd .. && promtool check config prometheus/prometheus.yml \
      && promtool test rules prometheus/tests/alerts_test.yml \
      && amtool check-config alertmanager/alertmanager.yml
```

Charts are rendered with `gonum.org/v1/plot` and the PDF with
`codeberg.org/go-pdf/fpdf` (pure Go, no cgo, no browser); Google APIs are
called over REST with `golang.org/x/oauth2` credentials.
