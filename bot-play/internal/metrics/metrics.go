// Package metrics defines bot-play's Prometheus metrics and the load-test
// statistics aggregator. Label values are always drawn from small fixed sets
// (never room ids, uids or assignment ids) to keep cardinality bounded.
package metrics

import (
	"slices"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
)

// KnownErrorCodes is the documented WebSocket error code set
// (docs/websocket-protocol.md §9). Anything else is reported as "other".
var KnownErrorCodes = []string{
	"bad_request", "unknown_type", "rate_limited", "unauthorized",
	"update_required", "maintenance", "not_in_room", "room_not_found",
	"room_full", "room_in_progress", "room_closed", "already_in_room",
	"not_host", "not_enough_players", "players_not_ready", "not_your_turn",
	"invalid_phase", "illegal_move", "stale_state", "insufficient_funds",
	"invalid_code", "rematch_closed", "not_friends", "item_not_owned",
	"bots_unavailable", "bots_not_allowed", "internal",
}

// BoundCode maps an error code onto the bounded label set.
func BoundCode(code string) string {
	if slices.Contains(KnownErrorCodes, code) {
		return code
	}
	return "other"
}

// Metrics bundles every collector on a private registry.
type Metrics struct {
	Registry *prometheus.Registry

	BotsActive              *prometheus.GaugeVec
	BotsTarget              prometheus.Gauge
	ConnectionFailures      *prometheus.CounterVec
	MatchmakingJoinAttempts prometheus.Counter
	RoomJoins               *prometheus.CounterVec
	GameActions             *prometheus.CounterVec
	InvalidActionResponses  *prometheus.CounterVec
	Reconnects              *prometheus.CounterVec
	ActionLatency           *prometheus.HistogramVec
	ConfigReloads           *prometheus.CounterVec
	ConfigReloadFailures    prometheus.Counter
	CompressionNegotiated   *prometheus.CounterVec
	WSBytesReceived         prometheus.Counter
	StateResyncs            *prometheus.CounterVec
	HashMismatches          prometheus.Counter
	EventsIgnored           *prometheus.CounterVec
	AssignmentsReceived     *prometheus.CounterVec
	AssignmentsRejected     *prometheus.CounterVec
	FillRequests            *prometheus.CounterVec
	BotSessions             *prometheus.CounterVec
	GamesStarted            *prometheus.CounterVec
	GamesFinished           *prometheus.CounterVec
	ControllerTokens        *prometheus.CounterVec
	ChatMessages            *prometheus.CounterVec
	MalformedSent           *prometheus.CounterVec
	ControllerReady         prometheus.Gauge
	ResyncVerifications     *prometheus.CounterVec

	// Stats is non-nil in load-test mode; every Record* call also feeds it.
	Stats *LoadStats
}

