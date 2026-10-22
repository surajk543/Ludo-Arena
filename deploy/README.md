# Production runbook: ludo.sungamestudio.com

How the production server is built, and how to deploy, roll back and change
the server or the database. Commands run **on the VPS as root** unless they
say otherwise. A formatted copy of this page is [`read.html`](read.html).

| | |
|---|---|
| Public URL | `https://ludo.sungamestudio.com` (REST `/api/v1/*`, WebSocket `/api/v1/ws`) |
| Server | Bluehost Ultimate VPS NVMe 16 (`rpm.tav.mybluehost.me`), Mumbai, Ubuntu 24.04, 8 vCPU, 16 GB RAM, 450 GB NVMe |
| IP | `129.121.171.63` |
| DNS | Cloudflare (not Namecheap): `ludo` A record → `129.121.171.63`, **DNS only** (grey cloud) |
| TLS | Let's Encrypt, auto-renewed by `certbot.timer` |
| Deploy tool | `ludo-deploy` (source: [`scripts/ludo-deploy`](scripts/ludo-deploy)) |

## 1. What runs where

```
app ──HTTPS/WSS──▶ nginx :443 ──▶ backend 127.0.0.1:8080 ──▶ PostgreSQL 16 127.0.0.1:5432
                       ▲                │                 └─▶ Redis 7      127.0.0.1:6379
bot-play ──────────────┘ (loopback)     metrics 127.0.0.1:9090 (bot-play: 127.0.0.1:9091)
```

| Service | systemd unit | Runs as | Listens | Notes |
|---|---|---|---|---|
| nginx | `nginx` | www-data | `:80` → redirect, `:443` | TLS, WebSocket proxy; the only public service besides SSH |
| Backend | `ludo-backend` | ludo | `127.0.0.1:8080`, metrics `127.0.0.1:9090` | `APP_ENV=production` |
| bot-play | `ludo-bot-play` | ludo | metrics `127.0.0.1:9091` | Practice-game bots; connects to `https://ludo.sungamestudio.com` via `/etc/hosts` → 127.0.0.1 |
| PostgreSQL 16 | `postgresql@16-main` | postgres | `127.0.0.1:5432` | Database `ludo_arena`, role `ludo` |
| Redis 7 | `redis-server` | redis | `127.0.0.1:6379` | Password; AOF every second + RDB; `noeviction` |

The firewall (ufw) allows only 22, 80 and 443. Nothing else is reachable from
the internet.

| Path | What |
|---|---|
| `/opt/ludo-arena/src` | Git checkout used for builds (read-only deploy key) |
| `/opt/ludo-arena/releases/<utc>-<commit>/` | Built releases: `backend/`, `bot-play/`, `RELEASE`, `MIGRATIONS` |
| `/opt/ludo-arena/current` | Symlink to the live release (the units run from it) |
| `/etc/ludo-arena/backend.env` | Backend settings and secrets (mode 0640 root:ludo) |
| `/etc/ludo-arena/bot-play.env` | `BOT_SERVICE_KEY` (its SHA-256 is in `backend.env`) |
| `/etc/ludo-arena/secrets/` | Database password, Google Play service-account key |
| `/etc/redis/ludo-arena-secret.conf` | Redis password |
| `/var/backups/ludo-arena/` | Database dumps (nightly + before migrations) |
| `/root/.ssh/ludo_arena_deploy` | Deploy key (GitHub → Ludo-Arena → Settings → Deploy keys, read-only) |

## 2. Get on the server

```bash
ssh root@ludo.sungamestudio.com          # or root@129.121.171.63
ludo-deploy status                       # what is live and healthy
```

From a Mac without an SSH key, one password login can be reused for 12 hours:

```bash
ssh -M -S /tmp/ludo.sock -o ControlPersist=12h -fN root@129.121.171.63   # asks for the root password
ssh -S /tmp/ludo.sock root@129.121.171.63 ludo-deploy status
```

The root password can be reset in Bluehost → Hosting → this VPS → Manage →
Overview → Root Password.

## 3. Deploy

Production is built from GitHub on the VPS. Merge the change into `master`
first (or name a branch, tag or commit for a test deploy).

```bash
ludo-deploy deploy                 # master
ludo-deploy deploy ops/vps-deploy  # a branch, tag or commit
```

