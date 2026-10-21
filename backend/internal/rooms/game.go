package rooms

import (
	"context"
	"errors"
	"slices"
	"strconv"
	"time"

	"github.com/google/uuid"

	"ludoroyale/internal/game/ludo"
	snakes "ludoroyale/internal/game/snakes_ladders"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/protocol"
	"ludoroyale/internal/wallet"
)

// ---- event payloads (docs/websocket-protocol.md §6) ----

type diceResultP struct {
	RoomID    string `json:"roomId"`
	V         int64  `json:"v"`
	H         uint32 `json:"h"`
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
	Room      *View  `json:"room,omitempty"`
}

type tokenRef struct {
	Seat  int `json:"seat"`
	Token int `json:"token"`
}

type transitionP struct {
	Kind string `json:"kind"`
	From int    `json:"from"`
	To   int    `json:"to"`
}

type moveAppliedP struct {
	RoomID     string       `json:"roomId"`
	V          int64        `json:"v"`
	H          uint32       `json:"h"`
	Seat       int          `json:"seat"`
	Token      int          `json:"token"`
	From       int          `json:"from"`
	To         int          `json:"to"`
	Captures   []tokenRef   `json:"captures"`
	Landing    *int         `json:"landing,omitempty"`
	Transition *transitionP `json:"transition,omitempty"`
	Home       bool         `json:"home,omitempty"`
	Auto       bool         `json:"auto,omitempty"`
	Room       *View        `json:"room,omitempty"`
}

type turnChangedP struct {
	RoomID    string `json:"roomId"`
	V         int64  `json:"v"`
	H         uint32 `json:"h"`
	Seat      int    `json:"seat"`
	TurnSeq   int    `json:"turnSeq"`
	Phase     string `json:"phase"`
	Deadline  int64  `json:"deadline"`
	SixStreak int    `json:"sixStreak"`
	Room      *View  `json:"room,omitempty"`
}

type seatP struct {
	RoomID string `json:"roomId"`
	V      int64  `json:"v"`
	Seat   int    `json:"seat"`
}

type forfeitP struct {
	RoomID string `json:"roomId"`
	V      int64  `json:"v"`
	H      uint32 `json:"h"`
	Seat   int    `json:"seat"`
	Reason string `json:"reason"`
	// Strikes is the seat's consecutive missed turns at the forfeit: for
	// "timeouts" the count that removed the player (MAX_STRIKES).
	Strikes int   `json:"strikes"`
	Room    *View `json:"room,omitempty"`
}

type finishedP struct {
	RoomID  string   `json:"roomId"`
	V       int64    `json:"v"`
	Result  *Result  `json:"result"`
	Rematch *Rematch `json:"rematch,omitempty"`
}

// ---- starting ----

// roomFee is the entry fee every seat pays when the round starts: the room's
// fee, except practice and load-test rooms, which are free. Bots pay like
// people (wallet/bots.go), so a bot seat changes nothing.
func roomFee(r *Room) int64 {
	if r.LoadTest || r.Mode == ModePractice {
		return 0
	}
	return r.EntryFee
}

// seatIDs splits the seated user ids into people and bots.
func seatIDs(r *Room) (people, bots []uuid.UUID) {
	for _, p := range r.Players {
		if p.Bot {
			bots = append(bots, parseUUID(p.UserID))
		} else {
			people = append(people, parseUUID(p.UserID))
		}
	}
	return people, bots
}

