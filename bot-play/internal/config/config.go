// Package config loads, validates and hot-reloads bot-play configuration.
//
// Every operational parameter lives in YAML (see configs/config.example.yaml
// for the documented reference). The only value taken from the environment is
// the bot service key (BOT_SERVICE_KEY), which is never accepted from a file.
package config

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"slices"
	"strings"
	"time"
	"unicode"

	"go.yaml.in/yaml/v3"

	"ludoroyale/botplay/internal/profiles"
)

// Environments.
const (
	EnvDevelopment = "development"
	EnvPreprod     = "preprod"
	EnvProduction  = "production"
)

// Modes.
const (
	ModePractice   = "practice"
	ModePublicFill = "public_fill"
	ModeLoadtest   = "loadtest"
)

// Game keys used in configuration, limits and metric labels.
const (
	GameLudo      = "ludo"           // ludo / classic
	GameLudoQuick = "ludo_quick"     // ludo / quick
	GameSnakes    = "snakes_ladders" // snakes_ladders / classic
)

// GameKeys lists every known game key.
var GameKeys = []string{GameLudo, GameLudoQuick, GameSnakes}

// Shutdown policies.
const (
	PolicyFinishGames = "finish_games"
	PolicyLeaveNow    = "leave_now"
)

// MaxConcurrentCap is the environment-specific ceiling for
// bots.max_concurrent_bots.
var MaxConcurrentCap = map[string]int{
	EnvDevelopment: 10000,
	EnvPreprod:     5000,
	EnvProduction:  500,
}

// GameKey maps a protocol (game, variant) pair to a configuration game key.
// It returns "" for unknown games.
func GameKey(game, variant string) string {
	switch game {
	case "ludo":
		if variant == "quick" {
			return GameLudoQuick
		}
		return GameLudo
	case "snakes_ladders":
		return GameSnakes
	}
	return ""
}

// GameVariant maps a game key back to the protocol (game, variant) pair.
func GameVariant(key string) (game, variant string) {
	switch key {
	case GameLudoQuick:
		return "ludo", "quick"
	case GameSnakes:
		return "snakes_ladders", "classic"
	default:
		return "ludo", "classic"
	}
}

// Config is the full bot-play configuration.
type Config struct {
	App        AppConfig        `yaml:"app"`
	Connection ConnectionConfig `yaml:"connection"`
	Bots       BotsConfig       `yaml:"bots"`
	Limits     LimitsConfig     `yaml:"limits"`
	Loadtest   LoadtestConfig   `yaml:"loadtest"`
	Metrics    MetricsConfig    `yaml:"metrics"`
}

// AppConfig: identity and logging.
type AppConfig struct {
	Name              string `yaml:"name"`
	Environment       string `yaml:"environment"`
	LogLevel          string `yaml:"log_level"`
	LogFormat         string `yaml:"log_format"`
	ReloadPollSeconds int    `yaml:"reload_poll_seconds"`
}

// ConnectionConfig: backend endpoints, timeouts, reconnection.
type ConnectionConfig struct {
	BackendHTTPURL            string `yaml:"backend_http_url"`
	BackendWSURL              string `yaml:"backend_ws_url"`
	ConnectTimeoutMS          int    `yaml:"connect_timeout_ms"`
	RequestTimeoutMS          int    `yaml:"request_timeout_ms"`
	AssignmentWaitSeconds     int    `yaml:"assignment_wait_seconds"`
	ReconnectEnabled          bool   `yaml:"reconnect_enabled"`
	ReconnectMaxAttempts      int    `yaml:"reconnect_max_attempts"`
	ReconnectBackoffBaseMS    int    `yaml:"reconnect_backoff_base_ms"`
	ReconnectBackoffMaxMS     int    `yaml:"reconnect_backoff_max_ms"`
	ReconnectResetSeconds     int    `yaml:"reconnect_reset_seconds"`
	MaintenanceBackoffSeconds int    `yaml:"maintenance_backoff_seconds"`
	PingIntervalSeconds       int    `yaml:"ping_interval_seconds"`
	PongTimeoutSeconds        int    `yaml:"pong_timeout_seconds"`
	OutboundQueueSize         int    `yaml:"outbound_queue_size"`
	ReadLimitBytes            int    `yaml:"read_limit_bytes"`
	// CompressionMode is the permessage-deflate offer: no_context_takeover
	// (default), context_takeover (what dart:io offers by default) or disabled.
	CompressionMode        string `yaml:"compression_mode"`
	ActionConfirmTimeoutMS int    `yaml:"action_confirm_timeout_ms"`
	ReadinessStaleSeconds  int    `yaml:"readiness_stale_seconds"`
}

