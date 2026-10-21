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
	"ludoroyale/internal/assets"
	"ludoroyale/internal/wallet"
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

	// GameStatsInterval is how often the cluster-wide live-game gauges
	// (players_in_game, rooms_in_game, players_in_lobby) are recounted.
	GameStatsInterval time.Duration

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
	Social           SocialConfig
	// Assets is the private R2 bucket holding the profile pictures.
	Assets AssetsConfig

	// AdminKeySHA256 is the sha256 of the operator key sent as X-Admin-Key
	// to /api/v1/admin/*; empty disables the admin API (routes answer 404).
	AdminKeySHA256 []byte

	// NameChangesPerDay is how many successful display-name changes an
	// account may make per rolling 24 h (NAME_CHANGES_PER_DAY, >= 1).
	NameChangesPerDay int

	// IAP configures coin pack purchases (docs/in-app-purchases.md).
	IAP IAPConfig
}

// IAPConfig configures coin packs and store verification. Without a store's
// configuration its purchases answer 503 iap_unavailable (the Shop still
// lists the packs). Key files are read at startup and never logged.
type IAPConfig struct {
	// CoinPacksFile is the pack list (COIN_PACKS_FILE, default
	// config/coin_packs.json), reloaded when it changes.
	CoinPacksFile string

	// GooglePlayServiceAccountFile is the service account JSON key
	// (GOOGLE_PLAY_SERVICE_ACCOUNT_FILE); empty disables Google Play.
	GooglePlayServiceAccountFile string
	// GooglePlayPackage is the app package (GOOGLE_PLAY_PACKAGE_NAME).
	GooglePlayPackage string
	// GooglePlayAPIURL overrides the Android Publisher host (test hook,
	// GOOGLE_PLAY_API_URL; refused in production).
	GooglePlayAPIURL string
	// GoogleVoidedInterval is how often voided purchases are polled
	// (GOOGLE_PLAY_VOIDED_POLL_INTERVAL, default 1h; 0 disables).
	GoogleVoidedInterval time.Duration
	// GoogleVoidedLookback is how far back each poll looks
	// (GOOGLE_PLAY_VOIDED_LOOKBACK, default 168h, 1h..720h).
	GoogleVoidedLookback time.Duration

	// AppleEnabled turns on App Store verification (APPLE_IAP_ENABLED); it is
	// also on when the App Store Server API key is configured.
	AppleEnabled bool
	// AppleBundleID is the app bundle id (APPLE_BUNDLE_ID).
	AppleBundleID string
	// AppleAllowSandbox accepts sandbox transactions (APPLE_IAP_ALLOW_SANDBOX,
	// default true: App Review and TestFlight buy in the sandbox).
	AppleAllowSandbox bool
	// App Store Server API key (APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID,
	// APPLE_IAP_KEY_FILE): all three or none.
	AppleKeyID, AppleIssuerID, AppleKeyFile string
	// Test hooks (refused in production): APPLE_ROOT_CA_FILE replaces Apple
	// Root CA - G3, APPLE_IAP_API_URL the App Store Server API host.
	AppleRootCAFile, AppleAPIURL string
}

// GoogleEnabled reports whether Google Play purchases can be verified.
func (c IAPConfig) GoogleEnabled() bool { return c.GooglePlayServiceAccountFile != "" }

// AppleOn reports whether App Store purchases can be verified.
func (c IAPConfig) AppleOn() bool { return c.AppleEnabled || c.AppleKeyFile != "" }

// Defaults for IAPConfig.
const (
	DefaultAppPackage           = "com.ludoroyale.app"
	DefaultGoogleVoidedInterval = time.Hour
	DefaultGoogleVoidedLookback = 7 * 24 * time.Hour
)

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
	MaxStrikes              int // consecutive turn timeouts that forfeit a player
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

// DefaultMaxStrikes is the default MAX_STRIKES: consecutive missed turns
// (turn timeouts) after which a player is removed from the running game.
const DefaultMaxStrikes = 5

// DefaultNameChangesPerDay is the default NAME_CHANGES_PER_DAY.
const DefaultNameChangesPerDay = 3

// BotConfig configures the bot service boundary.
type BotConfig struct {
	ServiceKeySHA256  []byte // sha256 of the shared bot service key; empty disables bot APIs
	PublicFillEnabled bool
	MaxPerRoom        int
	LoadTestEnabled   bool
	SessionTTL        time.Duration
	AssignmentTTL     time.Duration
	// PictureShare is the long-run share of bot seats (0..1) that wear an
	// active profile picture (BOT_PICTURE_SHARE, default 0.3).
	PictureShare float64
	// PictureKeepMin..PictureKeepMax is how many matches a bot persona keeps
	// its picture (or no picture) before its wardrobe changes
	// (BOT_PICTURE_KEEP_MIN / BOT_PICTURE_KEEP_MAX, default 2..5).
	PictureKeepMin, PictureKeepMax int
	// PersonaTTL is how long an unused bot persona (look, level, picture,
	// stable public id) is remembered (BOT_PERSONA_TTL, default 30 days).
	PersonaTTL time.Duration
	// Coins are the coin rules of bot wallets: BOT_COINS_START (1 crore),
	// BOT_COINS_RECHARGE_BELOW (1 lakh) → BOT_COINS_RECHARGE_TO (1 crore),
	// BOT_COINS_RESET_ABOVE (10 crore) → BOT_COINS_RESET_TO (1 crore). See
	// backend/docs/game-rules.md "Coins with bots".
	Coins wallet.BotRules
}

