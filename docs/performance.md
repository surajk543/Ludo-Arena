# WebSocket Performance, Compression & Load Tests

All numbers below are **measured** on a single Apple M5 Pro development
machine on 2026-10-21, with the Go backend (one instance), Redis 7.4 and the
bot-play load generator **all on the same machine** (they compete for CPU, so
production servers with dedicated cores should do better; we do not claim
any number we did not measure). Raw results:
[`bot-play/loadtest-results/2026-10-21-m5pro.json`](../bot-play/loadtest-results/2026-10-21-m5pro.json).

## Design summary

| Mechanism | Setting (default) | Why |
|---|---|---|
| Negotiated `permessage-deflate` (RFC 7692) | `WS_COMPRESSION=no_context_takeover` | Interoperable with `dart:io` and `coder/websocket`; negotiated at the handshake, invisible to the app protocol |
| Compression threshold | `WS_COMPRESSION_THRESHOLD=1024` bytes | Delta events (~150 B) get **larger** when deflated without context; only snapshots/resyncs are compressed |
| Compression level | `flate.BestSpeed` (fixed by `coder/websocket`) | Levels 6/9 save only 2–3 % more for 25–60 % more CPU (measured below) |
| Delta events | `game.dice_result`, `game.move_applied`, `game.turn_changed`, … with state version `v` and FNV-1a hash `h` | 6× fewer bytes than sending snapshots, with verifiable correctness |
| Full snapshots | join, reconnect, `game.request_sync`, gap/hash mismatch, queue overflow | Authoritative recovery |
| Bounded outbound queue | `WS_OUTBOUND_QUEUE=128` per connection | On overflow the queued deltas are replaced by one fresh snapshot; 3 overflows/min or a 10 s write stall closes with `4508` |
| Inbound limit | `WS_READ_LIMIT=4096` bytes **after decompression** | Decompression-bomb protection (limit applies to the inflated stream) |
| Heartbeat | server ping 20 s / pong 10 s; client app-level ping 15 s | Dead-connection detection |
| Per-connection rate limit | 10 commands/s, burst 20; abusive clients closed (`4429`) | Abuse protection before expensive processing |

### Security notes on compression

Server→client messages never contain tokens or secrets, and every member of a
room already knows everything in that room's messages (there is no hidden
information in Ludo or Snakes & Ladders). Attacker-influenced content
(display names) and a private room's code are therefore never mixed with
secrets in a compression context, so CRIME/BREACH-style attacks have nothing
to extract. With the default no-context-takeover mode each message is also
compressed independently. All messages are validated after decompression and
the inbound size limit applies to the decompressed size.

## 1. Compression of real protocol messages (offline)

Messages produced by the real engines and encoders while playing full games
(`backend/internal/rooms/compression_bench_test.go`;
`COMPRESSION_REPORT=1 go test -run TestCompressionReport -v ./internal/rooms/`).
Writers are pooled like in production. Percentages are compressed ÷ original.

| Sample | Msgs | Avg bytes | BestSpeed (L1) | L1 µs/msg | L6 | L6 µs/msg | L9 | Context takeover (L1) |
|---|---|---|---|---|---|---|---|---|
| Ludo 2p deltas | 523 | 165 | 171 (104 %) | 0.3 | 161 | 2.8 | 138 | 42 (26 %) |
| Ludo 2p snapshots | 19 | 1015 | 479 (47 %) | 5.9 | 470 | 7.3 | 467 | 76 (7 %) |
| Ludo 4p deltas | 1053 | 166 | 172 (104 %) | 0.3 | 164 | 2.8 | 139 | 39 (23 %) |
| Ludo 4p snapshots | 38 | 1635 | 544 (33 %) | 6.8 | 530 | 9.4 | 528 | 83 (5 %) |
| Snakes 4p deltas | 153 | 162 | 168 (104 %) | 0.3 | 160 | 2.5 | 136 | 39 (24 %) |
| Snakes 4p snapshots | 6 | 1602 | 547 (34 %) | 6.3 | 516 | 8.2 | 514 | 139 (9 %) |

Conclusions: deltas are too small for independent deflate; snapshots compress
well at BestSpeed; higher levels are not worth the CPU; context takeover
compresses everything well but costs memory per connection (see §2).

## 2. Load tests (live backend, real protocol)

Method (`bot-play/scripts/loadtest_matrix.py`): for each scenario a fresh
backend starts with the scenario's settings; bot-play (load-test mode,
isolated pool, no wallets) ramps up the target number of WebSocket clients
playing a realistic mix (Ludo 50 %, Quick Ludo 30 %, Snakes 20 %; 2/3/4-player
rooms 40/20/40 %; 200–800 ms think time; 30 reconnects/min churn with resync
verification; 2 % deliberately slow readers (250 ms per message); 0.1 %
malformed messages). After ramp-up and a warm-up, server Prometheus counters
are scraped at the start and end of a 60 s steady window; CPU and RSS of the
backend and Redis are sampled with `ps`. **Payload bytes** = uncompressed
application messages; **wire bytes** = bytes actually written to the socket
(WebSocket frames including headers, after compression; TLS not included).

### 2a. Compression and delta matrix (1,000 concurrent clients)