// BotsConfig: what bots do and how many.
type BotsConfig struct {
	Enabled                        bool                    `yaml:"enabled"`
	Modes                          []string                `yaml:"modes"`
	Games                          map[string]bool         `yaml:"games"`
	TargetActiveBots               int                     `yaml:"target_active_bots"`
	MaxConcurrentBots              int                     `yaml:"max_concurrent_bots"`
	PerGameMax                     map[string]int          `yaml:"per_game_max"`
	MaxBotsPerRoom                 int                     `yaml:"max_bots_per_room"`
	MaxRoomJoinsPerSecond          float64                 `yaml:"max_room_joins_per_second"`
	MaxConnectionAttemptsPerSecond float64                 `yaml:"max_connection_attempts_per_second"`
	LobbyWaitTimeoutSeconds        int                     `yaml:"lobby_wait_timeout_seconds"`
	AcceptRematch                  bool                    `yaml:"accept_rematch"`
	PublicMatchmaking              PublicMatchmakingConfig `yaml:"public_matchmaking"`
	ThinkTime                      ThinkTimeConfig         `yaml:"think_time"`
	Behavior                       BehaviorConfig          `yaml:"behavior"`
	Identity                       IdentityConfig          `yaml:"identity"`
	Chat                           ChatConfig              `yaml:"chat"`
	Shutdown                       ShutdownConfig          `yaml:"shutdown"`
}

// PublicMatchmakingConfig: public lobby fill assistance.
type PublicMatchmakingConfig struct {
	Enabled               bool            `yaml:"enabled"`
	PerGame               map[string]bool `yaml:"per_game"`
	PollIntervalMS        int             `yaml:"poll_interval_ms"`
	FillAfterSeconds      int             `yaml:"fill_after_seconds"`
	MinimumHumans         int             `yaml:"minimum_humans"`
	MaximumWaitSeconds    int             `yaml:"maximum_wait_seconds"`
	RefillCooldownSeconds int             `yaml:"refill_cooldown_seconds"`
}

// ThinkTimeConfig: global clamp applied to every profile's think time.
type ThinkTimeConfig struct {
	MinMS     int  `yaml:"min_ms"`
	MaxMS     int  `yaml:"max_ms"`
	Randomize bool `yaml:"randomize"`
}

// BehaviorConfig: profile selection and imperfections.
type BehaviorConfig struct {
	DefaultProfile              string  `yaml:"default_profile"`
	RandomSeed                  int64   `yaml:"random_seed"`
	DisconnectSimulationEnabled bool    `yaml:"disconnect_simulation_enabled"`
	DisconnectProbability       float64 `yaml:"disconnect_probability"`
}

// IdentityConfig: display names requested for bot sessions.
type IdentityConfig struct {
	DisplayNamePrefix string   `yaml:"display_name_prefix"`
	NamesPool         []string `yaml:"names_pool"`
}

// ChatConfig: quick-chat and emote reactions. Bots react sparingly to what
// happens in their game (a six, a capture, the result) like people do; every
// message goes through the per-match cap, the minimum interval and the bot's
// action limiter, and the server's own chat limits (1 per 3 s, 10 per
// minute per account) still apply.
type ChatConfig struct {
	Enabled bool `yaml:"enabled"`
	// InLoadtest lets load-test bots chat too (default false).
	InLoadtest bool `yaml:"in_loadtest"`
	// MaxPerMatch caps messages per bot per game round (0 = silent).
	MaxPerMatch int `yaml:"max_per_match"`
	// MinIntervalMS is the minimum gap between two messages of one bot
	// (>= 3000: the server allows one message per 3 s).
	MinIntervalMS int `yaml:"min_interval_ms"`
	// ReactionDelayMS is how long after the event the bot "types".
	ReactionDelayMS RangeMS `yaml:"reaction_delay_ms"`
	// EmoteShare is the share of reactions sent as an emote when both an
	// emote and a quick-chat phrase fit (emotes only from the session's
	// emotes list).
	EmoteShare  float64           `yaml:"emote_share"`
	Probability ChatProbabilities `yaml:"probability"`
}

// ChatProbabilities is the chance (0..1, before the profile's chattiness
// multiplier) that a bot reacts to each event.
type ChatProbabilities struct {
	GameStart    float64 `yaml:"game_start"`    // the game starts (good luck / wave)
	Six          float64 `yaml:"six"`           // the bot rolled a six
	Capture      float64 `yaml:"capture"`       // the bot captured an opponent token
	Captured     float64 `yaml:"captured"`      // one of the bot's tokens was captured
	OtherCapture float64 `yaml:"other_capture"` // an opponent captured a third player's token
	Win          float64 `yaml:"win"`           // the bot won
	Loss         float64 `yaml:"loss"`          // someone else won
}

