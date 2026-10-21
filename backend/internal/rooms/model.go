// Package rooms is the authoritative multiplayer room engine: public
// matchmaking, private rooms, practice rooms with bots, turn handling, timers,
// rematches, settlement, and the WebSocket command handlers. All live state is
// in Redis; every mutation is an optimistic compare-and-set that also
// publishes the resulting events in commit order (see store.go).
package rooms

import (
	"ludoroyale/internal/game/ludo"
	snakes "ludoroyale/internal/game/snakes_ladders"
	"ludoroyale/internal/playerinfo"
)

// Games, modes and statuses.
const (
	GameLudo   = "ludo"
	GameSnakes = "snakes_ladders"

	ModePublic   = "public"
	ModePrivate  = "private"
	ModePractice = "practice"

	StatusLobby    = "lobby"
	StatusPlaying  = "playing"
	StatusFinished = "finished"
	StatusClosed   = "closed"

	PhaseAwaitingRoll = "awaiting_roll"
	PhaseAwaitingMove = "awaiting_move"
	PhaseNone         = "none"
	PhaseFinished     = "finished"
)

// Player is a seat's internal state. UserID is never sent to other clients.
type Player struct {
	UserID      string              `json:"userId"`
	UID         string              `json:"uid"`
	Name        string              `json:"name"`
	Avatar      int                 `json:"avatar"`
	Level       int                 `json:"level"`
	Title       string              `json:"title"`
	Cosmetics   map[string]string   `json:"cosmetics"`
	Picture     *playerinfo.Picture `json:"picture,omitempty"`
	Bot         bool                `json:"bot"` // internal only: never in a client view
	BotProfile  string              `json:"botProfile,omitempty"`
	BotEmotes   []string            `json:"botEmotes,omitempty"` // emotes a bot seat may send (its persona's)
	BotSID      string              `json:"botSid,omitempty"`    // bot session id (revoked when the bot is removed)
	Connected   bool                `json:"connected"`
	ConnEpoch   int64               `json:"connEpoch"`
	Forfeited   bool                `json:"forfeited"`
	ForfeitWhy  string              `json:"forfeitWhy,omitempty"`
	Strikes     int                 `json:"strikes"`
	Actions     int                 `json:"actions"`
	JoinedAt    int64               `json:"joinedAt"`
	MatchmakeAt int64               `json:"matchmakeAt,omitempty"`
	FeePaid     int64               `json:"feePaid,omitempty"`
}

// Result of a finished round.
type Result struct {
	WinnerSeat int    `json:"winnerSeat"`
	Reason     string `json:"reason"`
	Placements []int  `json:"placements"`
	Payout     int64  `json:"payout"`
	Paid       bool   `json:"-"`
}

// Rematch voting state.
type Rematch struct {
	Open     bool  `json:"open"`
	Deadline int64 `json:"deadline"`
	Accepted []int `json:"accepted"`
	Declined []int `json:"declined"`
}

// Room is the complete authoritative room state stored in Redis.
type Room struct {
	ID           string `json:"id"`
	V            int64  `json:"v"`
	Game         string `json:"game"`
	Variant      string `json:"variant"`
	Mode         string `json:"mode"`
	Code         string `json:"code,omitempty"`
	Capacity     int    `json:"capacity"`
	Status       string `json:"status"`
	HostSeat     int    `json:"hostSeat"`
	AllowBots    bool   `json:"allowBots"`
	EntryFee     int64  `json:"entryFee"`
	Pot          int64  `json:"pot"`
	Round        int    `json:"round"`
	FillDeadline int64  `json:"fillDeadline"`
	CreatedAt    int64  `json:"createdAt"`
	StartedAt    int64  `json:"startedAt"`
	LoadTest     bool   `json:"loadTest,omitempty"`
	PendingBots  int    `json:"pendingBots"`
	BotRequested int64  `json:"botRequested,omitempty"`

	Players  []Player          `json:"players"`
	Ludo     *ludo.State       `json:"ludo,omitempty"`
	Snakes   *snakes.State     `json:"snakes,omitempty"`
	Deadline int64             `json:"deadline"`
	Result   *Result           `json:"result,omitempty"`
	Paid     bool              `json:"paid,omitempty"`
	Rematch  *Rematch          `json:"rematch,omitempty"`
	Settle   map[string]string `json:"settle,omitempty"` // settlement bookkeeping flags
	Extra    map[string]int64  `json:"extra,omitempty"`
}

