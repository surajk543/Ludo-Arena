package runner

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"golang.org/x/time/rate"

	"ludoroyale/botplay/internal/client"
	"ludoroyale/botplay/internal/config"
	"ludoroyale/botplay/internal/connection"
	"ludoroyale/botplay/internal/strategy"
)

const gameNone = "none"

// RetireMode tells a bot how to wind down.
type RetireMode int32

const (
	// RetireNone: keep working.
	RetireNone RetireMode = iota
	// RetireAfterGame: finish the current game (or leave a load-test
	// matchmaking lobby immediately), then exit.
	RetireAfterGame
	// RetireNow: leave the room immediately (forfeits a running game), then exit.
	RetireNow
)

func (m RetireMode) String() string {
	return [...]string{"none", "after_game", "now"}[m]
}

// Bot is one bot session and its game loop.
type Bot struct {
	id         uint64
	svc        *Service
	kind       string // practice | private | public_fill | loadtest
	assignment *client.Assignment
	game       string // config game key or "none"; guarded by svc.mu
	name       string
	log        *slog.Logger
	strat      *strategy.Strategy
	actLim     *rate.Limiter
	reconnLim  *rate.Limiter
	slowReader bool

	retire    atomic.Int32
	retireCh  chan struct{}
	churnCh   chan struct{}
	connected atomic.Bool
	inGame    atomic.Bool

	session *client.Session

	// Game-loop state; owned by the bot goroutine.
	g gameState
}

func (s *Service) newBotLocked(kind, game string, a *client.Assignment) *Bot {
	cfg := s.store.Config()
	id := s.nextBotID()
	seed := randomSeed()
	if cfg.Bots.Behavior.RandomSeed != 0 {
		seed = uint64(cfg.Bots.Behavior.RandomSeed) + id*0x9e3779b97f4a7c15
	}
	b := &Bot{
		id: id, svc: s, kind: kind, assignment: a, game: game,
		strat:     strategy.New(seed),
		actLim:    rate.NewLimiter(rate.Limit(cfg.Limits.MaxActionsPerSecondPerBot), 2),
		reconnLim: rate.NewLimiter(rate.Limit(float64(cfg.Limits.MaxReconnectAttemptsPerMinute)/60), cfg.Limits.MaxReconnectAttemptsPerMinute),
		retireCh:  make(chan struct{}, 1),
		churnCh:   make(chan struct{}, 1),
	}
	b.name = b.pickName(cfg)
	attrs := []any{"bot_id", id, "kind", kind}
	if a != nil {
		attrs = append(attrs, "assignment_id", a.ID, "room_id", a.RoomID, "game", game)
	}
	b.log = s.log.With(attrs...)
	b.g.mySeat = -1
	return b
}

func (b *Bot) pickName(cfg *config.Config) string {
	id := cfg.Bots.Identity
	var base string
	if len(id.NamesPool) > 0 {
		base = id.NamesPool[b.strat.IntN(len(id.NamesPool))]
	} else {
		base = fmt.Sprintf("%04d", b.strat.IntN(10000))
	}
	if id.DisplayNamePrefix == "" {
		return base
	}
	return id.DisplayNamePrefix + " " + base
}

// Retire asks the bot to wind down (the strongest requested mode wins).
func (b *Bot) Retire(mode RetireMode) {
	for {
		cur := b.retire.Load()
		if int32(mode) <= cur {
			return
		}
		if b.retire.CompareAndSwap(cur, int32(mode)) {
			break
		}
	}
	select {
	case b.retireCh <- struct{}{}:
	default:
	}
}

// RetireMode returns the current retire request.
func (b *Bot) RetireMode() RetireMode { return RetireMode(b.retire.Load()) }

// Churn asks a load-test bot to drop its connection and reconnect.
func (b *Bot) Churn() {
	select {
	case b.churnCh <- struct{}{}:
	default:
	}
}