// MinChatIntervalMS is the server's quick-chat burst limit (1 per 3 s).
const MinChatIntervalMS = 3000

// MinInterval returns bots.chat.min_interval_ms as a duration.
func (c ChatConfig) MinInterval() time.Duration { return ms(c.MinIntervalMS) }

// ShutdownConfig: graceful stop behaviour.
type ShutdownConfig struct {
	GracefulTimeoutSeconds int    `yaml:"graceful_timeout_seconds"`
	Policy                 string `yaml:"policy"`
}

// LimitsConfig: per-bot safety limits.
type LimitsConfig struct {
	MaxActionsPerSecondPerBot     float64 `yaml:"max_actions_per_second_per_bot"`
	MaxReconnectAttemptsPerMinute int     `yaml:"max_reconnect_attempts_per_minute"`
}

// RangeMS is a min/max millisecond range.
type RangeMS struct {
	Min int `yaml:"min"`
	Max int `yaml:"max"`
}

// LoadtestConfig: development / preproduction traffic generation.
type LoadtestConfig struct {
	Enabled              bool               `yaml:"enabled"`
	AllowedHosts         []string           `yaml:"allowed_hosts"`
	ForbiddenHosts       []string           `yaml:"forbidden_hosts"`
	TargetConnections    int                `yaml:"target_connections"`
	RampPerSecond        float64            `yaml:"ramp_per_second"`
	DurationSeconds      int                `yaml:"duration_seconds"`
	GameMix              map[string]float64 `yaml:"game_mix"`
	CapacityMix          map[int]float64    `yaml:"capacity_mix"`
	ThinkTimeMS          RangeMS            `yaml:"think_time_ms"`
	ChurnPerMinute       float64            `yaml:"churn_per_minute"`
	SlowReaderFraction   float64            `yaml:"slow_reader_fraction"`
	SlowReaderDelayMS    int                `yaml:"slow_reader_delay_ms"`
	MalformedMessageRate float64            `yaml:"malformed_message_rate"`
	ReportPath           string             `yaml:"report_path"`
}

// MetricsConfig: health + Prometheus listener.
type MetricsConfig struct {
	Enabled    bool   `yaml:"enabled"`
	ListenAddr string `yaml:"listen_addr"`
}

// DefaultNames is the default identity.names_pool.
var DefaultNames = []string{
	"Asha", "Ravi", "Meera", "Arjun", "Kiran", "Nisha", "Dev", "Isha",
	"Kabir", "Tara", "Rohan", "Anya", "Vikram", "Zara", "Sami", "Lina",
}

// Default returns the built-in defaults. A YAML file only needs to override
// what differs.
func Default() *Config {
	return &Config{
		App: AppConfig{
			Name:              "bot-play",
			Environment:       EnvDevelopment,
			LogLevel:          "info",
			LogFormat:         "json",
			ReloadPollSeconds: 5,
		},
		Connection: ConnectionConfig{
			BackendHTTPURL:            "http://localhost:8080/api/v1",
			BackendWSURL:              "ws://localhost:8080/api/v1/ws",
			ConnectTimeoutMS:          5000,
			RequestTimeoutMS:          5000,
			AssignmentWaitSeconds:     20,
			ReconnectEnabled:          true,
			ReconnectMaxAttempts:      8,
			ReconnectBackoffBaseMS:    500,
			ReconnectBackoffMaxMS:     30000,
			ReconnectResetSeconds:     30,
			MaintenanceBackoffSeconds: 30,
			PingIntervalSeconds:       15,
			PongTimeoutSeconds:        10,
			OutboundQueueSize:         64,
			ReadLimitBytes:            1 << 20,
			CompressionMode:           "no_context_takeover",
			ActionConfirmTimeoutMS:    5000,
			ReadinessStaleSeconds:     60,
		},
		Bots: BotsConfig{
			Enabled:                        true,
			Modes:                          []string{ModePractice},
			TargetActiveBots:               50,
			MaxConcurrentBots:              100,
			MaxBotsPerRoom:                 3,
			MaxRoomJoinsPerSecond:          5,
			MaxConnectionAttemptsPerSecond: 10,
			LobbyWaitTimeoutSeconds:        90,
			PublicMatchmaking: PublicMatchmakingConfig{
				PollIntervalMS:        2000,
				FillAfterSeconds:      15,
				MinimumHumans:         1,
				MaximumWaitSeconds:    27,
				RefillCooldownSeconds: 10,
			},
			ThinkTime: ThinkTimeConfig{MinMS: 300, MaxMS: 6000, Randomize: true},
			Behavior:  BehaviorConfig{DefaultProfile: "balanced"},
			Identity:  IdentityConfig{DisplayNamePrefix: "Bot"},
			Chat: ChatConfig{
				Enabled: true, MaxPerMatch: 3, MinIntervalMS: 8000,
				ReactionDelayMS: RangeMS{Min: 600, Max: 2500}, EmoteShare: 0.5,
				Probability: ChatProbabilities{GameStart: 0.06, Six: 0.02, Capture: 0.15, Captured: 0.12,
					OtherCapture: 0.03, Win: 0.35, Loss: 0.2},
			},
			Shutdown: ShutdownConfig{GracefulTimeoutSeconds: 60, Policy: PolicyFinishGames},
		},
		Limits: LimitsConfig{
			MaxActionsPerSecondPerBot:     4,
			MaxReconnectAttemptsPerMinute: 6,
		},
		Loadtest: LoadtestConfig{
			AllowedHosts:      []string{"localhost", "127.0.0.1"},
			TargetConnections: 100,
			RampPerSecond:     10,
			DurationSeconds:   600,
			ThinkTimeMS:       RangeMS{Min: 200, Max: 1500},
			SlowReaderDelayMS: 250,
			ReportPath:        "loadtest-report.json",
		},
		Metrics: MetricsConfig{Enabled: true, ListenAddr: "127.0.0.1:9091"},
	}
}

