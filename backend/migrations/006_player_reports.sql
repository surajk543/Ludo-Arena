-- Player reports (user-approved table, see docs/progression.md "Player
-- reports"). A human reports another human they shared a room with; the
-- reporter sees the review status of their own reports, operators review
-- them through the admin API. Idempotent: applied on every start.
--
-- Both ids are accounts (wallet.wallets) and are removed with them
-- (ON DELETE CASCADE), like every other progression table. `note` is an
-- operator note and is never shown to the reporter. The per-reporter daily
-- limit and the 24 h duplicate rule are enforced by the backend inside a
-- transaction that holds a per-reporter advisory lock.
CREATE SCHEMA IF NOT EXISTS progression;

CREATE TABLE IF NOT EXISTS progression.player_reports (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID        NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    reported_id UUID        NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    reason      TEXT        NOT NULL CHECK (reason IN ('cheating', 'offensive_name', 'abusive_behavior', 'leaving_or_stalling', 'other')),
    room_id     TEXT        NOT NULL CHECK (length(room_id) BETWEEN 1 AND 64),
    game        TEXT        NOT NULL CHECK (length(game) BETWEEN 1 AND 32),
    status      TEXT        NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted', 'reviewing', 'action_taken', 'dismissed')),
    note        TEXT        NULL CHECK (note IS NULL OR length(note) <= 1000),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (reporter_id <> reported_id)
);

-- Indexes: "my reports" (newest first) and the rolling 24 h window per
-- reporter; the operator queue by status; per-reported-player counts (and the
-- ON DELETE CASCADE from wallets). Created only while missing, so later
-- starts take no table lock (CREATE INDEX IF NOT EXISTS locks the table even
-- when the index exists).
DO $$
BEGIN
    IF to_regclass('progression.player_reports_reporter_created') IS NULL THEN
        CREATE INDEX player_reports_reporter_created
            ON progression.player_reports (reporter_id, created_at DESC);
    END IF;
    IF to_regclass('progression.player_reports_status_created') IS NULL THEN
        CREATE INDEX player_reports_status_created
            ON progression.player_reports (status, created_at);
    END IF;
    IF to_regclass('progression.player_reports_reported') IS NULL THEN
        CREATE INDEX player_reports_reported
            ON progression.player_reports (reported_id);
    END IF;
END
$$;
