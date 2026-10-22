// Package server wires every backend component together. It is used by
// cmd/server and by the integration tests, so tests exercise the exact
// production wiring.
package server

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/account"
	"ludoarena/internal/apppolicy"
	"ludoarena/internal/async"
	"ludoarena/internal/auth"
	"ludoarena/internal/buildinfo"
	"ludoarena/internal/config"
	"ludoarena/internal/gameevents"
	"ludoarena/internal/httpapi"
	"ludoarena/internal/iap"
	"ludoarena/internal/identity"
	"ludoarena/internal/legal"
	"ludoarena/internal/metrics"
	"ludoarena/internal/notify"
	"ludoarena/internal/playerinfo"
	"ludoarena/internal/profile"
	"ludoarena/internal/progression"
	"ludoarena/internal/protocol"
	"ludoarena/internal/ratelimit"
	"ludoarena/internal/reports"
	"ludoarena/internal/rooms"
	"ludoarena/internal/social"
	"ludoarena/internal/wallet"
	"ludoarena/internal/websocket"
)

// Extensions are optional subsystems registered by cmd/server (progression,
// social, analytics). Nil fields are skipped.
type Extensions struct {
	Progression  playerinfo.Provider
	Pictures     playerinfo.PictureSource
	Catalog      playerinfo.CatalogSource
	Recorder     gameevents.Recorder
	Inviter      gameevents.Inviter
	Inventory    gameevents.Inventory
	Routes       []func(rt *httpapi.Router)
	OnNewAccount func(ctx context.Context, userID uuid.UUID)
	OnActivity   func(ctx context.Context, userID uuid.UUID) // humans only (analytics)
	Background   []func(ctx context.Context)
}

// App is a fully wired backend.
type App struct {
	Cfg      *config.Config
	Log      *slog.Logger
	PG       *pgxpool.Pool
	RDB      *redis.Client
	Policy   *apppolicy.Store
	Auth     *auth.Service
	BotAuth  *auth.BotAuth
	IDs      *identity.Store
	Wallets  *wallet.Store
	Profiles *profile.Service
	Notifier *notify.Publisher
	Rooms    *rooms.Service
	Gateway  *websocket.Gateway
	Router   *httpapi.Router
	Legal    *legal.Notices
	Async    *async.Runner
	ext      Extensions
}

// Core holds the pieces Extensions may need before the App is assembled.
type Core struct {
	Cfg      *config.Config
	Log      *slog.Logger
	PG       *pgxpool.Pool
	RDB      *redis.Client
	Profiles *profile.Service
	Notifier *notify.Publisher
	Wallets  *wallet.Store
	// Async runs best-effort work off the request path (bounded queue,
	// drained on shutdown); see docs/architecture.md → PostgreSQL on the hot path.
	Async *async.Runner
}

// NewCore builds the shared base services.
func NewCore(cfg *config.Config, log *slog.Logger, pg *pgxpool.Pool, rdb *redis.Client) *Core {
	// Player-chosen display names live in PostgreSQL (authoritative) and the
	// Redis profile cache; see package profile.
	profiles := profile.New(rdb, cfg.Auth.PublicIDKey).
		WithPostgres(pg, profile.Options{NameChangesPerDay: cfg.NameChangesPerDay})
	return &Core{Cfg: cfg, Log: log, PG: pg, RDB: rdb,
		Profiles: profiles, Notifier: notify.New(rdb, log),
		Wallets: wallet.NewStore(pg), Async: async.New(async.Options{Log: log})}
}