// applyDerivedDefaults fills maps whose defaults depend on what the file set.
func (c *Config) applyDerivedDefaults() {
	if c.Bots.Games == nil {
		c.Bots.Games = map[string]bool{}
	}
	for _, g := range GameKeys {
		if _, ok := c.Bots.Games[g]; !ok {
			c.Bots.Games[g] = true // games default to enabled
		}
	}
	if c.Bots.PublicMatchmaking.PerGame == nil {
		c.Bots.PublicMatchmaking.PerGame = map[string]bool{}
	}
	for _, g := range GameKeys {
		if _, ok := c.Bots.PublicMatchmaking.PerGame[g]; !ok {
			c.Bots.PublicMatchmaking.PerGame[g] = false // fill must be enabled explicitly per game
		}
	}
	if len(c.Bots.Identity.NamesPool) == 0 {
		c.Bots.Identity.NamesPool = slices.Clone(DefaultNames)
	}
	if len(c.Loadtest.GameMix) == 0 {
		c.Loadtest.GameMix = map[string]float64{GameLudo: 50, GameLudoQuick: 25, GameSnakes: 25}
	}
	if len(c.Loadtest.CapacityMix) == 0 {
		c.Loadtest.CapacityMix = map[int]float64{2: 40, 3: 20, 4: 40}
	}
	if c.App.Environment == "preproduction" {
		c.App.Environment = EnvPreprod
	}
}

// Parse decodes YAML on top of the defaults (unknown keys are rejected) and
// validates the result (without profile cross-checks; see ValidateProfiles).
func Parse(b []byte) (*Config, error) {
	c := Default()
	dec := yaml.NewDecoder(bytes.NewReader(b))
	dec.KnownFields(true)
	if err := dec.Decode(c); err != nil && !errors.Is(err, io.EOF) { // empty file = defaults
		return nil, fmt.Errorf("config: parse: %w", err)
	}
	c.applyDerivedDefaults()
	if err := c.Validate(); err != nil {
		return nil, err
	}
	return c, nil
}

// LoadFile reads, parses and validates a config file.
func LoadFile(path string) (*Config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("config: read %s: %w", path, err)
	}
	return Parse(b)
}

// Duration helpers.
func ms(v int) time.Duration  { return time.Duration(v) * time.Millisecond }
func sec(v int) time.Duration { return time.Duration(v) * time.Second }

func (c ConnectionConfig) ConnectTimeout() time.Duration     { return ms(c.ConnectTimeoutMS) }
func (c ConnectionConfig) RequestTimeout() time.Duration     { return ms(c.RequestTimeoutMS) }
func (c ConnectionConfig) AssignmentWait() time.Duration     { return sec(c.AssignmentWaitSeconds) }
func (c ConnectionConfig) BackoffBase() time.Duration        { return ms(c.ReconnectBackoffBaseMS) }
func (c ConnectionConfig) BackoffMax() time.Duration         { return ms(c.ReconnectBackoffMaxMS) }
func (c ConnectionConfig) ReconnectReset() time.Duration     { return sec(c.ReconnectResetSeconds) }
func (c ConnectionConfig) MaintenanceBackoff() time.Duration { return sec(c.MaintenanceBackoffSeconds) }
func (c ConnectionConfig) PingInterval() time.Duration       { return sec(c.PingIntervalSeconds) }
func (c ConnectionConfig) PongTimeout() time.Duration        { return sec(c.PongTimeoutSeconds) }
func (c ConnectionConfig) ActionConfirmTimeout() time.Duration {
	return ms(c.ActionConfirmTimeoutMS)
}
func (c ConnectionConfig) ReadinessStale() time.Duration { return sec(c.ReadinessStaleSeconds) }