// SeatOf returns the seat of userID or -1.
func (r *Room) SeatOf(userID string) int {
	for i, p := range r.Players {
		if p.UserID == userID {
			return i
		}
	}
	return -1
}

// Humans counts human players.
func (r *Room) Humans() int {
	n := 0
	for _, p := range r.Players {
		if !p.Bot {
			n++
		}
	}
	return n
}

// Bots counts bot players.
func (r *Room) Bots() int { return len(r.Players) - r.Humans() }

// MemberIDs lists seated user ids that receive room events. Players who
// explicitly left (and may already be in another room) are excluded.
func (r *Room) MemberIDs() []string {
	out := make([]string, 0, len(r.Players))
	for _, p := range r.Players {
		if p.ForfeitWhy != "left" {
			out = append(out, p.UserID)
		}
	}
	return out
}

// turnInfo returns (seat, turnSeq, phase, dice, legal, sixStreak) from the engine.
func (r *Room) turnInfo() (seat, turnSeq int, phase string, dice int, legal []int, six int) {
	legal = []int{}
	switch {
	case r.Ludo != nil:
		s := r.Ludo
		phase = string(s.Phase)
		if s.Phase == ludo.PhaseAwaitingMove {
			legal = append(legal, s.Legal...)
		}
		return s.Turn, s.TurnSeq, phase, s.Dice, legal, s.SixStreak
	case r.Snakes != nil:
		s := r.Snakes
		return s.Turn, s.TurnSeq, string(s.Phase), s.Dice, legal, 0
	}
	return -1, 0, PhaseNone, 0, legal, 0
}

// hash returns the engine state hash at the engine's own turn.
func (r *Room) hash() uint32 {
	switch {
	case r.Ludo != nil:
		return r.Ludo.Hash()
	case r.Snakes != nil:
		return r.Snakes.Hash()
	}
	return 0
}

// ---- client view ----

// PlayerView is what every room member sees about a seat. It never says
// whether the seat is a bot: bots are indistinguishable from people.
type PlayerView struct {
	Seat      int               `json:"seat"`
	UID       string            `json:"uid"`
	Name      string            `json:"name"`
	Avatar    int               `json:"avatar"`
	Level     int               `json:"level"`
	Title     string            `json:"title"`
	Cosmetics map[string]string `json:"cosmetics"`
	// Picture is the seat's profile picture (null: the built-in avatar). Not
	// part of the state hash.
	Picture   *playerinfo.Picture `json:"picture"`
	Color     string              `json:"color"`
	Connected bool                `json:"connected"`
	Forfeited bool                `json:"forfeited"`
	// ForfeitWhy is "left" or "timeouts" for a forfeited seat (not part of
	// the state hash).
	ForfeitWhy string `json:"forfeitWhy,omitempty"`
	Strikes    int    `json:"strikes"`
}

// TurnView is the turn section of a snapshot.
type TurnView struct {
	Seat      int    `json:"seat"`
	Phase     string `json:"phase"`
	TurnSeq   int    `json:"turnSeq"`
	Deadline  int64  `json:"deadline"`
	Dice      int    `json:"dice"`
	Legal     []int  `json:"legal"`
	SixStreak int    `json:"sixStreak"`
}

// BoardView holds the game board.
type BoardView struct {
	Tokens    [][]int `json:"tokens,omitempty"`
	Positions []int   `json:"positions,omitempty"`
}