// run is the bot goroutine: create the session, connect, play, reconnect
// as needed, and always revoke the session on exit.
func (b *Bot) run() {
	defer b.svc.wg.Done()
	defer b.svc.unregister(b)
	ctx := b.svc.botsCtx
	if err := b.createSession(ctx); err != nil {
		return
	}
	defer b.revoke()

	attempt := 0       // consecutive failed connection attempts
	reconnect := false // a connection was established before (X-Reconnect: 1)
	for ctx.Err() == nil {
		cfg := b.svc.store.Config()
		if (attempt > 0 || reconnect) && !b.mayReconnect(cfg, attempt) {
			return
		}
		if err := b.waitToDial(ctx, cfg, attempt); err != nil {
			return
		}
		conn, hs, err := connection.Dial(ctx, b.dialOptions(cfg, reconnect))
		if err != nil {
			if reconnect {
				b.svc.m.RecordReconnect(false)
			}
			fatal, minDelay := b.classifyDialError(err)
			if fatal {
				return
			}
			b.g.minDelay = minDelay
			attempt++
			continue
		}
		b.svc.m.RecordCompression(hs.Compression)
		b.connected.Store(true)
		start := time.Now()
		res := b.serve(ctx, conn, reconnect)
		b.connected.Store(false)
		if res.done {
			return
		}
		if time.Since(start) >= cfg.Connection.ReconnectReset() {
			attempt = 0
		}
		fatal, minDelay := b.classifyClose(res.info)
		if fatal {
			return
		}
		b.g.minDelay = minDelay
		reconnect = true
		attempt++
	}
}

func (b *Bot) dialOptions(cfg *config.Config, reconnect bool) connection.DialOptions {
	v, build := config.ClientVersion()
	o := connection.DialOptions{
		URL: cfg.Connection.BackendWSURL, Token: b.session.AccessToken,
		Version: v, Build: build, Reconnect: reconnect,
		ConnectTimeout: cfg.Connection.ConnectTimeout(),
		QueueSize:      cfg.Connection.OutboundQueueSize,
		PingInterval:   cfg.Connection.PingInterval(),
		PongTimeout:    cfg.Connection.PongTimeout(),
		ReadLimit:      int64(cfg.Connection.ReadLimitBytes),
		Compression:    cfg.Connection.CompressionMode,
		OnBytes:        b.svc.m.RecordBytes,
		HTTPClient:     b.svc.wsHC,
	}
	if b.slowReader {
		o.SlowReadDelay = time.Duration(cfg.Loadtest.SlowReaderDelayMS) * time.Millisecond
	}
	return o
}

// mayReconnect applies reconnect policy: enabled, attempt budget, service
// enabled (disabled bots stop reconnecting into rooms), not retiring now.
func (b *Bot) mayReconnect(cfg *config.Config, attempt int) bool {
	switch {
	case !cfg.Connection.ReconnectEnabled:
		b.log.Info("connection lost; reconnect disabled")
	case attempt > cfg.Connection.ReconnectMaxAttempts:
		b.log.Warn("connection lost; reconnect attempts exhausted", "attempts", attempt)
	case !cfg.Bots.Enabled:
		b.log.Info("connection lost; bots disabled, not reconnecting")
	case b.RetireMode() == RetireNow:
		b.log.Info("connection lost while retiring; not reconnecting")
	case b.svc.stopping.Load() && b.RetireMode() != RetireNone && !b.inGame.Load():
		b.log.Info("connection lost during shutdown; not reconnecting")
	default:
		return true
	}
	return false
}

// waitToDial applies backoff (full jitter), the per-bot reconnect budget,
// maintenance back-off with per-bot staggering, and the global
// connection-attempt limiter.
func (b *Bot) waitToDial(ctx context.Context, cfg *config.Config, attempt int) error {
	var d time.Duration
	if attempt > 0 {
		bo := client.Backoff{Base: cfg.Connection.BackoffBase(), Max: cfg.Connection.BackoffMax()}
		d = bo.Delay(attempt - 1)
	}
	d = max(d, b.g.minDelay)
	b.g.minDelay = 0
	if rem := b.svc.maintenanceRemaining(); rem > 0 {
		// Wait out maintenance, then spread reconnects over the back-off window.
		d = max(d, rem+client.FullJitter(cfg.Connection.MaintenanceBackoff()))
	}
	if err := client.Sleep(ctx, d); err != nil {
		return err
	}
	if attempt > 0 {
		if r := b.reconnLim.Reserve(); r.OK() {
			if err := client.Sleep(ctx, r.Delay()); err != nil {
				r.Cancel()
				return err
			}
		}
	}
	return b.svc.connLim.Wait(ctx)
}

