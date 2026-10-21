# Cosmetics Catalog (v1)

Shared ids used by the backend catalog (`backend/config/catalog.json`), the
Flutter renderers (`frontend/lib/shared/game_visuals/`) and the Collection Room.
**Every item is purely cosmetic** — nothing changes dice, rules, matchmaking or
rewards. There are no random/loot-box items.

Acquisition types: `starter` (every account owns it, no row stored), `level`
(granted automatically when the level is reached), `mission` / `event`
(granted by claiming that objective), `purchase` (fixed price in diamonds
only, bought explicitly in the Shop).

| Slot / kind | id | Name | Rarity | Acquisition |
|---|---|---|---|---|
| dice | `dice_classic` | Classic Ivory | common | starter |
| dice | `dice_neon` | Neon Pulse | rare | level 5 |
| dice | `dice_golden` | Royal Gold | epic | purchase 40 diamonds |
| dice | `dice_autumn` | Autumn Leaf | rare | event `autumn_cup` |
| token | `token_classic` | Classic Pawn | common | starter |
| token | `token_gem` | Gemstone | rare | level 3 |
| token | `token_royal` | Royal Pawn | epic | level 10 |
| token | `token_crown` | Crown Piece | legendary | purchase 100 diamonds |
| ludo_board | `ludo_board_classic` | Classic | common | starter |
| ludo_board | `ludo_board_midnight` | Midnight Marble | rare | level 8 |
| ludo_board | `ludo_board_royal` | Royal Court | epic | purchase 200 diamonds |
| snakes_board | `snakes_board_classic` | Classic Meadow | common | starter |
| snakes_board | `snakes_board_jungle` | Jungle Temple | rare | level 6 |
| snakes_board | `snakes_board_candy` | Candy Land | epic | purchase 200 diamonds |
| trail | `trail_none` | No Trail | common | starter |
| trail | `trail_sparkle` | Sparkle | rare | level 7 |
| trail | `trail_comet` | Comet | epic | purchase 20 diamonds |
| victory | `victory_confetti` | Confetti | common | starter |
| victory | `victory_fireworks` | Fireworks | rare | level 12 |
| victory | `victory_crown` | Golden Crown | epic | purchase 40 diamonds |
| frame | `frame_none` | No Frame | common | starter |
| frame | `frame_bronze` | Bronze Ring | common | level 2 |
| frame | `frame_silver` | Silver Laurel | rare | level 10 |
| frame | `frame_gold` | Gold Laurel | epic | level 20 |
| frame | `frame_royal` | Royal Crest | legendary | purchase 60 diamonds |
| title | `title_rookie` | Rookie | common | starter |
| title | `title_strategist` | Strategist | rare | level 5 |
| title | `title_dice_master` | Dice Master | epic | level 15 |
| title | `title_royal` | Royal Highness | legendary | level 30 |
| title | `title_weekly_champion` | Weekly Champion | epic | mission `weekly_ten_matches` |
| badge | `badge_first_win` | First Victory | common | mission (first win, automatic) |
| badge | `badge_friendly` | Good Company | rare | mission `weekly_ten_matches` |
| emote | `emote_wave` | Wave | common | starter |
| emote | `emote_thumbs` | Thumbs Up | common | starter |
| emote | `emote_laugh` | Laugh | common | level 3 |
| emote | `emote_wow` | Wow | rare | level 6 |
| emote | `emote_crown` | Crown | epic | purchase 10 diamonds |

Equip slots: `dice, token, ludo_board, snakes_board, frame, title, victory,
trail`. Default loadout = the starter item of each slot.

Level milestones (rewards granted once, server-side, when the level is first
reached): 2 → `frame_bronze`; 3 → `token_gem`, `emote_laugh`; 5 →
`dice_neon`, `title_strategist`; 6 → `snakes_board_jungle`, `emote_wow`; 7 →
`trail_sparkle`; 8 → `ludo_board_midnight`; 10 → `frame_silver`,
`token_royal`; 12 → `victory_fireworks`; 15 → `title_dice_master`; 20 →
`frame_gold`; 30 → `title_royal`.

## Collection vs Shop (app)

Both screens read the same server data (`GET /collection`, and the picture
shelf below); the split is presentation only — the backend stays
authoritative for ownership, prices and purchases.

