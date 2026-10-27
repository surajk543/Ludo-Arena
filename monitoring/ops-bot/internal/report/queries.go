package report

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

// Queries builds the PromQL expressions used by the reports. Job names are
// configurable (BACKEND_JOB, BOTPLAY_JOB, NODE_JOB). Cluster-wide gauges
// (players_in_game, rooms_in_game, players_in_lobby, active_users_estimate)
// are reported identically by every backend instance, so they are combined
// with max, never sum. Per-instance gauges (ws_connections_active) are summed.
type Queries struct {
	Backend, BotPlay, Node string
}

// diskFilter keeps real data filesystems: it drops pseudo filesystems and
// the macOS system volumes so a full recovery partition never alerts.
const diskFilter = `fstype!~"tmpfs|overlay|squashfs|devtmpfs|devfs|devicefs|nullfs|autofs|ramfs|fuse.*",` +
	`mountpoint!~"/(boot|snap|System|Volumes|Library|private|run|var/lib/docker)(/.*)?"`

func (q Queries) sel(job string, extra ...string) string {
	parts := append([]string{fmt.Sprintf("job=%q", job)}, extra...)
	return "{" + strings.Join(parts, ",") + "}"
}

func (q Queries) procJobs() string {
	return fmt.Sprintf("job=~%q", regexp.QuoteMeta(q.Backend)+"|"+regexp.QuoteMeta(q.BotPlay))
}

// HostCPU is the CPU utilisation (%) per host over the last rate window.
func (q Queries) HostCPU(window time.Duration) string {
	return fmt.Sprintf(`100 * (1 - avg by (instance) (rate(node_cpu_seconds_total%s[%s])))`,
		q.sel(q.Node, `mode="idle"`), promDur(window))
}

// HostRAM is the memory utilisation (%) per host: MemAvailable on Linux,
// with a macOS fallback (app + wired + compressed memory) for local runs.
func (q Queries) HostRAM() string {
	n := q.sel(q.Node)
	return fmt.Sprintf(`max by (instance) (100 * (1 - node_memory_MemAvailable_bytes%[1]s / node_memory_MemTotal_bytes%[1]s)`+
		` or 100 * (node_memory_internal_bytes%[1]s - node_memory_purgeable_bytes%[1]s + node_memory_wired_bytes%[1]s`+
		` + node_memory_compressed_bytes%[1]s) / node_memory_total_bytes%[1]s)`, n)
}

// HostDisk is the fullest data filesystem (%) per host.
func (q Queries) HostDisk() string {
	s := q.sel(q.Node, diskFilter)
	return fmt.Sprintf(`max by (instance) (100 * (1 - node_filesystem_avail_bytes%[1]s / node_filesystem_size_bytes%[1]s))`, s)
}

// ProcRSS is the resident memory of every backend and bot-play process.
func (q Queries) ProcRSS() string {
	return fmt.Sprintf(`process_resident_memory_bytes{%s}`, q.procJobs())
}

// ProcCPU is the CPU use (% of one core) of every backend and bot-play process.
func (q Queries) ProcCPU(window time.Duration) string {
	return fmt.Sprintf(`100 * rate(process_cpu_seconds_total{%s}[%s])`, q.procJobs(), promDur(window))
}

// PlayersInGame is players seated in running games by actor (human|bot).
func (q Queries) PlayersInGame() string {
	return fmt.Sprintf(`max by (actor) (players_in_game%s)`, q.sel(q.Backend))
}

// Online is open WebSocket connections by actor (summed over instances).
func (q Queries) Online() string {
	return fmt.Sprintf(`sum by (actor) (ws_connections_active%s)`, q.sel(q.Backend))
}

// OnlineHumans is the real players' open WebSocket connections (summed over
// instances; one connection per player).
func (q Queries) OnlineHumans() string {
	return fmt.Sprintf(`sum(ws_connections_active%s)`, q.sel(q.Backend, `actor="human"`))
}

// PlayingHumans is real players seated in running games.
func (q Queries) PlayingHumans() string {
	return fmt.Sprintf(`max(players_in_game%s)`, q.sel(q.Backend, `actor="human"`))
}

