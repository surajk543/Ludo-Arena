-- Bot wallets (owner-approved 2026-10-22; backend/docs/game-rules.md "Coins
-- with bots"). Bots play public and private matches for coins like people, so
-- every bot persona has a wallet row holding its play coins:
--
--   * is_bot = TRUE marks it. A bot wallet is NOT an account: it has no
--     identity, session, progression, inventory or friendship rows, and
--     everything that counts or looks up people (accounts, public ids,
--     friends, recent players, reports queue, account deletion, KPIs) leaves
--     is_bot rows out;
--   * its user_id is the persona's stable id (a UUIDv5 of pool, name and
--     slot; backend/internal/rooms/persona.go), created lazily the first time
--     the persona is seated (INSERT ... ON CONFLICT DO NOTHING) with
--     BOT_COINS_START coins and no diamonds;
--   * the recharge and reset rules (BOT_COINS_*) run in the same PostgreSQL
--     transactions as entry fees and payouts (backend/internal/wallet).
--
-- Idempotent: applied on every start; the column is added only while
-- missing, so later starts take no table lock.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'wallet.wallets'::regclass
          AND attname = 'is_bot'
          AND NOT attisdropped
    ) THEN
        ALTER TABLE wallet.wallets
            ADD COLUMN is_bot BOOLEAN NOT NULL DEFAULT FALSE;
    END IF;
END
$$;
