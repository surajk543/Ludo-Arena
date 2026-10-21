# Progression, Missions, Collection Room, Social & Analytics

Backend design for XP/levels, missions and events, reward claims, cosmetics
(Collection Room), friends, invites, leaderboards, player reports and
privacy-conscious analytics. HTTP contract: [`rest-api.md`](rest-api.md); push messages:
[`websocket-protocol.md`](websocket-protocol.md); item ids:
[`cosmetics-catalog.md`](cosmetics-catalog.md).

| Package | Owns |
|---|---|
| `backend/internal/progression` | XP, levels, milestones, missions/events, claims, inventory, loadout, purchases, finished-match recording. Implements `playerinfo.Provider`, `gameevents.Recorder`, `gameevents.Inventory`. |
| `backend/internal/social` | Friends + requests, recent opponents, friends leaderboard, private-room invites. Implements `gameevents.Inviter`. |
| `backend/internal/reports` | Player reports (`POST/GET /reports`) and the operator review API (`/admin/reports`). |
| `backend/internal/analytics` | Pseudonymous active-user sketches, `POST /telemetry/events`. |
| `backend/config/catalog.json`, `backend/config/missions.json` | Cosmetics catalog and missions/events configuration (validated at startup). |
| `backend/migrations/003_progression.sql`, `006_player_reports.sql`, `009_report_bots.sql` | The `progression` schema. |
| `backend/migrations/005_display_name.sql`, `backend/internal/profile` | The nullable `player_progress.display_name` column: player-chosen display names (`PATCH /me`), written and read by the `profile` package. |

Every item is cosmetic. Nothing here changes dice, rules, matchmaking or
payouts, and there are no random rewards.

---

## 1. Storage — PostgreSQL schema `progression`

Same database as `wallet` and `identity`. Every `user_id` references
`wallet.wallets(user_id)` (the account) with `ON DELETE CASCADE`, so erasing
an account erases its progression data. Account deletion
(`backend/internal/account`) also deletes every table's rows explicitly in
one transaction, locking the `player_progress` row before the wallet like
every progression write; a write that was waiting for that lock then finds no
account (`ErrUnknownUser` → 404, or skipped by match recording). **No match history, no currency
ledger, no profile table** — the only profile data is the optional
player-chosen display name (one nullable column, below).

| Table | Primary key | Why it exists |
|---|---|---|
| `player_progress(user_id, public_id, xp, level, updated_at, display_name)` | `user_id` | XP (`CHECK xp >= 0`) and the level already reached, so milestone items are granted exactly when a level is first reached. `public_id` (UNIQUE) is the durable public-id → account mapping that resolves friend codes when the Redis profile cache is cold. `display_name` (nullable `TEXT`, `CHECK octet_length BETWEEN 1 AND 64`, migration 005) is the name the player chose with `PATCH /me`; NULL = never chose one (provider or generated name). It is authoritative: sign-ins never overwrite it and the Redis `profile:{userId}` cache is rebuilt from it. Created lazily on first access or by `Bootstrap`. |
| `mission_progress(user_id, period_key, mission_id, value, updated_at)` | `(user_id, period_key, mission_id)` | Counters for the running periods. Capped at the mission target. |
| `mission_claims(user_id, period_key, mission_id, claimed_at)` | `(user_id, period_key, mission_id)` | The PK makes each reward claim exactly-once. |
| `match_receipts(user_id, match_id, processed_at)` | `(user_id, match_id)` | Idempotency receipts only (no results). Makes a finished match count exactly once per player. |
| `inventory(user_id, item_id, acquired_at)` | `(user_id, item_id)` | Owned cosmetics and owned profile pictures (`item_id` = `pp_…`, forever). Starter items are implicit (no rows). The PK makes grants and purchases exactly-once. |
| `loadout(user_id, slot, item_id)` | `(user_id, slot)` | Equipped items. A missing slot means the starter item; a row whose item no longer fits the catalog also falls back to starter. Slot `avatar` (migration 007) holds the equipped profile picture; it is reported as `picture`, never in `loadout`. |
| `profile_pictures(id, name, format, path, price_diamonds, sort_order, active, created_at)` | `id` (`pp_…`), `path` UNIQUE | Owner-approved (2026-10-21). The Store catalogue only (no player data): object path in the private R2 bucket, `image\|lottie`, diamond price, shelf order, `active = false` retires a picture. Seeded by migration 008 from `backend/config/profile_pictures.tsv`; see [cosmetics-catalog.md](cosmetics-catalog.md#profile-pictures). |
| `friendships(user_lo, user_hi, status, requested_by, created_at)` | `(user_lo, user_hi)`, `CHECK user_lo < user_hi` | One row per unordered pair: `pending` (request by `requested_by`) or `accepted`. Indexed on `user_hi` for "my relationships" lookups. Written only by `social`; read by `progression` inside the match transaction (friend XP bonus, friend missions). |
| `player_reports(id, reporter_id, reported_id, reason, room_id, game, status, note, created_at, updated_at, reported_bot, reported_profile)` | `id` (UUID), `CHECK reporter_id <> reported_id` | User-approved. One row per report: who reported whom, why (`cheating\|offensive_name\|abusive_behavior\|leaving_or_stalling\|other`), the review `status` (`submitted\|reviewing\|action_taken\|dismissed`) and an operator `note` (never shown to the reporter). `reporter_id` is an account; `reported_id` is an account or, with `reported_bot = true`, a bot persona's id (stable across that bot's sessions, so the once-per-player rule applies as to a person; no foreign key since migration 009: bots are not accounts). `reported_profile` (JSONB, bots only) keeps the bot's public profile at report time (`uid`, `name`, `avatar`, `picture`, `level`), the only name stored here, because no account holds it. `room_id` and `game` are plain references to where it happened — **no room or game state** (board, dice, turns, moves, chat, seats) is stored. Indexes `(reporter_id, created_at DESC)`, `(status, created_at)`, `(reported_id)`. Written only by `reports` (see §7.1). |

