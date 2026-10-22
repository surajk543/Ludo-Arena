// Package runner is the bot-play controller: it obtains controller tokens,
// receives assignments, plans public lobby fills, runs the load-test
// population, supervises every bot session and shuts down gracefully.
package runner

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"math/rand/v2"
	"net/http"
	"net/url"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/time/rate"

	"ludoarena/botplay/internal/client"
	"ludoarena/botplay/internal/config"
	"ludoarena/botplay/internal/matchmaking"
	"ludoarena/botplay/internal/metrics"
)

// Options wires a Service.
type Options struct {
	Store   *config.Store
	Client  *client.Client
	Metrics *metrics.Metrics
	Logger  *slog.Logger
	// LoadtestAcknowledged is true when --i-understand-this-is-a-load-test was passed.
	LoadtestAcknowledged bool
	// WSHTTPClient is used for WebSocket dials (tests); nil = default.
	WSHTTPClient *http.Client
}

// Service supervises all bots.
type Service struct {
	store  *config.Store
	client *client.Client
	m      *metrics.Metrics
	log    *slog.Logger
	ack    bool
	wsHC   *http.Client

	joinLim *rate.Limiter // bots.max_room_joins_per_second
	connLim *rate.Limiter // bots.max_connection_attempts_per_second

	mu      sync.Mutex
	bots    map[uint64]*Bot
	byGame  map[string]int
	seen    map[string]time.Time // assignment ids already served
	nextID  uint64
	wg      sync.WaitGroup // bot goroutines
	loopsWG sync.WaitGroup

	stopping   atomic.Bool
	maintUntil atomic.Int64 // unix nanos: backend maintenance back-off end
	spawnPause atomic.Int64 // unix nanos: load-test spawn back-off end
	spawnFails atomic.Int32

	botsCtx    context.Context
	botsCancel context.CancelFunc

	fatalOnce sync.Once
	fatal     chan error
	ltDone    chan struct{}
	ltOnce    sync.Once
	cooldowns *matchmaking.Cooldowns
	started   time.Time
	ltTarget  int // load-test target at start (for the report)
}

// New creates a service.
func New(o Options) *Service {
	cfg := o.Store.Config()
	s := &Service{
		store: o.Store, client: o.Client, m: o.Metrics, log: o.Logger, ack: o.LoadtestAcknowledged,
		wsHC:      o.WSHTTPClient,
		joinLim:   rate.NewLimiter(rate.Limit(cfg.Bots.MaxRoomJoinsPerSecond), burst(cfg.Bots.MaxRoomJoinsPerSecond)),
		connLim:   rate.NewLimiter(rate.Limit(cfg.Bots.MaxConnectionAttemptsPerSecond), burst(cfg.Bots.MaxConnectionAttemptsPerSecond)),
		bots:      map[uint64]*Bot{},
		byGame:    map[string]int{},
		seen:      map[string]time.Time{},
		fatal:     make(chan error, 1),
		ltDone:    make(chan struct{}),
		cooldowns: matchmaking.NewCooldowns(),
	}
	s.botsCtx, s.botsCancel = context.WithCancel(context.Background())
	return s
}

func burst(r float64) int { return max(1, int(math.Ceil(r))) }

// Run runs until ctx is cancelled (SIGINT/SIGTERM), a fatal error occurs
// (e.g. the backend refused load-test sessions) or the load-test duration
// elapses; then it shuts down gracefully and returns.
func (s *Service) Run(ctx context.Context) error {
	cfg := s.store.Config()
	if cfg.IsLoadtest() {
		if err := config.CheckLoadtestGuard(cfg, s.ack); err != nil {
			return err
		}
	}
	s.started = time.Now()
	s.ltTarget = cfg.Loadtest.TargetConnections
	if cfg.IsLoadtest() && s.m.Stats == nil {
		s.m.EnableLoadStats(s.started)
	}
	s.log.Info("bot-play starting", "environment", cfg.App.Environment, "modes", cfg.Bots.Modes,
		"enabled", cfg.Bots.Enabled, "target", cfg.EffectiveTarget(), "max_concurrent", cfg.Bots.MaxConcurrentBots)

	loopCtx, loopCancel := context.WithCancel(ctx)
	defer loopCancel()
	if _, err := s.client.ControllerToken(loopCtx); err != nil {
		s.log.Warn("controller token not available yet; will retry", "error", err.Error())
	}
	s.reconcile()
	s.goLoop(func() { s.configLoop(loopCtx) })
	s.goLoop(func() { s.reconcileLoop(loopCtx) })
	s.goLoop(func() { s.keepaliveLoop(loopCtx) })
	if cfg.IsLoadtest() {
		s.goLoop(func() { s.loadtestLoop(loopCtx) })
	} else {
		s.goLoop(func() { s.assignmentLoop(loopCtx) })
		s.goLoop(func() { s.fillLoop(loopCtx) })
	}

	var runErr error
	select {
	case <-ctx.Done():
		s.log.Info("shutdown requested")
	case runErr = <-s.fatal:
		s.log.Error("fatal error; shutting down", "error", runErr.Error())
	case <-s.ltDone:
		s.log.Info("load test duration elapsed; draining")
	}
	loopCancel()
	s.shutdown(runErr != nil)
	s.loopsWG.Wait()
	if cfg.IsLoadtest() {
		if err := s.writeReport(); err != nil {
			s.log.Error("failed to write load-test report", "error", err.Error())
		}
	}
	return runErr
}

