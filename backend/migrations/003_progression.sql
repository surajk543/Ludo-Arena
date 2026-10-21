-- Progression, missions, Collection Room and friendships (approved design,
-- see docs/progression.md). Idempotent: applied on every start.
--
-- Deliberately minimal: no match history, no currency ledger, no profile or
-- display-name columns. Every user_id is an account (wallet.wallets) and is
-- removed with it (ON DELETE CASCADE) so erasing an account erases its
-- progression data.
CREATE SCHEMA IF NOT EXISTS progression;

-- XP and level per account. public_id is the durable public player id
-- ("u_…", also the friend code) -> account mapping used to resolve friend
-- codes when the Redis profile cache is cold.
CREATE TABLE IF NOT EXISTS progression.player_progress (
    user_id    UUID        PRIMARY KEY REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    public_id  TEXT        NOT NULL UNIQUE CHECK (length(public_id) BETWEEN 3 AND 40),
    xp         BIGINT      NOT NULL DEFAULT 0 CHECK (xp >= 0),
    level      INT         NOT NULL DEFAULT 1 CHECK (level BETWEEN 1 AND 50),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Mission counters for the current periods (d2026-10-21, w2026-W43,
-- e-autumn_cup). Purged 60 days after the last update.
CREATE TABLE IF NOT EXISTS progression.mission_progress (
    user_id    UUID        NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    period_key TEXT        NOT NULL CHECK (length(period_key) BETWEEN 2 AND 64),
    mission_id TEXT        NOT NULL CHECK (length(mission_id) BETWEEN 1 AND 64),
    value      INT         NOT NULL CHECK (value >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, period_key, mission_id)
);
CREATE INDEX IF NOT EXISTS mission_progress_updated_at ON progression.mission_progress (updated_at);

-- One row per claimed reward: the primary key makes a claim exactly-once.
CREATE TABLE IF NOT EXISTS progression.mission_claims (
    user_id    UUID        NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    period_key TEXT        NOT NULL CHECK (length(period_key) BETWEEN 2 AND 64),
    mission_id TEXT        NOT NULL CHECK (length(mission_id) BETWEEN 1 AND 64),
    claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, period_key, mission_id)
);
CREATE INDEX IF NOT EXISTS mission_claims_claimed_at ON progression.mission_claims (claimed_at);

-- Idempotency receipts for finished matches (no results are stored). Inserted
-- in the same transaction as the XP / mission update; purged after 14 days.
CREATE TABLE IF NOT EXISTS progression.match_receipts (
    user_id      UUID        NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    match_id     TEXT        NOT NULL CHECK (length(match_id) BETWEEN 1 AND 128),
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, match_id)
);
CREATE INDEX IF NOT EXISTS match_receipts_processed_at ON progression.match_receipts (processed_at);

-- Owned cosmetics. Starter items are implicit (no rows).
CREATE TABLE IF NOT EXISTS progression.inventory (
    user_id     UUID        NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    item_id     TEXT        NOT NULL CHECK (length(item_id) BETWEEN 1 AND 64),
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, item_id)
);

-- Equipped cosmetics. A missing slot means the starter item.
CREATE TABLE IF NOT EXISTS progression.loadout (
    user_id UUID NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    slot    TEXT NOT NULL CHECK (slot IN ('dice', 'token', 'ludo_board', 'snakes_board', 'frame', 'title', 'victory', 'trail')),
    item_id TEXT NOT NULL CHECK (length(item_id) BETWEEN 1 AND 64),
    PRIMARY KEY (user_id, slot)
);

-- Friendships and pending friend requests, one row per unordered pair.
CREATE TABLE IF NOT EXISTS progression.friendships (
    user_lo      UUID        NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    user_hi      UUID        NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    status       TEXT        NOT NULL CHECK (status IN ('pending', 'accepted')),
    requested_by UUID        NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_lo, user_hi),
    CHECK (user_lo < user_hi),
    CHECK (requested_by = user_lo OR requested_by = user_hi)
);
CREATE INDEX IF NOT EXISTS friendships_user_hi ON progression.friendships (user_hi);