// New creates the metrics on a fresh registry (with Go runtime and process
// collectors).
func New() *Metrics {
	r := prometheus.NewRegistry()
	m := &Metrics{Registry: r}
	f := func(c prometheus.Collector) { r.MustRegister(c) }

	m.BotsActive = prometheus.NewGaugeVec(prometheus.GaugeOpts{Name: "bots_active", Help: "Running bot sessions by game (game=none: load-test bot between games)."}, []string{"game"})
	m.BotsTarget = prometheus.NewGauge(prometheus.GaugeOpts{Name: "bots_target", Help: "Effective bot population target."})
	m.ConnectionFailures = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "bot_connection_failures_total", Help: "WebSocket connection failures by reason."}, []string{"reason"})
	m.MatchmakingJoinAttempts = prometheus.NewCounter(prometheus.CounterOpts{Name: "matchmaking_join_attempts_total", Help: "matchmaking.join commands sent (load test)."})
	m.RoomJoins = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "room_joins_total", Help: "Bots seated in a room by kind."}, []string{"kind"})
	m.GameActions = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "game_actions_total", Help: "Commands sent by type."}, []string{"type"})
	m.InvalidActionResponses = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "invalid_action_responses_total", Help: "Server error responses by code."}, []string{"code"})
	m.Reconnects = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "reconnects_total", Help: "Bot reconnect attempts by result."}, []string{"result"})
	m.ActionLatency = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "action_latency_seconds",
		Help:    "Command sent -> authoritative server event.",
		Buckets: []float64{.002, .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5},
	}, []string{"action"})
	m.ConfigReloads = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "config_reloads_total", Help: "Config reload attempts by result."}, []string{"result"})
	m.ConfigReloadFailures = prometheus.NewCounter(prometheus.CounterOpts{Name: "config_reload_failures_total", Help: "Rejected config reloads (last valid config kept)."})
	m.CompressionNegotiated = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "compression_negotiated_total", Help: "WebSocket connections by permessage-deflate negotiation result."}, []string{"result"})
	m.WSBytesReceived = prometheus.NewCounter(prometheus.CounterOpts{Name: "ws_bytes_received_total", Help: "WebSocket payload bytes received after decompression."})
	m.StateResyncs = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "state_resyncs_total", Help: "game.request_sync sent by reason."}, []string{"reason"})
	m.HashMismatches = prometheus.NewCounter(prometheus.CounterOpts{Name: "state_hash_mismatches_total", Help: "Local state hash differed from the server h."})
	m.EventsIgnored = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "events_ignored_total", Help: "Versioned events ignored by reason."}, []string{"reason"})
	m.AssignmentsReceived = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "assignments_received_total", Help: "Assignments received from the backend by kind."}, []string{"kind"})
	m.AssignmentsRejected = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "assignments_rejected_total", Help: "Assignments not served by reason."}, []string{"reason"})
	m.FillRequests = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "public_fill_requests_total", Help: "Public lobby fill requests by result."}, []string{"result"})
	m.BotSessions = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "bot_sessions_total", Help: "Bot session creations by result."}, []string{"result"})
	m.GamesStarted = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "games_started_total", Help: "Games started with a bot seated, by game."}, []string{"game"})
	m.GamesFinished = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "games_finished_total", Help: "Games finished with a bot seated, by game."}, []string{"game"})
	m.ControllerTokens = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "controller_token_refreshes_total", Help: "Controller token fetches by result."}, []string{"result"})
	m.ChatMessages = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "chat_messages_total", Help: "Quick-chat / emote reactions by kind (quick|emote) and result (sent|rejected|dropped)."}, []string{"kind", "result"})
	m.MalformedSent = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "loadtest_malformed_sent_total", Help: "Deliberately malformed messages sent (load test)."}, []string{"kind"})
	m.ResyncVerifications = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "reconnect_resync_verifications_total", Help: "Post-reconnect snapshot verification (v not regressed, hash matches) by result."}, []string{"result"})
	m.ControllerReady = prometheus.NewGauge(prometheus.GaugeOpts{Name: "controller_ready", Help: "1 when the controller token is valid and the backend was reached recently."})

	for _, c := range []prometheus.Collector{
		m.BotsActive, m.BotsTarget, m.ConnectionFailures, m.MatchmakingJoinAttempts, m.RoomJoins,
		m.GameActions, m.InvalidActionResponses, m.Reconnects, m.ActionLatency, m.ConfigReloads,
		m.ConfigReloadFailures, m.CompressionNegotiated, m.WSBytesReceived, m.StateResyncs,
		m.HashMismatches, m.EventsIgnored, m.AssignmentsReceived, m.AssignmentsRejected,
		m.FillRequests, m.BotSessions, m.GamesStarted, m.GamesFinished, m.ControllerTokens,
		m.ChatMessages, m.MalformedSent, m.ControllerReady, m.ResyncVerifications,
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	} {
		f(c)
	}
	m.ConfigReloadFailures.Add(0)
	m.HashMismatches.Add(0)
	return m
}

// EnableLoadStats turns on load-test statistics collection.
func (m *Metrics) EnableLoadStats(start time.Time) *LoadStats {
	m.Stats = NewLoadStats(start)
	return m.Stats
}

// RecordConfigReload counts a reload attempt.
func (m *Metrics) RecordConfigReload(ok bool) {
	if ok {
		m.ConfigReloads.WithLabelValues("success").Inc()
		return
	}
	m.ConfigReloads.WithLabelValues("failure").Inc()
	m.ConfigReloadFailures.Inc()
}

// RecordChat counts a chat reaction: kind quick|emote, result
// sent|rejected (server error reply)|dropped (not sent: stale, leaving,
// limiter). Chat never feeds the load-test action statistics.
func (m *Metrics) RecordChat(kind, result string) {
	m.ChatMessages.WithLabelValues(kind, result).Inc()
}