// startGame charges every seat (people and bots) the entry fee in one
// PostgreSQL transaction, then switches the room to playing. If the room
// changed between charging and committing, every fee is refunded.
func (s *Service) startGame(ctx context.Context, roomID string) error {
	r, _, err := s.st.load(ctx, roomID)
	if err != nil {
		return err
	}
	if r.Status != StatusLobby {
		return protocol.ErrRoomInProgress
	}
	if len(r.Players) < 2 {
		return protocol.ErrNotEnoughPlayers
	}
	fee := roomFee(r)
	people, bots := seatIDs(r)
	settleKey := "settle:fee:" + r.ID + ":" + strconv.Itoa(r.Round)
	var charged map[uuid.UUID]wallet.Wallet
	if fee > 0 {
		ok, err := s.RDB.SetNX(ctx, settleKey, "1", 24*time.Hour).Result()
		if err != nil {
			return err
		}
		if !ok {
			return nil // another start is in progress for this round
		}
		charged, err = s.Wallets.ChargeEntry(ctx, people, bots, fee, s.Bots.Coins)
		if err != nil {
			s.RDB.Del(ctx, settleKey)
			var short *wallet.ShortError
			if errors.As(err, &short) {
				return s.removeBroke(ctx, roomID, short.Users)
			}
			metrics.SettlementFailures.WithLabelValues("entry_fee").Inc()
			return err
		}
	}
	playerSet := map[string]bool{}
	for _, p := range r.Players {
		playerSet[p.UserID] = true
	}

	_, err = s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		if r.Status != StatusLobby || len(r.Players) != len(playerSet) {
			return errStartChanged
		}
		for _, p := range r.Players {
			if !playerSet[p.UserID] {
				return errStartChanged
			}
		}
		return s.beginRound(m, fee)
	})
	if err != nil {
		if fee > 0 {
			s.refund(ctx, charged, bots, fee, "entry_fee_refund")
			s.RDB.Del(ctx, settleKey)
		}
		if errors.Is(err, errStartChanged) {
			return nil
		}
		return err
	}
	for _, uid := range people {
		if w, ok := charged[uid]; ok {
			s.notifyUser(ctx, uid.String(), protocol.TWalletUpdated, map[string]any{
				"coins": w.Coins, "diamonds": w.Diamonds,
				"delta": map[string]int64{"coins": -fee, "diamonds": 0}, "reason": "entry_fee"})
		}
	}
	return nil
}

var errStartChanged = errors.New("room changed while starting")

// beginRound initializes the engine and emits game.started.
func (s *Service) beginRound(m *mutation, fee int64) error {
	r := m.r
	n := len(r.Players)
	switch r.Game {
	case GameLudo:
		st, err := ludo.New(n, ludo.Variant(r.Variant))
		if err != nil {
			return protocol.ErrBadRequest
		}
		r.Ludo, r.Snakes = st, nil
	case GameSnakes:
		st, err := snakes.New(n)
		if err != nil {
			return protocol.ErrBadRequest
		}
		r.Snakes, r.Ludo = st, nil
	}
	now := s.nowMs()
	r.Status = StatusPlaying
	r.StartedAt = now
	r.Pot = fee * int64(len(r.Players)) // every seat paid, people and bots alike
	r.Result, r.Rematch, r.Paid = nil, nil, false
	r.FillDeadline = 0
	for i := range r.Players {
		p := &r.Players[i]
		p.Strikes, p.Actions, p.Forfeited, p.ForfeitWhy = 0, 0, false, ""
		p.FeePaid = fee
		if !p.Bot {
			if p.MatchmakeAt > 0 {
				metrics.MatchmakingWait.WithLabelValues(r.Game).Observe(float64(now-p.MatchmakeAt) / 1000)
				metrics.MatchmakingResults.WithLabelValues("matched").Inc()
				p.MatchmakeAt = 0
			}
		}
	}
	if r.Mode == ModePublic {
		m.op(sideOp{Op: "zrem", K: openKey(r.Game, r.Variant, r.Capacity, poolOf(r)), V: r.ID})
	}
	seat, seq, _, _, _, _ := r.turnInfo()
	r.Deadline = now + s.turnTimeout(r, seat).Milliseconds()
	m.schedule("turn", strconv.Itoa(seq), r.Deadline)
	m.emitSnapshot(protocol.TGameStarted, "")
	metrics.MatchesStarted.WithLabelValues(r.Game, r.Mode, mixOf(r)).Inc()
	return nil
}

func mixOf(r *Room) string {
	switch {
	case r.LoadTest:
		return "loadtest"
	case r.Bots() == 0:
		return "human_only"
	case r.Humans() == 0:
		return "bot_only"
	}
	return "mixed"
}

func poolOf(r *Room) string {
	if r.LoadTest {
		return "loadtest"
	}
	return "live"
}

func (s *Service) turnTimeout(r *Room, seat int) time.Duration {
	if seat >= 0 && seat < len(r.Players) && !r.Players[seat].Connected {
		return s.Game.TurnTimeoutDisconnected
	}
	return s.Game.TurnTimeout
}

// removeBroke drops players who could not pay from a lobby.
func (s *Service) removeBroke(ctx context.Context, roomID string, users []uuid.UUID) error {
	broke := map[string]bool{}
	for _, u := range users {
		broke[u.String()] = true
	}
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		for i := len(m.r.Players) - 1; i >= 0; i-- {
			if broke[m.r.Players[i].UserID] {
				s.removeSeat(m, i)
			}
		}
		if m.r.Status == StatusLobby {
			m.emitSnapshot(protocol.TRoomUpdated, "left")
		}
		return nil
	})
	for u := range broke {
		s.notifyUser(ctx, u, protocol.TError, protocol.ErrInsufficientFunds)
	}
	return err
}

