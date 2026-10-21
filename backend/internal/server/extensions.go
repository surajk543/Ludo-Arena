package server

import (
	"context"
	"errors"
	"os"

	"github.com/google/uuid"

	"ludoroyale/internal/analytics"
	"ludoroyale/internal/assets"
	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/iap"
	"ludoroyale/internal/progression"
	"ludoroyale/internal/reports"
	"ludoroyale/internal/rooms"
	"ludoroyale/internal/social"
)

// DefaultExtensions wires progression (XP, missions, Collection Room),
// social (friends, invites, recent opponents, leaderboard), player reports,
// coin pack purchases and pseudonymous analytics exactly as production runs
// them.
func DefaultExtensions(_ context.Context, core *Core) (Extensions, error) {
	minMatch := core.Cfg.MinMatchDuration
	opts := progression.Options{
		CatalogPath: core.Cfg.CatalogFile, MissionsPath: core.Cfg.MissionsFile, MinMatchDuration: &minMatch,
	}
	// Profile pictures live in a private R2 bucket; without R2 the Store still
	// works and POST /assets/sign answers 503 assets_unavailable.
	if core.Cfg.Assets.Enabled() {
		signer, err := assets.NewSigner(core.Cfg.Assets.R2, core.Cfg.Assets.URLTTL, nil)
		if err != nil {
			return Extensions{}, err
		}
		opts.Assets = signer
	} else {
		core.Log.Warn("R2 not configured: profile-picture downloads (POST /assets/sign) are unavailable")
	}
	prog, err := progression.New(core.PG, core.RDB, core.Profiles, core.Notifier, core.Log, opts)
	if err != nil {
		return Extensions{}, err
	}
	// social subscribes itself to prog for recent opponents; prog stays the
	// single match Recorder.
	soc := social.New(core.PG, core.RDB, core.Profiles, prog, core.Notifier, core.Log,
		social.Options{MaxFriends: core.Cfg.Social.FriendsMax, Bots: botLookup(core)})
	rep := reports.New(core.PG, core.Profiles, prog, roomLookup(core), core.Log, reports.Options{
		PerDay: core.Cfg.Social.ReportsPerDay, AdminKeySHA256: core.Cfg.AdminKeySHA256})
	tracker := analytics.New(core.RDB, core.Cfg.Telemetry.ActiveUserKey, core.Log)
	purchases, err := newIAP(core)
	if err != nil {
		return Extensions{}, err
	}
	packsPoll := func(ctx context.Context) { purchases.Catalog().Run(ctx, core.Cfg.Policy.PollInterval) }
	return Extensions{
		Progression: prog, Pictures: prog, Catalog: prog, Recorder: prog, Inviter: soc, Inventory: prog,
		Routes: []func(rt *httpapi.Router){prog.Register, soc.Register, rep.Register, tracker.Register,
			purchases.Register},
		OnNewAccount: func(ctx context.Context, id uuid.UUID) {
			// Off the sign-up request path. Every progression read and write
			// also creates the row lazily, so a late, failed or dropped
			// bootstrap is harmless (async_jobs_total{job="new_account"}).
			core.Async.Go("new_account", func(ctx context.Context) error { return prog.Bootstrap(ctx, id) })
			_ = tracker.Touch(ctx, id) // Redis only
		},
		// Humans only: the gateway never calls this for bot sessions.
		OnActivity: func(ctx context.Context, id uuid.UUID) { _ = tracker.Touch(ctx, id) },
		Background: []func(ctx context.Context){prog.Run, tracker.Run, packsPoll, purchases.RunVoided},
	}, nil
}

// newIAP wires coin pack purchases (docs/in-app-purchases.md). A store
// without configuration answers 503 iap_unavailable; a configured store
// whose key file is unreadable or invalid stops the startup.
func newIAP(core *Core) (*iap.Service, error) {
	cfg := core.Cfg.IAP
	packs, err := iap.LoadCatalog(cfg.CoinPacksFile, core.Log)
	if err != nil {
		return nil, err
	}
	opts := iap.Options{TokenKey: core.Cfg.Auth.PublicIDKey,
		VoidedInterval: cfg.GoogleVoidedInterval, VoidedLookback: cfg.GoogleVoidedLookback}
	if cfg.GoogleEnabled() {
		if opts.Google, err = iap.NewGooglePlay(iap.GoogleConfig{ServiceAccountFile: cfg.GooglePlayServiceAccountFile,
			PackageName: cfg.GooglePlayPackage, APIURL: cfg.GooglePlayAPIURL}); err != nil {
			return nil, err
		}
	} else {
		core.Log.Warn("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE not set: Google Play coin pack purchases answer 503 iap_unavailable")
	}
	if cfg.AppleOn() {
		ac := iap.AppleConfig{BundleID: cfg.AppleBundleID, AllowSandbox: cfg.AppleAllowSandbox,
			KeyID: cfg.AppleKeyID, IssuerID: cfg.AppleIssuerID, KeyFile: cfg.AppleKeyFile, APIURL: cfg.AppleAPIURL}
		if cfg.AppleRootCAFile != "" {
			if ac.RootCA, err = os.ReadFile(cfg.AppleRootCAFile); err != nil {
				return nil, errors.New("APPLE_ROOT_CA_FILE cannot be read")
			}
		}
		if opts.Apple, err = iap.NewAppStore(ac); err != nil {
			return nil, err
		}
	} else {
		core.Log.Warn("APPLE_IAP_ENABLED not set: App Store coin pack purchases answer 503 iap_unavailable")
	}
	return iap.New(core.PG, core.RDB, core.Notifier, core.Log, packs, opts), nil
}

// roomLookup reads live rooms (read-only) for the player-report seat checks.
func roomLookup(core *Core) reports.RoomLookup {
	return func(ctx context.Context, roomID string) (reports.RoomInfo, error) {
		r, err := rooms.LoadRoom(ctx, core.RDB, roomID)
		if errors.Is(err, rooms.ErrRoomGone) {
			return reports.RoomInfo{}, reports.ErrRoomGone
		}
		if err != nil {
			return reports.RoomInfo{}, err
		}
		info := reports.RoomInfo{Game: r.Game, Seats: make([]reports.Seat, len(r.Players))}
		for i, p := range r.Players {
			info.Seats[i] = reports.Seat{UserID: p.UserID, UID: p.UID, Bot: p.Bot,
				Name: p.Name, Avatar: p.Avatar, Picture: p.Picture, Level: p.Level}
		}
		return info, nil
	}
}

// botLookup finds a bot seat by public id for friend requests to bots
// (social.Options.Bots): in the requester's active room, else while the
// bot's session is live.
func botLookup(core *Core) social.BotLookup {
	return func(ctx context.Context, me uuid.UUID, uid string) (social.BotProfile, error) {
		p, err := rooms.FindBotSeat(ctx, core.RDB, me.String(), uid)
		if errors.Is(err, rooms.ErrNoBotSeat) {
			return social.BotProfile{}, social.ErrUnknownPlayer
		}
		if err != nil {
			return social.BotProfile{}, err
		}
		return social.BotProfile{UID: p.UID, Name: p.Name, Avatar: p.Avatar, Picture: p.Picture, Level: p.Level,
			Title: p.Title}, nil
	}
}