// LobbyHumans is real players waiting in room lobbies.
func (q Queries) LobbyHumans() string {
	return fmt.Sprintf(`max(players_in_lobby%s)`, q.sel(q.Backend, `actor="human"`))
}

// PGPool is the backend PostgreSQL pool connections by state (acquired,
// idle, constructing), summed over instances.
func (q Queries) PGPool() string {
	return fmt.Sprintf(`sum by (state) (postgres_pool_connections%s)`, q.sel(q.Backend))
}

// PGPoolMax is the summed pool limit (MaxConns) of every backend instance.
func (q Queries) PGPoolMax() string {
	return fmt.Sprintf(`sum(postgres_pool_max_connections%s)`, q.sel(q.Backend))
}

// HostCores is the number of CPUs per host.
func (q Queries) HostCores() string {
	return fmt.Sprintf(`count by (instance) (node_cpu_seconds_total%s)`, q.sel(q.Node, `mode="idle"`))
}

// HostMemTotal is the installed memory per host (Linux, with the macOS name).
func (q Queries) HostMemTotal() string {
	n := q.sel(q.Node)
	return fmt.Sprintf(`max by (instance) (node_memory_MemTotal_bytes%[1]s or node_memory_total_bytes%[1]s)`, n)
}

// RoomsByGame is rooms with a running game by game.
func (q Queries) RoomsByGame() string {
	return fmt.Sprintf(`sum by (game) (max by (game, mode) (rooms_in_game%s))`, q.sel(q.Backend))
}

// Lobby is players waiting in lobbies by actor.
func (q Queries) Lobby() string {
	return fmt.Sprintf(`max by (actor) (players_in_lobby%s)`, q.sel(q.Backend))
}

// StartedByMix is matches started in the window by mix (load tests excluded).
func (q Queries) StartedByMix(window time.Duration) string {
	return fmt.Sprintf(`sum by (mix) (increase(matches_started_total%s[%s]))`, q.sel(q.Backend, `mix!="loadtest"`), promDur(window))
}

// StartedByGame is matches started in the window by game (load tests excluded).
func (q Queries) StartedByGame(window time.Duration) string {
	return fmt.Sprintf(`sum by (game) (increase(matches_started_total%s[%s]))`, q.sel(q.Backend, `mix!="loadtest"`), promDur(window))
}

// StartedByGameMode is matches started by game and mode.
func (q Queries) StartedByGameMode(window time.Duration) string {
	return fmt.Sprintf(`sum by (game, mode) (increase(matches_started_total%s[%s]))`, q.sel(q.Backend, `mix!="loadtest"`), promDur(window))
}

// CompletedByGameMode is matches finished by game and mode.
func (q Queries) CompletedByGameMode(window time.Duration) string {
	return fmt.Sprintf(`sum by (game, mode) (increase(matches_completed_total%s[%s]))`, q.sel(q.Backend), promDur(window))
}

// Completed is matches finished in the window.
func (q Queries) Completed(window time.Duration) string {
	return fmt.Sprintf(`sum(increase(matches_completed_total%s[%s]))`, q.sel(q.Backend), promDur(window))
}

// NewAccounts is accounts created in the window by provider.
func (q Queries) NewAccounts(window time.Duration) string {
	return fmt.Sprintf(`sum by (provider) (increase(auth_accounts_created_total%s[%s]))`, q.sel(q.Backend), promDur(window))
}

// Logins is successful sign-ins in the window.
func (q Queries) Logins(window time.Duration) string {
	return fmt.Sprintf(`sum(increase(auth_logins_total%s[%s]))`, q.sel(q.Backend, `result="ok"`), promDur(window))
}

// ActiveUsers is the HyperLogLog estimate for window "day" or "week".
func (q Queries) ActiveUsers(window string) string {
	return fmt.Sprintf(`max(active_users_estimate%s)`, q.sel(q.Backend, fmt.Sprintf("window=%q", window)))
}

// ActiveUsersMax is the highest estimate over the range (the day's final value).
func (q Queries) ActiveUsersMax(window string, rng time.Duration) string {
	return fmt.Sprintf(`max(max_over_time(active_users_estimate%s[%s]))`, q.sel(q.Backend, fmt.Sprintf("window=%q", window)), promDur(rng))
}

