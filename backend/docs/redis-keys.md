# Redis Key Layout

Redis holds live, mostly ephemeral state. Durable data (wallets, identities,
progression) is in PostgreSQL. All keys live in one logical database; Redis
Cluster is **not** supported (commit scripts touch keys not declared in
`KEYS`). Recommended production settings: `appendonly yes`,
`appendfsync everysec`, RDB snapshots, `maxmemory-policy noeviction`, private
network only, AUTH/TLS.

| Key | Type | TTL | Written by | Purpose |
|---|---|---|---|---|
| `room:{roomId}` | hash `{rev, s}` | lobby 30 min · playing 3 h · finished 10 min + rematch window · closed 2 min (refreshed on every commit) | rooms | Full authoritative room state (JSON) + optimistic revision |
| `user:{userId}:room` | string | 6 h | rooms (atomic with room commits, guarded) | One active room per user |
| `roomcode:{CODE}` | string | room TTL | rooms | Private room code → room id |
| `mm:open:{pool}:{game}:{variant}:{capacity}` | zset (score = created ms) | — (members removed on start/close) | rooms | Open public lobbies; `pool` = `live` or `loadtest` |
| `sched` | zset (score = due ms) | — | rooms | Distributed timers: `turn`, `fill`, `lobbykick`, `rematch`, `practice`, `botexp`, `payout`, `record` |
| `settle:fee:{room}:{round}` / `settle:pay:{room}:{round}` | string | 24 h / 7 d | rooms | Settlement guards (entry fees / payout at most once) |
| `settle:retry:*`, `record:retry:*` | counter | 1 h | rooms | Bounded retry counters |
| `bot:assignments` | list | — | rooms | Pending bot assignment ids (long-poll queue) |
| `botasg:{id}` | string | `BOT_ASSIGNMENT_TTL` | rooms | Assignment payload; claimed with GETDEL |
| `botsess:{uid}` | string | bot session TTL | rooms | Bot public id → session/room (revocation) |
| `sess:{sid}` | hash `{uid, cur, actor}` | refresh TTL (sliding) | auth | Session family; deleting it revokes access + refresh |
| `rt:{sha256}` | string | refresh TTL | auth | Refresh-token hash → session (old hashes remain as reuse tombstones) |
| `usess:{userId}` | string (sid) | refresh TTL (slides with refresh) | auth | The account's one live **human** session. Set atomically by every sign-in (Lua), which deletes the previous `sess:{old}`; cleared on logout only if it still names that sid. Never written for bot sessions |
| `sessrep:{sid}` | string (newer sid) | refresh TTL | auth | Tombstone: `sid` was ended by a newer sign-in of the account → refresh / REST / WS upgrade answer `session_replaced`. Not written by logout or reuse revocation |
| `profile:{userId}` | hash `{name, avatar}` | none | profile | Display cache. A player-chosen name is authoritative in PostgreSQL (`progression.player_progress.display_name`) and written here in the same request; if this key is lost, reads (`Get`/`GetMany`, `HSETNX`) and the next sign-in rebuild it. Provider/generated names are cache-only (refreshed on sign-in) |
| `namechg:{userId}` | zset (member = change id, score = unix ms) | 24 h after the last change | profile | Rolling 24 h window of successful display-name changes (`NAME_CHANGES_PER_DAY`); checked and recorded atomically by a Lua script. Not affected by `RATE_LIMIT_DISABLED`. Losing it only resets the limit |
| `pubid:{uid}` | string | none | profile | Public id → account id cache |
| `presence:{userId}` | string | 60 s (refreshed) | gateway | Online indicator (friends list) |
| `dedup:{userId}:{msgId}` | string | 2 min | gateway | WebSocket command de-duplication |
| `rl:{rule}:{key}:{window}` | counter | window | ratelimit | Fixed-window rate limits (e.g. `rl:profile_user:…`, 20 `PATCH /me` per minute per account) |
| `ev:room:{roomId}` / `ev:user:{userId}` | pub/sub channels | — | rooms / notify / gateway | Cross-instance event fan-out. `ev:user:*` also carries gateway control messages (`{"ctl":"kick","conn":…}`, `{"ctl":"revoke","sid":…}`) that are never forwarded to clients |
| progression/social/analytics keys | see `docs/progression.md` | | | Recent opponents, weekly leaderboard, idempotency replays, active-user sketches |

## Atomic commits

Every room mutation runs `commitScript` (Lua): check revision → check guards
(e.g. "user pointer is unset or already this room") → write state + TTL →
apply side operations (pointers, codes, open-lobby set, timers, bot queue) →
`PUBLISH` the ordered event batch. Because Redis runs scripts serially, events
are published in commit order even with many backend instances.

## Redis restart / data loss

With AOF `everysec`, at most ~1 s of room changes can be lost on a crash.
Clients detect any resulting version gap or hash mismatch and resync from the
restored snapshot. If Redis data is lost entirely, live rooms, sessions (users
sign in again; guests resume with their guest secret), presence and timers are
lost — wallets, identities, progression and player-chosen display names are
not (PostgreSQL; display profiles are rebuilt from it). Game recovery
across a total Redis loss is **not** provided.
