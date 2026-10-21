# WebSocket Protocol — `ludo-royale.v1`

Real-time gameplay, matchmaking, private rooms, rematch, quick chat and
in-app social notifications run over one authenticated WebSocket per client.
The Go server (`backend/internal/websocket`, `backend/internal/rooms`) is
authoritative for everything described here. Flutter
(`frontend/lib/core/realtime`) mirrors this contract exactly.

Account, wallet, progression and room-code preview operations use REST — see
[`rest-api.md`](rest-api.md).

---

## 1. Connection

```
GET /api/v1/ws
Authorization: Bearer <accessToken>
Sec-WebSocket-Protocol: ludo-royale.v1
Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits   (offered by dart:io)
X-App-Platform: android | ios
X-App-Version: 1.0.0
X-App-Build: 1
X-Reconnect: 1            (only when this connection replaces a dropped one)
```

The server rejects the HTTP upgrade (no WebSocket is created) with a JSON
error body (same shape as REST errors) when:

| HTTP | `error.code` | Client action |
|---|---|---|
| 401 | `unauthorized` | Refresh the access token, then reconnect |
| 426 | `update_required` | Re-check app policy → force-update screen |
| 503 | `maintenance` | Re-check app policy → maintenance screen |
| 429 | `rate_limited` | Back off, reconnect later |
| 400 | `bad_request` / `client_version_required` | Bug: stop reconnecting |

Only one live connection per user. A newer connection closes the older one
with close code `4409`.

### Close codes (after upgrade)

| Code | Meaning | Client behaviour |
|---|---|---|
| 1000 | Normal close (client initiated) | — |
| 1001 | Server shutting down | Reconnect with backoff |
| 1008 | Policy violation (message too large / malformed frames) | Reconnect with backoff |
| 4400 | Protocol violation (repeated invalid messages) | Reconnect with backoff |
| 4401 | Session revoked or expired | Refresh token; if refresh fails → sign-in screen |
| 4409 | Session replaced by a newer connection | Do **not** auto-reconnect; show "Signed in on another device" with a Reconnect button |
| 4426 | Client version no longer supported | Policy re-check → force-update screen |
| 4429 | Rate limit abuse | Reconnect after ≥ 10 s |
| 4503 | Maintenance started | Policy re-check → maintenance screen |
| 4508 | Slow consumer (outbound queue overflowed repeatedly) | Reconnect; a full snapshot follows |

### Reconnect strategy (client)

Bounded exponential backoff with full jitter: `delay = random(0, min(30 s,
0.5 s × 2^attempt))`. Reset `attempt` after a connection has stayed up for
30 s. Pause reconnecting while the app is backgrounded; reconnect immediately
on resume. Before each attempt, refresh the access token if it expires within
60 s.

### Compression

`permessage-deflate` (RFC 7692) is negotiated at the handshake. The server
runs `coder/websocket` in **no-context-takeover** mode by default
(`WS_COMPRESSION=no_context_takeover`, threshold
`WS_COMPRESSION_THRESHOLD` bytes, default 1024). Messages smaller than the
threshold are sent uncompressed. The client (`dart:io` `WebSocket` with
`CompressionOptions`) negotiates and decodes transparently. The application
protocol is identical whether or not a frame is compressed. `connection.ready`
reports what was actually negotiated.

Limits: inbound messages ≤ 4096 bytes **after decompression** (larger →
close 1008). Clients must ignore unknown server message types and unknown
fields.

### Heartbeat

- The server sends WebSocket ping frames every 20 s and closes connections that
  do not answer within 10 s.
- The client sends `{"t":"ping"}` every 15 s; the server answers
  `{"t":"pong","p":{"ts":<server ms>}}`. If no pong arrives within 10 s, the
  client treats the connection as dead and reconnects.

---

## 2. Envelope

Each frame contains exactly one UTF-8 JSON object.

Client → server:

```json
{"t": "game.roll_dice", "id": "c7", "p": { ... }}
```

