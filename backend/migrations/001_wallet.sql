-- Wallet balances. This is the only wallet data PostgreSQL stores:
-- no ledger, history or profile columns.
CREATE SCHEMA IF NOT EXISTS wallet;

CREATE TABLE IF NOT EXISTS wallet.wallets (
    user_id  UUID   PRIMARY KEY,
    coins    BIGINT NOT NULL CHECK (coins >= 0),
    diamonds BIGINT NOT NULL CHECK (diamonds >= 0)
);
