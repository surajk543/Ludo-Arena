-- Device binding for guest restore after an app update or reinstall (see
-- docs/authentication.md "Device binding"). Adds the internal provider
-- 'device' to identity.auth_identities; no new table. Its subject is
-- hex(HMAC-SHA256(key, platform || ':' || deviceId)) with a key derived from
-- PUBLIC_ID_KEY: the raw device id is never stored. The existing keys give
-- one account per device (PRIMARY KEY (provider, subject)) and one device per
-- account (UNIQUE (user_id, provider)).
--
-- Idempotent: applied on every start. The constraint is only replaced while
-- it does not yet allow 'device', so later starts take no table lock.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'identity.auth_identities'::regclass
          AND conname = 'auth_identities_provider_check'
          AND pg_get_constraintdef(oid) LIKE '%''device''%'
    ) THEN
        ALTER TABLE identity.auth_identities
            DROP CONSTRAINT IF EXISTS auth_identities_provider_check;
        ALTER TABLE identity.auth_identities
            ADD CONSTRAINT auth_identities_provider_check
            CHECK (provider IN ('guest', 'google', 'facebook', 'apple', 'device'));
    END IF;
END
$$;