| Field | Type | Notes |
|---|---|---|
| `t` | string | Message type (required) |
| `id` | string | Client message id, 1–64 chars, **unique per user for at least 2 minutes across connections** (e.g. a random per-connection prefix plus a counter). Required for every type except `ping`. Used for replies and de-duplication. |
| `p` | object | Payload (may be omitted when empty) |

Server → client:

```json
{"t": "game.dice_result", "r": "c7", "p": { ... }}
```

| Field | Type | Notes |
|---|---|---|
| `t` | string | Message type |
| `r` | string | Present when the message is the direct reply to a client message `id` |
| `p` | object | Payload |

**De-duplication:** the server remembers `(userId, id)` for 2 minutes. A
repeated `id` is not executed again; the server answers
`{"t":"ack","r":"<id>","p":{"dup":true}}`.

**Errors** (reply to a specific command, or unsolicited):

```json
{"t": "error", "r": "c7", "p": {"code": "not_your_turn", "msg": "It is not your turn.", "retry": false}}
```

---

## 3. State versioning and deltas

Every room has a monotonically increasing state version `v`. Every event that
changes room state carries the **new** `v`; each event increments `v` by
exactly 1.

Client reconciliation rule for any event carrying `roomId` and `v`:

1. `v <= local.v` → duplicate/old → ignore.
2. `v == local.v + 1` → apply the delta, set `local.v = v`, then compare `h`
   (if present) with the locally computed state hash (see
   `backend/docs/game-rules.md` → "State hash"). On mismatch → send
   `game.request_sync`.
3. `v > local.v + 1` → a gap → send `game.request_sync` and buffer nothing
   (the snapshot replaces local state).

Full snapshots (`room` objects in `game.started`, `game.state`,
`room.updated`) **replace** local state unconditionally if
`room.v >= local.v`.

Turn actions also carry `turnSeq` (increments every time the turn or phase
changes). The client must echo the `turnSeq` it is acting on; the server
rejects stale actions with `stale_state` and sends a fresh `game.state`. This
makes double taps harmless.

### Outbound queue policy (server)

Each connection has a bounded outbound queue (default 128 messages). If it is
full when an event must be queued, the server drops the queued room deltas
**for that connection only**, marks the connection for resync, and the writer
sends a single authoritative `game.state` snapshot (plus `wallet.updated` if a
wallet event was dropped) as soon as it can. Nothing is lost silently: the
snapshot supersedes every dropped delta. A connection that overflows 3 times
in 60 s, or whose write blocks longer than 10 s, is closed with `4508`.

---

## 4. Room snapshot (`room` object)

```json
{
  "id": "r_8f1c2e7a",
  "v": 42,
  "game": "ludo",                 // "ludo" | "snakes_ladders"
  "variant": "classic",           // "classic" | "quick" (ludo only)
  "mode": "private",              // "public" | "private" | "practice"
  "allowBots": false,             // private rooms: host allowed bot seats
  "code": "K7Q2MX",               // private rooms only (members see it)
  "capacity": 4,
  "status": "playing",            // "lobby" | "playing" | "finished" | "closed"
  "hostSeat": 0,                  // private rooms; -1 for public
  "entryFee": 1000,
  "pot": 4000,
  "round": 1,                     // increments on each rematch in the same room
  "fillDeadline": 0,              // public lobby: unix ms when it starts/times out
  "players": [
    {
      "seat": 0,
      "uid": "u_3f9a1c",          // opaque public player id (NOT the account id)
      "name": "Asha",
      "avatar": 3,
      "level": 7,
      "title": "title_rookie",
      "cosmetics": {"dice": "dice_classic", "token": "token_classic", "frame": "frame_none",
                    "trail": "trail_none", "victory": "victory_confetti"},
      "color": "red",
      "connected": true,
      "bot": false,               // server-determined from the session; UI must show a BOT badge
      "forfeited": false,
      "strikes": 0
    }
  ],
  "turn": {
    "seat": 0,
    "phase": "awaiting_roll",     // "awaiting_roll" | "awaiting_move" | "none" | "finished"
    "turnSeq": 12,
    "deadline": 1761022800000,    // unix ms, server clock
    "dice": 0,                    // last roll in this turn, 0 = none
    "legal": [],                  // ludo: legal token indices while awaiting_move
    "sixStreak": 0
  },
  "board": {
    "tokens": [[-1, -1, 5, 56], [0, -1, -1, -1]],   // ludo: [seat][token] progress
    "positions": [34, 0]                            // snakes: [seat] square
  },
  "result": {                     // present when status == "finished"
    "winnerSeat": 0,
    "reason": "completed",        // "completed" | "forfeit"
    "placements": [0, 1],         // seats in finishing order
    "payout": 4000
  },
  "rematch": {                    // present when status == "finished"
    "open": true,
    "deadline": 1761022860000,
    "accepted": [0],              // seats that accepted
    "declined": []
  },
  "h": 2948263811
}
```