// New assembles the application.
func New(ctx context.Context, core *Core, ext Extensions, dice rooms.Dice) (*App, error) {
	cfg, log := core.Cfg, core.Log
	if err := checkDice(cfg.Env, dice); err != nil {
		return nil, err
	}
	policy, err := apppolicy.NewStore(cfg.Policy.File, cfg.Policy.FlagFile, cfg.Env, log)
	if err != nil {
		return nil, err
	}
	if ext.Progression == nil {
		ext.Progression = playerinfo.StarterProvider{}
	}
	// The welcome grant is live: app-policy "welcome" > WELCOME_* > default,
	// read when each account is created (never re-applied to old accounts).
	welcome := func() identity.Welcome {
		coins, diamonds := policy.Welcome(cfg.Wallet.WelcomeCoins, cfg.Wallet.WelcomeDiamonds)
		return identity.Welcome{Coins: coins, Diamonds: diamonds}
	}
	ids := identity.NewStoreWithGrant(core.PG, welcome)
	signer := auth.NewSigner(cfg.Auth.JWTSigningKey, cfg.Auth.JWTIssuer)
	sessions := auth.NewSessions(core.RDB, cfg.Auth.RefreshTokenTTL)
	verifier := auth.NewVerifier(ctx, auth.ProviderConfig{
		GoogleClientIDs: cfg.Auth.GoogleClientIDs, GoogleJWKSURL: cfg.Auth.GoogleJWKSURL,
		AppleAudiences: cfg.Auth.AppleAudiences, AppleJWKSURL: cfg.Auth.AppleJWKSURL,
		FacebookAppID: cfg.Auth.FacebookAppID, FacebookAppSecret: cfg.Auth.FacebookAppSecret,
		FacebookJWKSURL: cfg.Auth.FacebookJWKSURL, FacebookGraphURL: cfg.Auth.FacebookGraphURL,
	})
	authSvc := auth.NewService(signer, sessions, ids, core.Profiles, verifier, cfg.Auth.AccessTokenTTL, cfg.Auth.RefreshTokenTTL)
	authSvc.OnNewAccount = ext.OnNewAccount
	botAuth := auth.NewBotAuth(cfg.Bots.ServiceKeySHA256, signer, sessions)
	limiter := ratelimit.New(core.RDB, log, cfg.RateLimitDisabled)
	if cfg.RateLimitDisabled {
		log.Warn("RATE LIMITS DISABLED (load-test configuration)")
	}

	roomSvc := rooms.New(rooms.Deps{
		RDB: core.RDB, Wallets: core.Wallets, Profiles: core.Profiles, Progression: ext.Progression,
		Pictures: ext.Pictures, Catalog: ext.Catalog, Recorder: ext.Recorder, Inviter: ext.Inviter, Inventory: ext.Inventory, Policy: policy,
		BotAuth: botAuth, Limiter: limiter, Notifier: core.Notifier, Log: log, Game: cfg.Game,
		Bots: cfg.Bots, Env: cfg.Env, FullSnaps: cfg.WS.FullSnapshots, Dice: dice,
		StatsInterval: cfg.GameStatsInterval,
	})
	gw := websocket.New(cfg.WS, log, authSvc, policy, limiter, roomSvc, core.RDB, cfg.TrustedProxyHops)
	gw.OnHumanConnect = ext.OnActivity
	// One live human session per account: a sign-in elsewhere closes the
	// replaced session's WebSocket on whichever instance holds it.
	authSvc.OnSessionReplaced = func(ctx context.Context, userID uuid.UUID, oldSessionID string) {
		gw.RevokeSession(context.WithoutCancel(ctx), userID.String(), oldSessionID)
	}

	rt := httpapi.NewRouter(log, authSvc, policy, limiter, cfg.TrustedProxyHops)
	// DELETE /api/v1/account: leaves the active room, erases the account in
	// PostgreSQL, revokes its sessions, closes its socket, purges Redis.
	account.New(account.Deps{PG: core.PG, RDB: core.RDB, Log: log, Auth: authSvc, Profiles: core.Profiles,
		Limiter: limiter, LeaveRoom: roomSvc.LeaveActive, CloseSockets: gw.CloseAccount,
		UserRules: accountRateRules()}).Register(rt)
	acct := &httpapi.Account{Log: log, Auth: authSvc, IDs: ids, Profiles: core.Profiles,
		Progression: ext.Progression, Policy: policy, Env: cfg.Env,
		DeviceKey: identity.DeviceKey(cfg.Auth.PublicIDKey),
		Extra: func() map[string]any {
			// Entry fees and the welcome grant are live (app policy, per request).
			w := welcome()
			return map[string]any{
				"rulesVersion": 1, "protocolVersion": protocol.Version,
				"entryFees":   roomSvc.EntryFees(),
				"turnSeconds": int(cfg.Game.TurnTimeout.Seconds()),
				"welcome":     map[string]int64{"coins": w.Coins, "diamonds": w.Diamonds},
			}
		}}
	acct.Register(rt)
	httpapi.RegisterAppleCallback(rt, cfg.Auth.AppleAndroidPkg)
	roomSvc.RegisterRoutes(rt)
	if botAuth.Enabled() {
		roomSvc.RegisterBotRoutes(rt, cfg.Env)
	}
	for _, reg := range ext.Routes {
		reg(rt)
	}
	notices := legal.New(cfg.LegalNoticesFile, log)
	notices.Register(rt)
	mux := rt.Mux()
	mux.Handle("GET /api/v1/ws", gw)
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		httpapi.WriteJSON(w, http.StatusOK, buildinfo.Health())
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		cctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := core.PG.Ping(cctx); err != nil {
			httpapi.WriteJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "postgres unavailable"})
			return
		}
		if err := core.RDB.Ping(cctx).Err(); err != nil {
			httpapi.WriteJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "redis unavailable"})
			return
		}
		httpapi.WriteJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})

	return &App{Cfg: cfg, Log: log, PG: core.PG, RDB: core.RDB, Policy: policy, Auth: authSvc, BotAuth: botAuth,
		IDs: ids, Wallets: core.Wallets, Profiles: core.Profiles, Notifier: core.Notifier, Rooms: roomSvc,
		Gateway: gw, Router: rt, Legal: notices, Async: core.Async, ext: ext}, nil
}

