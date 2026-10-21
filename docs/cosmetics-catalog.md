# Cosmetics Catalog (v1)

Shared ids used by the backend catalog (`backend/config/catalog.json`), the
Flutter renderers (`frontend/lib/shared/game_visuals/`) and the Collection Room.
**Every item is purely cosmetic** — nothing changes dice, rules, matchmaking or
rewards. There are no random/loot-box items.

Acquisition types: `starter` (every account owns it, no row stored), `level`
(granted automatically when the level is reached), `mission` / `event`
(granted by claiming that objective), `purchase` (fixed price, coins or
diamonds, bought explicitly).

| Slot / kind | id | Name | Rarity | Acquisition |
|---|---|---|---|---|
| dice | `dice_classic` | Classic Ivory | common | starter |
| dice | `dice_neon` | Neon Pulse | rare | level 5 |
| dice | `dice_golden` | Royal Gold | epic | purchase 40 diamonds |
| dice | `dice_autumn` | Autumn Leaf | rare | event `autumn_cup` |
| token | `token_classic` | Classic Pawn | common | starter |
| token | `token_gem` | Gemstone | rare | level 3 |
| token | `token_royal` | Royal Pawn | epic | level 10 |
| token | `token_crown` | Crown Piece | legendary | purchase 150,000 coins |
| ludo_board | `ludo_board_classic` | Classic | common | starter |
| ludo_board | `ludo_board_midnight` | Midnight Marble | rare | level 8 |
| ludo_board | `ludo_board_royal` | Royal Court | epic | purchase 30 diamonds |
| snakes_board | `snakes_board_classic` | Classic Meadow | common | starter |
| snakes_board | `snakes_board_jungle` | Jungle Temple | rare | level 6 |
| snakes_board | `snakes_board_candy` | Candy Land | epic | purchase 200,000 coins |
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
