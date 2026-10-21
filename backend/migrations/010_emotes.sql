-- Store emotes (owner-approved table, 2026-10-21; see
-- docs/cosmetics-catalog.md "Store emotes" and docs/rest-api.md "Store").
-- Idempotent: applied on every start.
--
-- progression.emotes is the catalogue of emotes sold for diamonds in the
-- Shop, shaped like progression.profile_pictures (007): one row per emote
-- with the object's PATH in the private R2 bucket (never a URL; the backend
-- signs paths on request), its format and its fixed diamond price. It holds
-- no player data. Ownership is progression.inventory (item_id = emote id,
-- forever), so account deletion (ON DELETE CASCADE) needs nothing extra.
-- Emotes are owned, not equipped: an owned emote can be sent in any match
-- (chat.emote), exactly like the built-in emotes of config/catalog.json.
--
-- Rows are seeded by 011_emotes_seed.sql (ON CONFLICT DO NOTHING, so an
-- operator's later UPDATE of price, name, order or `active` survives
-- restarts). Retire an emote with active = false (owners keep and can still
-- send it); do not delete rows. Paths are immutable: new art = new path.
CREATE SCHEMA IF NOT EXISTS progression;

CREATE TABLE IF NOT EXISTS progression.emotes (
    id             TEXT        PRIMARY KEY CHECK (id ~ '^em_[a-z0-9_]{1,61}$'),
    name           TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 64),
    format         TEXT        NOT NULL CHECK (format IN ('lottie', 'image')),
    path           TEXT        NOT NULL UNIQUE CHECK (path LIKE 'emotes/%' AND char_length(path) <= 255),
    price_diamonds INT         NOT NULL CHECK (price_diamonds > 0),
    sort_order     INT         NOT NULL DEFAULT 0,
    active         BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Shelf order (the Store lists by sort_order, id). Created only while
-- missing, so later starts take no table lock.
DO $$
BEGIN
    IF to_regclass('progression.emotes_shelf') IS NULL THEN
        CREATE INDEX emotes_shelf ON progression.emotes (sort_order, id);
    END IF;
END
$$;