// Abandons is human forfeits in the window by reason.
func (q Queries) Abandons(window time.Duration) string {
	return fmt.Sprintf(`sum by (reason) (increase(players_abandoned_total%s[%s]))`, q.sel(q.Backend), promDur(window))
}

// PeakPlaying is the highest players_in_game per actor over the window.
func (q Queries) PeakPlaying(window time.Duration) string {
	return fmt.Sprintf(`max by (actor) (max_over_time(players_in_game%s[%s]))`, q.sel(q.Backend), promDur(window))
}

// PeakOnline is the highest summed WebSocket connections per actor.
func (q Queries) PeakOnline(window time.Duration) string {
	return fmt.Sprintf(`max_over_time(%s[%s:1m])`, q.Online(), promDur(window))
}

// WaitAvg is the mean matchmaking wait in seconds.
func (q Queries) WaitAvg(window time.Duration) string {
	s, w := q.sel(q.Backend), promDur(window)
	return fmt.Sprintf(`sum(increase(matchmaking_wait_seconds_sum%s[%s])) / sum(increase(matchmaking_wait_seconds_count%s[%s]))`, s, w, s, w)
}

// WaitP95 is the 95th percentile matchmaking wait in seconds.
func (q Queries) WaitP95(window time.Duration) string {
	return fmt.Sprintf(`histogram_quantile(0.95, sum by (le) (increase(matchmaking_wait_seconds_bucket%s[%s])))`, q.sel(q.Backend), promDur(window))
}

// MatchmakingResults is matchmaking outcomes by result.
func (q Queries) MatchmakingResults(window time.Duration) string {
	return fmt.Sprintf(`sum by (result) (increase(matchmaking_results_total%s[%s]))`, q.sel(q.Backend), promDur(window))
}

// HTTPByClass is HTTP requests by status class.
func (q Queries) HTTPByClass(window time.Duration) string {
	return fmt.Sprintf(`sum by (class) (increase(http_requests_total%s[%s]))`, q.sel(q.Backend), promDur(window))
}

// Settlement is wallet settlement failures by operation.
func (q Queries) Settlement(window time.Duration) string {
	return fmt.Sprintf(`sum by (op) (increase(wallet_settlement_failures_total%s[%s]))`, q.sel(q.Backend), promDur(window))
}

// ClientErrors is client-reported errors.
func (q Queries) ClientErrors(window time.Duration) string {
	return fmt.Sprintf(`sum(increase(client_errors_total%s[%s]))`, q.sel(q.Backend), promDur(window))
}

// PeakHostCPU is the highest 5-minute CPU % per host over the window.
func (q Queries) PeakHostCPU(window time.Duration) string {
	return fmt.Sprintf(`max_over_time((%s)[%s:5m])`, q.HostCPU(5*time.Minute), promDur(window))
}

// PeakHostRAM is the highest RAM % per host over the window.
func (q Queries) PeakHostRAM(window time.Duration) string {
	return fmt.Sprintf(`max_over_time((%s)[%s:5m])`, q.HostRAM(), promDur(window))
}

// Up is the scrape health of a job.
func (q Queries) Up(job string) string { return fmt.Sprintf(`up%s`, q.sel(job)) }

// Firing lists firing alerts.
const Firing = `ALERTS{alertstate="firing"}`

// FiredDuring lists the alerts that fired at any point in the window.
func FiredDuring(window time.Duration) string {
	return fmt.Sprintf(`max by (alertname, severity) (max_over_time(ALERTS{alertstate="firing"}[%s]))`, promDur(window))
}

// promDur renders a duration as a PromQL duration (whole seconds or larger units).
func promDur(d time.Duration) string {
	s := int64(d / time.Second)
	switch {
	case s <= 0:
		return "1s"
	case s%86400 == 0:
		return fmt.Sprintf("%dd", s/86400)
	case s%3600 == 0:
		return fmt.Sprintf("%dh", s/3600)
	case s%60 == 0:
		return fmt.Sprintf("%dm", s/60)
	default:
		return fmt.Sprintf("%ds", s)
	}
}