// classifyDialError maps an upgrade rejection to (fatal, minimum delay).
func (b *Bot) classifyDialError(err error) (bool, time.Duration) {
	var de *connection.DialError
	if !errors.As(err, &de) {
		b.svc.m.RecordConnFailure("dial_error")
		b.log.Warn("dial failed", "error", err.Error())
		return false, 0
	}
	switch de.Status {
	case 0:
		b.svc.m.RecordConnFailure("dial_error")
		b.log.Warn("dial failed", "error", de.Error())
		return false, 0
	case http.StatusUnauthorized:
		b.svc.m.RecordConnFailure("unauthorized")
		b.log.Warn("upgrade rejected: bot session invalid or expired")
		return true, 0
	case http.StatusServiceUnavailable:
		b.svc.m.RecordConnFailure("maintenance")
		b.svc.noteMaintenance()
		b.log.Info("upgrade rejected: maintenance; backing off")
		return false, de.RetryAfter
	case http.StatusTooManyRequests:
		b.svc.m.RecordConnFailure("rate_limited")
		return false, max(de.RetryAfter, 10*time.Second)
	case http.StatusUpgradeRequired:
		b.svc.m.RecordConnFailure("update_required")
		b.log.Error("upgrade rejected with update_required; bots should be exempt from version policy")
		return true, 0
	case http.StatusBadRequest:
		b.svc.m.RecordConnFailure("bad_request")
		b.log.Error("upgrade rejected as bad request; not retrying (bug)", "code", de.Code)
		return true, 0
	default:
		b.svc.m.RecordConnFailure("rejected")
		b.log.Warn("upgrade rejected", "status", de.Status, "code", de.Code)
		return de.Status < 500, 0
	}
}

// classifyClose maps a close code to (fatal, minimum delay) per the
// protocol's close code table.
func (b *Bot) classifyClose(info connection.CloseInfo) (bool, time.Duration) {
	reason := closeReason(info.Code)
	if info.Local && info.Code == connection.CloseLocal {
		reason = "local"
	}
	if reason != "local" {
		b.svc.m.RecordConnFailure(reason)
	}
	b.log.Info("connection closed", "code", info.Code, "reason", reason)
	switch info.Code {
	case connection.CloseReplaced:
		b.log.Warn("session replaced by a newer connection (4409); not reconnecting")
		return true, 0
	case connection.CloseRevoked:
		b.log.Warn("bot session revoked or expired (4401); exiting")
		return true, 0
	case connection.CloseVersion:
		b.log.Error("closed with 4426; bots should be exempt from version policy")
		return true, 0
	case connection.CloseMaintenance:
		b.svc.noteMaintenance()
		return false, 0
	case connection.CloseRateLimited:
		return false, 10 * time.Second
	}
	return false, 0
}

func closeReason(code int) string {
	switch code {
	case connection.CloseGoingAway:
		return "server_shutdown"
	case connection.ClosePolicy:
		return "policy_violation"
	case connection.CloseProtocol:
		return "protocol_violation"
	case connection.CloseRevoked:
		return "revoked"
	case connection.CloseReplaced:
		return "replaced"
	case connection.CloseVersion:
		return "version"
	case connection.CloseRateLimited:
		return "rate_limited"
	case connection.CloseMaintenance:
		return "maintenance"
	case connection.CloseSlowConsumer:
		return "slow_consumer"
	case connection.CloseAbnormal:
		return "abnormal"
	case connection.ClosePongTimeout:
		return "pong_timeout"
	case connection.CloseQueueOverflow:
		return "queue_overflow"
	case connection.CloseWriteError:
		return "write_error"
	case connection.CloseHandshakeError:
		return "no_ready"
	case connection.CloseLocal:
		return "local"
	case connection.CloseNormal:
		return "normal"
	default:
		return "other"
	}
}