func (p PublicMatchmakingConfig) PollInterval() time.Duration   { return ms(p.PollIntervalMS) }
func (p PublicMatchmakingConfig) FillAfter() time.Duration      { return sec(p.FillAfterSeconds) }
func (p PublicMatchmakingConfig) MaximumWait() time.Duration    { return sec(p.MaximumWaitSeconds) }
func (p PublicMatchmakingConfig) RefillCooldown() time.Duration { return sec(p.RefillCooldownSeconds) }

func (s ShutdownConfig) GracefulTimeout() time.Duration { return sec(s.GracefulTimeoutSeconds) }
func (b BotsConfig) LobbyWaitTimeout() time.Duration    { return sec(b.LobbyWaitTimeoutSeconds) }
func (l LoadtestConfig) Duration() time.Duration        { return sec(l.DurationSeconds) }

// HasMode reports whether a mode is configured.
func (b BotsConfig) HasMode(m string) bool { return slices.Contains(b.Modes, m) }

// IsLoadtest reports whether this configuration runs the load-test mode.
func (c *Config) IsLoadtest() bool { return c.Bots.HasMode(ModeLoadtest) }

// EffectiveTarget is the population the controller aims for: the load-test
// target in loadtest mode, otherwise target_active_bots; both are capped by
// max_concurrent_bots. A disabled service targets 0.
func (c *Config) EffectiveTarget() int {
	if !c.Bots.Enabled {
		return 0
	}
	t := c.Bots.TargetActiveBots
	if c.IsLoadtest() {
		t = c.Loadtest.TargetConnections
	}
	return min(t, c.Bots.MaxConcurrentBots)
}

// GameLimit returns the per-game maximum (max_concurrent_bots when unset).
func (c *Config) GameLimit(game string) int {
	if v, ok := c.Bots.PerGameMax[game]; ok {
		return v
	}
	return c.Bots.MaxConcurrentBots
}

type verr struct{ errs []error }

func (v *verr) addf(format string, a ...any) { v.errs = append(v.errs, fmt.Errorf(format, a...)) }
func (v *verr) rng(name string, val, lo, hi int) {
	if val < lo || val > hi {
		v.addf("%s: %d is out of range %d..%d", name, val, lo, hi)
	}
}
func (v *verr) frng(name string, val, lo, hi float64, loExclusive bool) {
	if val != val || val > hi || val < lo || (loExclusive && val == lo) {
		op := ">="
		if loExclusive {
			op = ">"
		}
		v.addf("%s: %g must be %s %g and <= %g", name, val, op, lo, hi)
	}
}

