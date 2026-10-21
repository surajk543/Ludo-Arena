-- In-app purchases of coin packs (owner-approved table, 2026-10-22; see
-- docs/in-app-purchases.md). One row per store transaction that granted
-- coins and diamonds. Idempotent: applied on every start.
--
--   * UNIQUE (store, transaction_id) makes a grant exactly-once: the row is
--     inserted in the same transaction as the wallet credit, so a replayed or
--     concurrent submission of the same purchase can never credit twice.
--   * transaction_id is the App Store transactionId, or for Google Play the
--     hex SHA-256 of the purchase token (the raw token is never stored);
--     order_id is Google's order number (GPA.…) for support, NULL for Apple.
--   * coins / diamonds are what this purchase granted (from the server's pack
--     configuration at grant time); a refund takes them back (never below 0)
--     and sets status 'refunded'.
--   * No payment details exist here: stores never send them.
--
-- user_id is an account (wallet.wallets) and is removed with it (ON DELETE
-- CASCADE; account deletion also deletes the rows explicitly).
CREATE SCHEMA IF NOT EXISTS progression;

CREATE TABLE IF NOT EXISTS progression.purchases (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID        NOT NULL REFERENCES wallet.wallets (user_id) ON DELETE CASCADE,
    store          TEXT        NOT NULL CHECK (store IN ('google_play', 'app_store')),
    product_id     TEXT        NOT NULL CHECK (length(product_id) BETWEEN 1 AND 150),
    transaction_id TEXT        NOT NULL CHECK (length(transaction_id) BETWEEN 1 AND 128),
    order_id       TEXT        NULL CHECK (order_id IS NULL OR length(order_id) BETWEEN 1 AND 128),
    coins          BIGINT      NOT NULL CHECK (coins >= 0),
    diamonds       BIGINT      NOT NULL CHECK (diamonds >= 0),
    status         TEXT        NOT NULL DEFAULT 'granted' CHECK (status IN ('granted', 'refunded')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    refunded_at    TIMESTAMPTZ NULL,
    UNIQUE (store, transaction_id),
    CHECK ((status = 'refunded') = (refunded_at IS NOT NULL))
);

-- Per-account listing and the ON DELETE CASCADE from wallets. Created only
-- while missing, so later starts take no table lock.
DO $$
BEGIN
    IF to_regclass('progression.purchases_user_created') IS NULL THEN
        CREATE INDEX purchases_user_created ON progression.purchases (user_id, created_at DESC);
    END IF;
END
$$;
