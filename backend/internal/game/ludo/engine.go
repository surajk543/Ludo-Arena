package ludo

import (
	"cmp"
	"slices"
)

// Roll applies a dice roll by player. value must be 1..6 and come from the
// caller's random source. It applies the three-sixes rule, computes the legal
// moves and passes the turn when the roll is void or no move exists. On
// success the phase is awaiting_move (≥ 1 legal move) or awaiting_roll for
// the next player.
func (s *State) Roll(player, value int) (RollResult, error) {
	if err := s.checkActor(player, PhaseAwaitingRoll); err != nil {
		return RollResult{}, err
	}
	if value < 1 || value > 6 {
		return RollResult{}, ErrBadDice
	}

	s.Dice = value
	if value == 6 {
		s.SixStreak++
	} else {
		s.SixStreak = 0
	}
	res := RollResult{Player: player, Value: value, SixStreak: s.SixStreak, Legal: []int{}}

	switch {
	case s.SixStreak >= 3:
		res.Voided = true
		res.TurnPassed = true
		s.passTurn()
	default:
		legal := s.legalMoves(player, value)
		if len(legal) == 0 {
			res.TurnPassed = true
			s.passTurn()
			break
		}
		s.Legal = legal
		s.Phase = PhaseAwaitingMove
		s.TurnSeq++
		res.Legal = append([]int{}, legal...)
	}

	res.Phase, res.Turn, res.TurnSeq = s.Phase, s.Turn, s.TurnSeq
	return res, nil
}

// Move moves the given token of player by the current roll. token must be
// listed in Legal. It applies captures, home arrival, the extra-turn rule,
// win detection and the turn advance.
func (s *State) Move(player, token int) (MoveResult, error) {
	if err := s.checkActor(player, PhaseAwaitingMove); err != nil {
		return MoveResult{}, err
	}
	p := &s.Players[player]
	if token < 0 || token >= len(p.Tokens) || !slices.Contains(s.Legal, token) {
		return MoveResult{}, ErrIllegalMove
	}
	from := p.Tokens[token]
	to, ok := s.target(from, s.Dice)
	if !ok { // only reachable with a corrupted state
		return MoveResult{}, ErrIllegalMove
	}

	p.Tokens[token] = to
	res := MoveResult{Player: player, Token: token, From: from, To: to, Captures: []Capture{}}

	if abs := TrackIndex(p.Color, to); abs >= 0 && !IsSafe(abs) {
		for seat := range s.Players {
			o := &s.Players[seat]
			if seat == player || o.Forfeited {
				continue
			}
			for t, prog := range o.Tokens {
				if TrackIndex(o.Color, prog) == abs {
					o.Tokens[t] = Base
					res.Captures = append(res.Captures, Capture{Player: seat, Token: t})
				}
			}
		}
	}
	res.ReachedHome = to == Home

	switch {
	case s.allHome(player):
		res.Won = true
		s.finish(player)
	case s.Dice == 6 || len(res.Captures) > 0 || res.ReachedHome:
		// Extra roll for the same player; several reasons still give one.
		res.ExtraTurn = true
		s.Phase = PhaseAwaitingRoll
		s.Dice = 0
		s.Legal = []int{}
		s.TurnSeq++
	default:
		res.TurnPassed = true
		s.passTurn()
	}

	res.Phase, res.Turn, res.TurnSeq = s.Phase, s.Turn, s.TurnSeq
	return res, nil
}

// Forfeit removes player from the game: their tokens return to base and they
// take no further turns. If it was their turn, the turn passes. If only one
// non-forfeited player remains, that player wins. Forfeit returns true only
// when this call ended the game; it is a no-op (returning false) when the
// game is already over, the seat is invalid or already forfeited.
func (s *State) Forfeit(player int) (finished bool) {
	if s.Phase == PhaseFinished || player < 0 || player >= len(s.Players) || s.Players[player].Forfeited {
		return false
	}
	p := &s.Players[player]
	p.Forfeited = true
	for i := range p.Tokens {
		p.Tokens[i] = Base
	}
	s.ForfeitOrder = append(s.ForfeitOrder, player)

	if s.ActiveCount() <= 1 {
		winner := s.nextActive(player)
		if winner != s.Turn {
			s.Turn = winner
			s.Dice = 0
			s.SixStreak = 0
		}
		s.finish(winner)
		return true
	}
	if player == s.Turn {
		s.passTurn()
	}
	return false
}