// refund gives every charged seat its fee back (bots too; only people are
// notified).
func (s *Service) refund(ctx context.Context, charged map[uuid.UUID]wallet.Wallet, bots []uuid.UUID, fee int64, reason string) {
	for uid := range charged {
		w, err := s.Wallets.Credit(ctx, uid, fee, 0)
		if err != nil {
			metrics.SettlementFailures.WithLabelValues("refund").Inc()
			s.Log.Error("entry fee refund failed", "error", err.Error())
			continue
		}
		if slices.Contains(bots, uid) {
			continue
		}
		s.notifyUser(ctx, uid.String(), protocol.TWalletUpdated, map[string]any{
			"coins": w.Coins, "diamonds": w.Diamonds,
			"delta": map[string]int64{"coins": fee, "diamonds": 0}, "reason": reason})
	}
}

// ---- turns ----

// actor validates that userID may act now in roomID with turnSeq.
func (s *Service) actor(r *Room, userID string, turnSeq int) (int, error) {
	if r.Status != StatusPlaying {
		return -1, protocol.ErrInvalidPhase
	}
	seat := r.SeatOf(userID)
	if seat < 0 {
		return -1, protocol.ErrNotInRoom
	}
	if r.Players[seat].Forfeited {
		return -1, protocol.ErrInvalidPhase
	}
	turnSeat, seq, _, _, _, _ := r.turnInfo()
	if seq != turnSeq {
		return -1, protocol.ErrStaleState
	}
	if turnSeat != seat {
		return -1, protocol.ErrNotYourTurn
	}
	return seat, nil
}

// Roll handles game.roll_dice.
func (s *Service) Roll(ctx context.Context, userID, roomID string, turnSeq int) error {
	_, err := s.mutate(ctx, roomID, func(m *mutation) error { return s.roll(m, userID, turnSeq) })
	return err
}

// roll is an own roll: it resets the player's missed-turn strikes.
func (s *Service) roll(m *mutation, userID string, turnSeq int) error {
	seat, err := s.actor(m.r, userID, turnSeq)
	if err != nil {
		return err
	}
	p := &m.r.Players[seat]
	p.Strikes = 0
	p.Actions++
	return s.applyRoll(m, seat, false)
}

// Move handles game.make_move (Ludo).
func (s *Service) Move(ctx context.Context, userID, roomID string, turnSeq, token int) error {
	_, err := s.mutate(ctx, roomID, func(m *mutation) error { return s.move(m, userID, turnSeq, token) })
	return err
}

// move is an own move: it resets the player's missed-turn strikes.
func (s *Service) move(m *mutation, userID string, turnSeq, token int) error {
	seat, err := s.actor(m.r, userID, turnSeq)
	if err != nil {
		return err
	}
	if m.r.Ludo == nil || m.r.Ludo.Phase != ludo.PhaseAwaitingMove {
		return protocol.ErrInvalidPhase
	}
	p := &m.r.Players[seat]
	p.Strikes = 0
	p.Actions++
	return s.applyMove(m, seat, token, false)
}

func engineErr(err error) error {
	switch {
	case errors.Is(err, ludo.ErrNotYourTurn), errors.Is(err, snakes.ErrNotYourTurn):
		return protocol.ErrNotYourTurn
	case errors.Is(err, ludo.ErrInvalidPhase), errors.Is(err, snakes.ErrInvalidPhase),
		errors.Is(err, ludo.ErrGameOver), errors.Is(err, snakes.ErrGameOver):
		return protocol.ErrInvalidPhase
	case errors.Is(err, ludo.ErrIllegalMove):
		return protocol.ErrIllegalMove
	}
	return protocol.ErrBadRequest
}