func (s *Service) goLoop(f func()) {
	s.loopsWG.Add(1)
	go func() {
		defer s.loopsWG.Done()
		f()
	}()
}

func (s *Service) fail(err error) {
	s.fatalOnce.Do(func() { s.fatal <- err })
}

// shutdown stops new work and drains bots per bots.shutdown.policy within
// graceful_timeout_seconds; then forces the rest to leave.
func (s *Service) shutdown(force bool) {
	s.stopping.Store(true)
	cfg := s.store.Config()
	mode := RetireAfterGame
	if force || cfg.Bots.Shutdown.Policy == config.PolicyLeaveNow {
		mode = RetireNow
	}
	n := s.retireAll(mode)
	s.log.Info("draining bots", "bots", n, "policy", cfg.Bots.Shutdown.Policy, "timeout", cfg.Bots.Shutdown.GracefulTimeout().String())
	if waitTimeout(&s.wg, cfg.Bots.Shutdown.GracefulTimeout()) {
		s.botsCancel()
		return
	}
	s.log.Warn("graceful timeout reached; forcing remaining bots to leave", "bots", s.Count())
	s.retireAll(RetireNow)
	if waitTimeout(&s.wg, 5*time.Second) {
		s.botsCancel()
		return
	}
	s.botsCancel() // hard stop: abort connections (sessions are still revoked)
	if !waitTimeout(&s.wg, 15*time.Second) {
		s.log.Error("bots did not exit after hard stop", "bots", s.Count())
	}
}

func waitTimeout(wg *sync.WaitGroup, d time.Duration) bool {
	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-done:
		return true
	case <-t.C:
		return false
	}
}

func (s *Service) retireAll(mode RetireMode) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, b := range s.bots {
		b.Retire(mode)
	}
	return len(s.bots)
}

// Count returns the number of running bots.
func (s *Service) Count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.bots)
}

// Snapshot of per-game counts (for tests and metrics).
func (s *Service) CountsByGame() map[string]int {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make(map[string]int, len(s.byGame))
	for k, v := range s.byGame {
		out[k] = v
	}
	return out
}

// Ready implements /readyz: controller token valid and backend reachable.
func (s *Service) Ready() error {
	if !s.client.TokenValid() {
		return errors.New("controller token not valid")
	}
	stale := s.store.Config().Connection.ReadinessStale()
	if last := s.client.LastSuccess(); last.IsZero() || time.Since(last) > stale {
		return fmt.Errorf("backend not reached within %s", stale)
	}
	if s.inMaintenance() {
		return errors.New("backend reports maintenance")
	}
	return nil
}

// Maintenance back-off (503 / 4503): new work pauses; bots reconnect only
// after it ends, each with its own jittered delay (reconnect-storm guard).
func (s *Service) noteMaintenance() {
	d := client.Jitter(s.store.Config().Connection.MaintenanceBackoff(), 0.2)
	until := time.Now().Add(d).UnixNano()
	for {
		cur := s.maintUntil.Load()
		if cur >= until || s.maintUntil.CompareAndSwap(cur, until) {
			break
		}
	}
	s.m.ControllerReady.Set(0)
}

func (s *Service) inMaintenance() bool { return time.Now().UnixNano() < s.maintUntil.Load() }

func (s *Service) maintenanceRemaining() time.Duration {
	return time.Duration(s.maintUntil.Load() - time.Now().UnixNano())
}