// AutoMoveToken returns the token to move on a timeout while awaiting_move:
// the legal token with the highest progress, ties to the lowest index. ok is
// false in any other phase.
func (s *State) AutoMoveToken() (token int, ok bool) {
	if s.Phase != PhaseAwaitingMove || len(s.Legal) == 0 {
		return -1, false
	}
	tokens := s.Players[s.Turn].Tokens
	best := s.Legal[0]
	for _, t := range s.Legal[1:] {
		if tokens[t] > tokens[best] || (tokens[t] == tokens[best] && t < best) {
			best = t
		}
	}
	return best, true
}

// checkActor validates that player may act in phase want.
func (s *State) checkActor(player int, want Phase) error {
	if s.Phase == PhaseFinished {
		return ErrGameOver
	}
	if player != s.Turn || player < 0 || player >= len(s.Players) {
		return ErrNotYourTurn
	}
	if s.Phase != want {
		return ErrInvalidPhase
	}
	return nil
}

// target returns the progress a token at progress would reach with dice, and
// whether that move is legal.
func (s *State) target(progress, dice int) (int, bool) {
	switch {
	case progress == Base:
		return 0, s.Variant.CanEnter(dice)
	case progress < 0 || progress >= Home:
		return 0, false
	}
	to := progress + dice
	if to > Home {
		return 0, false
	}
	return to, true
}

// legalMoves lists the movable tokens of player for dice, keeping only the
// lowest index among tokens with identical progress.
func (s *State) legalMoves(player, dice int) []int {
	tokens := s.Players[player].Tokens
	legal := []int{}
	for i, prog := range tokens {
		if _, ok := s.target(prog, dice); !ok {
			continue
		}
		if slices.Contains(tokens[:i], prog) {
			continue
		}
		legal = append(legal, i)
	}
	return legal
}

func (s *State) allHome(player int) bool {
	for _, t := range s.Players[player].Tokens {
		if t != Home {
			return false
		}
	}
	return true
}

// nextActive returns the next non-forfeited seat after seat, wrapping around.
func (s *State) nextActive(seat int) int {
	n := len(s.Players)
	for i := 1; i <= n; i++ {
		next := (seat + i) % n
		if !s.Players[next].Forfeited {
			return next
		}
	}
	return seat
}

// passTurn gives the turn to the next active player, awaiting a roll.
func (s *State) passTurn() {
	s.Turn = s.nextActive(s.Turn)
	s.Phase = PhaseAwaitingRoll
	s.Dice = 0
	s.SixStreak = 0
	s.Legal = []int{}
	s.TurnSeq++
}

// finish ends the game with winner (who becomes Turn).
func (s *State) finish(winner int) {
	s.Turn = winner
	s.Winner = winner
	s.Phase = PhaseFinished
	s.Legal = []int{}
	s.TurnSeq++
	s.Placements = s.placements(winner)
}

// score is the total progress of a seat (base 0 … home 57 per token).
func (s *State) score(seat int) int {
	total := 0
	for _, t := range s.Players[seat].Tokens {
		total += t + 1
	}
	return total
}

// placements computes the finishing order: winner, other active players by
// score desc (ties → lower seat), forfeited players latest-forfeit first.
func (s *State) placements(winner int) []int {
	out := []int{winner}
	var active []int
	for seat, p := range s.Players {
		if seat != winner && !p.Forfeited {
			active = append(active, seat)
		}
	}
	slices.SortStableFunc(active, func(a, b int) int {
		if c := cmp.Compare(s.score(b), s.score(a)); c != 0 {
			return c
		}
		return cmp.Compare(a, b)
	})
	out = append(out, active...)
	return appendForfeited(out, s.ForfeitOrder, func(seat int) bool {
		return seat >= 0 && seat < len(s.Players) && s.Players[seat].Forfeited
	}, len(s.Players))
}

// appendForfeited appends the forfeited seats, most recent forfeit first,
// then any forfeited seat missing from order (by seat), without duplicates.
func appendForfeited(out, order []int, forfeited func(int) bool, n int) []int {
	seen := make([]bool, n)
	for _, seat := range out {
		seen[seat] = true
	}
	for i := len(order) - 1; i >= 0; i-- {
		if seat := order[i]; forfeited(seat) && !seen[seat] {
			seen[seat] = true
			out = append(out, seat)
		}
	}
	for seat := range n {
		if forfeited(seat) && !seen[seat] {
			seen[seat] = true
			out = append(out, seat)
		}
	}
	return out
}