// createSession performs POST /bot/sessions with bounded retries.
func (b *Bot) createSession(ctx context.Context) error {
	cfg := b.svc.store.Config()
	req := client.SessionRequest{Name: b.name}
	if b.assignment != nil {
		req.AssignmentID = b.assignment.ID
		req.Profile = cfg.Bots.Behavior.DefaultProfile
	} else {
		req.Mode = config.ModeLoadtest
	}
	bo := client.Backoff{Base: cfg.Connection.BackoffBase(), Max: 5 * time.Second}
	for attempt := 0; ; attempt++ {
		if err := b.waitJoinSlot(ctx); err != nil {
			return err
		}
		sess, err := b.svc.client.CreateSession(ctx, req)
		if err == nil {
			b.session = sess
			b.svc.m.RecordSession(true)
			if b.kind == client.KindLoadtest {
				b.svc.noteSessionResult(true)
			} else {
				b.svc.m.RoomJoins.WithLabelValues(b.kind).Inc()
			}
			b.g.roomID = sess.RoomID
			if b.g.roomID == "" && b.assignment != nil {
				b.g.roomID = b.assignment.RoomID
			}
			b.log = b.log.With("uid", sess.UID)
			b.log.Info("bot session created", "name", b.name)
			return nil
		}
		b.svc.m.RecordSession(false)
		if ctx.Err() != nil {
			return ctx.Err()
		}
		var ae *client.APIError
		isAPI := errors.As(err, &ae)
		if b.kind == client.KindLoadtest {
			b.svc.noteSessionResult(false)
			if isAPI && (ae.Status == http.StatusForbidden || (ae.Status == http.StatusBadRequest && strings.Contains(ae.Code, "environment"))) {
				b.svc.fail(&config.GuardError{Reason: config.GuardBackendRefused,
					Detail: fmt.Sprintf("backend refused load-test sessions (%d %s: %s); it refuses them when APP_ENV=production or BOT_LOADTEST_ENABLED=false", ae.Status, ae.Code, ae.Message)})
				return err
			}
		}
		if client.IsMaintenance(err) {
			b.svc.noteMaintenance()
		}
		retryable := !isAPI || ae.Retryable()
		if !retryable || attempt >= 2 {
			b.log.Warn("bot session not created", "error", err.Error())
			return err
		}
		if b.assignment != nil && b.assignment.ExpiresAt > 0 && time.Now().UnixMilli() >= b.assignment.ExpiresAt {
			b.log.Warn("assignment expired before session creation")
			return err
		}
		if err := client.Sleep(ctx, max(bo.Delay(attempt), client.RetryAfter(err))); err != nil {
			return err
		}
	}
}

// waitJoinSlot applies bots.max_room_joins_per_second to session creation
// (each assignment session seats the bot in a room).
func (b *Bot) waitJoinSlot(ctx context.Context) error {
	if b.kind == client.KindLoadtest {
		return nil // load-test joins are limited at matchmaking.join time
	}
	wctx := ctx
	if b.assignment != nil && b.assignment.ExpiresAt > 0 {
		var cancel context.CancelFunc
		wctx, cancel = context.WithDeadline(ctx, time.UnixMilli(b.assignment.ExpiresAt))
		defer cancel()
	}
	return b.svc.joinLim.Wait(wctx)
}

// revoke performs DELETE /bot/sessions/{uid} with a fresh context so it runs
// even during shutdown.
func (b *Bot) revoke() {
	if b.session == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := b.svc.client.RevokeSession(ctx, b.session.UID); err != nil {
		b.log.Warn("session revoke failed", "error", err.Error())
		return
	}
	b.log.Info("bot session revoked")
}