// Validate checks every field. It returns all problems at once.
func (c *Config) Validate() error {
	v := &verr{}
	env := c.App.Environment

	// app
	if strings.TrimSpace(c.App.Name) == "" || len(c.App.Name) > 64 {
		v.addf("app.name: must be 1..64 characters")
	}
	if _, ok := MaxConcurrentCap[env]; !ok {
		v.addf("app.environment: %q is not one of development, preprod, production", env)
	}
	if !slices.Contains([]string{"debug", "info", "warn", "error"}, c.App.LogLevel) {
		v.addf("app.log_level: %q is not one of debug, info, warn, error", c.App.LogLevel)
	}
	if !slices.Contains([]string{"json", "text"}, c.App.LogFormat) {
		v.addf("app.log_format: %q is not one of json, text", c.App.LogFormat)
	}
	v.rng("app.reload_poll_seconds", c.App.ReloadPollSeconds, 0, 3600)

	// connection
	cn := c.Connection
	validateURL(v, "connection.backend_http_url", cn.BackendHTTPURL, env, "http", "https")
	validateURL(v, "connection.backend_ws_url", cn.BackendWSURL, env, "ws", "wss")
	v.rng("connection.connect_timeout_ms", cn.ConnectTimeoutMS, 100, 60000)
	v.rng("connection.request_timeout_ms", cn.RequestTimeoutMS, 100, 60000)
	v.rng("connection.assignment_wait_seconds", cn.AssignmentWaitSeconds, 1, 25) // backend caps wait at 25
	v.rng("connection.reconnect_max_attempts", cn.ReconnectMaxAttempts, 0, 100)
	v.rng("connection.reconnect_backoff_base_ms", cn.ReconnectBackoffBaseMS, 10, 60000)
	v.rng("connection.reconnect_backoff_max_ms", cn.ReconnectBackoffMaxMS, 10, 300000)
	if cn.ReconnectBackoffMaxMS < cn.ReconnectBackoffBaseMS {
		v.addf("connection.reconnect_backoff_max_ms: must be >= reconnect_backoff_base_ms")
	}
	v.rng("connection.reconnect_reset_seconds", cn.ReconnectResetSeconds, 1, 3600)
	v.rng("connection.maintenance_backoff_seconds", cn.MaintenanceBackoffSeconds, 1, 3600)
	v.rng("connection.ping_interval_seconds", cn.PingIntervalSeconds, 1, 60)
	v.rng("connection.pong_timeout_seconds", cn.PongTimeoutSeconds, 1, 60)
	v.rng("connection.outbound_queue_size", cn.OutboundQueueSize, 8, 4096)
	v.rng("connection.read_limit_bytes", cn.ReadLimitBytes, 4096, 16<<20)
	switch cn.CompressionMode {
	case "no_context_takeover", "context_takeover", "disabled":
	default:
		v.addf("connection.compression_mode: must be no_context_takeover, context_takeover or disabled")
	}
	v.rng("connection.action_confirm_timeout_ms", cn.ActionConfirmTimeoutMS, 200, 60000)
	v.rng("connection.readiness_stale_seconds", cn.ReadinessStaleSeconds, 5, 3600)

	// bots
	b := c.Bots
	seen := map[string]bool{}
	for _, m := range b.Modes {
		if !slices.Contains([]string{ModePractice, ModePublicFill, ModeLoadtest}, m) {
			v.addf("bots.modes: unknown mode %q (want practice, public_fill, loadtest)", m)
		}
		if seen[m] {
			v.addf("bots.modes: duplicate mode %q", m)
		}
		seen[m] = true
	}
	if b.Enabled && len(b.Modes) == 0 {
		v.addf("bots.modes: at least one mode is required when bots.enabled is true")
	}
	if seen[ModeLoadtest] && len(b.Modes) > 1 {
		v.addf("bots.modes: loadtest is exclusive and cannot be combined with other modes")
	}
	for k := range b.Games {
		if !slices.Contains(GameKeys, k) {
			v.addf("bots.games: unknown game %q (want %s)", k, strings.Join(GameKeys, ", "))
		}
	}
	envCap := MaxConcurrentCap[env]
	if envCap == 0 {
		envCap = MaxConcurrentCap[EnvProduction]
	}
	v.rng("bots.max_concurrent_bots", b.MaxConcurrentBots, 1, envCap)
	v.rng("bots.target_active_bots", b.TargetActiveBots, 0, max(b.MaxConcurrentBots, 0))
	for k, n := range b.PerGameMax {
		if !slices.Contains(GameKeys, k) {
			v.addf("bots.per_game_max: unknown game %q", k)
		}
		v.rng("bots.per_game_max."+k, n, 0, max(b.MaxConcurrentBots, 0))
	}
	v.rng("bots.max_bots_per_room", b.MaxBotsPerRoom, 1, 3)
	v.frng("bots.max_room_joins_per_second", b.MaxRoomJoinsPerSecond, 0, 1000, true)
	v.frng("bots.max_connection_attempts_per_second", b.MaxConnectionAttemptsPerSecond, 0, 1000, true)
	v.rng("bots.lobby_wait_timeout_seconds", b.LobbyWaitTimeoutSeconds, 5, 600)

	pm := b.PublicMatchmaking
	for k := range pm.PerGame {
		if !slices.Contains(GameKeys, k) {
			v.addf("bots.public_matchmaking.per_game: unknown game %q", k)
		}
	}
	v.rng("bots.public_matchmaking.poll_interval_ms", pm.PollIntervalMS, 100, 60000)
	v.rng("bots.public_matchmaking.fill_after_seconds", pm.FillAfterSeconds, 0, 300)
	v.rng("bots.public_matchmaking.minimum_humans", pm.MinimumHumans, 1, 3)
	v.rng("bots.public_matchmaking.maximum_wait_seconds", pm.MaximumWaitSeconds, 1, 600)
	if pm.MaximumWaitSeconds <= pm.FillAfterSeconds {
		v.addf("bots.public_matchmaking.maximum_wait_seconds: must be > fill_after_seconds")
	}
	v.rng("bots.public_matchmaking.refill_cooldown_seconds", pm.RefillCooldownSeconds, 1, 600)

	tt := b.ThinkTime
	v.rng("bots.think_time.min_ms", tt.MinMS, 0, profiles.MaxThinkTimeMS)
	v.rng("bots.think_time.max_ms", tt.MaxMS, 0, profiles.MaxThinkTimeMS)
	if tt.MinMS > tt.MaxMS {
		v.addf("bots.think_time: min_ms (%d) must be <= max_ms (%d)", tt.MinMS, tt.MaxMS)
	}
	if strings.TrimSpace(b.Behavior.DefaultProfile) == "" {
		v.addf("bots.behavior.default_profile: required")
	}
	v.frng("bots.behavior.disconnect_probability", b.Behavior.DisconnectProbability, 0, 0.2, false)

	if p := b.Identity.DisplayNamePrefix; len(p) > 12 || !printable(p) {
		v.addf("bots.identity.display_name_prefix: must be <= 12 printable characters")
	}
	for i, n := range b.Identity.NamesPool {
		if n == "" || len(n) > 16 || !printable(n) {
			v.addf("bots.identity.names_pool[%d]: must be 1..16 printable characters", i)
		}
	}
	ch := b.Chat
	v.rng("bots.chat.max_per_match", ch.MaxPerMatch, 0, 10)
	v.rng("bots.chat.min_interval_ms", ch.MinIntervalMS, MinChatIntervalMS, 600000)
	v.rng("bots.chat.reaction_delay_ms.min", ch.ReactionDelayMS.Min, 0, profiles.MaxThinkTimeMS)
	v.rng("bots.chat.reaction_delay_ms.max", ch.ReactionDelayMS.Max, 0, profiles.MaxThinkTimeMS)
	if ch.ReactionDelayMS.Min > ch.ReactionDelayMS.Max {
		v.addf("bots.chat.reaction_delay_ms: min must be <= max")
	}
	v.frng("bots.chat.emote_share", ch.EmoteShare, 0, 1, false)
	pr := ch.Probability
	for _, f := range []struct {
		name string
		val  float64
	}{
		{"game_start", pr.GameStart}, {"six", pr.Six}, {"capture", pr.Capture}, {"captured", pr.Captured},
		{"other_capture", pr.OtherCapture}, {"win", pr.Win}, {"loss", pr.Loss},
	} {
		v.frng("bots.chat.probability."+f.name, f.val, 0, 1, false)
	}
	v.rng("bots.shutdown.graceful_timeout_seconds", b.Shutdown.GracefulTimeoutSeconds, 1, 3600)
	if b.Shutdown.Policy != PolicyFinishGames && b.Shutdown.Policy != PolicyLeaveNow {
		v.addf("bots.shutdown.policy: %q is not one of finish_games, leave_now", b.Shutdown.Policy)
	}

	// limits
	v.frng("limits.max_actions_per_second_per_bot", c.Limits.MaxActionsPerSecondPerBot, 0, 20, true)
	v.rng("limits.max_reconnect_attempts_per_minute", c.Limits.MaxReconnectAttemptsPerMinute, 1, 120)

	// loadtest
	lt := c.Loadtest
	if env == EnvProduction && (lt.Enabled || seen[ModeLoadtest]) {
		v.addf("loadtest: load-test mode can never be enabled in the production environment")
	}
	if seen[ModeLoadtest] && !lt.Enabled {
		v.addf("bots.modes: loadtest requires loadtest.enabled: true")
	}
	if lt.Enabled || seen[ModeLoadtest] {
		v.rng("loadtest.target_connections", lt.TargetConnections, 1, max(b.MaxConcurrentBots, 1))
		if len(lt.AllowedHosts) == 0 {
			v.addf("loadtest.allowed_hosts: at least one host is required")
		}
	}
	for i, h := range append(slices.Clone(lt.AllowedHosts), lt.ForbiddenHosts...) {
		if strings.TrimSpace(h) == "" || strings.ContainsAny(h, "/: ") {
			v.addf("loadtest hosts[%d]: %q must be a bare hostname or *.suffix pattern", i, h)
		}
	}
	v.frng("loadtest.ramp_per_second", lt.RampPerSecond, 0, 1000, true)
	v.rng("loadtest.duration_seconds", lt.DurationSeconds, 1, 86400)
	mixSum := 0.0
	for k, w := range lt.GameMix {
		if !slices.Contains(GameKeys, k) {
			v.addf("loadtest.game_mix: unknown game %q", k)
		}
		v.frng("loadtest.game_mix."+k, w, 0, 1e6, false)
		mixSum += w
	}
	if mixSum <= 0 {
		v.addf("loadtest.game_mix: at least one weight must be > 0")
	}
	capSum := 0.0
	for k, w := range lt.CapacityMix {
		if k < 2 || k > 4 {
			v.addf("loadtest.capacity_mix: capacity %d must be 2, 3 or 4", k)
		}
		v.frng(fmt.Sprintf("loadtest.capacity_mix.%d", k), w, 0, 1e6, false)
		capSum += w
	}
	if capSum <= 0 {
		v.addf("loadtest.capacity_mix: at least one weight must be > 0")
	}
	v.rng("loadtest.think_time_ms.min", lt.ThinkTimeMS.Min, 0, profiles.MaxThinkTimeMS)
	v.rng("loadtest.think_time_ms.max", lt.ThinkTimeMS.Max, 0, profiles.MaxThinkTimeMS)
	if lt.ThinkTimeMS.Min > lt.ThinkTimeMS.Max {
		v.addf("loadtest.think_time_ms: min must be <= max")
	}
	v.frng("loadtest.churn_per_minute", lt.ChurnPerMinute, 0, 100000, false)
	v.frng("loadtest.slow_reader_fraction", lt.SlowReaderFraction, 0, 1, false)
	v.rng("loadtest.slow_reader_delay_ms", lt.SlowReaderDelayMS, 0, 10000)
	v.frng("loadtest.malformed_message_rate", lt.MalformedMessageRate, 0, 0.5, false)
	if (lt.Enabled || seen[ModeLoadtest]) && strings.TrimSpace(lt.ReportPath) == "" {
		v.addf("loadtest.report_path: required when load testing")
	}

	// metrics
	if c.Metrics.Enabled {
		if _, _, err := net.SplitHostPort(c.Metrics.ListenAddr); err != nil {
			v.addf("metrics.listen_addr: %q is not host:port", c.Metrics.ListenAddr)
		}
	}
	return errors.Join(v.errs...)
}

