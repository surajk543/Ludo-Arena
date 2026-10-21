package runner

import (
	"context"
	"math/rand/v2"
	"time"

	"golang.org/x/time/rate"

	"ludoroyale/botplay/internal/client"
)

// loadtestLoop ramps the load-test population to loadtest.target_connections
// at ramp_per_second, injects connection churn, and signals the end of the
// run after duration_seconds.
func (s *Service) loadtestLoop(ctx context.Context) {
	cfg := s.store.Config()
	end := s.started.Add(cfg.Loadtest.Duration())
	ramp := rate.NewLimiter(rate.Limit(cfg.Loadtest.RampPerSecond), burst(cfg.Loadtest.RampPerSecond))
	tick := time.NewTicker(50 * time.Millisecond)
	defer tick.Stop()
	nextChurn := time.Time{}
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
		cfg = s.store.Config()
		now := time.Now()
		if now.After(end) {
			s.ltOnce.Do(func() { close(s.ltDone) })
			return
		}
		ramp.SetLimit(rate.Limit(cfg.Loadtest.RampPerSecond))
		ramp.SetBurst(burst(cfg.Loadtest.RampPerSecond))
		if s.stopping.Load() || s.inMaintenance() || now.UnixNano() < s.spawnPause.Load() {
			continue
		}
		for s.headroom() > 0 && ramp.Allow() {
			s.spawnLoadtestBot()
		}
		// Churn: forced disconnect + reconnect (X-Reconnect: 1) of a random
		// connected bot, as a Poisson process of churn_per_minute events.
		if rpm := cfg.Loadtest.ChurnPerMinute; rpm > 0 {
			if nextChurn.IsZero() {
				nextChurn = now.Add(expInterval(rpm))
			}
			for !nextChurn.After(now) {
				s.churnRandomBot()
				nextChurn = nextChurn.Add(expInterval(rpm))
			}
		} else {
			nextChurn = time.Time{}
		}
	}
}

func expInterval(perMinute float64) time.Duration {
	return time.Duration(rand.ExpFloat64() / perMinute * float64(time.Minute))
}

func (s *Service) spawnLoadtestBot() {
	cfg := s.store.Config()
	s.mu.Lock()
	if s.headroomLocked(cfg) <= 0 || s.stopping.Load() {
		s.mu.Unlock()
		return
	}
	b := s.newBotLocked(client.KindLoadtest, gameNone, nil)
	b.slowReader = cfg.Loadtest.SlowReaderFraction > 0 && b.strat.Float64() < cfg.Loadtest.SlowReaderFraction
	s.registerLocked(b)
	s.mu.Unlock()
	s.publishActive()
	go b.run()
}

func (s *Service) churnRandomBot() {
	s.mu.Lock()
	var candidates []*Bot
	for _, b := range s.bots {
		if b.connected.Load() && b.RetireMode() == RetireNone {
			candidates = append(candidates, b)
		}
	}
	s.mu.Unlock()
	if len(candidates) == 0 {
		return
	}
	candidates[rand.IntN(len(candidates))].Churn()
}

// noteSessionResult backs off load-test spawning after consecutive session
// failures so a broken backend is not hammered.
func (s *Service) noteSessionResult(ok bool) {
	if ok {
		s.spawnFails.Store(0)
		return
	}
	n := s.spawnFails.Add(1)
	d := client.Backoff{Base: 500 * time.Millisecond, Max: 30 * time.Second}.Delay(int(n))
	s.spawnPause.Store(time.Now().Add(d).UnixNano())
}