`board` contains only the key for the room's game. `uid` is a per-account
pseudonymous public id; account ids, provider ids and emails are never sent to
other players.

---

## 5. Client → server messages

| Type | Payload | Reply | Notes |
|---|---|---|---|
| `ping` | – | `pong` | No `id` needed |
| `matchmaking.join` | `{"game":"ludo","variant":"classic","capacity":4}` | `matchmaking.status` (`searching`) + `room.updated` | Seats the player in an open public lobby or creates one |
| `matchmaking.cancel` | `{}` | `matchmaking.status` (`cancelled`) | Only while the lobby has not started |
| `room.create` | `{"game":"snakes_ladders","variant":"classic","capacity":3}` | `room.updated` (contains `code`) | Private room; creator is host, seat 0 |
| `room.join` | `{"code":"K7Q2MX"}` | `room.updated` | Rate limited (10/min/user) |
| `room.leave` | `{"roomId":"r_…"}` | `ack` | Lobby: frees the seat (host passes to next seat). Playing: forfeit. Finished: leaves the room. |
| `practice.start` | `{"game":"ludo","variant":"classic","bots":2}` | `room.updated` | Practice room: caller + 1–3 bots (total ≤ 4). Starts automatically when the bots are seated; closes with `bots_unavailable` if none arrive within 20 s. |
| `room.allow_bots` | `{"roomId":"r_…","allow":true}` | `room.updated` | Private host only, lobby only |
| `room.add_bot` | `{"roomId":"r_…"}` | `ack` then `room.updated` when the bot sits down | Private host only; requires `allowBots`; respects capacity |
| `room.remove_bot` | `{"roomId":"r_…","seat":2}` | `room.updated` | Private host only, lobby only |
| `room.invite` | `{"roomId":"r_…","friendUid":"u_…"}` | `ack` | Sends `social.invite` to an online friend |
| `game.start` | `{"roomId":"r_…"}` | `game.started` (broadcast) | Private host only; ≥ 2 connected players |
| `game.roll_dice` | `{"roomId":"r_…","turnSeq":12}` | `game.dice_result` (broadcast) | The server picks the value (`crypto/rand`); any other field (`dice`, `value`, …) is `bad_request`; one roll per `turnSeq` |
| `game.make_move` | `{"roomId":"r_…","turnSeq":13,"token":2}` | `game.move_applied` (broadcast) | Ludo only |
| `game.request_sync` | `{"roomId":"r_…"}` (optional) | `game.state` | Without `roomId` → the user's active room |
| `game.rematch` | `{"roomId":"r_…","accept":true}` | `room.rematch` (broadcast) | Only while `rematch.open` |
| `chat.quick` | `{"roomId":"r_…","msg":"gg"}` | broadcast `chat.quick` | Predefined ids only; 1 per 3 s, 10 per minute |
| `chat.emote` | `{"roomId":"r_…","emote":"emote_wave"}` | broadcast `chat.emote` | Emote must be owned (Collection Room); same limits |

