-- Durable provider identity -> internal account mapping (approved design:
-- separate schema, see docs/authentication.md). A row's user_id always has a
-- wallet, because both rows are created in one transaction.
CREATE SCHEMA IF NOT EXISTS identity;

CREATE TABLE IF NOT EXISTS identity.auth_identities (
    provider   TEXT        NOT NULL CHECK (provider IN ('guest', 'google', 'facebook', 'apple')),
    subject    TEXT        NOT NULL CHECK (length(subject) BETWEEN 1 AND 255),
    user_id    UUID        NOT NULL REFERENCES wallet.wallets (user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, subject)
);

-- One identity per provider per account (a guest links at most one Google, ...).
CREATE UNIQUE INDEX IF NOT EXISTS auth_identities_user_provider
    ON identity.auth_identities (user_id, provider);