func (s *Service) applyRoll(m *mutation, seat int, auto bool) error {
	r := m.r
	value := s.Dice.Roll()
	strikes := r.Players[seat].Strikes
	if r.Ludo != nil {
		before := r.Ludo.Clone()
		res, err := r.Ludo.Roll(seat, value)
		if err != nil {
			return engineErr(err)
		}
		switch {
		case res.Voided || res.TurnPassed:
			m.emitV(protocol.TDiceResult, func(v int64) any {
				return diceResultP{RoomID: r.ID, V: v, H: before.Hash(), Seat: seat, Value: value,
					TurnSeq: before.TurnSeq, Phase: PhaseAwaitingRoll, Deadline: r.Deadline, Legal: []int{},
					SixStreak: res.SixStreak, Voided: res.Voided, Auto: auto, Strikes: strikes, Room: m.fullSnap()}
			})
			s.afterTurnChange(m)
		case len(res.Legal) == 1:
			m.emitV(protocol.TDiceResult, func(v int64) any {
				return diceResultP{RoomID: r.ID, V: v, H: r.Ludo.Hash(), Seat: seat, Value: value,
					TurnSeq: res.TurnSeq, Phase: PhaseAwaitingMove, Deadline: r.Deadline, Legal: res.Legal,
					SixStreak: res.SixStreak, Auto: auto, Strikes: strikes, Room: m.fullSnap()}
			})
			return s.applyMove(m, seat, res.Legal[0], auto)
		default:
			r.Deadline = s.nowMs() + s.turnTimeout(r, seat).Milliseconds()
			m.schedule("turn", strconv.Itoa(res.TurnSeq), r.Deadline)
			m.emitV(protocol.TDiceResult, func(v int64) any {
				return diceResultP{RoomID: r.ID, V: v, H: r.Ludo.Hash(), Seat: seat, Value: value,
					TurnSeq: res.TurnSeq, Phase: PhaseAwaitingMove, Deadline: r.Deadline, Legal: res.Legal,
					SixStreak: res.SixStreak, Auto: auto, Strikes: strikes, Room: m.fullSnap()}
			})
		}
		return nil
	}

	before := r.Snakes.Clone()
	res, err := r.Snakes.Roll(seat, value)
	if err != nil {
		return engineErr(err)
	}
	m.emitV(protocol.TDiceResult, func(v int64) any {
		return diceResultP{RoomID: r.ID, V: v, H: before.Hash(), Seat: seat, Value: value,
			TurnSeq: before.TurnSeq, Phase: PhaseAwaitingRoll, Deadline: r.Deadline, Legal: []int{},
			Auto: auto, Strikes: strikes, Room: m.fullSnap()}
	})
	if res.Moved {
		mv := moveAppliedP{RoomID: r.ID, H: r.Snakes.HashAt(before.TurnSeq, seat), Seat: seat,
			From: res.From, To: res.To, Captures: []tokenRef{}, Auto: auto}
		if res.Transition != nil {
			landing := res.Landing
			mv.Landing = &landing
			mv.Transition = &transitionP{Kind: res.Transition.Kind, From: res.Transition.From, To: res.Transition.To}
		}
		m.emitV(protocol.TMoveApplied, func(v int64) any { mv.V = v; mv.Room = m.fullSnap(); return mv })
	}
	if res.Won {
		return s.finishGame(m, "completed")
	}
	s.afterTurnChange(m)
	return nil
}

func (s *Service) applyMove(m *mutation, seat, token int, auto bool) error {
	r := m.r
	seqBefore := r.Ludo.TurnSeq
	res, err := r.Ludo.Move(seat, token)
	if err != nil {
		return engineErr(err)
	}
	caps := make([]tokenRef, 0, len(res.Captures))
	for _, c := range res.Captures {
		caps = append(caps, tokenRef{Seat: c.Player, Token: c.Token})
	}
	m.emitV(protocol.TMoveApplied, func(v int64) any {
		return moveAppliedP{RoomID: r.ID, V: v, H: r.Ludo.HashAt(seqBefore, seat), Seat: seat, Token: token,
			From: res.From, To: res.To, Captures: caps, Home: res.ReachedHome, Auto: auto, Room: m.fullSnap()}
	})
	if res.Won || r.Ludo.Phase == ludo.PhaseFinished {
		return s.finishGame(m, "completed")
	}
	s.afterTurnChange(m)
	return nil
}

// afterTurnChange sets a fresh deadline for the current turn and emits it.
func (s *Service) afterTurnChange(m *mutation) {
	r := m.r
	seat, seq, phase, _, _, six := r.turnInfo()
	r.Deadline = s.nowMs() + s.turnTimeout(r, seat).Milliseconds()
	m.schedule("turn", strconv.Itoa(seq), r.Deadline)
	m.emitV(protocol.TTurnChanged, func(v int64) any {
		return turnChangedP{RoomID: r.ID, V: v, H: r.hash(), Seat: seat, TurnSeq: seq, Phase: phase,
			Deadline: r.Deadline, SixStreak: six, Room: m.fullSnap()}
	})
}

// handleTurnTimeout acts for a player whose deadline passed.
func (s *Service) handleTurnTimeout(ctx context.Context, roomID string, seq int) error {
	_, err := s.mutate(ctx, roomID, func(m *mutation) error { return s.turnTimedOut(m, seq) })
	return err
}