// View is the full room snapshot sent to members.
type View struct {
	ID           string       `json:"id"`
	V            int64        `json:"v"`
	Game         string       `json:"game"`
	Variant      string       `json:"variant"`
	Mode         string       `json:"mode"`
	Code         string       `json:"code,omitempty"`
	AllowBots    bool         `json:"allowBots"`
	Capacity     int          `json:"capacity"`
	Status       string       `json:"status"`
	HostSeat     int          `json:"hostSeat"`
	EntryFee     int64        `json:"entryFee"`
	Pot          int64        `json:"pot"`
	Round        int          `json:"round"`
	FillDeadline int64        `json:"fillDeadline"`
	PendingBots  int          `json:"pendingBots"` // practice and private rooms only (0 in public rooms)
	Players      []PlayerView `json:"players"`
	// ComputerSeats lists, in practice and private rooms only, the seats
	// filled with computer players the player or host asked for. Public
	// rooms never reveal which seats are bots.
	ComputerSeats []int     `json:"computerSeats,omitempty"`
	Turn          TurnView  `json:"turn"`
	Board         BoardView `json:"board"`
	Result        *Result   `json:"result,omitempty"`
	Rematch       *Rematch  `json:"rematch,omitempty"`
	H             uint32    `json:"h"`
}

// seatColors returns color names for n seats (same mapping for both games).
func seatColors(n int) []string {
	cs, err := ludo.ColorsFor(n)
	out := make([]string, n)
	if err != nil {
		for i := range out {
			out[i] = ludo.Color(i % 4).String()
		}
		return out
	}
	for i, c := range cs {
		out[i] = c.String()
	}
	return out
}

// View renders the client snapshot.
func (r *Room) View() View {
	n := len(r.Players)
	colorN := n
	if r.Status == StatusLobby && r.Capacity >= 2 {
		colorN = r.Capacity
	}
	colors := seatColors(max(colorN, 1))
	v := View{
		ID: r.ID, V: r.V, Game: r.Game, Variant: r.Variant, Mode: r.Mode, Code: r.Code,
		AllowBots: r.AllowBots, Capacity: r.Capacity, Status: r.Status, HostSeat: r.HostSeat,
		EntryFee: r.EntryFee, Pot: r.Pot, Round: r.Round, FillDeadline: r.FillDeadline,
		Result: r.Result, Rematch: r.Rematch,
		Players: make([]PlayerView, n),
	}
	knownBots := r.Mode == ModePractice || r.Mode == ModePrivate
	if knownBots {
		v.PendingBots = r.PendingBots
	}
	for i, p := range r.Players {
		color := ""
		if i < len(colors) {
			color = colors[i]
		}
		v.Players[i] = PlayerView{Seat: i, UID: p.UID, Name: p.Name, Avatar: p.Avatar, Level: p.Level,
			Title: p.Title, Cosmetics: p.Cosmetics, Picture: p.Picture, Color: color, Connected: p.Connected,
			Forfeited: p.Forfeited, Strikes: p.Strikes}
		if knownBots && p.Bot {
			v.ComputerSeats = append(v.ComputerSeats, i)
		}
		if p.Forfeited {
			v.Players[i].ForfeitWhy = p.ForfeitWhy
		}
	}
	seat, seq, phase, dice, legal, six := r.turnInfo()
	if r.Status == StatusLobby || r.Status == StatusClosed {
		seat, phase = -1, PhaseNone
	}
	v.Turn = TurnView{Seat: seat, Phase: phase, TurnSeq: seq, Deadline: r.Deadline, Dice: dice, Legal: legal, SixStreak: six}
	switch {
	case r.Ludo != nil:
		v.Board.Tokens = make([][]int, len(r.Ludo.Players))
		for i, p := range r.Ludo.Players {
			v.Board.Tokens[i] = append([]int{}, p.Tokens...)
		}
		v.H = r.Ludo.Hash()
	case r.Snakes != nil:
		v.Board.Positions = append([]int{}, r.Snakes.Positions...)
		v.H = r.Snakes.Hash()
	}
	return v
}