Indexes on `match_receipts.processed_at`, `mission_progress.updated_at` and
`mission_claims.claimed_at` serve the purge job.

`backend/tests/schema_guard_test.go` fails when a migration adds a table
outside the approved list or a column that looks like gameplay state
(board, token, position, dice, turn, move, seat, snapshot, state, legal,
phase, room, game, …; only `player_reports.room_id` / `.game` and
`player_progress.display_name` are allowed exceptions).

The migration is idempotent (`CREATE ... IF NOT EXISTS`) and is applied on
every start with the other migrations.

### Concurrency model

Every write transaction for an account first runs
`INSERT ... ON CONFLICT DO NOTHING` + `SELECT ... FOR UPDATE` on its
`player_progress` row (`lockProgress`). Writes for one account are therefore
serialized: level-up detection is consistent, and lock order is always
"progress row first", so claims, purchases and match records for the same
account cannot deadlock. Friend-graph changes lock both accounts' rows in id
order; every change that creates an accepted friendship (request with
auto-accept, accept) counts both sides' friends under those locks, so the
friend cap cannot be exceeded by concurrent accepts. Player reports take a
per-reporter transaction advisory lock (`pg_advisory_xact_lock`) instead of
a row lock. (The insert has no conflict target on purpose: with
`ON CONFLICT (user_id)` two concurrent first inserts fail on the `public_id`
unique index.)

## 2. Exactly-once guarantees

| Operation | Single transaction | What makes it exactly-once |
|---|---|---|
| Match award (per player) | receipt insert + XP + mission counters + milestone/first-win items | `match_receipts` PK: `ON CONFLICT DO NOTHING`; if no row was inserted, nothing else runs. Concurrent duplicates block on the PK and then skip. |
| Mission claim | claim insert + progress check + `wallet.AdjustTx` credit + XP + items | `mission_claims` PK. A failed check (`not_completed`) rolls the claim row back. |
| Purchase | inventory insert + `wallet.AdjustTx` debit | `inventory` PK (`already_owned` → rollback). An insufficient balance (`wallet.ErrInsufficientFunds`; balances never go negative) rolls the inventory row back. |
| Level milestones | inside the XP update | `inventory` PK; every milestone up to the new level is (re)offered, so a newly added milestone is caught up on the next level-up. |

The wallet change always commits atomically with the row that proves it
happened. `Idempotency-Key` (claims, purchases) is a response cache on top:
the successful JSON is stored in Redis for 24 h (`idem:{userId}:{key}`) and
replayed verbatim; concurrent requests with the same key wait for the first.
If Redis is unavailable the request still executes once (the database
constraints above are the real guarantee).

## 3. XP, levels and anti-farming