// RecordAction counts a command sent.
func (m *Metrics) RecordAction(typ string) {
	m.GameActions.WithLabelValues(typ).Inc()
	if m.Stats != nil {
		m.Stats.action(typ)
	}
}

// ObserveLatency records command -> authoritative event latency.
func (m *Metrics) ObserveLatency(action string, d time.Duration) {
	m.ActionLatency.WithLabelValues(action).Observe(d.Seconds())
	if m.Stats != nil {
		m.Stats.latency(action, d)
	}
}

// RecordError counts an error response.
func (m *Metrics) RecordError(code string) {
	c := BoundCode(code)
	m.InvalidActionResponses.WithLabelValues(c).Inc()
	if m.Stats != nil {
		m.Stats.errorCode(c)
	}
}

// RecordConnFailure counts a connection failure.
func (m *Metrics) RecordConnFailure(reason string) {
	m.ConnectionFailures.WithLabelValues(reason).Inc()
	if m.Stats != nil {
		m.Stats.connFailure(reason)
	}
}

// RecordReconnect counts a reconnect outcome.
func (m *Metrics) RecordReconnect(success bool) {
	r := "failure"
	if success {
		r = "success"
	}
	m.Reconnects.WithLabelValues(r).Inc()
	if m.Stats != nil {
		m.Stats.reconnect(success)
	}
}

// RecordResync counts a state resync request.
func (m *Metrics) RecordResync(reason string) {
	m.StateResyncs.WithLabelValues(reason).Inc()
	if m.Stats != nil {
		m.Stats.resync(reason)
	}
}

// RecordHashMismatch counts a state hash mismatch.
func (m *Metrics) RecordHashMismatch() {
	m.HashMismatches.Inc()
	if m.Stats != nil {
		m.Stats.hashMismatch()
	}
}

// RecordBytes counts received payload bytes.
func (m *Metrics) RecordBytes(n int) {
	m.WSBytesReceived.Add(float64(n))
	if m.Stats != nil {
		m.Stats.bytes(n)
	}
}

// RecordCompression counts the permessage-deflate negotiation outcome.
func (m *Metrics) RecordCompression(negotiated bool) {
	r := "none"
	if negotiated {
		r = "negotiated"
	}
	m.CompressionNegotiated.WithLabelValues(r).Inc()
	if m.Stats != nil {
		m.Stats.compressionResult(r)
	}
}

// RecordSession counts a bot session creation.
func (m *Metrics) RecordSession(ok bool) {
	r := "failure"
	if ok {
		r = "success"
	}
	m.BotSessions.WithLabelValues(r).Inc()
	if m.Stats != nil {
		m.Stats.session(ok)
	}
}

// RecordGameStarted counts a started game.
func (m *Metrics) RecordGameStarted(game string) {
	m.GamesStarted.WithLabelValues(game).Inc()
	if m.Stats != nil {
		m.Stats.gameStarted(game)
	}
}

// RecordGameFinished counts a finished game.
func (m *Metrics) RecordGameFinished(game string) {
	m.GamesFinished.WithLabelValues(game).Inc()
	if m.Stats != nil {
		m.Stats.gameFinished(game)
	}
}

// RecordResyncVerification counts a post-reconnect resync verification
// (result: verified | failed | room_gone).
func (m *Metrics) RecordResyncVerification(result string) {
	m.ResyncVerifications.WithLabelValues(result).Inc()
	if m.Stats != nil {
		m.Stats.resyncVerification(result)
	}
}

// RecordMalformed counts a deliberately malformed message.
func (m *Metrics) RecordMalformed(kind string) {
	m.MalformedSent.WithLabelValues(kind).Inc()
	if m.Stats != nil {
		m.Stats.malformed(kind)
	}
}

// SetActive publishes the active population (and tracks the peak).
func (m *Metrics) SetActive(byGame map[string]int, total int) {
	for _, g := range []string{"ludo", "ludo_quick", "snakes_ladders", "none"} {
		m.BotsActive.WithLabelValues(g).Set(float64(byGame[g]))
	}
	if m.Stats != nil {
		m.Stats.population(total)
	}
}
