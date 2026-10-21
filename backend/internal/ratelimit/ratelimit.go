// Package ratelimit implements fixed-window rate limits shared by all backend
// instances through Redis.
package ratelimit

import (
	"context"
	"log/slog"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

// Rule is a named limit: at most Limit events per Window per key.
type Rule struct {
	Name   string
	Limit  int
	Window time.Duration
}

// Common rules (documented in docs/architecture.md → Security).
var (
	AuthPerIP        = Rule{"auth_ip", 30, time.Minute}
	GuestCreatePerIP = Rule{"guest_ip", 10, time.Hour}
	RefreshPerIP     = Rule{"refresh_ip", 60, time.Minute}
	PolicyPerIP      = Rule{"policy_ip", 120, time.Minute}
	LinkPerUser      = Rule{"link_user", 10, time.Minute}
	RoomCodePerUser  = Rule{"room_code_user", 10, time.Minute}
	MatchmakePerUser = Rule{"matchmake_user", 20, time.Minute}
	WalletOpPerUser  = Rule{"wallet_user", 30, time.Minute}
	SocialPerUser    = Rule{"social_user", 30, time.Minute}
	WSConnectPerUser = Rule{"ws_connect_user", 30, time.Minute}
	BotServicePerIP  = Rule{"bot_service_ip", 600, time.Minute}
	TelemetryPerIP   = Rule{"telemetry_ip", 60, time.Minute}
)

var script = redis.NewScript(`
local n = redis.call('INCR', KEYS[1])
if n == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]) end
return n`)

// Limiter checks rules against Redis counters.
type Limiter struct {
	rdb      *redis.Client
	log      *slog.Logger
	disabled bool
	now      func() time.Time
}

// New returns a limiter. When disabled is true every check passes (local
// load tests only; refused in production by config validation upstream).
func New(rdb *redis.Client, log *slog.Logger, disabled bool) *Limiter {
	return &Limiter{rdb: rdb, log: log, disabled: disabled, now: time.Now}
}

// Allow counts one event for key under rule. It fails open on Redis errors
// (logged) because the game itself is unavailable when Redis is down.
func (l *Limiter) Allow(ctx context.Context, rule Rule, key string) (bool, time.Duration) {
	if l == nil || l.disabled {
		return true, 0
	}
	now := l.now()
	window := now.UnixMilli() / rule.Window.Milliseconds()
	k := "rl:" + rule.Name + ":" + key + ":" + strconv.FormatInt(window, 10)
	n, err := script.Run(ctx, l.rdb, []string{k}, rule.Window.Milliseconds()).Int()
	if err != nil {
		l.log.Warn("rate limiter unavailable", "rule", rule.Name, "error", err.Error())
		return true, 0
	}
	if n > rule.Limit {
		retry := time.Duration((window+1)*rule.Window.Milliseconds()-now.UnixMilli()) * time.Millisecond
		return false, retry
	}
	return true, 0
}
