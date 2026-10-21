// Package protocol defines the WebSocket wire format (docs/websocket-protocol.md):
// compact envelopes, message types and error codes shared by the gateway and
// the room engine.
package protocol

import (
	"encoding/json"
	"errors"
)

// Subprotocol is negotiated via Sec-WebSocket-Protocol.
const (
	Subprotocol = "ludo-royale.v1"
	Version     = 1
)

// Client → server message types.
const (
	TPing              = "ping"
	TMatchmakingJoin   = "matchmaking.join"
	TMatchmakingCancel = "matchmaking.cancel"
	TRoomCreate        = "room.create"
	TRoomJoin          = "room.join"
	TRoomLeave         = "room.leave"
	TRoomInvite        = "room.invite"
	TRoomAllowBots     = "room.allow_bots"
	TRoomAddBot        = "room.add_bot"
	TRoomRemoveBot     = "room.remove_bot"
	TPracticeStart     = "practice.start"
	TGameStart         = "game.start"
	TGameRoll          = "game.roll_dice"
	TGameMove          = "game.make_move"
	TGameSync          = "game.request_sync"
	TGameRematch       = "game.rematch"
	TChatQuick         = "chat.quick"
	TChatEmote         = "chat.emote"
)

// Server → client message types.
const (
	TReady             = "connection.ready"
	TPong              = "pong"
	TAck               = "ack"
	TError             = "error"
	TMatchmakingStatus = "matchmaking.status"
	TRoomUpdated       = "room.updated"
	TGameStarted       = "game.started"
	TGameState         = "game.state"
	TDiceResult        = "game.dice_result"
	TMoveApplied       = "game.move_applied"
	TTurnChanged       = "game.turn_changed"
	TPlayerConnected   = "player.connected"
	TPlayerDisconn     = "player.disconnected"
	TPlayerForfeited   = "player.forfeited"
	TGameFinished      = "game.finished"
	TRoomRematch       = "room.rematch"
	TWalletUpdated     = "wallet.updated"
	TProgression       = "progression.updated"
	TSocialInvite      = "social.invite"
	TSocialFriendReq   = "social.friend_request"
)

// KnownClientTypes bounds metric label cardinality.
var KnownClientTypes = map[string]bool{
	TPing: true, TMatchmakingJoin: true, TMatchmakingCancel: true, TRoomCreate: true, TRoomJoin: true,
	TRoomLeave: true, TRoomInvite: true, TRoomAllowBots: true, TRoomAddBot: true, TRoomRemoveBot: true,
	TPracticeStart: true, TGameStart: true, TGameRoll: true, TGameMove: true, TGameSync: true,
	TGameRematch: true, TChatQuick: true, TChatEmote: true,
}

// Inbound is a decoded client envelope.
type Inbound struct {
	T  string          `json:"t"`
	ID string          `json:"id"`
	P  json.RawMessage `json:"p,omitempty"`
}

// Outbound is a server envelope.
type Outbound struct {
	T string `json:"t"`
	R string `json:"r,omitempty"`
	P any    `json:"p,omitempty"`
}

// Encode serializes an outbound message once (shared by all recipients).
func Encode(t, replyTo string, payload any) []byte {
	b, err := json.Marshal(Outbound{T: t, R: replyTo, P: payload})
	if err != nil {
		// Payloads are server-built structs; failure is a programming error.
		panic(err)
	}
	return b
}

// Error is a protocol-level error (the "error" message payload).
type Error struct {
	Code  string `json:"code"`
	Msg   string `json:"msg"`
	Retry bool   `json:"retry"`
}

func (e *Error) Error() string { return e.Code }

// E builds a protocol error.
func E(code, msg string) *Error { return &Error{Code: code, Msg: msg} }

// Retryable marks an error as retryable.
func (e *Error) Retryable() *Error { c := *e; c.Retry = true; return &c }

// Error codes (docs/websocket-protocol.md §9).
var (
	ErrBadRequest        = E("bad_request", "The message is malformed.")
	ErrUnknownType       = E("unknown_type", "Unknown message type.")
	ErrRateLimited       = E("rate_limited", "Too many messages. Please slow down.").Retryable()
	ErrMaintenance       = E("maintenance", "The game is under maintenance.")
	ErrUpdateRequired    = E("update_required", "Please update the app.")
	ErrNotInRoom         = E("not_in_room", "You are not in this room.")
	ErrRoomNotFound      = E("room_not_found", "Room not found.")
	ErrRoomFull          = E("room_full", "This room is full.")
	ErrRoomInProgress    = E("room_in_progress", "This game has already started.")
	ErrRoomClosed        = E("room_closed", "This room is closed.")
	ErrAlreadyInRoom     = E("already_in_room", "You are already in another game.")
	ErrNotHost           = E("not_host", "Only the host can do that.")
	ErrNotEnoughPlayers  = E("not_enough_players", "At least two players are needed.")
	ErrPlayersNotReady   = E("players_not_ready", "Some players are disconnected.")
	ErrNotYourTurn       = E("not_your_turn", "It is not your turn.")
	ErrInvalidPhase      = E("invalid_phase", "That action is not allowed right now.")
	ErrIllegalMove       = E("illegal_move", "That move is not allowed.")
	ErrStaleState        = E("stale_state", "Your game view was out of date and has been refreshed.")
	ErrInsufficientFunds = E("insufficient_funds", "You don't have enough coins.")
	ErrInvalidCode       = E("invalid_code", "That room code is not valid.")
	ErrRematchClosed     = E("rematch_closed", "The rematch window has closed.")
	ErrNotFriends        = E("not_friends", "You can only invite friends.")
	ErrItemNotOwned      = E("item_not_owned", "You don't own that item yet.")
	ErrBotsUnavailable   = E("bots_unavailable", "Practice opponents are unavailable right now.").Retryable()
	ErrBotsNotAllowed    = E("bots_not_allowed", "Bots are not allowed in this room.")
	ErrInternal          = E("internal", "Something went wrong.").Retryable()
)

// AsError converts err into a protocol error (internal for unknown errors).
func AsError(err error) *Error {
	var pe *Error
	if errors.As(err, &pe) {
		return pe
	}
	return ErrInternal
}

// QuickChat lists the allowed predefined quick-chat ids.
var QuickChat = map[string]bool{
	"gg": true, "nice_move": true, "well_played": true, "rematch": true,
	"again": true, "good_luck": true, "oops": true, "thanks": true,
}
