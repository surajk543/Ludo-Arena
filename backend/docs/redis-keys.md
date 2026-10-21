# Redis Key Layout

Redis holds live, mostly ephemeral state. Durable data (wallets, identities,
progression) is in PostgreSQL. All keys live in one logical database; Redis
Cluster is **not** supported (commit scripts touch keys not declared in
`KEYS`). Recommended production settings: `appendonly yes`,
`appendfsync everysec`, RDB snapshots, `maxmemory-policy noeviction`, private
network only, AUTH/TLS.

| Key | Type | TTL | Written by | Purpose |
|---|---|---|---|---|
| `room:{roomId}` | hash `{rev, s}` | lobby 30 min · playing 3 h · finished 10 min + rematch window · closed 2 min (refreshed on every commit) | rooms | Full authoritative room state (JSON) + optimistic revision. Also read (never written) by player reports to verify that reporter and reported player hold a seat |
| `user:{userId}:room` | string | 6 h | rooms (atomic with room commits, guarded) | One active room per user |
| `roomcode:{CODE}` | string | room TTL | rooms | Private room code → room id |
| `mm:open:{pool}:{game}:{variant}:{capacity}` | zset (score = created ms) | — (members removed on start/close) | rooms | Open public lobbies; `pool` = `live` or `loadtest` |
| `sched` | zset (score = due ms) | — | rooms | Distributed timers: `turn`, `fill`, `lobbykick`, `rematch`, `practice`, `botexp`, `payout`, `record` |
| `idx:rooms:live` | hash: room id → `{rev}\|{status}\|{game}\|{mode}\|{humans}\|{bots}` | — (entries removed on finish/close; expired rooms pruned by the recount) | rooms (atomic with every room commit) | Live-room index behind the cluster-wide game gauges: one entry per room in `lobby` or `playing`; `humans`/`bots` count non-forfeited seats. `rev` equals the room's `rev` after that commit, so an entry is valid only while it matches `room:{id}` rev |
| `stats:game` | string (JSON recount) | 4 × `GAME_STATS_INTERVAL` | rooms (lease holder) | Last cluster-wide recount (`players_in_game`, `rooms_in_game`, `players_in_lobby`); instances without the lease publish this value |
| `stats:game:lease` | string (instance id) | 2 × `GAME_STATS_INTERVAL` (renewed by the holder each interval; released on shutdown) | rooms | Elects the one instance that recounts each interval |
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
| `seat:{userId}` | string (JSON `{l, lo, p}`) | 1 h | progression | Seat summary cache: level + non-starter loadout slots + equipped profile-picture id (`p`, omitted when none; resolved against the in-memory picture catalogue), read by room joins instead of PostgreSQL. Deleted after every committed level-up (match record, mission claim), equip and profile-picture apply. Filled on a miss only by the holder of `seat:{userId}:lease` |
| `seat:{userId}:lease` | string (token) | 5 s | progression | Fill lease taken atomically with a cache miss; deleted with the entry on invalidation, so a fill that read PostgreSQL before a concurrent commit never stores the old value |
| `emotes:{userId}` | set | 1 h | progression | Owned non-starter emotes (chat hot path). Members are never stale (inventory is append-only); a missing member is confirmed in PostgreSQL and added. Grants add to an existing set |
| `presence:{userId}` | string | 60 s (refreshed) | gateway | Online indicator (friends list) |
| `dedup:{userId}:{msgId}` | string | 2 min | gateway | WebSocket command de-duplication |
| `rl:{rule}:{key}:{window}` | counter | window | ratelimit | Fixed-window rate limits (e.g. `rl:profile_user:…`, 20 `PATCH /me` per minute per account) |
| `ev:room:{roomId}` / `ev:user:{userId}` | pub/sub channels | — | rooms / notify / gateway | Cross-instance event fan-out. `ev:user:*` also carries gateway control messages (`{"ctl":"kick","conn":…}`, `{"ctl":"revoke","sid":…}`) that are never forwarded to clients |
| progression/social/analytics keys | see `docs/progression.md` | | | Recent opponents, weekly leaderboard, idempotency replays (`idem:{userId}:{key}`, also used by Store purchases), active-user sketches. The profile-picture Store adds no Redis keys (its catalogue is an in-memory snapshot per instance; ownership and the equipped picture are in PostgreSQL) apart from `rl:asset_sign_user:*` counters. Player reports and the friend cap keep no Redis state of their own (only `rl:report_user:*`, `rl:report_read_user:*`, `rl:admin_ip:*` rate-limit counters); reports are stored in PostgreSQL |

## Atomic commits

Every room mutation runs `commitScript` (Lua): check revision → check guards
(e.g. "user pointer is unset or already this room") → write state + TTL →
apply side operations (pointers, codes, open-lobby set, timers, bot queue) →
write or remove the room's `idx:rooms:live` entry → `PUBLISH` the ordered
event batch. Because Redis runs scripts serially, events are published in
commit order even with many backend instances.

## Live game counts

`idx:rooms:live` is written in the same script as the room state, so it can
never disagree with a committed room. Every `GAME_STATS_INTERVAL` (default
15 s, ±10 % jitter) the instance holding `stats:game:lease` recounts it
(`backend/internal/rooms/stats.go`): `HSCAN` pages of 256 entries, each
checked by one Lua call that reads the entry and `room:{id}` `rev` together.
An entry whose room key is gone (TTL expiry) is deleted; one whose `rev`
differs from the room's (written by an instance without the index, e.g.
during a rolling deploy) is counted from the room state itself and dropped if
the room is no longer live. The result is cached in `stats:game`, which the
other instances publish, so every instance exports the same values and Redis
does the work once per interval. Measured on a local Redis 7.4: about 2 µs of
Redis time per live room (≈ 0.5 ms per 256-room call); a full recount of
20,000 live rooms takes ≈ 48 ms end to end. The index entry adds one small
`HSET`/`HDEL` to each room commit.

## Redis restart / data loss

With AOF `everysec`, at most ~1 s of room changes can be lost on a crash.
Clients detect any resulting version gap or hash mismatch and resync from the
restored snapshot. If Redis data is lost entirely, live rooms, sessions (users
sign in again; guests resume with their guest secret), presence and timers are
lost — wallets, identities, progression and player-chosen display names are
not (PostgreSQL; display profiles are rebuilt from it). Game recovery
across a total Redis loss is **not** provided.
