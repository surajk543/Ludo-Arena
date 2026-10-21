// Package connection implements the bot side of the `ludo-royale.v1`
// WebSocket protocol (docs/websocket-protocol.md): the transport (one reader
// and one writer goroutine per connection, bounded outbound queue,
// heartbeat), the message types, and the versioned room-state reducer.
package connection

import (
	"encoding/json"
	"time"
)

// Subprotocol is the only supported WebSocket subprotocol.
const Subprotocol = "ludo-royale.v1"

// Client -> server message types used by bots.
const (
	TPing              = "ping"
	TMatchmakingJoin   = "matchmaking.join"
	TMatchmakingCancel = "matchmaking.cancel"
	TRoomLeave         = "room.leave"
	TRollDice          = "game.roll_dice"
	TMakeMove          = "game.make_move"
	TRequestSync       = "game.request_sync"
	TRematch           = "game.rematch"
	TChatQuick         = "chat.quick"
	TChatEmote         = "chat.emote"
)

// Server -> client message types.
const (
	TReady              = "connection.ready"
	TPong               = "pong"
	TAck                = "ack"
	TError              = "error"
	TMatchmakingStatus  = "matchmaking.status"
	TRoomUpdated        = "room.updated"
	TGameStarted        = "game.started"
	TGameState          = "game.state"
	TDiceResult         = "game.dice_result"
	TMoveApplied        = "game.move_applied"
	TTurnChanged        = "game.turn_changed"
	TPlayerConnected    = "player.connected"
	TPlayerDisconnected = "player.disconnected"
	TPlayerForfeited    = "player.forfeited"
	TGameFinished       = "game.finished"
	TRoomRematch        = "room.rematch"
)

// Room status / turn phase values.
const (
	StatusLobby    = "lobby"
	StatusPlaying  = "playing"
	StatusFinished = "finished"
	StatusClosed   = "closed"

	PhaseAwaitingRoll = "awaiting_roll"
	PhaseAwaitingMove = "awaiting_move"
	PhaseNone         = "none"
	PhaseFinished     = "finished"
)

// Close codes (after upgrade).
const (
	CloseNormal         = 1000
	CloseGoingAway      = 1001
	ClosePolicy         = 1008
	CloseProtocol       = 4400
	CloseRevoked        = 4401 // any reason ("session revoked"; humans also "session replaced", "account deleted"): fatal for bots
	CloseReplaced       = 4409
	CloseVersion        = 4426
	CloseRateLimited    = 4429
	CloseMaintenance    = 4503
	CloseSlowConsumer   = 4508
	CloseAbnormal       = 1006 // no close frame (network drop)
	CloseNoStatus       = -1
	ClosePongTimeout    = -2 // local: heartbeat failed
	CloseQueueOverflow  = -3 // local: outbound queue full
	CloseLocal          = -4 // local: closed by this process
	CloseWriteError     = -6 // local: write failed
	CloseHandshakeError = -7 // local: no connection.ready in time
)

// Outbound is a client -> server envelope.
type Outbound struct {
	T  string `json:"t"`
	ID string `json:"id,omitempty"`
	P  any    `json:"p,omitempty"`
}

// Inbound is a server -> client envelope.
type Inbound struct {
	T    string          `json:"t"`
	R    string          `json:"r,omitempty"`
	P    json.RawMessage `json:"p,omitempty"`
	Size int             `json:"-"` // payload bytes after decompression
	At   time.Time       `json:"-"`
}

// Room is the full room snapshot.
type Room struct {
	ID           string   `json:"id"`
	V            int64    `json:"v"`
	Game         string   `json:"game"`
	Variant      string   `json:"variant"`
	Mode         string   `json:"mode"`
	AllowBots    bool     `json:"allowBots"`
	Code         string   `json:"code,omitempty"`
	Capacity     int      `json:"capacity"`
	Status       string   `json:"status"`
	HostSeat     int      `json:"hostSeat"`
	EntryFee     int64    `json:"entryFee"`
	Pot          int64    `json:"pot"`
	Round        int      `json:"round"`
	FillDeadline int64    `json:"fillDeadline"`
	Players      []Player `json:"players"`
	Turn         Turn     `json:"turn"`
	Board        Board    `json:"board"`
	Result       *Result  `json:"result,omitempty"`
	Rematch      *Rematch `json:"rematch,omitempty"`
	H            *uint32  `json:"h,omitempty"`
}

