# Production VPS: ludo.sungamestudio.com

One Bluehost VPS (Ultimate VPS NVMe 16, Mumbai, Ubuntu 24.04, `129.121.171.63`)
runs the whole production stack. DNS is on Cloudflare: `ludo` is an **A record,
DNS only** (grey cloud). Game sockets go straight to nginx, with no proxy idle
timeouts, and Let's Encrypt issues the certificate.

```
app ──TLS──▶ nginx :443 ──▶ backend 127.0.0.1:8080 ──▶ PostgreSQL 16 (localhost)
                 ▲                │                  └─▶ Redis 7 (localhost, password)
bot-play ────────┘ (loopback, /etc/hosts)            metrics 127.0.0.1:9090 / :9091
```

Only ports 22, 80 and 443 are open (ufw). PostgreSQL, Redis, the backend
and metrics listen on localhost only.

| File | Installed as |
|---|---|
| `nginx/nginx.conf` | `/etc/nginx/nginx.conf` |
| `nginx/ludo.sungamestudio.com.conf` | `/etc/nginx/sites-available/ludo.sungamestudio.com` |
| `sysctl/99-ludo-royale.conf` | `/etc/sysctl.d/99-ludo-royale.conf` |
| `systemd/ludo-backend.service`, `ludo-bot-play.service` | `/etc/systemd/system/` |
| `systemd/nginx-limits.conf` | `/etc/systemd/system/nginx.service.d/limits.conf` |
| `redis/ludo-royale.conf` | `/etc/redis/ludo-royale.conf` (included from `redis.conf`) |
| `postgresql/ludo-royale.conf` | `/etc/postgresql/16/main/conf.d/ludo-royale.conf` |
| `backend.env.example` | `/etc/ludo-royale/backend.env` (secrets generated on the server) |

Secrets exist only on the server: `/etc/ludo-royale/backend.env`,
`/etc/ludo-royale/bot-play.env`, `/etc/ludo-royale/secrets/` (database
password, Google Play key) and `/etc/redis/ludo-royale-secret.conf`. Never copy
them into the repository.

## Provision (once, idempotent)

```bash
scp -r deploy root@ludo.sungamestudio.com:/root/
ssh root@ludo.sungamestudio.com bash /root/deploy/scripts/provision.sh
```

Then add the values that cannot be generated on the server to
`/etc/ludo-royale/backend.env`: the four `R2_*` (profile pictures and emotes)
and `GOOGLE_PLAY_SERVICE_ACCOUNT_FILE=/etc/ludo-royale/secrets/google-play.json`
(copy the key there, `chmod 0640`, group `ludo`).

## Release / roll back

```bash
deploy/scripts/release.sh                 # build from this checkout, upload, restart
ROLLBACK=1 deploy/scripts/release.sh      # back to the previous release
```

A restart closes every WebSocket with `1001`; the app reconnects and resyncs.
Releases are kept in `/opt/ludo-royale/releases` (last 5); `current` points at
the active one.

## Operations

```bash
journalctl -u ludo-backend -f                         # logs (also ludo-bot-play, nginx)
systemctl reload ludo-backend                         # SIGHUP: app policy + legal page
touch /etc/ludo-royale/MAINTENANCE                    # emergency maintenance (rm to end)
curl -s 127.0.0.1:9090/metrics | grep ws_connections  # live sockets
ls /var/backups/ludo-royale                           # nightly pg_dump, 14 days (local only)
```

Backups are local to the VPS. Copy them off the machine (or set up PITR,
`docs/deployment.md`) before real money flows through the wallets.

## WebSocket capacity

Each WebSocket holds one client connection and one loopback connection in
nginx, one file descriptor in the backend, and one ephemeral port from
nginx to `127.0.0.1:8080`.

| Limit | Value | Allows |
|---|---|---|
| nginx `worker_connections` × workers | 65,536 × vCPUs | ~32k sockets per worker |
| nginx / backend `LimitNOFILE` | 1,048,576 | far above 20k |
| `fs.file-max`, `fs.nr_open` | 2,097,152 | |
| `ip_local_port_range` | 10240–65535 | ~55k nginx→backend sockets (default ~28k) |
| `nf_conntrack_max` | 1,048,576 | ufw tracks 2 entries per socket |
| `somaxconn`, SYN backlog | 65,535 | reconnect storms after a deploy |
| `WS_MAX_CONNECTIONS` (backend) | 50,000 | |
| nginx `proxy_read_timeout` (WS) | 120 s | server pings every 20 s |

Sockets are not the bottleneck; Redis CPU is (`docs/performance.md`: one
backend and one Redis reached ~9,000 players in active games on an M5 Pro,
with ≤ 6,000 recommended). The connection limits above allow 20k+ connected
players, but plan game capacity from measurements on this VPS.
