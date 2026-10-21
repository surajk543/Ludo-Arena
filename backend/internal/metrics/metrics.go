// Package metrics defines the backend's Prometheus metrics. Labels are
// bounded (no user, room or token values) and product metrics count human
// players only; bot activity is reported separately and never mixed in.
package metrics

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Registry holds every backend metric.
var Registry = prometheus.NewRegistry()

func counter(name, help string, labels ...string) *prometheus.CounterVec {
	c := prometheus.NewCounterVec(prometheus.CounterOpts{Name: name, Help: help}, labels)
	Registry.MustRegister(c)
	return c
}

func histogram(name, help string, buckets []float64, labels ...string) *prometheus.HistogramVec {
	h := prometheus.NewHistogramVec(prometheus.HistogramOpts{Name: name, Help: help, Buckets: buckets}, labels)
	Registry.MustRegister(h)
	return h
}

func counter0(name, help string) prometheus.Counter {
	c := prometheus.NewCounter(prometheus.CounterOpts{Name: name, Help: help})
	Registry.MustRegister(c)
	return c
}

func histogram0(name, help string, buckets []float64) prometheus.Histogram {
	h := prometheus.NewHistogram(prometheus.HistogramOpts{Name: name, Help: help, Buckets: buckets})
	Registry.MustRegister(h)
	return h
}

func gauge0(name, help string) prometheus.Gauge {
	g := prometheus.NewGauge(prometheus.GaugeOpts{Name: name, Help: help})
	Registry.MustRegister(g)
	return g
}

func gauge(name, help string, labels ...string) *prometheus.GaugeVec {
	g := prometheus.NewGaugeVec(prometheus.GaugeOpts{Name: name, Help: help}, labels)
	Registry.MustRegister(g)
	return g
}

var latencyBuckets = []float64{.0005, .001, .0025, .005, .01, .025, .05, .1, .25, .5, 1, 2.5}

// WebSocket transport.
var (
	WSConnections          = gauge("ws_connections_active", "Open WebSocket connections.", "actor")
	WSConnects             = counter("ws_connects_total", "WebSocket connection attempts by result.", "result")
	WSCompression          = counter("ws_compression_negotiated_total", "Negotiated permessage-deflate mode per accepted connection.", "mode")
	WSReconnects           = counter("ws_reconnects_total", "Connections flagged X-Reconnect by the client.", "actor")
	WSMsgsReceived         = counter("ws_messages_received_total", "Client messages received.", "type")
	WSMsgsSent             = counter("ws_messages_sent_total", "Server messages written.", "type")
	WSMsgsRejected         = counter("ws_messages_rejected_total", "Client messages rejected before processing.", "reason")
	WSPayloadBytesSent     = counter0("ws_payload_bytes_sent_total", "Uncompressed application payload bytes written.")
	WSPayloadBytesReceived = counter0("ws_payload_bytes_received_total", "Application payload bytes received after decompression.")
	WSWireBytesSent        = counter0("ws_wire_bytes_sent_total", "Measured bytes written to the connection (WebSocket frames incl. headers, after compression, before TLS).")
	WSWireBytesReceived    = counter0("ws_wire_bytes_received_total", "Measured bytes read from the connection (frames incl. headers, before decompression, after TLS).")
	WSWriteSeconds         = histogram0("ws_write_seconds", "Time to write one message (includes compression).", latencyBuckets)
	WSProcessSeconds       = histogram("ws_message_processing_seconds", "Time to process one client command.", latencyBuckets, "type")
	WSQueueDepth           = histogram0("ws_outbound_queue_depth", "Outbound queue depth observed at enqueue.", []float64{0, 1, 2, 4, 8, 16, 32, 64, 128})
	WSSlowClients          = counter("ws_slow_client_events_total", "Outbound queue overflows (coalesced to a snapshot) and slow-client disconnects.", "event")
	WSResyncs              = counter("ws_resyncs_total", "Full snapshots sent for synchronization.", "reason")
	WSBroadcastFanout      = histogram0("ws_broadcast_fanout", "Local recipients per room broadcast.", []float64{0, 1, 2, 3, 4, 8})
)