// turnTimedOut adds a strike to the player whose turn seq timed out and
// acts for them, or forfeits them ("timeouts") at MAX_STRIKES consecutive
// missed turns.
func (s *Service) turnTimedOut(m *mutation, seq int) error {
	r := m.r
	if r.Status != StatusPlaying {
		return errNoop
	}
	seat, curSeq, phase, _, _, _ := r.turnInfo()
	if curSeq != seq {
		return errNoop // the turn already moved on
	}
	now := s.nowMs()
	if now < r.Deadline-50 {
		m.schedule("turn", strconv.Itoa(seq), r.Deadline) // fired early (clock skew); retry later
		return nil
	}
	if s.Policy != nil && s.Policy.GlobalMaintenanceActive() {
		// Maintenance pauses games: no auto-moves, forfeits or payouts.
		r.Deadline = now + s.Game.TurnTimeout.Milliseconds()
		m.write = true
		m.schedule("turn", strconv.Itoa(seq), now+5000)
		return nil
	}
	p := &r.Players[seat]
	p.Strikes++
	if p.Strikes >= s.Game.MaxStrikes {
		// MAX_STRIKES consecutive missed turns: removed from the game
		// (the app tells the player why and leaves the match).
		return s.forfeit(m, seat, "timeouts")
	}
	switch {
	case r.Snakes != nil:
		return s.applyRoll(m, seat, true)
	case phase == PhaseAwaitingRoll:
		if err := s.applyRoll(m, seat, true); err != nil {
			return err
		}
		if r.Ludo.Phase == ludo.PhaseAwaitingMove && r.Ludo.Turn == seat {
			if tok, ok := r.Ludo.AutoMoveToken(); ok {
				return s.applyMove(m, seat, tok, true)
			}
		}
		return nil
	default:
		tok, ok := r.Ludo.AutoMoveToken()
		if !ok {
			return errNoop
		}
		return s.applyMove(m, seat, tok, true)
	}
}

// forfeit removes a player from the running game.
func (s *Service) forfeit(m *mutation, seat int, reason string) error {
	r := m.r
	p := &r.Players[seat]
	if p.Forfeited {
		return nil
	}
	p.Forfeited, p.ForfeitWhy = true, reason
	if !p.Bot {
		metrics.PlayersAbandoned.WithLabelValues(r.Game, reason).Inc()
	}
	turnSeat, seqBefore, _, _, _, _ := r.turnInfo()
	var finished bool
	var h uint32
	if r.Ludo != nil {
		finished = r.Ludo.Forfeit(seat)
		h = r.Ludo.HashAt(seqBefore, turnSeat)
	} else {
		finished = r.Snakes.Forfeit(seat)
		h = r.Snakes.HashAt(seqBefore, turnSeat)
	}
	m.emitV(protocol.TPlayerForfeited, func(v int64) any {
		return forfeitP{RoomID: r.ID, V: v, H: h, Seat: seat, Reason: reason, Strikes: p.Strikes, Room: m.fullSnap()}
	})
	if finished {
		return s.finishGame(m, "forfeit")
	}
	if _, seqAfter, _, _, _, _ := r.turnInfo(); seqAfter != seqBefore {
		s.afterTurnChange(m)
	}
	return nil
}

// finishGame records the result, opens the rematch window and schedules the
// payout and match recording (both idempotent, retried by the scheduler).
func (s *Service) finishGame(m *mutation, reason string) error {
	r := m.r
	var winner int
	var placements []int
	if r.Ludo != nil {
		winner, placements = r.Ludo.Winner, append([]int{}, r.Ludo.Placements...)
	} else {
		winner, placements = r.Snakes.Winner, append([]int{}, r.Snakes.Placements...)
	}
	// The winner takes the pot, person or bot (a bot's goes to its wallet).
	payout := int64(0)
	if winner >= 0 && winner < len(r.Players) {
		payout = r.Pot
	}
	now := s.nowMs()
	r.Status = StatusFinished
	r.Deadline = 0
	r.Result = &Result{WinnerSeat: winner, Reason: reason, Placements: placements, Payout: payout}
	r.Rematch = &Rematch{Open: true, Deadline: now + s.Game.RematchWindow.Milliseconds(), Accepted: []int{}, Declined: []int{}}
	round := strconv.Itoa(r.Round)
	m.schedule("rematch", round, r.Rematch.Deadline)
	if payout > 0 {
		m.schedule("payout", round, now)
	}
	if !r.LoadTest {
		m.schedule("record", round, now)
	}
	m.emitV(protocol.TGameFinished, func(v int64) any {
		return finishedP{RoomID: r.ID, V: v, Result: r.Result, Rematch: r.Rematch}
	})
	metrics.MatchesCompleted.WithLabelValues(r.Game, r.Mode, reason).Inc()
	return nil
}
