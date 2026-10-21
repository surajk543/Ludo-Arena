-- Reports against bot seats (docs/progression.md "Player reports"). A player
-- reports any opponent from the in-game pod, and a bot must be indistinguishable
-- from a person there, so its report is stored like any other. Bots are not
-- accounts (no wallet.wallets row; their ids are per-session UUIDs from
-- BotAuth.IssueBot), so:
--
--   * the foreign key reported_id → wallet.wallets is dropped (reporter_id
--     keeps its key). Nothing relied on its ON DELETE CASCADE: account
--     deletion (backend/internal/account) deletes the reports filed by and
--     against the account explicitly, in its transaction;
--   * reported_bot marks rows whose reported_id is a bot. The operator queue
--     (GET /admin/reports) leaves them out;
--   * reported_profile keeps the bot's public profile at report time
--     ({"uid","name","avatar","level"}) because there is no account to read
--     it from later; NULL for accounts (their live profile is shown).
--
-- Idempotent: applied on every start. Every change runs only while it is
-- still needed, so later starts take no table lock.
DO $$
DECLARE
    fk TEXT;
BEGIN
    FOR fk IN
        SELECT c.conname
          FROM pg_constraint c
          JOIN pg_attribute a
            ON a.attrelid = c.conrelid AND a.attname = 'reported_id' AND NOT a.attisdropped
         WHERE c.conrelid = 'progression.player_reports'::regclass
           AND c.contype = 'f'
           AND c.conkey = ARRAY[a.attnum]
    LOOP
        EXECUTE format('ALTER TABLE progression.player_reports DROP CONSTRAINT %I', fk);
    END LOOP;

    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'progression.player_reports'::regclass
          AND attname = 'reported_bot'
          AND NOT attisdropped
    ) THEN
        ALTER TABLE progression.player_reports
            ADD COLUMN reported_bot BOOLEAN NOT NULL DEFAULT FALSE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'progression.player_reports'::regclass
          AND attname = 'reported_profile'
          AND NOT attisdropped
    ) THEN
        ALTER TABLE progression.player_reports
            ADD COLUMN reported_profile JSONB NULL
            CONSTRAINT player_reports_reported_profile_check
            CHECK (reported_profile IS NULL
                   OR (jsonb_typeof(reported_profile) = 'object'
                       AND pg_column_size(reported_profile) <= 1024));
    END IF;
END
$$;
