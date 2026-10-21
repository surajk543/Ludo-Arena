-- Player-chosen display names (PATCH /api/v1/me; see docs/rest-api.md and
-- docs/progression.md). A nullable column on the existing per-account
-- progression row, not a new table (approved). NULL means the player never
-- chose a name: the name then comes from the sign-in provider or is generated
-- ("Player XXXX"), as before. A chosen name is authoritative here; Redis
-- profile:{userId} only caches it, and sign-ins never overwrite it.
--
-- The server validates names (3–16 characters after NFC normalization, see
-- backend/internal/profile/names.go); the CHECK is only a coarse storage
-- bound (16 code points are at most 64 bytes of UTF-8).
--
-- Idempotent: applied on every start. The column is only added while it is
-- missing, so later starts take no table lock.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'progression.player_progress'::regclass
          AND attname = 'display_name'
          AND NOT attisdropped
    ) THEN
        ALTER TABLE progression.player_progress
            ADD COLUMN display_name TEXT
            CONSTRAINT player_progress_display_name_check
            CHECK (octet_length(display_name) BETWEEN 1 AND 64);
    END IF;
END
$$;