| | **Collection Room** (`/collection`) | **Shop** (`/shop`; `/store` redirects) |
|---|---|---|
| Cosmetics | Everything **owned** (starter, bought, earned) plus what can still be **earned** by playing (`level`, `mission`, `event`), shown locked with how to earn it ("Reach level 10", mission, event). Equip / reset as before. | Only items with `acquisition.type == "purchase"` (fixed price in **diamonds** — the Shop never sells for coins; the catalogue loader refuses a coin price) that the player does **not own yet**, one category per kind that has priced items: dice, tokens, Ludo boards, Snakes boards, trails, victory, frames, emotes (titles and badges are never sold). |
| Profile pictures | **Pictures** tab: the owned pictures (`filter=owned`, paged), Apply / back to the classic avatar. | **Pictures** category: pictures not owned yet (`excludeOwned=true`; All / Animated / Static), bought with diamonds. |
| After a purchase | The item appears here (equip / apply it any time). | The item leaves the Shop; its sheet offers Equip/Apply now and View in Collection. |

An empty Collection tab, and every tab with items for sale, links to that
Shop category (`/shop?category=dice`, `picture`, …). The Shop opens on the
category chosen last in the running app. The lobby's **Shop** button is
pinned at the top of Home.

## Profile pictures

Players buy **profile pictures** in the app's **Shop** (`/shop`, Pictures
category; the API keeps its `/store/…` paths) with **diamonds**. A bought
picture is the player's **forever** (no expiry, no rental) and moves to the
Collection's Pictures tab; the player can apply any picture they own, or go
back to the built-in avatar. Pictures are cosmetic only. API:
[`rest-api.md` → Store](rest-api.md#store-profile-pictures).

**Catalogue** — `progression.profile_pictures` (owner-approved table,
2026-10-21; migration `007_profile_pictures.sql`), seeded from
`backend/config/profile_pictures.tsv` by `008_profile_pictures_seed.sql`
(160 pictures: 145 Lottie animations, 15 PNG images; 5–50 diamonds each).

| Column | Meaning |
|---|---|
| `id` | `pp_[a-z0-9_]{1,61}`, stable public id |
| `name` | display name (1–64) |
| `format` | `lottie` (JSON animation) \| `image` (PNG) |
| `path` | object key in the bucket (`profile_pictures/…`, unique, immutable) — the database stores the **path**, never a URL |
| `price_diamonds` | fixed price (> 0) |
| `sort_order` | shelf order (then `id`) |
| `active` | `false` retires a picture: no longer listed or sold (owners keep it, still see it and can apply it) |

Operators change prices, names, order or `active` with SQL; the seed never
overwrites a row (`ON CONFLICT DO NOTHING`) and every backend instance
reloads the catalogue within a minute. Never delete a row (the seed would
re-create it); retire it. **New art = new path** (and a new row, or an
updated `path` once the new object exists): objects are immutable, which is
what lets phones cache them forever.

**Ownership and equipping** — ownership is a `progression.inventory` row
(`item_id` = picture id), the equipped picture is `progression.loadout` slot
`avatar`. Both are removed with the account. Purchases follow the
Collection rules (one transaction, exactly once, `Idempotency-Key`).
Applying takes effect for rooms joined afterwards. The picture shows as
`picture` (PlayerPicture `{"id","format","path"}` or `null`) on the player's
own `User`, friends, friend requests, recent players, the friends leaderboard,
report targets and room seats. Bots wear a random active picture with
probability `BOT_PICTURE_SHARE` (default 0.3) so they look like players.

**Storage and privacy** — the art lives in the Cloudflare R2 bucket
`ludo-royale`, which is **private** (no public bucket URL, no custom domain;
an unsigned request is refused). Keys: `profile_pictures/lottie_animation/<file>.json`
and `profile_pictures/image/<file>.png`; every object carries
`Content-Type` (`application/json` / `image/png`) and
`Cache-Control: private, max-age=31536000, immutable`. The app never holds
R2 credentials: it asks `POST /assets/sign` for up to 50 paths at a time and
gets SigV4 query-presigned GET URLs valid `ASSET_URL_TTL` (default 10
minutes), only for paths named by a catalogue row. It downloads each file
once into app storage (`<applicationSupportDirectory>/profile_pictures/<path>`)
and never downloads the same path again. Backend configuration (all four or
none; only in `backend/.env` / the secret store): `R2_ACCOUNT_ID`,
`R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` (an R2 API token
limited to this bucket). Without them the Shop still lists, sells and
applies pictures, and signing answers 503 `assets_unavailable`. Signed URLs
and secrets are never logged.

**Adding pictures** — add rows to `backend/config/profile_pictures.tsv`
(`id, name, format, source_key, path, price_diamonds, sort_order`),
regenerate the seed (`UPDATE_PICTURE_SEED=1 go test ./migrations -run
TestPictureSeedMatchesManifest`), and copy the files into the bucket with
`go run ./cmd/r2-import-pictures` (from `backend/`, after
`set -a; . ./.env; set +a`; `-dry-run` first). The tool downloads each
`source_key` from King Teen Patti's public copy
(`https://assets.sungamestudio.com/`), validates it, uploads it to `path`
with the headers above, skips objects that already exist with the same size
and verifies every upload.
