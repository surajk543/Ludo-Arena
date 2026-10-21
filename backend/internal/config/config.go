// Package config loads backend configuration from environment variables.
// Secrets (signing keys, provider secrets, the bot service key hash) are only
// ever read from the environment and are never logged.
package config

import (
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"ludoroyale/internal/apppolicy"
)

// Environment names accepted by APP_ENV.
const (
	EnvDevelopment   = "development"
	EnvPreproduction = "preproduction"
	EnvProduction    = "production"
)

// Config is the complete backend configuration.
type Config struct {
	Env         string
	HTTPAddr    string
	MetricsAddr string
	LogLevel    string
	PublicURL   string // externally visible base URL, used for the Apple callback

	DatabaseURL   string
	DBMaxConns    int32
	RedisAddr     string
	RedisPassword string
	RedisDB       int
	RedisTLS      bool

	// RateLimitDisabled turns off Redis rate limits (load tests only; refused
	// in production).
	RateLimitDisabled bool

	// TrustedProxyHops is how many reverse proxies append to X-Forwarded-For.
	// 0 means the remote address of the TCP connection is the client.
	TrustedProxyHops int

	Auth   AuthConfig
	Policy PolicyConfig

	CatalogFile  string // cosmetics catalog (progression)
	MissionsFile string // missions/events config (progression)
	// LegalNoticesFile is the static open-source notices page served at
	// GET /legal/open-source (404 while missing).
	LegalNoticesFile string
	// MinMatchDuration is the anti-farming minimum length of a match that
	// earns XP and mission progress (>= 10 s in production).
	MinMatchDuration time.Duration
	WS               WSConfig
	Game             GameConfig
	Bots             BotConfig
	Wallet           WalletConfig
	Telemetry        TelemetryConfig
}

// AuthConfig configures application sessions and identity providers.
type AuthConfig struct {
	JWTSigningKey     []byte // HS256 key, >= 32 bytes
	JWTIssuer         string
	AccessTokenTTL    time.Duration
	RefreshTokenTTL   time.Duration
	PublicIDKey       []byte // HMAC key deriving public player ids
	GoogleClientIDs   []string
	AppleAudiences    []string // iOS bundle id and/or Services ID
	AppleAndroidPkg   string   // package for the Android intent redirect
	FacebookAppID     string
	FacebookAppSecret string
	// Test hooks: override provider JWKS endpoints (never set in production).
	GoogleJWKSURL    string
	AppleJWKSURL     string
	FacebookJWKSURL  string
	FacebookGraphURL string
}

// PolicyConfig configures the app version / maintenance policy.
type PolicyConfig struct {
	File         string
	FlagFile     string
	PollInterval time.Duration
}

// WSConfig configures the realtime gateway.
type WSConfig struct {
	CompressionMode      string // disabled | no_context_takeover | context_takeover
	CompressionThreshold int
	ReadLimit            int64
	OutboundQueue        int
	WriteTimeout         time.Duration
	PingInterval         time.Duration
	PongTimeout          time.Duration
	MsgRatePerSec        float64
	MsgBurst             int
	FullSnapshots        bool // benchmark mode: send a full snapshot with every event
	MaxConnections       int
}

// GameConfig configures room and turn timing.
type GameConfig struct {
	TurnTimeout             time.Duration
	TurnTimeoutDisconnected time.Duration
	MaxStrikes              int
	FillTimeout             time.Duration
	LobbyDisconnectGrace    time.Duration
	RematchWindow           time.Duration
	LobbyTTL                time.Duration
	FinishedTTL             time.Duration
	PracticeBotWait         time.Duration
	// EntryFeeLudo / EntryFeeSnakes are the fallback entry fees (ENTRY_FEE_*
	// or the built-in defaults). An "entryFees" value in the app-policy file
	// overrides them live; read the effective fee via rooms.Service.EntryFee.
	EntryFeeLudo   int64
	EntryFeeSnakes int64
}

// Built-in entry fee defaults in coins, used when neither the app-policy file
// nor ENTRY_FEE_LUDO / ENTRY_FEE_SNAKES set a value.
const (
	DefaultEntryFeeLudo   int64 = 100_000
	DefaultEntryFeeSnakes int64 = 50_000
)

