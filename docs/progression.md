# Progression, Missions, Collection Room, Social & Analytics

Backend design for XP/levels, missions and events, reward claims, cosmetics
(Collection Room), friends, invites, leaderboards and privacy-conscious
analytics. HTTP contract: [`rest-api.md`](rest-api.md); push messages:
[`websocket-protocol.md`](websocket-protocol.md); item ids:
[`cosmetics-catalog.md`](cosmetics-catalog.md).

| Package | Owns |
|---|---|
| `backend/internal/progression` | XP, levels, milestones, missions/events, claims, inventory, loadout, purchases, finished-match recording. Implements `playerinfo.Provider`, `gameevents.Recorder`, `gameevents.Inventory`. |
| `backend/internal/social` | Friends + requests, recent opponents, friends leaderboard, private-room invites. Implements `gameevents.Inviter`. |
| `backend/internal/analytics` | Pseudonymous active-user sketches, `POST /telemetry/events`. |
| `backend/config/catalog.json`, `backend/config/missions.json` | Cosmetics catalog and missions/events configuration (validated at startup). |
| `backend/migrations/003_progression.sql` | The `progression` schema. |

Every item is cosmetic. Nothing here changes dice, rules, matchmaking or
payouts, and there are no random rewards.

---

## 1. Storage — PostgreSQL schema `progression`

Same database as `wallet` and `identity`. Every `user_id` references
`wallet.wallets(user_id)` (the account) with `ON DELETE CASCADE`, so erasing
an account erases its progression data. **No match history, no currency
ledger, no profile or display-name columns.**

| Table | Primary key | Why it exists |
|---|---|---|
| `player_progress(user_id, public_id, xp, level, updated_at)` | `user_id` | XP (`CHECK xp >= 0`) and the level already reached, so milestone items are granted exactly when a level is first reached. `public_id` (UNIQUE) is the durable public-id → account mapping that resolves friend codes when the Redis profile cache is cold. Created lazily on first access or by `Bootstrap`. |
| `mission_progress(user_id, period_key, mission_id, value, updated_at)` | `(user_id, period_key, mission_id)` | Counters for the running periods. Capped at the mission target. |
| `mission_claims(user_id, period_key, mission_id, claimed_at)` | `(user_id, period_key, mission_id)` | The PK makes each reward claim exactly-once. |
| `match_receipts(user_id, match_id, processed_at)` | `(user_id, match_id)` | Idempotency receipts only (no results). Makes a finished match count exactly once per player. |
| `inventory(user_id, item_id, acquired_at)` | `(user_id, item_id)` | Owned cosmetics. Starter items are implicit (no rows). The PK makes grants and purchases exactly-once. |
| `loadout(user_id, slot, item_id)` | `(user_id, slot)` | Equipped items. A missing slot means the starter item; a row whose item no longer fits the catalog also falls back to starter. |
| `friendships(user_lo, user_hi, status, requested_by, created_at)` | `(user_lo, user_hi)`, `CHECK user_lo < user_hi` | One row per unordered pair: `pending` (request by `requested_by`) or `accepted`. Indexed on `user_hi` for "my relationships" lookups. Written only by `social`; read by `progression` inside the match transaction (friend XP bonus, friend missions). |

Indexes on `match_receipts.processed_at`, `mission_progress.updated_at` and
`mission_claims.claimed_at` serve the purge job.

The migration is idempotent (`CREATE ... IF NOT EXISTS`) and is applied on
every start with the other migrations.

### Concurrency model

Every write transaction for an account first runs
`INSERT ... ON CONFLICT DO NOTHING` + `SELECT ... FOR UPDATE` on its
`player_progress` row (`lockProgress`). Writes for one account are therefore
serialized: level-up detection is consistent, and lock order is always
"progress row first", so claims, purchases and match records for the same
account cannot deadlock. Friend-graph changes lock both accounts' rows in id
order. (The insert has no conflict target on purpose: with
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
forfeited ones — they did meet).

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
- Requests auto-accept when the other player already requested you;
  repeating a pending request is idempotent; you cannot friend yourself.