- `nextLevelXp(level) = 100 + 50 × (level − 1)` XP from `level` to
  `level + 1`; `levelXp` = total XP at which the current level started
  (`100(L−1) + 25(L−1)(L−2)`); max level 50 (reached at 63,700 XP). XP keeps
  accumulating after level 50 (weekly leaderboard), the level does not.
- XP per **eligible** finished match: completed 20, win +15, +5 if another
  human participant is an accepted friend. Mission rewards add their `xp`.
- **Eligibility (anti-farming)** — a human participant earns completion XP
  and mission progress only if: not forfeited (left or timed out), at least 3
  own actions (rolls/moves the player made, `Participant.Actions`), and the
  match lasted at least 30 s (`FinishedAt − StartedAt`). Bots never earn
  anything; bot-only games produce nothing. A "human" participant whose id has
  no account is skipped (logged).
- Practice games against bots count like any completed match for the human
  (entry fee 0, no payout — see the WebSocket protocol), within the rules
  above. XP is server-side only; clients never report XP.
- `badge_first_win` is granted on the first eligible win.

## 4. Match recording (`RecordMatch`)

The room engine emits one `gameevents.MatchRecord` per finished round
(`MatchID = "{roomId}:{round}"`). For each eligible human, one transaction:
lock progress row → insert receipt (duplicate → stop) → friend check → mission
counters for every active period (`daily`, `weekly`, running `events`) whose
filter matches (`game`, `variant`, `mode`, `withFriend`, metric
`complete`/`win`) → XP + level + milestone items → first-win badge → commit.
After commit (best effort): `progression.updated`
`{xp, level, xpGained, levelUp?, unlocked, missions:[changed missions]}` via
the Notifier, weekly leaderboard `ZINCRBY`, metrics. Finally the registered
observers run (social stores recent opponents for every human, including
forfeited ones — they did meet — and, in public matches, the bots, exactly
like people).

Period assignment uses the match's `FinishedAt` (UTC). A failing player is
logged and the first error is returned; re-delivering the same record is
always safe.

## 5. Missions and events

`backend/config/missions.json`:

- `daily`: a pool; `dailyCount` (3) missions are selected per UTC day by
  sorting the pool by `sha256(dayKey + "|" + missionId)` — deterministic, the
  same for every player, displayed in pool order.
- `weekly`: the weekly challenge(s) — `weekly_ten_matches` (complete 10
  matches in any game; 2,000 coins + 5 diamonds + 150 XP + `title_weekly_champion`
  + `badge_friendly`).
- `events`: optional, each with `startsAtUtc` / `endsAtUtc` (max 56 days) and
  its own missions; only active inside `[start, end)`. Shipped:
  `autumn_cup` (2026-10-19 → 2026-11-02 UTC, 3 Quick Ludo matches →
  `dice_autumn`).

Mission fields: `id`, `title`, `description`, `metric` (`complete` | `win`),
`filter` (`game`, `variant`, `mode`, `withFriend`), `target`, `reward`
(`coins`, `diamonds`, `xp`, `items`). Reward items must be catalog items whose
acquisition names that mission (or that event).

| Period | Key | Resets |
|---|---|---|
| daily | `dYYYY-MM-DD` (e.g. `d2026-10-21`) | 00:00 UTC |
| weekly | `wYYYY-Www` ISO week (e.g. `w2026-W43`) | Monday 00:00 UTC |
| event | `e-{eventId}` (e.g. `e-autumn_cup`) | `endsAtUtc` |

Only missions of a **current** period can be claimed (`404 not_found`
otherwise); an unclaimed reward of a past period is forfeited. Missing a
period never touches XP, level or collection — there are no streaks or
penalties.

Changing the config: edit the JSON and restart. Startup fails on any
validation error (unknown items, wrong acquisition, bad targets/filters,
overlapping ids, invalid windows). Changing the daily pool mid-day can change
that day's selection (progress for missions that left the set is simply not
shown). **Never reuse an event id** for a different run: claims are keyed by
`e-{eventId}` and are purged 60 days after the claim.

## 6. Collection Room

`backend/config/catalog.json` mirrors `cosmetics-catalog.md` (37 items;
validated: unique ids, kinds, rarities, one starter per slot equal to
`playerinfo.StarterLoadout`, level 2..50, exactly one positive price
currency for `purchase` items). Level milestones are derived from the
`level` items.