// DefaultBotPictureShare is the default BOT_PICTURE_SHARE.
const DefaultBotPictureShare = 0.3

// AssetsConfig configures the private Cloudflare R2 bucket of the profile
// pictures (R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY:
// all four or none). Without it the Store still lists, sells and applies
// pictures, and POST /assets/sign answers 503 assets_unavailable. The
// secret is never logged.
type AssetsConfig struct {
	R2 assets.Config
	// URLTTL is how long signed GET URLs stay valid (ASSET_URL_TTL, default
	// 10m, 1m..1h).
	URLTTL time.Duration
}

// Enabled reports whether R2 is configured.
func (a AssetsConfig) Enabled() bool { return a.R2.Configured() }

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

// SocialConfig configures friends and player reports.
type SocialConfig struct {
	// FriendsMax is the maximum number of accepted friends per account
	// (FRIENDS_MAX, default 20). Accounts already above it keep their
	// friends but cannot add more.
	FriendsMax int
	// ReportsPerDay is how many player reports an account may file in any
	// rolling 24 h window (REPORTS_PER_DAY, default 2).
	ReportsPerDay int
}

// Defaults for SocialConfig.
const (
	DefaultFriendsMax    = 20
	DefaultReportsPerDay = 2
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
	getFloat := func(key string, def float64) float64 {
		raw := get(key, "")
		if raw == "" {
			return def
		}
		f, err := strconv.ParseFloat(raw, 64)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: not a number", key))
			return def
		}
		return f
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
	c.GameStatsInterval = getDur("GAME_STATS_INTERVAL", 15*time.Second)
	if c.GameStatsInterval < time.Second {
		errs = append(errs, errors.New("GAME_STATS_INTERVAL must be at least 1s"))
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
	c.NameChangesPerDay = getInt("NAME_CHANGES_PER_DAY", DefaultNameChangesPerDay)
	if c.NameChangesPerDay < 1 {
		errs = append(errs, errors.New("NAME_CHANGES_PER_DAY must be >= 1"))
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
		MaxStrikes:              getInt("MAX_STRIKES", DefaultMaxStrikes),
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
		PictureShare:      getFloat("BOT_PICTURE_SHARE", DefaultBotPictureShare),
		PictureKeepMin:    getInt("BOT_PICTURE_KEEP_MIN", 2),
		PictureKeepMax:    getInt("BOT_PICTURE_KEEP_MAX", 5),
		PersonaTTL:        getDur("BOT_PERSONA_TTL", 30*24*time.Hour),
		Coins: wallet.BotRules{
			Start:         int64(getInt("BOT_COINS_START", int(wallet.DefaultBotStart))),
			RechargeBelow: int64(getInt("BOT_COINS_RECHARGE_BELOW", int(wallet.DefaultBotRechargeBelow))),
			RechargeTo:    int64(getInt("BOT_COINS_RECHARGE_TO", int(wallet.DefaultBotRechargeTo))),
			ResetAbove:    int64(getInt("BOT_COINS_RESET_ABOVE", int(wallet.DefaultBotResetAbove))),
			ResetTo:       int64(getInt("BOT_COINS_RESET_TO", int(wallet.DefaultBotResetTo))),
		},
	}
	if err := c.Bots.Coins.Validate(); err != nil {
		errs = append(errs, err)
	}
	if c.Bots.PictureShare < 0 || c.Bots.PictureShare > 1 {
		errs = append(errs, errors.New("BOT_PICTURE_SHARE must be between 0 and 1"))
	}
	if c.Bots.PictureKeepMin < 1 || c.Bots.PictureKeepMax < c.Bots.PictureKeepMin || c.Bots.PictureKeepMax > 100 {
		errs = append(errs, errors.New("BOT_PICTURE_KEEP_MIN/MAX must satisfy 1 <= min <= max <= 100"))
	}
	if c.Bots.PersonaTTL < 24*time.Hour {
		errs = append(errs, errors.New("BOT_PERSONA_TTL must be at least 24h"))
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

	c.Social = SocialConfig{
		FriendsMax:    getInt("FRIENDS_MAX", DefaultFriendsMax),
		ReportsPerDay: getInt("REPORTS_PER_DAY", DefaultReportsPerDay),
	}
	if c.Social.FriendsMax < 1 {
		errs = append(errs, errors.New("FRIENDS_MAX must be >= 1"))
	}
	if c.Social.ReportsPerDay < 1 {
		errs = append(errs, errors.New("REPORTS_PER_DAY must be >= 1"))
	}
	if raw := get("ADMIN_API_KEY_SHA256", ""); raw != "" {
		b, err := hex.DecodeString(raw)
		if err != nil || len(b) != 32 {
			errs = append(errs, errors.New("ADMIN_API_KEY_SHA256 must be 64 hex characters"))
		} else {
			c.AdminKeySHA256 = b
		}
	}

	c.Assets = AssetsConfig{
		R2: assets.Config{
			AccountID: get("R2_ACCOUNT_ID", ""), Bucket: get("R2_BUCKET", ""),
			AccessKeyID: get("R2_ACCESS_KEY_ID", ""), SecretAccessKey: get("R2_SECRET_ACCESS_KEY", ""),
			// Test hook (fake R2); never set in production.
			Endpoint: get("R2_ENDPOINT", ""),
		},
		URLTTL: getDur("ASSET_URL_TTL", assets.DefaultURLTTL),
	}
	if c.Assets.URLTTL < assets.MinURLTTL || c.Assets.URLTTL > assets.MaxURLTTL {
		errs = append(errs, fmt.Errorf("ASSET_URL_TTL must be between %s and %s", assets.MinURLTTL, assets.MaxURLTTL))
	}
	if c.Assets.R2.Endpoint != "" && c.Env == EnvProduction {
		errs = append(errs, errors.New("R2_ENDPOINT is a test hook and is not allowed in production"))
	}
	if c.Assets.R2.Endpoint != "" && !c.Assets.Enabled() {
		errs = append(errs, errors.New("R2_ENDPOINT requires the four R2_* variables"))
	}
	if c.Assets.Enabled() {
		// All four or none: refuse a partial configuration at startup.
		if err := c.Assets.R2.Validate(); err != nil {
			errs = append(errs, err)
		}
	}

	c.IAP = IAPConfig{
		CoinPacksFile:                get("COIN_PACKS_FILE", "config/coin_packs.json"),
		GooglePlayServiceAccountFile: get("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE", ""),
		GooglePlayPackage:            get("GOOGLE_PLAY_PACKAGE_NAME", DefaultAppPackage),
		GooglePlayAPIURL:             get("GOOGLE_PLAY_API_URL", ""),
		GoogleVoidedInterval:         getDur("GOOGLE_PLAY_VOIDED_POLL_INTERVAL", DefaultGoogleVoidedInterval),
		GoogleVoidedLookback:         getDur("GOOGLE_PLAY_VOIDED_LOOKBACK", DefaultGoogleVoidedLookback),
		AppleEnabled:                 getBool("APPLE_IAP_ENABLED", false),
		AppleBundleID:                get("APPLE_BUNDLE_ID", DefaultAppPackage),
		AppleAllowSandbox:            getBool("APPLE_IAP_ALLOW_SANDBOX", true),
		AppleKeyID:                   get("APPLE_IAP_KEY_ID", ""),
		AppleIssuerID:                get("APPLE_IAP_ISSUER_ID", ""),
		AppleKeyFile:                 get("APPLE_IAP_KEY_FILE", ""),
		AppleRootCAFile:              get("APPLE_ROOT_CA_FILE", ""),
		AppleAPIURL:                  get("APPLE_IAP_API_URL", ""),
	}
	errs = append(errs, c.IAP.validate(c.Env)...)

	if len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	return c, nil
}

func (c IAPConfig) validate(env string) []error {
	var errs []error
	if c.GoogleVoidedInterval != 0 && (c.GoogleVoidedInterval < time.Second ||
		(env == EnvProduction && c.GoogleVoidedInterval < time.Minute)) {
		errs = append(errs, errors.New("GOOGLE_PLAY_VOIDED_POLL_INTERVAL must be 0 (off) or >= 1s (>= 1m in production)"))
	}
	if c.GoogleVoidedLookback < time.Hour || c.GoogleVoidedLookback > 30*24*time.Hour {
		errs = append(errs, errors.New("GOOGLE_PLAY_VOIDED_LOOKBACK must be between 1h and 720h"))
	}
	if n := countSet(c.AppleKeyID, c.AppleIssuerID, c.AppleKeyFile); n != 0 && n != 3 {
		errs = append(errs, errors.New("APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID and APPLE_IAP_KEY_FILE: set all three or none"))
	}
	if env == EnvProduction && (c.GooglePlayAPIURL != "" || c.AppleRootCAFile != "" || c.AppleAPIURL != "") {
		errs = append(errs, errors.New("GOOGLE_PLAY_API_URL, APPLE_ROOT_CA_FILE and APPLE_IAP_API_URL are test hooks and are not allowed in production"))
	}
	return errs
}

func countSet(vals ...string) int {
	n := 0
	for _, v := range vals {
		if v != "" {
			n++
		}
	}
	return n
}

// BotsEnabled reports whether the bot service boundary is configured.
func (c *Config) BotsEnabled() bool { return len(c.Bots.ServiceKeySHA256) == 32 }
