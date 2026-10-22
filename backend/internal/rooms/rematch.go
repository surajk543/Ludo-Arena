package rooms

import (
	"context"
	"strconv"

	"ludoarena/internal/metrics"
	"ludoarena/internal/protocol"
)

// eligibleRematch lists seats that may vote: humans who finished the round
// (not forfeited) and did not leave.
func eligibleRematch(r *Room) []int {
	var out []int
	for i, p := range r.Players {
		if !p.Bot && !p.Forfeited && p.ForfeitWhy != "left" {
			out = append(out, i)
		}
	}
	return out
}

func (s *Service) rematchDecided(r *Room) bool {
	if r.Rematch == nil {
		return false
	}
	for _, seat := range eligibleRematch(r) {
		if !containsInt(r.Rematch.Accepted, seat) && !containsInt(r.Rematch.Declined, seat) {
			return false
		}
	}
	return true
}

// VoteRematch records an explicit accept/decline. No rematch starts without
// each participant's consent.
func (s *Service) VoteRematch(ctx context.Context, c Caller, roomID string, accept bool) error {
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		seat := r.SeatOf(c.UserID)
		if seat < 0 {
			return protocol.ErrNotInRoom
		}
		if r.Status != StatusFinished || r.Rematch == nil || !r.Rematch.Open {
			return protocol.ErrRematchClosed
		}
		if !containsInt(eligibleRematch(r), seat) {
			return protocol.ErrRematchClosed
		}
		if containsInt(r.Rematch.Accepted, seat) || containsInt(r.Rematch.Declined, seat) {
			return errNoop
		}
		if accept {
			r.Rematch.Accepted = append(r.Rematch.Accepted, seat)
			metrics.Rematches.WithLabelValues("accepted").Inc()
		} else {
			r.Rematch.Declined = append(r.Rematch.Declined, seat)
			metrics.Rematches.WithLabelValues("declined").Inc()
		}
		m.emitV(protocol.TRoomRematch, func(v int64) any {
			return map[string]any{"roomId": r.ID, "v": v, "rematch": r.Rematch}
		})
		if s.rematchDecided(r) {
			round := r.Round
			m.then(func(ctx context.Context) { _ = s.resolveRematch(ctx, roomID, round) })
		}
		return nil
	})
	return err
}

// resolveRematch closes voting (all answered or deadline) and starts the next
// round with the players who accepted:
//   - private: same room and code, back to the lobby (host starts it);
//   - practice: same room, fresh bot seats requested, auto-starts;
//   - public: a new private room with the accepting players (>= 2).
func (s *Service) resolveRematch(ctx context.Context, roomID string, round int) error {
	var publicGroup []Player
	var game, variant string
	var capacity int
	var revoke []string
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		if r.Status != StatusFinished || r.Round != round || r.Rematch == nil || !r.Rematch.Open {
			return errNoop
		}
		r.Rematch.Open = false
		var keep []Player
		for _, seat := range r.Rematch.Accepted {
			p := r.Players[seat]
			if p.ForfeitWhy == "left" {
				continue
			}
			keep = append(keep, p)
		}
		if r.Mode == ModePublic || len(keep) == 0 || (r.Mode == ModePrivate && len(keep) < 1) {
			if r.Mode == ModePublic && len(keep) >= 2 {
				publicGroup, game, variant, capacity = keep, r.Game, r.Variant, len(keep)
				for _, p := range keep {
					m.clearPointer(p.UserID)
				}
			}
			m.emitV(protocol.TRoomRematch, func(v int64) any {
				return map[string]any{"roomId": r.ID, "v": v, "rematch": r.Rematch}
			})
			return nil
		}
		// Private / practice: reset the same room for the next round.
		hostID := ""
		if r.HostSeat >= 0 && r.HostSeat < len(r.Players) {
			hostID = r.Players[r.HostSeat].UserID
		}
		for _, p := range r.Players {
			kept := false
			for _, k := range keep {
				if k.UserID == p.UserID {
					kept = true
				}
			}
			if !kept {
				m.clearPointer(p.UserID)
				m.extraTo = append(m.extraTo, p.UserID)
				if p.Bot && p.BotSID != "" {
					revoke = append(revoke, p.BotSID)
				}
			}
		}
		for i := range keep {
			keep[i].Forfeited, keep[i].ForfeitWhy, keep[i].Strikes, keep[i].Actions = false, "", 0, 0
		}
		r.Players = keep
		r.HostSeat = 0
		for i, p := range keep {
			if p.UserID == hostID {
				r.HostSeat = i
			}
		}
		r.Round++
		r.Status = StatusLobby
		r.Ludo, r.Snakes, r.Result, r.Rematch = nil, nil, nil, nil
		r.Pot, r.Deadline, r.Paid = 0, 0, false
		if r.Mode == ModePractice {
			bots := r.Capacity - len(keep)
			if bots > 0 {
				s.requestBots(m, "practice", bots)
				m.schedule("practice", strconv.Itoa(r.Round), s.nowMs()+s.Game.PracticeBotWait.Milliseconds())
			}
		}
		m.emitSnapshot(protocol.TRoomUpdated, "rematch_started")
		metrics.Rematches.WithLabelValues("started").Inc()
		return nil
	})
	for _, sid := range revoke {
		_ = s.BotAuth.Revoke(ctx, sid)
	}
	if err != nil || publicGroup == nil {
		return err
	}
	return s.publicRematch(ctx, roomID, game, variant, capacity, publicGroup)
}

// publicRematch creates a new private room for players who accepted a
// rematch after a public game.
func (s *Service) publicRematch(ctx context.Context, oldRoomID, game, variant string, capacity int, players []Player) error {
	now := s.nowMs()
	for attempt := 0; attempt < 5; attempt++ {
		code := newCode()
		ok, err := s.RDB.SetNX(ctx, codeKey(code), "pending", s.Game.LobbyTTL).Result()
		if err != nil || !ok {
			continue
		}
		for i := range players {
			p := &players[i]
			p.Forfeited, p.ForfeitWhy, p.Strikes, p.Actions, p.Connected = false, "", 0, 0, true
		}
		r := &Room{ID: newRoomID(), Game: game, Variant: variant, Mode: ModePrivate, Code: code,
			Capacity: capacity, Status: StatusLobby, HostSeat: 0, EntryFee: s.EntryFee(game), Round: 1,
			CreatedAt: now, Players: players}
		_, err = s.create(ctx, r, func(m *mutation) error {
			for _, p := range players {
				m.setPointer(p.UserID)
			}
			m.emitSnapshot(protocol.TRoomUpdated, "rematch_started")
			return nil
		})
		if err != nil {
			s.RDB.Del(ctx, codeKey(code))
			return err
		}
		metrics.Rematches.WithLabelValues("started").Inc()
		// Tell the old room's players where the rematch went.
		_, _ = s.mutate(ctx, oldRoomID, func(m *mutation) error {
			m.emitV(protocol.TRoomRematch, func(v int64) any {
				return map[string]any{"roomId": oldRoomID, "v": v, "rematch": m.r.Rematch, "newRoomId": r.ID}
			})
			return nil
		})
		return nil
	}
	return protocol.ErrInternal
}
