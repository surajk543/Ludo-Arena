// Package server wires every backend component together. It is used by
// cmd/server and by the integration tests, so tests exercise the exact
// production wiring.
package server

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/apppolicy"
	"ludoroyale/internal/auth"
	"ludoroyale/internal/config"
	"ludoroyale/internal/gameevents"
	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/identity"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/notify"
	"ludoroyale/internal/playerinfo"
	"ludoroyale/internal/profile"
	"ludoroyale/internal/protocol"
	"ludoroyale/internal/ratelimit"
	"ludoroyale/internal/rooms"
	"ludoroyale/internal/wallet"
	"ludoroyale/internal/websocket"
)

// Extensions are optional subsystems registered by cmd/server (progression,
// social, analytics). Nil fields are skipped.
type Extensions struct {
	Progression  playerinfo.Provider
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
}

// NewCore builds the shared base services.
func NewCore(cfg *config.Config, log *slog.Logger, pg *pgxpool.Pool, rdb *redis.Client) *Core {
	return &Core{Cfg: cfg, Log: log, PG: pg, RDB: rdb,
		Profiles: profile.New(rdb, cfg.Auth.PublicIDKey), Notifier: notify.New(rdb, log),
		Wallets: wallet.NewStore(pg)}
}

// New assembles the application.
func New(ctx context.Context, core *Core, ext Extensions, dice rooms.Dice) (*App, error) {
	cfg, log := core.Cfg, core.Log
	policy, err := apppolicy.NewStore(cfg.Policy.File, cfg.Policy.FlagFile, cfg.Env, log)
	if err != nil {
		return nil, err
	}
	if ext.Progression == nil {
		ext.Progression = playerinfo.StarterProvider{}
	}
	ids := identity.NewStore(core.PG, identity.Welcome{Coins: cfg.Wallet.WelcomeCoins, Diamonds: cfg.Wallet.WelcomeDiamonds})
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
		Recorder: ext.Recorder, Inviter: ext.Inviter, Inventory: ext.Inventory, Policy: policy,
		BotAuth: botAuth, Limiter: limiter, Notifier: core.Notifier, Log: log, Game: cfg.Game,
		Bots: cfg.Bots, Env: cfg.Env, FullSnaps: cfg.WS.FullSnapshots, Dice: dice,
	})
	gw := websocket.New(cfg.WS, log, authSvc, policy, limiter, roomSvc, core.RDB, cfg.TrustedProxyHops)
	gw.OnHumanConnect = ext.OnActivity

	rt := httpapi.NewRouter(log, authSvc, policy, limiter, cfg.TrustedProxyHops)
	acct := &httpapi.Account{Log: log, Auth: authSvc, IDs: ids, Profiles: core.Profiles,
		Progression: ext.Progression, Policy: policy, Env: cfg.Env,
		Extra: func() map[string]any {
			return map[string]any{
				"rulesVersion": 1, "protocolVersion": protocol.Version,
				"entryFees":   map[string]int64{"ludo": cfg.Game.EntryFeeLudo, "snakes_ladders": cfg.Game.EntryFeeSnakes},
				"turnSeconds": int(cfg.Game.TurnTimeout.Seconds()),
				"welcome":     map[string]int64{"coins": cfg.Wallet.WelcomeCoins, "diamonds": cfg.Wallet.WelcomeDiamonds},
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
	mux := rt.Mux()
	mux.Handle("GET /api/v1/ws", gw)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		httpapi.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
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
		Gateway: gw, Router: rt, ext: ext}, nil
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
	for _, bg := range a.ext.Background {
		go bg(ctx)
	}
}