// headroom returns how many more bots may start now.
func (s *Service) headroomLocked(cfg *config.Config) int {
	return max(0, cfg.EffectiveTarget()-len(s.bots))
}

func (s *Service) gameHeadroomLocked(cfg *config.Config) map[string]int {
	out := map[string]int{}
	for _, g := range config.GameKeys {
		out[g] = max(0, cfg.GameLimit(g)-s.byGame[g])
	}
	return out
}

func (s *Service) headroom() int {
	cfg := s.store.Config()
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.headroomLocked(cfg)
}

// register adds a bot under the lock (caller verified limits).
func (s *Service) registerLocked(b *Bot) {
	s.bots[b.id] = b
	s.byGame[b.game]++
	s.wg.Add(1)
}

func (s *Service) unregister(b *Bot) {
	s.mu.Lock()
	if _, ok := s.bots[b.id]; ok {
		delete(s.bots, b.id)
		s.byGame[b.game]--
	}
	s.mu.Unlock()
	s.publishActive()
}

// setGame moves a load-test bot between game buckets. It fails when the
// per-game limit would be exceeded.
func (s *Service) setGame(b *Bot, game string) bool {
	cfg := s.store.Config()
	s.mu.Lock()
	if b.game == game {
		s.mu.Unlock()
		return true
	}
	if game != gameNone && s.byGame[game] >= cfg.GameLimit(game) {
		s.mu.Unlock()
		return false
	}
	s.byGame[b.game]--
	s.byGame[game]++
	b.game = game
	s.mu.Unlock()
	s.publishActive()
	return true
}

func (s *Service) publishActive() {
	s.mu.Lock()
	by := make(map[string]int, len(s.byGame))
	for k, v := range s.byGame {
		by[k] = v
	}
	total := len(s.bots)
	s.mu.Unlock()
	s.m.SetActive(by, total)
}

func (s *Service) nextBotID() uint64 {
	s.nextID++
	return s.nextID
}

// admitAssignment decides whether to serve one backend assignment and, if
// so, starts its bot. It returns a rejection reason or "".
func (s *Service) admitAssignment(a client.Assignment) string {
	cfg := s.store.Config()
	if s.stopping.Load() {
		return "stopping"
	}
	if !cfg.Bots.Enabled {
		return "disabled"
	}
	var mode string
	switch a.Kind {
	case client.KindPractice, client.KindPrivate:
		mode = config.ModePractice
	case client.KindPublicFill:
		mode = config.ModePublicFill
	default:
		return "unknown_kind"
	}
	if !cfg.Bots.HasMode(mode) {
		return "mode_disabled"
	}
	key := config.GameKey(a.Game, a.Variant)
	if key == "" {
		return "unknown_game"
	}
	if !cfg.Bots.Games[key] {
		return "game_disabled"
	}
	if a.ID == "" || a.RoomID == "" {
		return "invalid"
	}
	if a.ExpiresAt > 0 && time.Now().UnixMilli() >= a.ExpiresAt {
		return "expired"
	}
	s.mu.Lock()
	if _, dup := s.seen[a.ID]; dup {
		s.mu.Unlock()
		return "duplicate"
	}
	if s.headroomLocked(cfg) <= 0 {
		s.mu.Unlock()
		return "at_capacity"
	}
	if s.byGame[key] >= cfg.GameLimit(key) {
		s.mu.Unlock()
		return "game_at_capacity"
	}
	s.seen[a.ID] = time.Now()
	b := s.newBotLocked(a.Kind, key, &a)
	s.registerLocked(b)
	s.mu.Unlock()
	s.publishActive()
	go b.run()
	return ""
}

func (s *Service) handleAssignments(list []client.Assignment, source string) {
	for _, a := range list {
		kind := a.Kind
		switch kind {
		case client.KindPractice, client.KindPrivate, client.KindPublicFill:
		default:
			kind = "other"
		}
		s.m.AssignmentsReceived.WithLabelValues(kind).Inc()
		if reason := s.admitAssignment(a); reason != "" {
			s.m.AssignmentsRejected.WithLabelValues(reason).Inc()
			s.log.Warn("assignment not served", "reason", reason, "source", source,
				"assignment_id", a.ID, "room_id", a.RoomID, "kind", a.Kind, "game", a.Game, "variant", a.Variant)
		}
	}
	s.pruneSeen()
}

