// Package analytics keeps privacy-conscious aggregate product signals:
//
//   - Active users: daily / weekly Redis HyperLogLog sketches of a keyed
//     pseudonym, HMAC-SHA256(key, accountID). Raw account ids never enter the
//     sketches, the key is a server secret (ACTIVE_USER_KEY), and an HLL cannot
//     be enumerated, so the data answers only "about how many".
//   - Client telemetry: whitelisted counters (client errors, state-hash
//     mismatches, reconnect outcomes) that only increment Prometheus metrics;
//     nothing is stored per user or per request.
//
// Humans only: callers must invoke Touch for human accounts only (never for
// bot sessions); this package cannot tell them apart.
package analytics

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/ratelimit"
)

// sketchTTL keeps a day sketch long enough for "yesterday" and a week sketch
// for the following weeks' comparisons.
const sketchTTL = 40 * 24 * time.Hour

// Tracker records active-user sketches and serves the telemetry endpoint.
type Tracker struct {
	rdb      *redis.Client
	key      []byte
	log      *slog.Logger
	now      func() time.Time
	interval time.Duration
}

// New returns a Tracker. key is the HMAC secret for pseudonyms (>= 32 bytes
// recommended; config.Telemetry.ActiveUserKey).
func New(rdb *redis.Client, key []byte, log *slog.Logger) *Tracker {
	if log == nil {
		log = slog.Default()
	}
	return &Tracker{rdb: rdb, key: key, log: log, now: time.Now, interval: time.Minute}
}

// SetClock overrides the clock (tests).
func (t *Tracker) SetClock(now func() time.Time) { t.now = now }

// DayKey is the daily sketch key, e.g. au:d:20261021 (UTC).
func DayKey(at time.Time) string { return "au:d:" + at.UTC().Format("20060102") }

// WeekKey is the ISO-week sketch key, e.g. au:w:2026-W43 (UTC).
func WeekKey(at time.Time) string {
	y, w := at.UTC().ISOWeek()
	return fmt.Sprintf("au:w:%04d-W%02d", y, w)
}

// pseudonym is HMAC-SHA256(key, accountID) as hex.
func (t *Tracker) pseudonym(userID uuid.UUID) string {
	m := hmac.New(sha256.New, t.key)
	m.Write(userID[:])
	return hex.EncodeToString(m.Sum(nil))
}

// Touch marks a human account active today and this week. Call it for humans
// only (e.g. on sign-in / refresh / WebSocket connect).
func (t *Tracker) Touch(ctx context.Context, userID uuid.UUID) error {
	now := t.now()
	p := t.pseudonym(userID)
	day, week := DayKey(now), WeekKey(now)
	pipe := t.rdb.Pipeline()
	pipe.PFAdd(ctx, day, p)
	pipe.Expire(ctx, day, sketchTTL)
	pipe.PFAdd(ctx, week, p)
	pipe.Expire(ctx, week, sketchTTL)
	_, err := pipe.Exec(ctx)
	return err
}

// Estimates are approximate (HyperLogLog, ~0.81% standard error) counts.
type Estimates struct {
	Day  int64 // distinct humans active today (UTC)
	Week int64 // distinct humans active this ISO week
	// Returning approximates humans active yesterday AND today:
	// |Y ∩ T| = |Y| + |T| − |Y ∪ T| (inclusion–exclusion on PFCOUNT). The
	// error of the intersection is relative to the union, so it is coarse for
	// small populations; it is clamped to [0, min(|Y|, |T|)].
	Returning int64
}

// Estimates reads the current sketches.
func (t *Tracker) Estimates(ctx context.Context) (Estimates, error) {
	now := t.now()
	today, yesterday := DayKey(now), DayKey(now.AddDate(0, 0, -1))
	pipe := t.rdb.Pipeline()
	d := pipe.PFCount(ctx, today)
	w := pipe.PFCount(ctx, WeekKey(now))
	y := pipe.PFCount(ctx, yesterday)
	u := pipe.PFCount(ctx, yesterday, today)
	if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, redis.Nil) {
		return Estimates{}, err
	}
	e := Estimates{Day: d.Val(), Week: w.Val()}
	ret := y.Val() + d.Val() - u.Val()
	if ret < 0 {
		ret = 0
	}
	if m := min(y.Val(), d.Val()); ret > m {
		ret = m
	}
	e.Returning = ret
	return e, nil
}

// Update refreshes the gauges once.
func (t *Tracker) Update(ctx context.Context) error {
	e, err := t.Estimates(ctx)
	if err != nil {
		return err
	}
	metrics.ActiveUsers.WithLabelValues("day").Set(float64(e.Day))
	metrics.ActiveUsers.WithLabelValues("week").Set(float64(e.Week))
	metrics.ReturningUsers.WithLabelValues("day").Set(float64(e.Returning))
	return nil
}

// Run refreshes active_users_estimate{window="day"|"week"} and
// returning_users_estimate{window="day"} every minute until ctx ends.
func (t *Tracker) Run(ctx context.Context) {
	tick := time.NewTicker(t.interval)
	defer tick.Stop()
	for {
		if err := t.Update(ctx); err != nil && ctx.Err() == nil {
			t.log.Warn("active user estimates unavailable", "error", err.Error())
		}
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}

// ---------------------------------------------------------------- telemetry

// Telemetry limits.
const (
	maxTelemetryEvents = 8
	maxTelemetryCount  = 20
)

// Register adds POST /api/v1/telemetry/events (no authentication, rate
// limited per IP, version gated).
func (t *Tracker) Register(rt *httpapi.Router) {
	ip := ratelimit.TelemetryPerIP
	rt.Handle("POST /api/v1/telemetry/events", httpapi.Route{Gate: true, IPRule: &ip, MaxBody: 2 << 10}, t.handleTelemetry)
}

// IncrementTelemetry applies one whitelisted event to the aggregate metrics.
// Unknown kinds and counts < 1 are ignored (reported as false); counts are
// capped at 20 per event.
func IncrementTelemetry(kind string, count int) bool {
	if count < 1 {
		return false
	}
	if count > maxTelemetryCount {
		count = maxTelemetryCount
	}
	switch kind {
	case "client_error", "hash_mismatch":
		metrics.ClientErrors.WithLabelValues(kind).Add(float64(count))
	case "reconnect_success":
		metrics.ReconnectResults.WithLabelValues("success").Add(float64(count))
	case "reconnect_failure":
		metrics.ReconnectResults.WithLabelValues("failure").Add(float64(count))
	default:
		return false
	}
	return true
}

func (t *Tracker) handleTelemetry(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Events []struct {
			Kind  string `json:"kind"`
			Count int    `json:"count"`
		} `json:"events"`
	}
	if err := httpapi.DecodeJSON(r, &body); err != nil {
		return err
	}
	if len(body.Events) == 0 || len(body.Events) > maxTelemetryEvents {
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "events must contain 1-8 entries.")
	}
	accepted := 0
	for _, e := range body.Events {
		if IncrementTelemetry(e.Kind, e.Count) {
			accepted++
		}
	}
	httpapi.WriteJSON(w, http.StatusAccepted, map[string]int{"accepted": accepted})
	return nil
}