Quick-chat ids: `gg` (Good game!), `nice_move` (Nice move!), `well_played`
(Well played!), `rematch` (Rematch?), `again` (Let's play again.), `good_luck`
(Good luck!), `oops` (Oops!), `thanks` (Thanks!).

---

## 6. Server → client messages

| Type | Payload | Delta? |
|---|---|---|
| `connection.ready` | `{"uid","protocol":1,"serverTime","activeRoomId","compression":"permessage-deflate; client_no_context_takeover; server_no_context_takeover" \| "none","heartbeatSec":20}` | – |
| `pong` | `{"ts"}` | – |
| `ack` | `{"dup"?:true}` | – |
| `error` | `{"code","msg","retry"}` | – |
| `matchmaking.status` | `{"status":"searching"\|"cancelled"\|"timeout","game","variant","capacity","roomId"}` | – |
| `room.updated` | `{"room":<snapshot>,"reason":"created"\|"joined"\|"left"\|"host_changed"\|"rematch_started"\|...}` | full |
| `game.started` | `{"room":<snapshot>}` | full |
| `game.state` | `{"room":<snapshot>}` | full |
| `game.dice_result` | `{"roomId","v","h","seat","value","turnSeq","phase","deadline","legal":[...],"sixStreak","voided"?:true,"auto"?:true,"strikes"}` | delta |
| `game.move_applied` | `{"roomId","v","h","seat","token","from","to","captures":[{"seat","token"}],"landing"?:int,"transition"?:{"kind":"snake"\|"ladder","from","to"},"home"?:true,"auto"?:true}` | delta |
| `game.turn_changed` | `{"roomId","v","h","seat","turnSeq","phase","deadline","sixStreak"}` | delta |
| `player.connected` | `{"roomId","v","seat"}` | delta |
| `player.disconnected` | `{"roomId","v","seat"}` | delta |
| `player.forfeited` | `{"roomId","v","h","seat","reason":"left"\|"timeouts"}` | delta |
| `game.finished` | `{"roomId","v","result":{...},"rematch":{...}}` | delta |
| `room.rematch` | `{"roomId","v","rematch":{...}}` | delta |
| `wallet.updated` | `{"coins","diamonds","delta":{"coins","diamonds"},"reason":"entry_fee"\|"payout"\|"mission"\|"purchase"\|"level"}` | – |
| `progression.updated` | `{"xp","level","xpGained","levelUp"?:true,"unlocked":["item_id"],"missions":[{"id","progress","target","completed"}]}` | – |
| `chat.quick` | `{"roomId","seat","msg"}` | – (not versioned) |
| `chat.emote` | `{"roomId","seat","emote"}` | – (not versioned) |
| `social.invite` | `{"inviteId","fromUid","fromName","roomId","code","game","expiresAt"}` | – |
| `social.friend_request` | `{"fromUid","fromName"}` | – |

### Applying deltas (client reducer)

- `game.dice_result`: `turn.dice=value; turn.turnSeq; turn.phase; turn.deadline;
  turn.legal; turn.sixStreak; players[seat].strikes=strikes`. If `voided`, the
  turn will pass in a following `game.turn_changed`.
- `game.move_applied`: Ludo → `board.tokens[seat][token]=to`, each capture →
  `board.tokens[c.seat][c.token]=-1`. Snakes → `board.positions[seat]=to`
  (`landing` is the square reached before a snake/ladder transition, for
  animation only). Set `turn.legal=[]`.
- `game.turn_changed`: `turn.seat, turn.turnSeq, turn.phase, turn.deadline,
  turn.sixStreak`; `turn.dice=0; turn.legal=[]`.
- `player.connected` / `player.disconnected`: `players[seat].connected`.
- `player.forfeited`: `players[seat].forfeited=true`; Ludo: all that seat's
  tokens become `-1`.
- `game.finished`: `status="finished"; result; rematch; turn.phase="finished"`.
- `room.rematch`: `rematch=...`.

Typical event sequence for one Ludo turn with a single legal move:
`game.dice_result (v=41)` → `game.move_applied (v=42)` →
`game.turn_changed (v=43)`.

---

## 7. Matchmaking start policy (public)

1. `matchmaking.join` seats the player in the open public lobby (same game,
   variant and capacity) with the closest average level, oldest first, or
   creates a new lobby.
2. The lobby starts as soon as it is full.
3. Otherwise, at `fillDeadline` (`MATCHMAKING_FILL_SECONDS`, default 30 s
   after the lobby was created) it starts with the players present if there
   are ≥ 2; with only one player the lobby closes and that player receives
   `matchmaking.status` `timeout`.
4. A disconnected lobby player is removed after `LOBBY_DISCONNECT_GRACE_SECONDS`
   (default 15 s).
5. Bots: if the operator enables public matchmaking assistance in
   `bot-play`, it may request bot seats for a lobby that has waited
   `fill_after_seconds` (and has at least `minimum_humans` humans). The backend
   validates the request (lobby still open, capacity, `BOT_MAX_PER_ROOM`,
   `BOT_PUBLIC_FILL_ENABLED`) and the bots appear with `bot: true`.

### Bots and coins

Any room that contains a bot seat at game start is played with **entry fee 0
and no coin payout**. XP and mission progress for the human players work as in
any other completed match. Bots have no wallet, XP or collection.

## 8. Rematch policy

- When a game finishes, `rematch.open=true` for `REMATCH_SECONDS` (default
  30 s). Each eligible player (a human who did not forfeit or leave) may
  accept or decline; bots never vote.
- Voting closes when every eligible player has answered or the deadline
  passes. Only players who **accepted** are carried into the next round.
- **Private rooms:** the **same room and code** return to the lobby
  (`room.updated` reason `rematch_started`, `round+1`, fresh `turnSeq`, board,
  dice and deadlines; no game state is reused). Players who declined or left
  are removed; the host passes to the next seat if the host did not accept.
  Nothing starts automatically: the host starts the round (≥ 2 connected
  players) and may invite friends or add bots to fill seats. If nobody
  accepted, the room closes.
- **Practice rooms:** if the human accepted, the room returns to the lobby
  with fresh bot seats requested; it starts when the bots are seated.
- **Public rooms:** if ≥ 2 players accepted, a **new private room** with a new
  code is created for them and `room.rematch` carries `newRoomId`; otherwise
  no rematch happens.
- A player who leaves (`room.leave`) or starts matchmaking (Play Again) counts
  as declined. No rematch round starts without each participant's acceptance.

## 9. Error codes

`bad_request`, `unknown_type`, `rate_limited`, `unauthorized`,
`update_required`, `maintenance`, `not_in_room`, `room_not_found`,
`room_full`, `room_in_progress`, `room_closed`, `already_in_room`,
`not_host`, `not_enough_players`, `players_not_ready`, `not_your_turn`,
`invalid_phase`, `illegal_move`, `stale_state`, `insufficient_funds`,
`invalid_code`, `rematch_closed`, `not_friends`, `item_not_owned`,
`bots_unavailable`, `bots_not_allowed`, `internal`.

## 10. Bot clients

Bots (the separate `bot-play/` service) use this exact protocol on the same
endpoint with a **bot session token** (see `rest-api.md` → "Bot service").
Differences enforced by the server:

- `X-App-Platform: bot` is accepted only with a bot token; app version
  policy does not apply to bots, maintenance mode does.
- A bot token is scoped to one room assignment (or to the load-test pool) and
  expires after at most 2 hours. Bots cannot call wallet, progression,
  collection, social or account endpoints, cannot create or join rooms by code,
  and cannot send `chat.*` messages.
- Bots submit `game.roll_dice` / `game.make_move` like humans and are subject
  to the same turn, phase, `turnSeq` and rate-limit checks.

`retry: true` means the same command may succeed later without user action.
