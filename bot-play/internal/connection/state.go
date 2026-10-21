package connection

import (
	"encoding/json"
	"fmt"
	"hash/fnv"

	"ludoroyale/botplay/internal/ludo"
	"ludoroyale/botplay/internal/snakes_ladders"
)

// Outcome is the result of applying a message to the local room state.
type Outcome int

const (
	// Applied: a delta with v == local.v+1 was applied (and h matched or was absent).
	Applied Outcome = iota
	// Replaced: a full snapshot replaced local state.
	Replaced
	// Duplicate: v <= local.v (or an older snapshot); ignored.
	Duplicate
	// Gap: v > local.v+1; nothing applied, request a sync.
	Gap
	// HashMismatch: applied, but the local hash differs from h; request a sync.
	HashMismatch
	// OtherRoom: the event is for a different room; ignored.
	OtherRoom
	// NoState: a delta arrived before any snapshot; request a sync.
	NoState
	// Invalid: undecodable payload; request a sync.
	Invalid
)

func (o Outcome) String() string {
	return [...]string{"applied", "replaced", "duplicate", "gap", "hash_mismatch", "other_room", "no_state", "invalid"}[o]
}

// NeedsSync reports whether the outcome requires game.request_sync.
func (o Outcome) NeedsSync() bool {
	return o == Gap || o == HashMismatch || o == NoState || o == Invalid
}

// IsVersionedDelta reports whether t is a delta carrying roomId and v.
func IsVersionedDelta(t string) bool {
	switch t {
	case TDiceResult, TMoveApplied, TTurnChanged, TPlayerConnected, TPlayerDisconnected,
		TPlayerForfeited, TGameFinished, TRoomRematch:
		return true
	}
	return false
}

// IsSnapshot reports whether t carries a full room snapshot.
func IsSnapshot(t string) bool {
	return t == TRoomUpdated || t == TGameStarted || t == TGameState
}

// RoomState is the bot's local copy of one room, maintained with the
// documented reconciliation rules. Not safe for concurrent use.
type RoomState struct {
	room *Room
}

// Room returns the current room (nil before the first snapshot). Callers
// must not mutate it.
func (s *RoomState) Room() *Room { return s.room }

// V returns the local version (0 without state).
func (s *RoomState) V() int64 {
	if s.room == nil {
		return 0
	}
	return s.room.V
}

// Reset drops local state.
func (s *RoomState) Reset() { s.room = nil }

// ApplySnapshot replaces local state unconditionally if room.v >= local.v
// (for the same room); a snapshot for a different room always replaces.
func (s *RoomState) ApplySnapshot(r *Room) Outcome {
	if r == nil {
		return Invalid
	}
	if s.room != nil && s.room.ID == r.ID && r.V < s.room.V {
		return Duplicate
	}
	if r.Players == nil {
		r.Players = []Player{}
	}
	s.room = r
	return Replaced
}

// VerifySnapshotHash checks a snapshot's h against the locally computed hash.
// ok is false when the snapshot carries no h or the hash is not defined for
// its state (e.g. a lobby).
func VerifySnapshotHash(r *Room) (match bool, ok bool) {
	if r == nil || r.H == nil || r.Status == StatusLobby {
		return false, false
	}
	h, ok := StateHash(r)
	if !ok {
		return false, false
	}
	return h == *r.H, true
}

// ApplyDelta applies a versioned delta following the reconciliation rules:
// v <= local → Duplicate; v == local+1 → apply, then verify h; v > local+1 → Gap.
func (s *RoomState) ApplyDelta(t string, raw json.RawMessage) (Outcome, error) {
	var hdr deltaHeader
	if err := json.Unmarshal(raw, &hdr); err != nil {
		return Invalid, fmt.Errorf("decode %s header: %w", t, err)
	}
	if s.room == nil {
		return NoState, nil
	}
	if hdr.RoomID != "" && hdr.RoomID != s.room.ID {
		return OtherRoom, nil
	}
	switch {
	case hdr.V <= s.room.V:
		return Duplicate, nil
	case hdr.V > s.room.V+1:
		return Gap, nil
	}
	if err := s.apply(t, raw); err != nil {
		return Invalid, err
	}
	s.room.V = hdr.V
	s.room.H = hdr.H
	if hdr.H != nil {
		if h, ok := StateHash(s.room); ok && h != *hdr.H {
			return HashMismatch, nil
		}
	}
	return Applied, nil
}