- Owned = starter, or an `inventory` row. Level items are granted on level-up,
  mission/event items by claiming, `purchase` items by buying (fixed price).
- `PUT /collection/loadout` equips an owned item into the slot matching its
  kind; `itemId` null/empty (or the starter id) resets the slot (row deleted).
  Emotes and badges are owned, not equipped; emote ownership is checked by the
  room engine through `gameevents.Inventory.Owns`.

## 7. Social

- Friend code = public uid (`u_…`, case-insensitive). Resolution: the
  durable `player_progress.public_id`, falling back to the Redis profile cache
  (`profile.Resolve`), verified against `profile.PublicID` and then persisted.
- Requests to bots (bots must look like people in the app): a code that is
  no account but a bot seat the caller can see (`rooms.FindBotSeat`: in the
  caller's active room, else while the bot's session lives) gets the answer
  of a request to a person who never replies — the same checks and limits
  (friend cap, pending-sent cap counted over people and bots, hourly limit),
  `201` `status: "outgoing"` with the bot's profile, listed under `outgoing`
  and cancellable with `DELETE /friends/{uid}`. It is never accepted, sends
  no notification and lapses after 72 h (`social.DefaultBotRequestTTL`).
  Stored in Redis only (`botfr:{userId}`), never in `friendships`.
- Requests auto-accept when the other player already requested you;
  repeating a pending request is idempotent; you cannot friend yourself.
- Limits: `FRIENDS_MAX` accepted friends (default **20**, ≥ 1), 100 pending
  sent, 100 pending received; 60 friend requests per hour per account (plus
  the 30/min social write limit). A new friendship — sending a request,
  auto-accepting or accepting — fails with `friend_limit` when **either**
  side already has `FRIENDS_MAX` friends (checked under both accounts' row
  locks). Pending requests are capped separately and may outnumber free
  friend slots; the cap is enforced when one is accepted. Accounts that
  already have more friends (e.g. after `FRIENDS_MAX` was lowered) keep them
  but cannot add more until they are below the cap.
- `GET /friends` also returns `friendCount` (accepted friends), `maxFriends`
  (`FRIENDS_MAX`) and `onlineCount` (accepted friends online now); friends are
  sorted online first, then by name.
- Responses contain only public uid, display name, avatar, level, title,
  status and — **for accepted friends only** — `online` (Redis
  `presence:{userId}` set by the WebSocket gateway). Account ids, emails and
  provider ids of other players never leave the server.
- Recent opponents: last 20 within 14 days — people, and the bots met in
  public matches shown like people from their public card (`botprof:{uid}`,
  written by the room engine; practice and private-room computer players are
  not recorded). A bot whose card expired is dropped like a deleted account.
- Friends leaderboard: me + accepted friends ranked by XP gained this ISO
  week (match XP and mission XP), competition ranking (ties share a rank).
- Invites (`gameevents.Inviter.SendInvite`, used by the WebSocket
  `room.invite` command): accepted friends only (`gameevents.ErrNotFriends`,
  also for unknown uids), 10 per minute per sender
  (`social.ErrInviteRateLimited`), pushed as `social.invite`. Re-inviting the
  same friend to the same room re-delivers the same `inviteId`.
- New requests push `social.friend_request {fromUid, fromName}` to the
  recipient.

### 7.1 Player reports (`backend/internal/reports`)

- A human reports another human from the in-game player pod:
  `POST /reports {"uid","roomId","reason"}`. The room is read from Redis
  (`rooms.LoadRoom`, read-only): **both** players must hold a seat in it
  (forfeited and left seats count), so reports work during the game and
  while the finished room exists (finished: `FINISHED_ROOM_TTL` + rematch
  window ≈ 10.5 min; closed: 2 min); afterwards `room_not_found`.
- A bot seat is reported exactly like a person (same checks, limits and
  response; listed in "my reports" with the profile stored in
  `reported_profile`), so reports never reveal bots. The row has
  `reported_bot = true` and is left out of the operator queue
  (`GET /admin/reports`; `PATCH` answers 404). `cannot_report_bot` is no
  longer returned. Yourself → `cannot_report_self`; a uid that is not
  seated → `not_in_room` (or `not_found` when it is no account at all).