What it does, in order:

1. Fetches the repository and resolves the ref to a commit.
2. Builds `backend` and `bot-play` with Go 1.27.3 into
   `/opt/ludo-arena/releases/<utc>-<commit>/`, copies `backend/config/` and
   bot-play's `production.yaml` + `profiles.yaml`, and checks bot-play's
   configuration (`-validate`).
3. If any `backend/migrations/*.sql` file differs from the live release,
   takes a database backup first (`/var/backups/ludo-arena/*-pre-<release>.dump`).
4. Points `current` at the new release and restarts the backend, which
   applies the migrations at startup, then waits up to 30 s for `/readyz`.
5. **If the health check fails, it switches back to the previous release by
   itself** and exits with an error. The failed build stays on disk.
6. Restarts bot-play in the background and deletes old releases (keeps 5).

Check the result:

```bash
ludo-deploy status
curl -s https://ludo.sungamestudio.com/health        # version, commit, build time
curl -s https://ludo.sungamestudio.com/readyz        # {"status":"ready"}, from anywhere
journalctl -u ludo-backend -n 50 --no-pager
```

What players notice (measured): a deploy takes about 45 s, but players only
see the backend restart. On SIGTERM the backend closes every WebSocket
(code `1001`) and drains in-flight HTTP requests, which includes bot-play's
20 s assignment long-poll, so the old process exits **10–20 s** later and
only then does the new one start. During that gap REST calls answer `502`
and the app keeps retrying its socket; it reconnects and resyncs once the
new process is up. Running games continue because their state is in Redis.
bot-play waits for its running practice games to finish (up to 5 minutes)
before it restarts, so a practice game started in that window may wait for
a bot. Deploy when traffic is low. A rollback has the same 10–20 s gap.

Only one `ludo-deploy deploy`/`rollback` runs at a time (lock in
`/run/ludo-deploy.lock`).

### 3.1 Release a version (tag) and check what is live

Releases are git tags on `master` (`vMAJOR.MINOR.PATCH`). Tag, push, deploy
the tag, then check `/health`, which reports the build `ludo-deploy` stamped
in:

```bash
# on a Mac, after the PR is merged
git switch master && git pull
git tag -a v1.0.1 -m "Ludo Arena v1.0.1" && git push origin v1.0.1
gh release create v1.0.1 --generate-notes        # optional release notes

# on the VPS
ludo-deploy deploy v1.0.1
curl -s https://ludo.sungamestudio.com/health
# {"builtAt":"…","commit":"1a2b3c4","status":"ok","version":"v1.0.1"}
curl -s 127.0.0.1:9091/health                    # bot-play: version, build, commit
```

`ludo-deploy deploy master` (or a branch) works too; `/health` then shows
the nearest tag plus the commit, e.g. `v1.0.1-3-g1a2b3c4`. `ludo-deploy list`
and `ludo-deploy status` show the version of every release.

## 4. Roll back

```bash
ludo-deploy list                   # releases, * = live
ludo-deploy rollback               # the release before the live one
ludo-deploy rollback 20261022150102-1a2b3c4   # a specific one
```

Rollback re-points `current` and restarts; it does not rebuild anything.

**The database is not rolled back.** The backend never undoes a migration,
so the older release runs on the newer schema. This works when migrations
only add things (see §5.2). If a migration itself is the problem:

- preferred: fix it forward with a new migration and deploy;
- last resort: restore the backup taken before that deploy (§5.4). That
  loses every wallet, purchase and progression change made since.

If `ludo-deploy` itself is broken:

```bash
ls /opt/ludo-arena/releases
ln -sfn /opt/ludo-arena/releases/<name> /opt/ludo-arena/current
systemctl restart ludo-backend ludo-bot-play
```

## 5. Database

### 5.1 What is stored where

PostgreSQL (`ludo_arena`) holds accounts, wallets, progression, purchases
and reports: schemas `wallet`, `identity`, `progression`. Live games,
matchmaking, sessions and timers live in **Redis only**. The table list is
fixed by the owner (`CLAUDE.md`, enforced by `backend/tests/schema_guard_test.go`).
Ask before adding tables.