func (s *RoomState) apply(t string, raw json.RawMessage) error {
	r := s.room
	switch t {
	case TDiceResult:
		var p DiceResult
		if err := json.Unmarshal(raw, &p); err != nil {
			return err
		}
		r.Turn.Dice = p.Value
		r.Turn.TurnSeq = p.TurnSeq
		r.Turn.Phase = p.Phase
		r.Turn.Deadline = p.Deadline
		r.Turn.Legal = append([]int(nil), p.Legal...)
		r.Turn.SixStreak = p.SixStreak
		if pl := r.Player(p.Seat); pl != nil {
			pl.Strikes = p.Strikes
		}
	case TMoveApplied:
		var p MoveApplied
		if err := json.Unmarshal(raw, &p); err != nil {
			return err
		}
		switch r.Game {
		case "snakes_ladders":
			if p.Seat < 0 || p.Seat >= len(r.Board.Positions) {
				return fmt.Errorf("move_applied: seat %d out of range", p.Seat)
			}
			r.Board.Positions[p.Seat] = p.To
		default:
			if p.Seat < 0 || p.Seat >= len(r.Board.Tokens) || p.Token < 0 || p.Token >= len(r.Board.Tokens[p.Seat]) {
				return fmt.Errorf("move_applied: seat/token %d/%d out of range", p.Seat, p.Token)
			}
			r.Board.Tokens[p.Seat][p.Token] = p.To
			for _, c := range p.Captures {
				if c.Seat >= 0 && c.Seat < len(r.Board.Tokens) && c.Token >= 0 && c.Token < len(r.Board.Tokens[c.Seat]) {
					r.Board.Tokens[c.Seat][c.Token] = ludo.Base
				}
			}
		}
		r.Turn.Legal = []int{}
	case TTurnChanged:
		var p TurnChanged
		if err := json.Unmarshal(raw, &p); err != nil {
			return err
		}
		r.Turn.Seat = p.Seat
		r.Turn.TurnSeq = p.TurnSeq
		r.Turn.Phase = p.Phase
		r.Turn.Deadline = p.Deadline
		r.Turn.SixStreak = p.SixStreak
		r.Turn.Dice = 0
		r.Turn.Legal = []int{}
	case TPlayerConnected, TPlayerDisconnected:
		var p PlayerEvent
		if err := json.Unmarshal(raw, &p); err != nil {
			return err
		}
		if pl := r.Player(p.Seat); pl != nil {
			pl.Connected = t == TPlayerConnected
		}
	case TPlayerForfeited:
		var p PlayerForfeited
		if err := json.Unmarshal(raw, &p); err != nil {
			return err
		}
		if pl := r.Player(p.Seat); pl != nil {
			pl.Forfeited = true
		}
		if r.Game != "snakes_ladders" && p.Seat >= 0 && p.Seat < len(r.Board.Tokens) {
			for i := range r.Board.Tokens[p.Seat] {
				r.Board.Tokens[p.Seat][i] = ludo.Base
			}
		}
	case TGameFinished:
		var p GameFinished
		if err := json.Unmarshal(raw, &p); err != nil {
			return err
		}
		r.Status = StatusFinished
		r.Result = p.Result
		r.Rematch = p.Rematch
		r.Turn.Phase = PhaseFinished
	case TRoomRematch:
		var p RoomRematch
		if err := json.Unmarshal(raw, &p); err != nil {
			return err
		}
		r.Rematch = p.Rematch
	default:
		return fmt.Errorf("not a delta: %s", t)
	}
	return nil
}

// StateHash computes the documented FNV-1a state hash of a room.
func StateHash(r *Room) (uint32, bool) {
	var s string
	switch r.Game {
	case "ludo":
		if r.Board.Tokens == nil {
			return 0, false
		}
		s = ludo.Canonical(r.Turn.TurnSeq, r.Turn.Seat, r.Board.Tokens)
	case "snakes_ladders":
		if r.Board.Positions == nil {
			return 0, false
		}
		s = snakes_ladders.Canonical(r.Turn.TurnSeq, r.Turn.Seat, r.Board.Positions)
	default:
		return 0, false
	}
	return FNV1a(s), true
}

// FNV1a is the 32-bit FNV-1a hash of s.
func FNV1a(s string) uint32 {
	h := fnv.New32a()
	_, _ = h.Write([]byte(s))
	return h.Sum32()
}
