// Package gameevents defines the contract between the authoritative room
// engine and downstream systems (progression, missions, social, analytics):
// finished-match records and user notifications. It has no dependencies on
// either side, so neither imports the other.
package gameevents

import (
	"context"
	"time"

	"github.com/google/uuid"
)

// Participant is one seat in a finished match.
type Participant struct {
	UserID    uuid.UUID // bot seats: the bot persona's id, and Bot=true
	UID       string    // public player id shown in the room (people and bots)
	Seat      int
	Bot       bool
	Won       bool
	Placement int  // 1 = winner
	Forfeited bool // left or timed out (not eligible for completion rewards)
	Actions   int  // rolls + moves the player made themselves (anti-farming signal)
}

// MatchRecord is emitted exactly once per finished game round by the room
// engine (idempotency key: MatchID).
type MatchRecord struct {
	MatchID    string // "{roomId}:{round}"
	Game       string // ludo | snakes_ladders
	Variant    string // classic | quick
	Mode       string // public | private | practice
	Reason     string // completed | forfeit
	HasBots    bool
	Players    []Participant
	StartedAt  time.Time
	FinishedAt time.Time
}

// Humans returns the human participants.
func (m MatchRecord) Humans() []Participant {
	var out []Participant
	for _, p := range m.Players {
		if !p.Bot {
			out = append(out, p)
		}
	}
	return out
}

// Recorder consumes finished matches (progression, missions, recent
// opponents). Implementations must be idempotent per (MatchID, UserID).
type Recorder interface {
	RecordMatch(ctx context.Context, rec MatchRecord) error
}

// Notifier pushes a server message to a user's live WebSocket connection,
// wherever it is connected. Delivery is best effort (the user may be offline);
// clients re-fetch state over REST when they reconnect.
type Notifier interface {
	NotifyUser(ctx context.Context, userID uuid.UUID, msgType string, payload any)
}

// Playtime receives intervals of qualifying active play of people
// (implemented by progression: daily playtime milestones). The room engine
// decides what qualifies and reports each interval exactly once, after the
// room commit that closed or checkpointed it; final marks the end of a
// continuous stretch (the player stopped qualifying). Delivery is best
// effort: an interval lost to a crash is never re-sent, so a failure loses at
// most one checkpoint of playtime and never counts any time twice.
type Playtime interface {
	AddPlaytime(ctx context.Context, userID uuid.UUID, from, to time.Time, final bool)
}

// PlayStats receives the same intervals as Playtime, with the game played
// (ludo | snakes_ladders), for operator statistics (implemented by opsstats:
// minutes played per game and hour). It is independent of the daily
// playtime feature switch; same delivery guarantees as Playtime.
type PlayStats interface {
	RecordPlay(ctx context.Context, userID uuid.UUID, game string, from, to time.Time)
}

// Multi fans a record out to several recorders, returning the first error.
type Multi []Recorder

// RecordMatch implements Recorder.
func (m Multi) RecordMatch(ctx context.Context, rec MatchRecord) error {
	var first error
	for _, r := range m {
		if err := r.RecordMatch(ctx, rec); err != nil && first == nil {
			first = err
		}
	}
	return first
}

// Invite describes a private-room invitation sent to a friend.
type Invite struct {
	RoomID    string
	Code      string
	Game      string
	ExpiresAt time.Time
}

// ErrNotFriends is returned when inviting someone who is not a friend.
var ErrNotFriends = errorString("not friends")

// Inviter delivers private-room invites to friends (implemented by social).
type Inviter interface {
	SendInvite(ctx context.Context, from uuid.UUID, friendUID string, inv Invite) error
}

// Inventory answers cosmetic ownership questions (implemented by progression).
type Inventory interface {
	Owns(ctx context.Context, userID uuid.UUID, itemID string) (bool, error)
	// EmoteAsset returns the downloadable art (object path in the private
	// asset bucket and its format) of a Store emote, or ok false for any other
	// id (built-in emotes are drawn by the app). It reads an in-memory
	// snapshot: no I/O.
	EmoteAsset(itemID string) (path, format string, ok bool)
}

type errorString string

func (e errorString) Error() string { return string(e) }