// ValidateProfiles cross-checks the config against a profile set.
func (c *Config) ValidateProfiles(ps *profiles.Set) error {
	if ps == nil {
		return errors.New("profiles: not loaded")
	}
	if _, ok := ps.Get(c.Bots.Behavior.DefaultProfile); !ok {
		return fmt.Errorf("bots.behavior.default_profile: profile %q does not exist (have %s)",
			c.Bots.Behavior.DefaultProfile, strings.Join(ps.Names(), ", "))
	}
	return nil
}

func validateURL(v *verr, name, raw, env string, insecure, secure string) {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" || (u.Scheme != insecure && u.Scheme != secure) {
		v.addf("%s: %q must be an absolute %s:// or %s:// URL", name, raw, insecure, secure)
		return
	}
	if u.User != nil {
		v.addf("%s: credentials in URLs are not allowed", name)
	}
	if env == EnvProduction && u.Scheme != secure {
		v.addf("%s: production requires %s://", name, secure)
	}
}

func printable(s string) bool {
	for _, r := range s {
		if !unicode.IsPrint(r) {
			return false
		}
	}
	return true
}

// CheckReloadCompatible rejects runtime changes to settings that require a
// restart. The whole reload is rejected (and the previous config kept) when
// any of them changed.
func CheckReloadCompatible(old, next *Config) error {
	var errs []error
	chk := func(name string, changed bool) {
		if changed {
			errs = append(errs, fmt.Errorf("%s cannot change at runtime (restart required)", name))
		}
	}
	chk("app.environment", old.App.Environment != next.App.Environment)
	chk("connection.backend_http_url", old.Connection.BackendHTTPURL != next.Connection.BackendHTTPURL)
	chk("connection.backend_ws_url", old.Connection.BackendWSURL != next.Connection.BackendWSURL)
	chk("metrics.enabled", old.Metrics.Enabled != next.Metrics.Enabled)
	chk("metrics.listen_addr", old.Metrics.ListenAddr != next.Metrics.ListenAddr)
	chk("bots.modes (switching into or out of loadtest)", old.IsLoadtest() != next.IsLoadtest())
	chk("loadtest.enabled", old.Loadtest.Enabled != next.Loadtest.Enabled)
	chk("loadtest.allowed_hosts", !slices.Equal(old.Loadtest.AllowedHosts, next.Loadtest.AllowedHosts))
	chk("loadtest.forbidden_hosts", !slices.Equal(old.Loadtest.ForbiddenHosts, next.Loadtest.ForbiddenHosts))
	chk("loadtest.report_path", old.Loadtest.ReportPath != next.Loadtest.ReportPath)
	return errors.Join(errs...)
}