// Player is one seat in a room snapshot. Snapshots say nothing about which
// seats are bots (bots look like people); a bot finds its own seat by its
// session uid.
type Player struct {
	Seat   int    `json:"seat"`
	UID    string `json:"uid"`
	Name   string `json:"name"`
	Avatar int    `json:"avatar"`
	Level  int    `json:"level"`
	Title  string `json:"title,omitempty"`
	// Picture is the seat's profile picture (null: built-in avatar). Bots
	// only carry it; it is not part of the state hash.
	Picture   *PlayerPicture `json:"picture,omitempty"`
	Color     string         `json:"color"`
	Connected bool           `json:"connected"`
	Forfeited bool           `json:"forfeited"`
	// ForfeitWhy is "left" or "timeouts" on forfeited seats (absent otherwise).
	ForfeitWhy string `json:"forfeitWhy,omitempty"`
	Strikes    int    `json:"strikes"`
}

// PlayerPicture is a seat's profile picture (catalogue id, "image" |
// "lottie", object path in the private asset bucket).
type PlayerPicture struct {
	ID     string `json:"id"`
	Format string `json:"format"`
	Path   string `json:"path"`
}

// Turn is the current turn.
type Turn struct {
	Seat      int    `json:"seat"`
	Phase     string `json:"phase"`
	TurnSeq   int    `json:"turnSeq"`
	Deadline  int64  `json:"deadline"`
	Dice      int    `json:"dice"`
	Legal     []int  `json:"legal"`
	SixStreak int    `json:"sixStreak"`
}

// Board holds the key for the room's game only.
type Board struct {
	Tokens    [][]int `json:"tokens,omitempty"`    // ludo: [seat][token] progress
	Positions []int   `json:"positions,omitempty"` // snakes: [seat] square
}

// Result is present when a room is finished.
type Result struct {
	WinnerSeat int    `json:"winnerSeat"`
	Reason     string `json:"reason"`
	Placements []int  `json:"placements"`
	Payout     int64  `json:"payout"`
}

// Rematch is the rematch window state.
type Rematch struct {
	Open     bool  `json:"open"`
	Deadline int64 `json:"deadline"`
	Accepted []int `json:"accepted"`
	Declined []int `json:"declined"`
}

// SeatOf returns the seat of uid, or -1.
func (r *Room) SeatOf(uid string) int {
	if r == nil {
		return -1
	}
	for _, p := range r.Players {
		if p.UID == uid {
			return p.Seat
		}
	}
	return -1
}

// Player returns the player in seat, or nil.
func (r *Room) Player(seat int) *Player {
	for i := range r.Players {
		if r.Players[i].Seat == seat {
			return &r.Players[i]
		}
	}
	return nil
}

// Payloads.

// Ready is connection.ready.
type Ready struct {
	UID          string `json:"uid"`
	Protocol     int    `json:"protocol"`
	ServerTime   int64  `json:"serverTime"`
	ActiveRoomID string `json:"activeRoomId"`
	Compression  string `json:"compression"`
	HeartbeatSec int    `json:"heartbeatSec"`
}

// ErrorPayload is an error message.
type ErrorPayload struct {
	Code  string `json:"code"`
	Msg   string `json:"msg"`
	Retry bool   `json:"retry"`
}

// AckPayload is an ack.
type AckPayload struct {
	Dup bool `json:"dup,omitempty"`
}

// MatchmakingStatus is matchmaking.status.
type MatchmakingStatus struct {
	Status   string `json:"status"`
	Game     string `json:"game"`
	Variant  string `json:"variant"`
	Capacity int    `json:"capacity"`
	RoomID   string `json:"roomId"`
}

// RoomPayload carries a full snapshot (room.updated, game.started, game.state).
type RoomPayload struct {
	Room   *Room  `json:"room"`
	Reason string `json:"reason,omitempty"`
}

// deltaHeader is common to versioned deltas.
type deltaHeader struct {
	RoomID string  `json:"roomId"`
	V      int64   `json:"v"`
	H      *uint32 `json:"h,omitempty"`
}