- Per reporter, rolling 24 h window: at most one report per reported player
  (`already_reported`, checked first) and at most `REPORTS_PER_DAY` reports
  (default **2**, ≥ 1; `report_limit` with `Retry-After` and
  `details.resetsAt`). Window read, both checks and the insert run in one
  transaction holding `pg_advisory_xact_lock(<reports namespace>,
  hash(reporter))`, so concurrent bursts cannot exceed the limit on any
  number of instances. Rejected attempts store nothing and do not count.
- `GET /reports` lists my reports (newest first, ≤ 100) with the reported
  player's public profile (uid, name, avatar, picture, level; a bot's as stored with
  the report) and review status, plus
  `limit {perDay, remaining, resetsAt}`. Reporter ids and operator notes are
  never returned to players; the reported player is never told.
- Operators review through `GET /admin/reports` and
  `PATCH /admin/reports/{id}` (header `X-Admin-Key`, compared in constant
  time against `ADMIN_API_KEY_SHA256`; unset → the routes answer 404; not
  version gated; 60/min per IP). Expose them **only on the private
  network**. Status changes are logged (`player report reviewed`, report id
  and status only).

## 8. Redis (ephemeral only)

| Key | Type | TTL | Content |
|---|---|---|---|
| `lb:xp:{weekKey}` | ZSET | 21 days | weekly XP per account id (friends leaderboard) |
| `recent:{userId}` | ZSET | 14 days | recent opponents (account id, or `bot:{uid}` for a bot met in a public match → finish time ms), max 20 |
| `botfr:{userId}` | hash | 72 h after the last request (each entry lapses 72 h after it was sent; lapsed entries are removed when read) | pending friend requests to bots: bot uid → `{name, avatar, picture, level, title, at}` |
| `invite:{from}:{to}:{roomId}` | string | until the invite expires (10 s – 30 min) | invite id (dedupe) |
| `idem:{userId}:{key}` / `…:lock` | string | 24 h / 30 s | cached successful claim/purchase response |
| `au:d:{yyyymmdd}`, `au:w:{yyyy-Www}` | HyperLogLog | 40 days | pseudonymous active-user sketches |
| `seat:{userId}` (+ `…:lease`, 5 s) | string | 1 h | seat summary cache (level, non-starter loadout, equipped profile-picture id) for room joins; deleted after level-ups, equips and profile-picture applies ([architecture.md → PostgreSQL on the hot path](architecture.md#postgresql-on-the-hot-path)) |
| `emotes:{userId}` | set | 1 h | owned non-starter emotes (catalogue and Store `em_…` emotes) for `chat.emote`; grants add to it, misses are confirmed in PostgreSQL |
| `rl:invite_user:…`, `rl:friend_request_user:…`, `rl:report_user:…`, `rl:report_read_user:…`, `rl:admin_ip:…` | counter | window | rate limits |
| read only: `presence:{userId}`, `profile:{userId}`, `pubid:{uid}`, `room:{roomId}`, `user:{userId}:room`, `botsess:{uid}`, `botprof:{uid}` | | | set by the gateway / profile service / room engine (reports verify seats; friend requests and recent players find bots) |

Account deletion purges the account's `seat:`, `emotes:`, `recent:`, `botfr:` keys,
its member in other players' `recent:` sets and in the weekly `lb:xp:` sets,
and its rate-limit counters. A match recorded after the deletion never
re-adds the deleted account to anyone's recent players (`recent` ignores ids
without an account), and `GET /social/recent` drops such ids.

**If Redis is lost:** recent opponents and the current weekly leaderboard
reset, pending invites and friend requests to bots disappear (the sender can
re-invite), idempotency
replays are unavailable for the past 24 h (a retried claim/purchase gets the
normal `409 already_claimed` / `already_owned` instead of a replay), and the
day/week active-user estimates restart, and the seat/emote caches refill from
PostgreSQL on the next join or emote. Nothing durable is lost: XP, levels,
missions, claims, inventory, loadouts, friendships, chosen display names and
wallets live in PostgreSQL, and friend codes resolve from
`player_progress.public_id`. (The rolling name-change counter
`namechg:{userId}` resets, see `backend/docs/redis-keys.md`.)

## 9. Analytics (privacy-conscious)

- `analytics.Tracker.Touch(ctx, userID)` adds
  `HMAC-SHA256(ACTIVE_USER_KEY, accountId)` to the day and ISO-week
  HyperLogLogs. Sketches cannot be enumerated and contain no raw ids. **Call
  it for humans only** (sign-in, token refresh, WebSocket connect) — never for
  bot sessions; the tracker cannot tell them apart.
- `Run` refreshes every minute: `active_users_estimate{window="day"|"week"}`
  and `returning_users_estimate{window="day"}` = users active yesterday and
  today, estimated as `|Y| + |T| − |Y ∪ T|` (PFCOUNT inclusion–exclusion).
  This is **approximate** (HLL error ≈ 0.81 % of the union, so coarse for
  small numbers); it is clamped to `[0, min(|Y|, |T|)]`.
- `POST /telemetry/events` only increments `client_errors_total{kind}` and
  `client_reconnect_total{result}` for whitelisted kinds; nothing else is
  stored.

## 10. Retention

`progression.Service.Run` (hourly, first run 1 min after start; safe on
several instances):

| Data | Kept |
|---|---|
| `match_receipts` | 14 days after processing (a match is never re-delivered that late) |
| `mission_progress` | 60 days after the last update, never for a running period |
| `mission_claims` | 60 days after the claim, never for a running period |
| `player_progress`, `inventory`, `loadout`, `friendships`, `player_reports` | for the life of the account (reports are removed with either account) |
| everything above, for one account | until the player deletes the account (Settings → Delete account, `DELETE /api/v1/account`): one transaction deletes all of its rows in every table here — friendships on both sides, reports it filed **and** reports filed against it — together with its wallet and identities; its Redis keys (seat/emote caches, recent players on both sides, weekly leaderboard entries, rate-limit counters) are purged right after. See [authentication.md → Deleting an account](authentication.md#deleting-an-account) |
| `profile_pictures` | catalogue rows; retired with `active = false`, never deleted |

Deletes run in batches of 5,000 rows.

## 11. Backup and restore

Back up the schemas `wallet`, `identity` and `progression` **together**
(PostgreSQL PITR / continuous WAL archiving, or `pg_dump -n wallet -n identity
-n progression` from one snapshot) and restore them together. A consistent
snapshot keeps claims, receipts and inventory rows in step with the wallet
balances they changed; restoring one schema alone could re-enable an already
paid claim or lose a purchased item. After a restore, Redis needs no repair:
its keys are rebuilt as players play (see §8).

## 12. Metrics

`missions_completed_total{period}`, `mission_rewards_claimed_total{period}`
(`daily|weekly|event`), `xp_awarded_total{source}` (`match|mission`),
`level_ups_total`, `cosmetic_unlocks_total{source}`
(`level|mission|event|purchase|first_win`), `cosmetic_equips_total{slot}`,
`cosmetic_purchases_total{currency}`, `friend_requests_total{event}`
(`sent|sent_to_bot|accepted|auto_accepted|declined|cancelled|removed|rejected`),
`invites_sent_total{result}` (`sent|not_friends|rate_limited|error`),
`player_reports_total{reason,result}` (reason: the five reasons or
`invalid`; result: `created|already_reported|report_limit|cannot_report_self|not_in_room|not_found|room_not_found|bad_request|error`),
`returning_users_estimate{window}`; plus the existing
`active_users_estimate`, `client_errors_total`, `client_reconnect_total`.
All count humans only; labels are bounded.

## 13. Wiring (cmd/server)

```go
prog, err := progression.New(pool, rdb, profiles, notifier, log, progression.Options{
    CatalogPath: "config/catalog.json", MissionsPath: "config/missions.json"})
soc := social.New(pool, rdb, profiles, prog, notifier, log,
    social.Options{MaxFriends: cfg.Social.FriendsMax, Bots: botLookup /* rooms.FindBotSeat */}) // subscribes to prog
rep := reports.New(pool, profiles, prog, roomLookup /* rooms.LoadRoom */, log, reports.Options{
    PerDay: cfg.Social.ReportsPerDay, AdminKeySHA256: cfg.AdminKeySHA256})
tracker := analytics.New(rdb, cfg.Telemetry.ActiveUserKey, log)

prog.Register(router); soc.Register(router); rep.Register(router); tracker.Register(router)
go prog.Run(ctx); go tracker.Run(ctx)

authSvc.OnNewAccount = func(ctx context.Context, id uuid.UUID) { _ = prog.Bootstrap(ctx, id); _ = tracker.Touch(ctx, id) }
// httpapi.Account{Progression: prog}; room engine: Recorder = prog,
// Inviter = soc, Inventory = prog, playerinfo.Provider = prog.
```
