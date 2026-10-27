package rooms

// Daily playtime accrual (docs/progression.md → Daily playtime).
//
// The engine decides, inside the same commits that change a seat, whether
// the seat is actively playing: a person (not a bot), seated in a running
// round of a non-load-test room, connected, with the app in the foreground
// (app.focus), not forfeited, and not idle (fewer than PLAYTIME_IDLE_STRIKES
// consecutive missed own turns; waiting for other players never counts as
// idle). While it is, Player.PlayFrom holds the start of the open stretch.
//
// The open stretch is credited to Deps.Playtime (and, with the room's game,
// to Deps.PlayStats: operator minutes per game) after the commit that closes
// it (the seat stopped qualifying, or the round finished) and at checkpoints
// (every PLAYTIME_CHECKPOINT, on turn changes). Because the stretch lives in
// the room state and is moved forward by the same compare-and-set commit
// that reports it, an interval is reported at most once even with several
// instances, retries, reconnects or duplicate messages, and a person is in
// one room at a time. A crash between the commit and the report loses at
// most one checkpoint of that seat's playtime; it never counts time twice.

import (
	"context"
	"errors"
	"time"

	"ludoarena/internal/protocol"
)

// playEligible reports whether seat p of r accrues playtime right now. Either
// sink enables the accounting, so the operator statistics do not depend on
// the daily playtime feature switch.
func (s *Service) playEligible(r *Room, p *Player) bool {
	return (s.Playtime != nil || s.PlayStats != nil) && r.Status == StatusPlaying && !r.LoadTest && !p.Bot &&
		p.Connected && !p.Away && !p.Forfeited && p.Strikes < s.idleStrikes()
}

func (s *Service) idleStrikes() int {
	if s.Game.PlaytimeIdleStrikes >= 1 {
		return s.Game.PlaytimeIdleStrikes
	}
	return 1
}

func (s *Service) playCheckpoint() int64 {
	if s.Game.PlaytimeCheckpoint > 0 {
		return s.Game.PlaytimeCheckpoint.Milliseconds()
	}
	return time.Minute.Milliseconds()
}

// playSync reconciles a seat's open stretch with its eligibility: it opens a
// stretch when the seat starts qualifying, credits and closes it when it
// stops, and with checkpoint credits a stretch older than the checkpoint
// interval (keeping it open).
func (s *Service) playSync(m *mutation, seat int, checkpoint bool) {
	r := m.r
	if seat < 0 || seat >= len(r.Players) {
		return
	}
	p := &r.Players[seat]
	now := s.nowMs()
	eligible := s.playEligible(r, p)
	switch {
	case p.PlayFrom > 0 && !eligible:
		m.creditPlay(p.UserID, p.PlayFrom, now, true)
		p.PlayFrom = 0
	case p.PlayFrom > 0 && checkpoint && now-p.PlayFrom >= s.playCheckpoint():
		m.creditPlay(p.UserID, p.PlayFrom, now, false)
		p.PlayFrom = now
	case p.PlayFrom == 0 && eligible:
		p.PlayFrom = now
	default:
		return
	}
	m.write = true
}

// playSyncAll runs playSync for every seat.
func (s *Service) playSyncAll(m *mutation, checkpoint bool) {
	for i := range m.r.Players {
		s.playSync(m, i, checkpoint)
	}
}

// creditPlay reports [from, to) of a person's play after the commit, to both
// sinks from the same callback (so both see exactly the same intervals).
func (m *mutation) creditPlay(userID string, from, to int64, final bool) {
	pt, stats := m.s.Playtime, m.s.PlayStats
	if (pt == nil && stats == nil) || to <= from {
		return
	}
	id, game := parseUUID(userID), m.r.Game
	m.then(func(ctx context.Context) {
		ctx = context.WithoutCancel(ctx)
		start, end := time.UnixMilli(from), time.UnixMilli(to)
		if stats != nil {
			stats.RecordPlay(ctx, id, game, start, end)
		}
		if pt != nil {
			pt.AddPlaytime(ctx, id, start, end, final)
		}
	})
}

// SetFocus handles app.focus: a person's app left (false) or returned to
// (true) the foreground. It pauses or resumes playtime in the active room
// and changes nothing else (no event, no turn change).
func (s *Service) SetFocus(ctx context.Context, userID string, foreground bool) error {
	roomID := s.ActiveRoom(ctx, userID)
	if roomID == "" {
		return nil
	}
	_, err := s.mutate(ctx, roomID, func(m *mutation) error { return s.setFocus(m, userID, foreground) })
	if errors.Is(err, protocol.ErrRoomNotFound) {
		return nil
	}
	return err
}

func (s *Service) setFocus(m *mutation, userID string, foreground bool) error {
	seat := m.r.SeatOf(userID)
	if seat < 0 || m.r.Status == StatusClosed {
		return errNoop
	}
	p := &m.r.Players[seat]
	if p.Away == !foreground {
		return errNoop
	}
	p.Away = !foreground
	m.write = true
	s.playSync(m, seat, false)
	return nil
}