// DiceResult is game.dice_result.
type DiceResult struct {
	Seat      int    `json:"seat"`
	Value     int    `json:"value"`
	TurnSeq   int    `json:"turnSeq"`
	Phase     string `json:"phase"`
	Deadline  int64  `json:"deadline"`
	Legal     []int  `json:"legal"`
	SixStreak int    `json:"sixStreak"`
	Voided    bool   `json:"voided,omitempty"`
	Auto      bool   `json:"auto,omitempty"`
	Strikes   int    `json:"strikes"`
}

// Capture is one captured token.
type Capture struct {
	Seat  int `json:"seat"`
	Token int `json:"token"`
}

// Transition is a snake or ladder transition.
type Transition struct {
	Kind string `json:"kind"`
	From int    `json:"from"`
	To   int    `json:"to"`
}

// MoveApplied is game.move_applied.
type MoveApplied struct {
	Seat       int         `json:"seat"`
	Token      int         `json:"token"`
	From       int         `json:"from"`
	To         int         `json:"to"`
	Captures   []Capture   `json:"captures"`
	Landing    *int        `json:"landing,omitempty"`
	Transition *Transition `json:"transition,omitempty"`
	Home       bool        `json:"home,omitempty"`
	Auto       bool        `json:"auto,omitempty"`
}

// TurnChanged is game.turn_changed.
type TurnChanged struct {
	Seat      int    `json:"seat"`
	TurnSeq   int    `json:"turnSeq"`
	Phase     string `json:"phase"`
	Deadline  int64  `json:"deadline"`
	SixStreak int    `json:"sixStreak"`
}

// PlayerEvent is player.connected / player.disconnected.
type PlayerEvent struct {
	Seat int `json:"seat"`
}

// PlayerForfeited is player.forfeited. Strikes is the seat's consecutive
// missed turns (for "timeouts": the count that removed the player).
type PlayerForfeited struct {
	Seat    int    `json:"seat"`
	Reason  string `json:"reason"`
	Strikes int    `json:"strikes"`
}

// GameFinished is game.finished.
type GameFinished struct {
	Result  *Result  `json:"result"`
	Rematch *Rematch `json:"rematch"`
}

// RoomRematch is room.rematch.
type RoomRematch struct {
	Rematch *Rematch `json:"rematch"`
}

// Command payloads.

// RoomRef is {"roomId"}.
type RoomRef struct {
	RoomID string `json:"roomId"`
}

// RollDice is game.roll_dice.
type RollDice struct {
	RoomID  string `json:"roomId"`
	TurnSeq int    `json:"turnSeq"`
}

// MakeMove is game.make_move.
type MakeMove struct {
	RoomID  string `json:"roomId"`
	TurnSeq int    `json:"turnSeq"`
	Token   int    `json:"token"`
}

// MatchmakingJoin is matchmaking.join.
type MatchmakingJoin struct {
	Game     string `json:"game"`
	Variant  string `json:"variant"`
	Capacity int    `json:"capacity"`
}

// RematchAnswer is game.rematch.
type RematchAnswer struct {
	RoomID string `json:"roomId"`
	Accept bool   `json:"accept"`
}

// ChatQuick is chat.quick (a predefined quick-chat id).
type ChatQuick struct {
	RoomID string `json:"roomId"`
	Msg    string `json:"msg"`
}

// ChatEmote is chat.emote (an emote id the bot session may use).
type ChatEmote struct {
	RoomID string `json:"roomId"`
	Emote  string `json:"emote"`
}

// EmoteEvent is the chat.emote broadcast (not versioned). Bots never draw
// emotes: they only tolerate the payload, including the asset of Store
// emotes.
type EmoteEvent struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Emote  string `json:"emote"`
	// Asset is the art of a Store emote (em_… ids): an object path in the
	// private asset bucket and its format. Absent for built-in emotes.
	Asset *EmoteAsset `json:"asset,omitempty"`
}

// EmoteAsset is a Store emote's art (path, "lottie" | "image").
type EmoteAsset struct {
	Path   string `json:"path"`
	Format string `json:"format"`
}