- Limits: 200 accepted friends, 100 pending sent, 100 pending received;
  60 friend requests per hour per account (plus the 30/min social write limit).
- Responses contain only public uid, display name, avatar, level, title,
  status and — **for accepted friends only** — `online` (Redis
  `presence:{userId}` set by the WebSocket gateway). Account ids, emails and
  provider ids of other players never leave the server.
- Recent opponents: humans only, last 20 within 14 days.
- Friends leaderboard: me + accepted friends ranked by XP gained this ISO
  week (match XP and mission XP), competition ranking (ties share a rank).
- Invites (`gameevents.Inviter.SendInvite`, used by the WebSocket
  `room.invite` command): accepted friends only (`gameevents.ErrNotFriends`,
  also for unknown uids), 10 per minute per sender
  (`social.ErrInviteRateLimited`), pushed as `social.invite`. Re-inviting the
  same friend to the same room re-delivers the same `inviteId`.
- New requests push `social.friend_request {fromUid, fromName}` to the
  recipient.

## 8. Redis (ephemeral only)

| Key | Type | TTL | Content |
|---|---|---|---|
| `lb:xp:{weekKey}` | ZSET | 21 days | weekly XP per account id (friends leaderboard) |
| `recent:{userId}` | ZSET | 14 days | recent human opponents (account id → finish time ms), max 20 |
| `invite:{from}:{to}:{roomId}` | string | until the invite expires (10 s – 30 min) | invite id (dedupe) |
| `idem:{userId}:{key}` / `…:lock` | string | 24 h / 30 s | cached successful claim/purchase response |
| `au:d:{yyyymmdd}`, `au:w:{yyyy-Www}` | HyperLogLog | 40 days | pseudonymous active-user sketches |
| `rl:invite_user:…`, `rl:friend_request_user:…` | counter | window | rate limits |
| read only: `presence:{userId}`, `profile:{userId}`, `pubid:{uid}` | | | set by the gateway / profile service |

**If Redis is lost:** recent opponents and the current weekly leaderboard
reset, pending invites disappear (the sender can re-invite), idempotency
replays are unavailable for the past 24 h (a retried claim/purchase gets the
normal `409 already_claimed` / `already_owned` instead of a replay), and the
day/week active-user estimates restart. Nothing durable is lost: XP, levels,
missions, claims, inventory, loadouts, friendships and wallets live in
PostgreSQL, and friend codes resolve from `player_progress.public_id`.

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
| `player_progress`, `inventory`, `loadout`, `friendships` | for the life of the account |

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
(`sent|accepted|auto_accepted|declined|cancelled|removed|rejected`),
`invites_sent_total{result}` (`sent|not_friends|rate_limited|error`),
`returning_users_estimate{window}`; plus the existing
`active_users_estimate`, `client_errors_total`, `client_reconnect_total`.
All count humans only; labels are bounded.

## 13. Wiring (cmd/server)

```go
prog, err := progression.New(pool, rdb, profiles, notifier, log, progression.Options{
    CatalogPath: "config/catalog.json", MissionsPath: "config/missions.json"})
soc := social.New(pool, rdb, profiles, prog, notifier, log, social.Options{}) // subscribes to prog
tracker := analytics.New(rdb, cfg.Telemetry.ActiveUserKey, log)

prog.Register(router); soc.Register(router); tracker.Register(router)
go prog.Run(ctx); go tracker.Run(ctx)

authSvc.OnNewAccount = func(ctx context.Context, id uuid.UUID) { _ = prog.Bootstrap(ctx, id); _ = tracker.Touch(ctx, id) }
// httpapi.Account{Progression: prog}; room engine: Recorder = prog,
// Inviter = soc, Inventory = prog, playerinfo.Provider = prog.
```