// HTTP.
var (
	HTTPRequests = counter("http_requests_total", "HTTP requests by route pattern and status class.", "route", "class")
	HTTPSeconds  = histogram("http_request_seconds", "HTTP latency by route pattern.", latencyBuckets, "route")
)

// Auth (human accounts only).
var (
	AuthLogins   = counter("auth_logins_total", "Sign-ins by provider and result.", "provider", "result")
	AuthAccounts = counter("auth_accounts_created_total", "New accounts (welcome grant issued) by provider.", "provider")
	AuthLinks    = counter("auth_links_total", "Account linking attempts by provider and result.", "provider", "result")
	AuthRefresh  = counter("auth_refresh_total", "Refresh-token rotations by result.", "result")
	PolicyBlocks = counter("app_policy_blocks_total", "Requests blocked by the app policy.", "mode", "surface")
)

// Gameplay and product metrics (humans; bot-only games are labelled mix=bot_only).
var (
	MatchesStarted     = counter("matches_started_total", "Games started.", "game", "mode", "mix")
	MatchesCompleted   = counter("matches_completed_total", "Games finished.", "game", "mode", "reason")
	PlayersAbandoned   = counter("players_abandoned_total", "Human players who forfeited (left or timed out).", "game", "reason")
	MatchmakingWait    = histogram("matchmaking_wait_seconds", "Human wait from matchmaking.join to game start.", []float64{1, 2, 5, 10, 15, 20, 30, 45, 60, 120}, "game")
	MatchmakingResults = counter("matchmaking_results_total", "Matchmaking outcomes for humans.", "result")
	PrivateRooms       = counter("private_rooms_created_total", "Private rooms created.", "game")
	PracticeGames      = counter("practice_games_total", "Practice games requested.", "game")
	Rematches          = counter("rematch_total", "Rematch votes and outcomes.", "event")
	RuleErrors         = counter("game_rule_rejections_total", "Rejected game commands by error code.", "code")
	QuickChats         = counter("quick_chat_total", "Quick chat and emote messages.", "kind")
	ReconnectResults   = counter("client_reconnect_total", "Client-reported reconnect outcomes (telemetry).", "result")
	ClientErrors       = counter("client_errors_total", "Client-reported errors (telemetry).", "kind")
	SettlementFailures = counter("wallet_settlement_failures_total", "Entry-fee or payout operations that failed.", "op")
	ActiveUsers        = gauge("active_users_estimate", "Pseudonymous HyperLogLog estimates of active human users.", "window")
)

// Live game counts, cluster-wide: recounted from the Redis live-room index by
// one instance per GAME_STATS_INTERVAL and exposed with the same values by
// every instance (aggregate with max, not sum). Bots include load-test bots.
var (
	PlayersInGame      = gauge("players_in_game", "Non-forfeited players seated in rooms that are playing, cluster-wide (same value on every instance; aggregate with max).", "actor")
	RoomsInGame        = gauge("rooms_in_game", "Rooms that are playing, cluster-wide (same value on every instance; aggregate with max).", "game", "mode")
	PlayersInLobby     = gauge("players_in_lobby", "Players seated in rooms waiting to start (public, private and practice lobbies), cluster-wide (aggregate with max).", "actor")
	GameStatsRefreshed = gauge0("game_stats_refreshed_timestamp_seconds", "Unix time of the last successful cluster-wide recount behind players_in_game, rooms_in_game and players_in_lobby.")
)

// Bot service (operational; never mixed with product metrics).
var (
	BotSessions    = counter("bot_sessions_total", "Bot sessions issued by kind.", "kind")
	BotAssignments = counter("bot_assignments_total", "Bot seat assignments by kind and outcome.", "kind", "event")
)

func init() {
	Registry.MustRegister(collectors.NewGoCollector(), collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))
}

// Handler serves the registry in Prometheus text format.
func Handler() http.Handler {
	return promhttp.HandlerFor(Registry, promhttp.HandlerOpts{})
}