| Scenario | Server msgs/s | Payload KB/s | **Wire KB/s** | Wire ÷ payload | Avg wire B/msg | Server CPU (cores) | Server RSS | Redis CPU |
|---|---|---|---|---|---|---|---|---|
| Deltas, compression disabled | 4,326 | 617 | 632 | 1.025 | 150 | 0.32 | 134 MB | 24 % |
| **Deltas, deflate no-context, 1 KB threshold (default)** | 4,336 | 621 | 634 | 1.021 | 150 | 0.33 | 144 MB | 24 % |
| Deltas, deflate no-context, 128 B threshold | 4,291 | 612 | 633 | 1.033 | 151 | 0.33 | 153 MB | 22 % |
| Deltas, deflate **context takeover**, 128 B threshold | 4,371 | 625 | **157** | **0.251** | 37 | 0.32 | **1,216 MB** | 21 % |
| Full snapshot with every event, no compression | 4,394 | 3,833 | 3,848 | 1.004 | 897 | 0.30 | 134 MB | 21 % |
| Full snapshot with every event, deflate no-context | 4,358 | 3,843 | 2,294 | 0.597 | 539 | 0.35 | 147 MB | 21 % |

Every scenario: 1,000/1,000 sessions, 0 failed sessions, **0 hash
mismatches**, ~860–900 completed games per minute, client roll latency p50
≈ 0.6 ms / p95 ≈ 1.0–1.1 ms. Client p99 (≈ 250–500 ms) is dominated by the 2 %
of bots that deliberately read slowly.

Findings:
- **Deltas cut bandwidth ~6×** versus full snapshots; compressing snapshots
  only recovers 40 %, so "snapshots + deflate" still uses 3.6× the bandwidth of
  plain deltas.
- With deltas, no-context deflate changes nothing (messages are below or near
  the break-even size) — the threshold correctly avoids wasted CPU.
- **Context takeover saves 75 % of wire bytes** but adds ≈ 1.07 MB of
  compressor state per connection (RSS 144 MB → 1,216 MB at 1,000
  connections). Default stays **no context takeover** (memory bounds
  connections per instance); `WS_COMPRESSION=context_takeover` is available for
  bandwidth-constrained deployments with fewer connections per instance. (The
  first context-takeover run is marked invalid in the raw data: the load
  generator offered `server_no_context_takeover`; it is now configurable via
  `connection.compression_mode`.)

### 2b. Concurrency scaling (default configuration)

| Concurrent clients | Server msgs/s | Commands/s | Wire KB/s | Server CPU avg (cores) | Server RSS | Goroutines | Redis CPU | Roll p50 / p95 | Server cmd p99 | Slow-client events | Failed sessions | Hash mismatches |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1,000 | 4,336 | 699 | 634 | 0.33 | 144 MB | 3,037 | 24 % | 0.67 / 1.1 ms | ≤ 1 ms | 0 | 0 | 0 |
| 2,000 | 8,674 | 1,423 | 1,262 | 0.47 | 246 MB | 6,037 | 34 % | 0.46 / 0.76 ms | ≤ 1 ms | 0 | 0 | 0 |
| 4,000 | 17,417 | 2,837 | 2,541 | 0.80 | 442 MB | 12,039 | 51 % | 0.40 / 0.89 ms | ≤ 1 ms | 0 | 0 | 0 |
| 6,000 | 26,077 | 4,226 | 3,807 | 1.18 | 627 MB | 18,036 | 64 % | 0.47 / 1.6 ms | ≤ 2.5 ms | 0 | 0 | 0 |
| **9,000** | 38,812 | 6,294 | 5,666 | 1.81 | 922 MB | 27,035 | 74 % (spikes higher) | 0.59 / 3.8 ms | **≤ 250 ms** | 0 | 0 | 0 |

Resource use grows linearly: ≈ 3 goroutines and ≈ 100 KB RSS per connection;
≈ 0.2 cores and ≈ 10 percentage points of Redis CPU per 1,000 connections.
**Observed bottleneck: Redis** (single-threaded; every command is a Lua
compare-and-set + publish). **Highest load tested: 9,000 concurrent WebSocket
players on one backend instance with full game traffic** (38.8k server
messages/s, 6.3k commands/s, ~9,100 completed games/min, 0 failed sessions,
0 hash mismatches). At 9,000 the knee is visible: server command-processing
p99 rose from ≤ 2.5 ms (6,000) to ≤ 250 ms and client p95 from 1.6 ms to
3.8 ms while Redis averaged 74 % CPU. On comparable hardware we therefore
recommend planning **≤ 6,000 concurrent players per Redis** to keep latency
headroom. Horizontal scaling: any number of backend
instances can share one Redis; the next limit is Redis CPU, after which rooms
would need to be sharded across Redis instances (not implemented).

### Reproduce

```bash
cd backend && go build -o /tmp/ludo-server ./cmd/server
cd ../bot-play && go build -o /tmp/bot-play ./cmd/bot-play
BACKEND_BIN=/tmp/ludo-server BOTPLAY_BIN=/tmp/bot-play \
BACKEND_ENV_FILE=/path/to/dev.env BOT_SERVICE_KEY=... \
python3 scripts/loadtest_matrix.py --bots 1000 --steady 60
```

`dev.env` must be a **development** configuration with `BOT_SERVICE_KEY_SHA256`
matching `BOT_SERVICE_KEY`; the runner sets `RATE_LIMIT_DISABLED=true` and
`BOT_LOADTEST_ENABLED=true` (both refused in production).

## 3. Client (Flutter) side

The Flutter client uses `dart:io` `WebSocket` with `CompressionOptions`
(negotiated deflate; decompression handled by the Dart runtime), decodes
JSON envelopes on the UI isolate (messages are ≤ a few KB; the decode function
is isolated so it can move to a background isolate if profiling shows a
need), applies deltas through a pure reducer with version and hash checks, and
animates server-confirmed events in order (snapping on snapshots).

## Limitations

- Single-machine measurements; network latency, TLS cost and mobile radio
  behaviour are not represented.
- Redis Cluster is not supported (commit scripts touch undeclared keys);
  scaling beyond one Redis requires sharding rooms.
- `coder/websocket` fixes the deflate level at BestSpeed; the level
  comparison above is therefore an offline measurement.
