package runner

import (
	"context"
	"errors"
	"net/http"
	"time"

	"ludoarena/botplay/internal/client"
	"ludoarena/botplay/internal/config"
	"ludoarena/botplay/internal/matchmaking"
)

// assignmentLoop long-polls GET /bot/assignments while practice or
// public_fill mode is configured and there is headroom. It does not poll
// while at capacity, so assignments stay with the backend (and expire there)
// instead of being handed to a full instance.
func (s *Service) assignmentLoop(ctx context.Context) {
	bo := client.Backoff{Base: 500 * time.Millisecond, Max: 30 * time.Second}
	failures := 0
	for ctx.Err() == nil {
		cfg := s.store.Config()
		serving := cfg.Bots.Enabled && (cfg.Bots.HasMode(config.ModePractice) || cfg.Bots.HasMode(config.ModePublicFill))
		if !serving || s.stopping.Load() || s.headroom() <= 0 {
			_ = client.Sleep(ctx, time.Second)
			continue
		}
		if s.inMaintenance() {
			_ = client.Sleep(ctx, min(s.maintenanceRemaining(), 5*time.Second))
			continue
		}
		list, err := s.client.Assignments(ctx, cfg.Connection.AssignmentWait())
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			s.noteBackendError(err)
			failures++
			d := max(bo.Delay(failures), client.RetryAfter(err))
			s.log.Warn("assignment poll failed", "error", err.Error(), "retry_in", d.String())
			_ = client.Sleep(ctx, d)
			continue
		}
		failures = 0
		if len(list) > 0 {
			s.handleAssignments(list, "poll")
		}
	}
}

// fillLoop implements public matchmaking assistance (public_fill mode).
func (s *Service) fillLoop(ctx context.Context) {
	var pausedUntil time.Time
	backendFillOff := false
	failures := 0
	bo := client.Backoff{Base: time.Second, Max: time.Minute}
	for ctx.Err() == nil {
		cfg := s.store.Config()
		pm := cfg.Bots.PublicMatchmaking
		interval := client.Jitter(pm.PollInterval(), 0.1)
		active := cfg.Bots.Enabled && cfg.Bots.HasMode(config.ModePublicFill) && pm.Enabled &&
			!s.stopping.Load() && !s.inMaintenance() && time.Now().After(pausedUntil)
		if !active {
			_ = client.Sleep(ctx, interval)
			continue
		}
		list, err := s.client.Lobbies(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			s.noteBackendError(err)
			failures++
			_ = client.Sleep(ctx, max(bo.Delay(failures), client.RetryAfter(err), interval))
			continue
		}
		failures = 0
		if list.PublicFillEnabled != nil && !*list.PublicFillEnabled {
			if !backendFillOff {
				s.log.Info("backend reports public fill disabled (BOT_PUBLIC_FILL_ENABLED=false); not requesting fills")
			}
			backendFillOff = true
			_ = client.Sleep(ctx, interval)
			continue
		}
		backendFillOff = false
		lobbies := list.Lobbies
		now := time.Now()
		s.mu.Lock()
		params := matchmaking.FillParams{
			Enabled:        true,
			PerGame:        pm.PerGame,
			Games:          cfg.Bots.Games,
			FillAfter:      pm.FillAfter(),
			MaximumWait:    pm.MaximumWait(),
			MinimumHumans:  pm.MinimumHumans,
			MaxBotsPerRoom: cfg.Bots.MaxBotsPerRoom,
			RefillCooldown: pm.RefillCooldown(),
			Headroom:       s.headroomLocked(cfg),
			GameHeadroom:   s.gameHeadroomLocked(cfg),
		}
		s.mu.Unlock()
		plan, _ := matchmaking.PlanFills(lobbies, params, s.cooldowns, now)
		for _, req := range plan {
			if ctx.Err() != nil || s.stopping.Load() {
				return
			}
			// Record before the request so failures also respect the cooldown.
			s.cooldowns.Record(req.RoomID, time.Now())
			res, err := s.client.Fill(ctx, req.RoomID, req.Count)
			switch {
			case err == nil:
				s.m.FillRequests.WithLabelValues("ok").Inc()
				s.log.Info("public lobby fill requested", "room_id", req.RoomID, "game", req.Game,
					"count", req.Count, "assignments_in_response", len(res.Assignments), "requested", res.Requested)
				// Assignments not returned inline arrive via the long-poll.
				s.handleAssignments(res.Assignments, "fill")
			case client.IsStatus(err, http.StatusConflict):
				s.m.FillRequests.WithLabelValues("conflict").Inc()
				s.log.Debug("fill conflict (lobby changed, full or pending)", "room_id", req.RoomID)
			case client.IsStatus(err, http.StatusForbidden):
				s.m.FillRequests.WithLabelValues("forbidden").Inc()
				pausedUntil = time.Now().Add(time.Minute)
				s.log.Warn("backend refused public fill (BOT_PUBLIC_FILL_ENABLED off?); pausing fill for 60s", "room_id", req.RoomID)
			default:
				s.m.FillRequests.WithLabelValues("error").Inc()
				s.noteBackendError(err)
				if !errors.Is(err, context.Canceled) {
					s.log.Warn("fill request failed", "room_id", req.RoomID, "error", err.Error())
				}
			}
			if !time.Now().After(pausedUntil) || s.inMaintenance() {
				break
			}
		}
		s.cooldowns.Prune(now, 10*pm.RefillCooldown())
		_ = client.Sleep(ctx, interval)
	}
}
