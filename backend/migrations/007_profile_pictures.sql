-- Profile-picture Store (owner-approved table, 2026-10-21; see
-- docs/cosmetics-catalog.md "Profile pictures" and docs/rest-api.md "Store").
-- Idempotent: applied on every start.
--
-- progression.profile_pictures is the catalogue: one row per picture with
-- the object's PATH in the private R2 bucket (never a URL; the backend signs
-- paths on request), its format and its diamond price. It holds no player
-- data. Ownership is progression.inventory (item_id = picture id, forever)
-- and the equipped picture is progression.loadout slot 'avatar', so account
-- deletion (ON DELETE CASCADE on both) needs nothing extra.
--
-- Rows are seeded by 008_profile_pictures_seed.sql (ON CONFLICT DO NOTHING,
-- so an operator's later UPDATE of price, name, order or `active` survives
-- restarts). Retire a picture with active = false (owners keep and can still
-- apply it); do not delete rows. Paths are immutable: new art = new path.
CREATE SCHEMA IF NOT EXISTS progression;

CREATE TABLE IF NOT EXISTS progression.profile_pictures (
    id             TEXT        PRIMARY KEY CHECK (id ~ '^pp_[a-z0-9_]{1,61}$'),
    name           TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 64),
    format         TEXT        NOT NULL CHECK (format IN ('image', 'lottie')),
    path           TEXT        NOT NULL UNIQUE CHECK (path LIKE 'profile_pictures/%' AND char_length(path) <= 255),
    price_diamonds INT         NOT NULL CHECK (price_diamonds > 0),
    sort_order     INT         NOT NULL DEFAULT 0,
    active         BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Shelf order (the Store lists by sort_order, id). Created only while
-- missing, so later starts take no table lock.
DO $$
BEGIN
    IF to_regclass('progression.profile_pictures_shelf') IS NULL THEN
        CREATE INDEX profile_pictures_shelf ON progression.profile_pictures (sort_order, id);
    END IF;
END
$$;

-- The equipped picture is loadout slot 'avatar': widen the slot CHECK of
-- 003_progression.sql (Postgres named it loadout_slot_check). Replaced only
-- while it does not allow 'avatar' yet; added NOT VALID and validated
-- separately so the brief exclusive lock does not scan the table.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'progression.loadout'::regclass
          AND conname = 'loadout_slot_check'
          AND pg_get_constraintdef(oid) LIKE '%''avatar''%'
    ) THEN
        ALTER TABLE progression.loadout DROP CONSTRAINT IF EXISTS loadout_slot_check;
        ALTER TABLE progression.loadout ADD CONSTRAINT loadout_slot_check
            CHECK (slot IN ('dice', 'token', 'ludo_board', 'snakes_board', 'frame', 'title', 'victory', 'trail', 'avatar'))
            NOT VALID;
        ALTER TABLE progression.loadout VALIDATE CONSTRAINT loadout_slot_check;
    END IF;
END
$$;