func (s *Service) pruneSeen() {
	s.mu.Lock()
	defer s.mu.Unlock()
	cutoff := time.Now().Add(-10 * time.Minute)
	for id, t := range s.seen {
		if t.Before(cutoff) {
			delete(s.seen, id)
		}
	}
}

// reconcile applies the population target: when the service is disabled or
// over target, excess bots retire (after their game, or immediately with
// shutdown policy leave_now).
func (s *Service) reconcile() {
	cfg := s.store.Config()
	target := cfg.EffectiveTarget()
	s.m.BotsTarget.Set(float64(target))
	s.joinLim.SetLimit(rate.Limit(cfg.Bots.MaxRoomJoinsPerSecond))
	s.joinLim.SetBurst(burst(cfg.Bots.MaxRoomJoinsPerSecond))
	s.connLim.SetLimit(rate.Limit(cfg.Bots.MaxConnectionAttemptsPerSecond))
	s.connLim.SetBurst(burst(cfg.Bots.MaxConnectionAttemptsPerSecond))
	if s.stopping.Load() {
		return
	}
	mode := RetireAfterGame
	if cfg.Bots.Shutdown.Policy == config.PolicyLeaveNow {
		mode = RetireNow
	}
	s.mu.Lock()
	var active []*Bot
	for _, b := range s.bots {
		if b.RetireMode() == RetireNone {
			active = append(active, b)
		}
	}
	excess := len(active) - target
	if excess > 0 {
		// Prefer bots that are not in a running game, then the newest.
		sort.Slice(active, func(i, j int) bool {
			gi, gj := active[i].inGame.Load(), active[j].inGame.Load()
			if gi != gj {
				return !gi
			}
			return active[i].id > active[j].id
		})
		for _, b := range active[:excess] {
			b.Retire(mode)
		}
	}
	s.mu.Unlock()
	if excess > 0 {
		s.log.Info("population above target; retiring bots", "excess", excess, "target", target, "mode", mode.String())
	}
}

func (s *Service) reconcileLoop(ctx context.Context) {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			s.reconcile()
			s.publishActive()
		}
	}
}

func (s *Service) configLoop(ctx context.Context) {
	ch := s.store.Subscribe()
	for {
		select {
		case <-ctx.Done():
			return
		case snap := <-ch:
			cfg := snap.Config
			s.log.Info("applying configuration", "generation", snap.Generation, "enabled", cfg.Bots.Enabled,
				"modes", cfg.Bots.Modes, "target", cfg.EffectiveTarget(), "max_concurrent", cfg.Bots.MaxConcurrentBots)
			s.reconcile()
		}
	}
}

// keepaliveLoop keeps the controller token fresh and probes reachability so
// /readyz reflects reality even when no other calls are being made.
func (s *Service) keepaliveLoop(ctx context.Context) {
	t := time.NewTicker(5 * time.Second)
	defer t.Stop()
	for {
		ready := s.Ready() == nil
		if ready {
			s.m.ControllerReady.Set(1)
		} else {
			s.m.ControllerReady.Set(0)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		cfg := s.store.Config()
		if _, err := s.client.ControllerToken(ctx); err != nil {
			s.noteBackendError(err)
			continue
		}
		if time.Since(s.client.LastSuccess()) > cfg.Connection.ReadinessStale()/2 {
			if err := s.client.Ping(ctx); err != nil {
				s.noteBackendError(err)
			}
		}
	}
}

func (s *Service) noteBackendError(err error) {
	if client.IsMaintenance(err) {
		s.noteMaintenance()
	}
	if errors.Is(err, context.Canceled) {
		return
	}
	s.log.Debug("backend call failed", "error", err.Error())
}

func (s *Service) backendHost() string {
	u, err := url.Parse(s.store.Config().Connection.BackendHTTPURL)
	if err != nil {
		return ""
	}
	return u.Hostname()
}

func (s *Service) writeReport() error {
	if s.m.Stats == nil {
		return nil
	}
	cfg := s.store.Config()
	r := s.m.Stats.Build(cfg.App.Environment, s.backendHost(), s.ltTarget, cfg.Loadtest.TargetConnections, time.Now())
	if err := r.WriteFile(cfg.Loadtest.ReportPath); err != nil {
		return err
	}
	s.log.Info("load-test report written", "path", cfg.Loadtest.ReportPath, "peak_connections", r.PeakConnections,
		"games_finished", r.GamesFinished, "hash_mismatches", r.HashMismatches, "actions_per_second", r.ActionsPerSecond)
	return nil
}

func randomSeed() uint64 { return rand.Uint64() }