```bash
sudo -u postgres psql ludo_arena                    # interactive
sudo -u postgres psql ludo_arena -c '\dt wallet.*'
sudo -u postgres psql ludo_arena -c 'SELECT count(*) FROM wallet.wallets WHERE NOT is_bot'   # accounts
```

Be careful with writes: there is no undo except a backup restore.

### 5.2 Schema changes (migrations)

1. Add a file `backend/migrations/NNN_short_name.sql` (next number). The
   backend runs **every** migration file at **every** startup, in name order,
   under an advisory lock, so each file must be idempotent
   (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`,
   `ON CONFLICT DO NOTHING`, …).
2. Make it backward compatible, so the previous release still works on the
   new schema and a rollback is safe: add columns as nullable or with a
   default, add tables or indexes, never rename or drop in the same release.
   Drop old things in a later release, once nothing uses them.
3. Test it locally and in the e2e tests (`TEST_DATABASE_URL=… go test ./...`),
   merge, then `ludo-deploy deploy`. The deploy backs up the database first
   and the backend applies the migration when it starts.
4. Check: `journalctl -u ludo-backend -n 30` (a failed migration stops startup
   and the deploy rolls back by itself), then `ludo-deploy status`.

Large tables: `CREATE INDEX CONCURRENTLY` cannot run in a transaction; keep
such statements in their own file and test the lock time on a copy first.

### 5.3 Backups

| When | File | Kept |
|---|---|---|
| Every night 21:30 UTC (03:00 IST), `/etc/cron.d/ludo-arena-backup` | `ludo_arena-YYYY-MM-DD.dump` | 14 days |
| Before a deploy that changes migrations | `ludo_arena-<utc>-pre-<release>.dump` | until removed |
| By hand: `ludo-deploy backup [label]` | `ludo_arena-<utc>-<label>.dump` | until removed |

All of them are in `/var/backups/ludo-arena/` on the same disk. **Copy them
off the server** regularly. From a Mac:

```bash
scp root@ludo.sungamestudio.com:/var/backups/ludo-arena/ludo_arena-2026-10-23.dump ~/Backups/
```

### 5.4 Restore a backup

This replaces the whole database with the dump.

```bash
ludo-deploy backup before-restore                         # keep what is there now
systemctl stop ludo-bot-play ludo-backend
sudo -u postgres pg_restore --clean --if-exists --no-owner --role=ludo \
  -d ludo_arena /var/backups/ludo-arena/<file>.dump
systemctl start ludo-backend ludo-bot-play
ludo-deploy status
```

### 5.5 Redis

```bash
export REDISCLI_AUTH=$(awk '{print $2}' /etc/redis/ludo-arena-secret.conf)
redis-cli info clients | head; redis-cli dbsize
```

Redis holds live games; **never** run `FLUSHALL`/`FLUSHDB` on production.
Data survives restarts (AOF every second + RDB in `/var/lib/redis`). A Redis
restart pauses play for a few seconds; the backend reconnects by itself.

## 6. Change server configuration

The files in this folder are the source of truth for the server. Change them
in the repo first, then apply them on the server, so the next provisioning
gives the same result.

### 6.1 Backend settings (`/etc/ludo-arena/backend.env`)

```bash
nano /etc/ludo-arena/backend.env
systemctl restart ludo-backend          # sockets reconnect, like a deploy
```

- systemd reads this file: one `KEY=value` per line, **no inline comments**,
  no quotes. Option reference: `backend/.env.example`.
- `provision.sh` creates it once from [`backend.env.example`](backend.env.example)
  and never overwrites it. When a release needs a new setting, add the key
  to `backend.env.example` in the repo *and* to the server's file by hand.
- Secrets in it: `JWT_SIGNING_KEY` (changing it signs every player out),
  `PUBLIC_ID_KEY` (**never change it**: it would orphan every device
  binding and change every public player id), `ACTIVE_USER_KEY`,
  `DATABASE_URL` password, `REDIS_PASSWORD`, `BOT_SERVICE_KEY_SHA256`, the
  four `R2_*` (profile pictures and emotes) and
  `GOOGLE_PLAY_SERVICE_ACCOUNT_FILE`. Never commit them.

### 6.2 App policy, entry fees, catalogues, coin packs

These are files in `backend/config/` and ship with every release:
change them in the repo, merge, `ludo-deploy deploy`. The app policy
(`app-policy.production.json`: minimum versions, maintenance windows, entry
fees, welcome grant) is also re-read every 5 s and on
`systemctl reload ludo-backend`.

Emergency maintenance without a deploy:

```bash
touch /etc/ludo-arena/MAINTENANCE     # players see the maintenance message
rm /etc/ludo-arena/MAINTENANCE        # back to normal
```

### 6.3 nginx

Edit [`nginx/`](nginx/) in the repo, copy the file to the server, then:

```bash
nginx -t && systemctl reload nginx
```

A reload keeps existing WebSockets on the old workers for up to 30 s
(`worker_shutdown_timeout`); after that they are closed and the app
reconnects.

### 6.4 Kernel limits, PostgreSQL, Redis, units, firewall

Edit the files in this folder, then re-run provisioning (idempotent; it keeps
secrets, data and certificates):

```bash
# on the Mac, from the repository root
scp -r deploy root@ludo.sungamestudio.com:/root/
ssh root@ludo.sungamestudio.com bash /root/deploy/scripts/provision.sh
```

Provisioning restarts Redis, PostgreSQL and nginx (a few seconds of
disruption): run it when traffic is low. It does not restart the backend;
run `systemctl restart ludo-backend` if a unit file changed.

### 6.5 bot-play

Its settings are `bot-play/configs/environments/production.yaml` in the repo
(deployed with each release). `public_matchmaking` is off: bots join only
practice games. Turn it on in that file, set `BOT_PUBLIC_FILL_ENABLED=true` in
`backend.env`, deploy, and restart the backend.

### 6.6 Operating system

`unattended-upgrades` installs Ubuntu security updates automatically. All
services start on boot, so a reboot (`reboot`, or Bluehost → Reboot Server)
only interrupts play briefly.

## 7. TLS certificate and DNS

- The certificate renews itself (`systemctl list-timers certbot.timer`); a
  hook reloads nginx afterwards. Test renewal: `certbot renew --dry-run`.
  Expiry: `ludo-deploy status`.
- DNS is in Cloudflare → sungamestudio.com → DNS → Records. Keep `ludo` on
  **DNS only**. Turning the orange-cloud proxy on would put Cloudflare's
  idle timeouts in front of game sockets, change the client IP the backend
  sees (`TRUSTED_PROXY_HOPS`, nginx `real_ip`) and break Let's Encrypt's
  HTTP check as configured here.

## 8. Troubleshooting

```bash
ludo-deploy status
journalctl -u ludo-backend -f              # also ludo-bot-play, nginx
tail -f /var/log/nginx/error.log
curl -s 127.0.0.1:9090/metrics | grep -E '^(ws_connections_active|players_in_game|players_in_lobby) '
```

| Symptom | Check |
|---|---|
| App shows connection errors, `502` from nginx | `systemctl status ludo-backend`; `journalctl -u ludo-backend -n 100`; roll back |
| `/readyz` says `postgres unavailable` / `redis unavailable` | `systemctl status postgresql@16-main` / `redis-server` |
| Practice games get no bot | `systemctl status ludo-bot-play`; `curl -s 127.0.0.1:9091/readyz` |
| Purchases fail with `iap_unavailable` | Google Play key access in Play Console (log: `store credentials refused`); App Store needs `APPLE_IAP_ENABLED=true` |
| Profile pictures missing | `R2_*` in `backend.env`; log line `assetSigning` at startup |
| Disk filling up | `df -h /`; old dumps in `/var/backups/ludo-arena`; `journalctl --vacuum-size=1G` |

## 9. WebSocket capacity

Each player socket holds one client connection and one loopback connection
in nginx, one file descriptor in the backend and one ephemeral port from nginx
to `127.0.0.1:8080`.

| Limit | Value | Allows |
|---|---|---|
| nginx `worker_connections` × workers | 65,536 × 8 | ~260k sockets |
| nginx / backend `LimitNOFILE` | 1,048,576 | far above 20k |
| `fs.file-max`, `fs.nr_open` | 2,097,152 | |
| `ip_local_port_range` | 10240–65535 | ~55k nginx→backend sockets (default ~28k) |
| `nf_conntrack_max` | 1,048,576 | ufw tracks 2 entries per socket |
| `somaxconn`, SYN backlog | 65,535 | reconnect storms after a deploy |
| `WS_MAX_CONNECTIONS` (backend) | 50,000 | |
| nginx `proxy_read_timeout` (WS) | 120 s | server pings every 20 s |

### 9.1 Measured on this VPS (22 Oct 2026)

Load generator: two bot-play processes in load-test mode on the same VPS
(they share its 8 vCPUs), against a separate development backend, Redis and
database, through nginx + TLS on a loopback listener. Bots played real
Ludo, Quick Ludo and Snakes & Ladders games at a human pace (1.5–5 s per
action), with 30 reconnects/min of churn per process and 2 % deliberately
slow readers. Steady window: 120 s after a 100 s ramp.

| | 20,000 sockets |
|---|---|
| Connected / failed sessions | 20,000 / 0 |
| Hash mismatches (state divergence) | 0 |
| Reconnects | 888 of 888 succeeded |
| Machine CPU busy (incl. load generator) | 36–41 % of 8 vCPU |
| Backend | 1.5 cores, 1.9 GB RSS |
| nginx (8 workers) | 0.35 cores, 1.4 GB RSS |
| Redis | 0.24 cores, 0.1 GB RSS |
| Memory still available | ~10 GB of 16 GB |
| Server messages out / commands in | 15.7k/s / 2.3k/s |
| Server command processing | p99 ≤ 2.5 ms, p99.9 ≤ 5 ms |
| Client roll latency | p50 0.72 ms, p95 2.3 ms |
| nginx error-log lines | 0 |

The client p99 (~500 ms) and the 634 client pong timeouts come from the
2 % slow-reader bots (250 ms per message), which fall behind by design; all
of them reconnected. Without the load generator the server side needs about
2 cores and 3.5 GB for 20k players at this pace. Faster play costs more:
the repo's M5 Pro run (200–800 ms per action) reached its knee at ~9k
players on one Redis (`docs/performance.md`). Not yet measured here: a
reconnect storm (all 20k sockets reconnecting at once after a deploy).

## 10. Rebuild the server from scratch

1. Reinstall Ubuntu 24.04 (Bluehost → Server Image → Reimage) and point the
   Cloudflare `ludo` record at the new IP (DNS only).
2. From the repository root on a Mac:
   `scp -r deploy root@<ip>:/root/ && ssh root@<ip> bash /root/deploy/scripts/provision.sh`
3. The first run stops after printing a new deploy key: add it in GitHub →
   Ludo-Arena → Settings → Deploy keys (read-only; delete the old one) and run
   `provision.sh` again.
4. Add the values that are not generated on the server to
   `/etc/ludo-arena/backend.env`: the four `R2_*`, and
   `GOOGLE_PLAY_SERVICE_ACCOUNT_FILE=/etc/ludo-arena/secrets/google-play.json`
   after copying the key there (`chown root:ludo`, `chmod 0640`).
5. Restore the latest database dump (§5.4), then `ludo-deploy deploy`.

A new server generates new `JWT_SIGNING_KEY` and `PUBLIC_ID_KEY`. To keep
players signed in and their device bindings, copy
`/etc/ludo-arena/backend.env` from the old server instead (step 4).

## 11. Files in this folder

| File | Installed as |
|---|---|
| `scripts/provision.sh` | run once per server (idempotent) |
| `scripts/ludo-deploy` | `/usr/local/bin/ludo-deploy` |
| `nginx/nginx.conf` | `/etc/nginx/nginx.conf` |
| `nginx/ludo.sungamestudio.com.conf` | `/etc/nginx/sites-available/ludo.sungamestudio.com` |
| `sysctl/99-ludo-arena.conf` | `/etc/sysctl.d/99-ludo-arena.conf` |
| `systemd/ludo-backend.service`, `ludo-bot-play.service` | `/etc/systemd/system/` |
| `systemd/nginx-limits.conf` | `/etc/systemd/system/nginx.service.d/limits.conf` |
| `redis/ludo-arena.conf` | `/etc/redis/ludo-arena.conf` (included from `redis.conf`) |
| `postgresql/ludo-arena.conf` | `/etc/postgresql/16/main/conf.d/ludo-arena.conf` |
| `backend.env.example` | template for `/etc/ludo-arena/backend.env` |
| `read.html` | this runbook as a web page |