// Handler is the public HTTP handler.
func (a *App) Handler() http.Handler { return a.Router.Mux() }

// MetricsHandler serves Prometheus metrics (bind to an internal address).
func (a *App) MetricsHandler() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /metrics", metrics.Handler())
	return mux
}

// Start runs background loops until ctx is cancelled.
func (a *App) Start(ctx context.Context) {
	go a.Policy.Run(ctx, a.Cfg.Policy.PollInterval)
	go a.Gateway.Run(ctx)
	go a.Rooms.RunScheduler(ctx, 16)
	go a.Legal.Run(ctx)
	go a.Rooms.RunGameStats(ctx)
	go a.Async.Run(ctx)
	for _, bg := range a.ext.Background {
		go bg(ctx)
	}
}

// Wait blocks until background work has drained after the Start context was
// cancelled (bounded by the runner's drain timeout) or ctx is done.
func (a *App) Wait(ctx context.Context) error { return a.Async.Wait(ctx) }

// accountRateRules lists every rate limit keyed by account id; deleting an
// account removes their counters (ratelimit.Limiter.Forget).
func accountRateRules() []ratelimit.Rule {
	rules := []ratelimit.Rule{
		ratelimit.LinkPerUser, ratelimit.ProfilePerUser, ratelimit.RoomCodePerUser, ratelimit.MatchmakePerUser,
		ratelimit.WalletOpPerUser, ratelimit.SocialPerUser, ratelimit.WSConnectPerUser, ratelimit.AccountDeletePerUser,
		social.InvitePerUser, social.FriendRequestPerHour, social.ReadPerUser,
		progression.ReadPerUser, progression.LoadoutPerUser,
		reports.WritePerUser, reports.ReadPerUser,
		iap.ReadPerUser, iap.PurchasePerUser,
	}
	return append(rules, rooms.ChatRules()...)
}

// checkDice refuses any dice source other than crypto/rand in production
// (nil means the default CryptoDice). Deterministic dice exist for tests and
// load tests only.
func checkDice(env string, dice rooms.Dice) error {
	if env != config.EnvProduction || dice == nil {
		return nil
	}
	if _, ok := dice.(rooms.CryptoDice); ok {
		return nil
	}
	return errors.New("server: only crypto/rand dice are allowed in production")
}