// BotConfig configures the bot service boundary.
type BotConfig struct {
	ServiceKeySHA256  []byte // sha256 of the shared bot service key; empty disables bot APIs
	PublicFillEnabled bool
	MaxPerRoom        int
	LoadTestEnabled   bool
	SessionTTL        time.Duration
	AssignmentTTL     time.Duration
}

// WalletConfig configures the welcome grant fallbacks (WELCOME_* or the
// built-in defaults). A "welcome" object in the app-policy file overrides
// them live for accounts created afterwards.
type WalletConfig struct {
	WelcomeCoins    int64
	WelcomeDiamonds int64
}

// Built-in welcome grant defaults, used when neither the app-policy file nor
// WELCOME_COINS / WELCOME_DIAMONDS set a value.
const (
	DefaultWelcomeCoins    int64 = 1_000_000
	DefaultWelcomeDiamonds int64 = 50
)

// TelemetryConfig configures pseudonymous aggregate analytics.
type TelemetryConfig struct {
	ActiveUserKey []byte // HMAC key for daily/weekly active-user sketches
}

// Load reads configuration from the environment.
func Load() (*Config, error) {
	var errs []error
	get := func(key, def string) string {
		if v, ok := os.LookupEnv(key); ok && strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
		return def
	}
	getInt := func(key string, def int) int {
		raw := get(key, "")
		if raw == "" {
			return def
		}
		n, err := strconv.Atoi(raw)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: not an integer", key))
			return def
		}
		return n
	}
	getBool := func(key string, def bool) bool {
		raw := get(key, "")
		if raw == "" {
			return def
		}
		b, err := strconv.ParseBool(raw)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: not a boolean", key))
			return def
		}
		return b
	}
	getDur := func(key string, def time.Duration) time.Duration {
		raw := get(key, "")
		if raw == "" {
			return def
		}
		d, err := time.ParseDuration(raw)
		if err != nil {
			// Plain integers are seconds.
			if n, err2 := strconv.Atoi(raw); err2 == nil {
				return time.Duration(n) * time.Second
			}
			errs = append(errs, fmt.Errorf("%s: not a duration", key))
			return def
		}
		return d
	}
	getList := func(key string) []string {
		var out []string
		for _, part := range strings.Split(get(key, ""), ",") {
			if p := strings.TrimSpace(part); p != "" {
				out = append(out, p)
			}
		}
		return out
	}

	c := &Config{
		Env:               get("APP_ENV", EnvDevelopment),
		HTTPAddr:          get("HTTP_ADDR", ":8080"),
		MetricsAddr:       get("METRICS_ADDR", "127.0.0.1:9090"),
		LogLevel:          get("LOG_LEVEL", "info"),
		PublicURL:         strings.TrimRight(get("PUBLIC_URL", "http://localhost:8080"), "/"),
		DatabaseURL:       get("DATABASE_URL", ""),
		DBMaxConns:        int32(getInt("DB_MAX_CONNS", 20)),
		RedisAddr:         get("REDIS_ADDR", "127.0.0.1:6379"),
		RedisPassword:     get("REDIS_PASSWORD", ""),
		RedisDB:           getInt("REDIS_DB", 0),
		RedisTLS:          getBool("REDIS_TLS", false),
		TrustedProxyHops:  getInt("TRUSTED_PROXY_HOPS", 0),
		RateLimitDisabled: getBool("RATE_LIMIT_DISABLED", false),
	}
	if c.Env == EnvProduction && c.RateLimitDisabled {
		errs = append(errs, errors.New("RATE_LIMIT_DISABLED is not allowed in production"))
	}

	switch c.Env {
	case EnvDevelopment, EnvPreproduction, EnvProduction:
	default:
		errs = append(errs, fmt.Errorf("APP_ENV must be development, preproduction or production"))
	}
	if c.DatabaseURL == "" {
		errs = append(errs, errors.New("DATABASE_URL is required"))
	}

	signing := get("JWT_SIGNING_KEY", "")
	if len(signing) < 32 {
		errs = append(errs, errors.New("JWT_SIGNING_KEY must be at least 32 characters"))
	}
	publicIDKey := get("PUBLIC_ID_KEY", "")
	if len(publicIDKey) < 32 {
		errs = append(errs, errors.New("PUBLIC_ID_KEY must be at least 32 characters"))
	}
	c.Auth = AuthConfig{
		JWTSigningKey:     []byte(signing),
		JWTIssuer:         get("JWT_ISSUER", "ludo-royale"),
		AccessTokenTTL:    getDur("ACCESS_TOKEN_TTL", 15*time.Minute),
		RefreshTokenTTL:   getDur("REFRESH_TOKEN_TTL", 30*24*time.Hour),
		PublicIDKey:       []byte(publicIDKey),
		GoogleClientIDs:   getList("GOOGLE_CLIENT_IDS"),
		AppleAudiences:    getList("APPLE_AUDIENCES"),
		AppleAndroidPkg:   get("APPLE_ANDROID_PACKAGE", "com.ludoroyale.app"),
		FacebookAppID:     get("FACEBOOK_APP_ID", ""),
		FacebookAppSecret: get("FACEBOOK_APP_SECRET", ""),
		GoogleJWKSURL:     get("GOOGLE_JWKS_URL", "https://www.googleapis.com/oauth2/v3/certs"),
		AppleJWKSURL:      get("APPLE_JWKS_URL", "https://appleid.apple.com/auth/keys"),
		FacebookJWKSURL:   get("FACEBOOK_JWKS_URL", "https://limited.facebook.com/.well-known/oauth/openid/jwks/"),
		FacebookGraphURL:  get("FACEBOOK_GRAPH_URL", "https://graph.facebook.com"),
	}
	if c.Env == EnvProduction {
		// Provider endpoint overrides exist only for tests.
		if get("GOOGLE_JWKS_URL", "") != "" || get("APPLE_JWKS_URL", "") != "" ||
			get("FACEBOOK_JWKS_URL", "") != "" || get("FACEBOOK_GRAPH_URL", "") != "" {
			errs = append(errs, errors.New("provider endpoint overrides are not allowed in production"))
		}
	}

	c.CatalogFile = get("CATALOG_FILE", "config/catalog.json")
	c.MissionsFile = get("MISSIONS_FILE", "config/missions.json")
	c.LegalNoticesFile = get("LEGAL_NOTICES_FILE", "config/legal/open-source-notices.html")
	c.MinMatchDuration = getDur("PROGRESSION_MIN_MATCH_DURATION", 30*time.Second)
	if c.MinMatchDuration < 0 || (c.Env == EnvProduction && c.MinMatchDuration < 10*time.Second) {
		errs = append(errs, errors.New("PROGRESSION_MIN_MATCH_DURATION must be >= 10s in production and never negative"))
	}
	c.Policy = PolicyConfig{
		File:         get("APP_POLICY_FILE", "config/app-policy.development.json"),
		FlagFile:     get("APP_MAINTENANCE_FLAG_FILE", ""),
		PollInterval: getDur("APP_POLICY_POLL_SECONDS", 5*time.Second),
	}

	c.WS = WSConfig{
		CompressionMode:      get("WS_COMPRESSION", "no_context_takeover"),
		CompressionThreshold: getInt("WS_COMPRESSION_THRESHOLD", 1024),
		ReadLimit:            int64(getInt("WS_READ_LIMIT", 4096)),
		OutboundQueue:        getInt("WS_OUTBOUND_QUEUE", 128),
		WriteTimeout:         getDur("WS_WRITE_TIMEOUT", 10*time.Second),
		PingInterval:         getDur("WS_PING_INTERVAL", 20*time.Second),
		PongTimeout:          getDur("WS_PONG_TIMEOUT", 10*time.Second),
		MsgRatePerSec:        float64(getInt("WS_MSG_RATE", 10)),
		MsgBurst:             getInt("WS_MSG_BURST", 20),
		FullSnapshots:        getBool("WS_FULL_SNAPSHOTS", false),
		MaxConnections:       getInt("WS_MAX_CONNECTIONS", 50000),
	}
	switch c.WS.CompressionMode {
	case "disabled", "no_context_takeover", "context_takeover":
	default:
		errs = append(errs, errors.New("WS_COMPRESSION must be disabled, no_context_takeover or context_takeover"))
	}
	if c.WS.CompressionThreshold < 0 || c.WS.ReadLimit < 512 || c.WS.OutboundQueue < 8 {
		errs = append(errs, errors.New("WS_COMPRESSION_THRESHOLD >= 0, WS_READ_LIMIT >= 512 and WS_OUTBOUND_QUEUE >= 8 required"))
	}

	c.Game = GameConfig{
		TurnTimeout:             getDur("TURN_SECONDS", 20*time.Second),
		TurnTimeoutDisconnected: getDur("TURN_SECONDS_DISCONNECTED", 8*time.Second),
		MaxStrikes:              getInt("MAX_STRIKES", 3),
		FillTimeout:             getDur("MATCHMAKING_FILL_SECONDS", 30*time.Second),
		LobbyDisconnectGrace:    getDur("LOBBY_DISCONNECT_GRACE_SECONDS", 15*time.Second),
		RematchWindow:           getDur("REMATCH_SECONDS", 30*time.Second),
		LobbyTTL:                getDur("LOBBY_TTL", 30*time.Minute),
		FinishedTTL:             getDur("FINISHED_ROOM_TTL", 10*time.Minute),
		PracticeBotWait:         getDur("PRACTICE_BOT_WAIT_SECONDS", 20*time.Second),
		EntryFeeLudo:            int64(getInt("ENTRY_FEE_LUDO", int(DefaultEntryFeeLudo))),
		EntryFeeSnakes:          int64(getInt("ENTRY_FEE_SNAKES", int(DefaultEntryFeeSnakes))),
	}
	for _, f := range []struct {
		key string
		fee int64
	}{{"ENTRY_FEE_LUDO", c.Game.EntryFeeLudo}, {"ENTRY_FEE_SNAKES", c.Game.EntryFeeSnakes}} {
		if f.fee < 0 || f.fee > apppolicy.MaxEntryFee {
			errs = append(errs, fmt.Errorf("%s must be between 0 and %d", f.key, apppolicy.MaxEntryFee))
		}
	}
	if c.Game.MaxStrikes < 1 {
		errs = append(errs, errors.New("MAX_STRIKES must be >= 1"))
	}

	var botKey []byte
	if raw := get("BOT_SERVICE_KEY_SHA256", ""); raw != "" {
		b, err := hex.DecodeString(raw)
		if err != nil || len(b) != 32 {
			errs = append(errs, errors.New("BOT_SERVICE_KEY_SHA256 must be 64 hex characters"))
		}
		botKey = b
	}
	c.Bots = BotConfig{
		ServiceKeySHA256:  botKey,
		PublicFillEnabled: getBool("BOT_PUBLIC_FILL_ENABLED", false),
		MaxPerRoom:        getInt("BOT_MAX_PER_ROOM", 3),
		LoadTestEnabled:   getBool("BOT_LOADTEST_ENABLED", false),
		SessionTTL:        getDur("BOT_SESSION_TTL", 2*time.Hour),
		AssignmentTTL:     getDur("BOT_ASSIGNMENT_TTL", 30*time.Second),
	}
	if c.Bots.MaxPerRoom < 1 || c.Bots.MaxPerRoom > 3 {
		errs = append(errs, errors.New("BOT_MAX_PER_ROOM must be between 1 and 3"))
	}
	if c.Env == EnvProduction && c.Bots.LoadTestEnabled {
		errs = append(errs, errors.New("BOT_LOADTEST_ENABLED must be false in production"))
	}

	c.Wallet = WalletConfig{
		WelcomeCoins:    int64(getInt("WELCOME_COINS", int(DefaultWelcomeCoins))),
		WelcomeDiamonds: int64(getInt("WELCOME_DIAMONDS", int(DefaultWelcomeDiamonds))),
	}
	if c.Wallet.WelcomeCoins < 0 || c.Wallet.WelcomeCoins > apppolicy.MaxWelcomeCoins {
		errs = append(errs, fmt.Errorf("WELCOME_COINS must be between 0 and %d", apppolicy.MaxWelcomeCoins))
	}
	if c.Wallet.WelcomeDiamonds < 0 || c.Wallet.WelcomeDiamonds > apppolicy.MaxWelcomeDiamonds {
		errs = append(errs, fmt.Errorf("WELCOME_DIAMONDS must be between 0 and %d", apppolicy.MaxWelcomeDiamonds))
	}
	c.Telemetry = TelemetryConfig{ActiveUserKey: []byte(get("ACTIVE_USER_KEY", publicIDKey))}

	if len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	return c, nil
}

// BotsEnabled reports whether the bot service boundary is configured.
func (c *Config) BotsEnabled() bool { return len(c.Bots.ServiceKeySHA256) == 32 }
