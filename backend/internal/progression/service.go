// Package progression owns XP and levels, level milestones, daily/weekly
// missions and events, reward claims, the Collection Room (inventory, loadout,
// purchases) and finished-match recording for human players.
//
// Durable state lives in the PostgreSQL schema `progression` (see
// migrations/003_progression.sql and docs/progression.md). Every currency
// change goes through wallet.AdjustTx inside the same transaction as the
// claim / purchase / receipt row whose primary key makes it exactly-once.
// Redis holds only ephemeral data: the weekly XP leaderboard and cached
// idempotent responses.
package progression

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"regexp"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/assets"
	"ludoarena/internal/gameevents"
	"ludoarena/internal/playerinfo"
	"ludoarena/internal/profile"
)

// Errors.
var (
	ErrUnknownUser     = errors.New("unknown account")
	ErrUnknownPlayer   = errors.New("unknown public player id")
	ErrMissionNotFound = errors.New("mission not found in a current period")
	ErrNotCompleted    = errors.New("mission not completed")
	ErrAlreadyClaimed  = errors.New("mission reward already claimed")
	ErrItemNotFound    = errors.New("item not found")
	ErrItemLocked      = errors.New("item not owned or not purchasable")
	ErrAlreadyOwned    = errors.New("item already owned")
	ErrWrongSlot       = errors.New("item does not fit this slot")
	ErrUnknownSlot     = errors.New("unknown loadout slot")
)

// WebSocket message types pushed through the Notifier.
const (
	MsgProgressionUpdated = "progression.updated"
	MsgWalletUpdated      = "wallet.updated"
)

// Redis TTLs.
const (
	leaderboardTTL = 21 * 24 * time.Hour
	idempotencyTTL = 24 * time.Hour
)

// Retention (docs/progression.md → Retention).
const (
	ReceiptRetention = 14 * 24 * time.Hour
	MissionRetention = 60 * 24 * time.Hour
)

// Options configure the service.
type Options struct {
	CatalogPath  string           // default "config/catalog.json"
	MissionsPath string           // default "config/missions.json"
	Now          func() time.Time // default time.Now (tests inject a clock)
	// PurgeInterval is how often Run purges expired rows (default 1 h).
	PurgeInterval time.Duration
	// MinMatchDuration overrides the anti-farming minimum match length
	// (default MinMatchDuration; set PROGRESSION_MIN_MATCH_DURATION).
	MinMatchDuration *time.Duration
	// Assets presigns profile-picture paths (POST /assets/sign); nil when R2
	// is not configured (the route then answers 503 assets_unavailable).
	Assets AssetSigner
	// PictureReload is how often Run reloads the profile-picture catalogue
	// (default PictureReload).
	PictureReload time.Duration
	// PlaytimeFlush is how much unsaved daily playtime Redis may hold before
	// it is written to PostgreSQL (PLAYTIME_FLUSH_INTERVAL; default
	// DefaultPlaytimeFlush).
	PlaytimeFlush time.Duration
}

// MatchObserver is called after a finished match was recorded (social uses
// it for recent opponents). It must be idempotent: a match may be delivered
// more than once.
type MatchObserver func(ctx context.Context, rec gameevents.MatchRecord)

// Service implements playerinfo.Provider, gameevents.Recorder and
// gameevents.Inventory, and serves the progression/collection REST API.
type Service struct {
	pool     *pgxpool.Pool
	rdb      *redis.Client
	profiles *profile.Service
	notifier gameevents.Notifier
	log      *slog.Logger
	now      func() time.Time
	catalog  *Catalog
	missions *MissionConfig
	purgeInt time.Duration
	minMatch time.Duration

	pics      pictures      // profile-picture catalogue snapshot (pictures.go)
	emos      pictures      // Store emote catalogue snapshot (emotes.go)
	picReload time.Duration // catalogue reload interval
	signer    AssetSigner   // nil: asset signing unavailable

	ptFlush time.Duration  // daily playtime flush interval (playtime.go)
	ptWG    sync.WaitGroup // background playtime work (waited for by Run)

	mu        sync.RWMutex
	observers []MatchObserver
}

var (
	_ playerinfo.Provider  = (*Service)(nil)
	_ gameevents.Recorder  = (*Service)(nil)
	_ gameevents.Inventory = (*Service)(nil)
)

// New loads and validates the catalog and missions configuration. notifier
// may be nil (no pushes).
func New(pool *pgxpool.Pool, rdb *redis.Client, profiles *profile.Service, notifier gameevents.Notifier,
	log *slog.Logger, opts Options) (*Service, error) {
	if opts.CatalogPath == "" {
		opts.CatalogPath = "config/catalog.json"
	}
	if opts.MissionsPath == "" {
		opts.MissionsPath = "config/missions.json"
	}
	if opts.Now == nil {
		opts.Now = time.Now
	}
	if opts.PurgeInterval <= 0 {
		opts.PurgeInterval = time.Hour
	}
	if opts.PictureReload <= 0 {
		opts.PictureReload = PictureReload
	}
	if opts.PlaytimeFlush <= 0 {
		opts.PlaytimeFlush = DefaultPlaytimeFlush
	}
	if log == nil {
		log = slog.Default()
	}
	cat, err := LoadCatalog(opts.CatalogPath)
	if err != nil {
		return nil, err
	}
	ms, err := LoadMissions(opts.MissionsPath, cat)
	if err != nil {
		return nil, err
	}
	log.Info("progression config loaded", "catalogVersion", cat.Version, "items", len(cat.Items()),
		"missionsVersion", ms.Version, "dailyPool", len(ms.Daily), "events", len(ms.Events),
		"playtime", ms.Playtime != nil && ms.Playtime.Enabled)
	minMatch := MinMatchDuration
	if opts.MinMatchDuration != nil {
		minMatch = *opts.MinMatchDuration
	}
	s := &Service{pool: pool, rdb: rdb, profiles: profiles, notifier: notifier, log: log, now: opts.Now,
		catalog: cat, missions: ms, purgeInt: opts.PurgeInterval, minMatch: minMatch,
		picReload: opts.PictureReload, signer: opts.Assets, ptFlush: opts.PlaytimeFlush}
	// The profile-picture catalogue is loaded once here (migrations have
	// seeded it) and reloaded by Run.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := s.ReloadPictures(ctx); err != nil {
		return nil, fmt.Errorf("load profile-picture catalogue: %w", err)
	}
	if err := s.ReloadEmotes(ctx); err != nil {
		return nil, fmt.Errorf("load emote catalogue: %w", err)
	}
	log.Info("profile-picture and emote catalogues loaded", "pictures", len(s.pics.get().rows),
		"active", len(s.pics.get().active), "emotes", len(s.emos.get().rows),
		"activeEmotes", len(s.emos.get().active), "assetSigning", s.signer != nil)
	return s, nil
}

// Catalog returns the cosmetics catalog.
func (s *Service) Catalog() *Catalog { return s.catalog }

// CatalogItems implements playerinfo.CatalogSource (bot personas): the
// cosmetics catalogue plus the active Store emotes, which a persona may own
// like a player who bought them (no wallet, no inventory).
func (s *Service) CatalogItems() []playerinfo.CatalogItem {
	items := s.catalog.BotItems()
	for _, r := range s.emos.get().active {
		items = append(items, playerinfo.CatalogItem{ID: r.ID, Kind: KindEmote, Purchase: true, StoreEmote: true})
	}
	return items
}

var _ playerinfo.CatalogSource = (*Service)(nil)

// MissionConfig returns the missions configuration.
func (s *Service) MissionConfig() *MissionConfig { return s.missions }

// Now returns the service clock.
func (s *Service) Now() time.Time { return s.now() }

// OnMatch registers an observer for recorded matches.
func (s *Service) OnMatch(fn MatchObserver) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.observers = append(s.observers, fn)
}

// LeaderboardKey is the Redis ZSET of weekly XP per account for a week key.
func LeaderboardKey(weekKey string) string { return "lb:xp:" + weekKey }

// ---------------------------------------------------------------- accounts

// insertProgress lazily creates the progression row of an account: a wallet
// row that is not a bot's (bot wallets never get progression rows). The
// conflict target is deliberately omitted so both unique indexes (user_id,
// public_id) arbitrate: with `ON CONFLICT (user_id)` two concurrent first
// inserts for the same account fail on the public_id index with 23505.
const insertProgress = `
	INSERT INTO progression.player_progress (user_id, public_id)
	SELECT w.user_id, $2 FROM wallet.wallets w WHERE w.user_id = $1 AND NOT w.is_bot
	ON CONFLICT DO NOTHING`

// Bootstrap creates the account's progression row (idempotent). Call it for
// new accounts; every other entry point also creates the row lazily. It
// returns ErrUnknownUser when userID is not an account (no wallet, or a bot's).
func (s *Service) Bootstrap(ctx context.Context, userID uuid.UUID) error {
	tag, err := s.pool.Exec(ctx, insertProgress, userID, s.profiles.PublicID(userID))
	if err != nil {
		return mapFK(err)
	}
	if tag.RowsAffected() == 1 {
		return nil
	}
	var exists bool
	if err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM progression.player_progress WHERE user_id = $1)`,
		userID).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return ErrUnknownUser
	}
	return nil
}

// lockProgress ensures the row exists and locks it for the transaction. Every
// write transaction for an account starts here, so writes for one account are
// serialized (no deadlocks, consistent level-up detection).
func (s *Service) lockProgress(ctx context.Context, tx pgx.Tx, userID uuid.UUID) (xp int64, level int, err error) {
	pub := s.profiles.PublicID(userID)
	if _, err := tx.Exec(ctx, insertProgress, userID, pub); err != nil {
		return 0, 0, mapFK(err)
	}
	var stored string
	err = tx.QueryRow(ctx, `SELECT xp, level, public_id FROM progression.player_progress WHERE user_id = $1 FOR UPDATE`,
		userID).Scan(&xp, &level, &stored)
	if errors.Is(err, pgx.ErrNoRows) {
		// The account was deleted while this transaction waited for the lock.
		return 0, 0, ErrUnknownUser
	}
	if err != nil {
		return 0, 0, err
	}
	if stored != pub { // PUBLIC_ID_KEY changed: keep the durable mapping in sync
		if _, err := tx.Exec(ctx, `UPDATE progression.player_progress SET public_id = $2 WHERE user_id = $1`, userID, pub); err != nil {
			return 0, 0, err
		}
	}
	return xp, level, nil
}

// LockAccountsTx ensures and locks the progression rows of several accounts in
// id order (social uses it to serialize friend-graph changes).
func (s *Service) LockAccountsTx(ctx context.Context, tx pgx.Tx, ids ...uuid.UUID) error {
	for _, id := range ids {
		if _, err := tx.Exec(ctx, insertProgress, id, s.profiles.PublicID(id)); err != nil {
			return mapFK(err)
		}
	}
	rows, err := tx.Query(ctx, `SELECT user_id FROM progression.player_progress WHERE user_id = ANY($1) ORDER BY user_id FOR UPDATE`, ids)
	if err != nil {
		return err
	}
	locked := map[uuid.UUID]bool{}
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		locked[id] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	for _, id := range ids {
		if !locked[id] { // deleted while this transaction waited for the lock
			return ErrUnknownUser
		}
	}
	return nil
}

func mapFK(err error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23503" {
		return ErrUnknownUser
	}
	return err
}

var publicIDPattern = regexp.MustCompile(`^u_[a-z0-9]{6,32}$`)

// ResolvePublicID maps a public player id (friend code) to its account using
// the durable progression.player_progress.public_id column, falling back to
// the Redis profile cache (and then persisting the mapping).
func (s *Service) ResolvePublicID(ctx context.Context, uid string) (uuid.UUID, error) {
	if !publicIDPattern.MatchString(uid) {
		return uuid.Nil, ErrUnknownPlayer
	}
	var id uuid.UUID
	err := s.pool.QueryRow(ctx, `SELECT user_id FROM progression.player_progress WHERE public_id = $1`, uid).Scan(&id)
	if err == nil {
		return id, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, err
	}
	id, err = s.profiles.Resolve(ctx, uid)
	if err != nil || s.profiles.PublicID(id) != uid {
		return uuid.Nil, ErrUnknownPlayer
	}
	if err := s.Bootstrap(ctx, id); err != nil {
		if errors.Is(err, ErrUnknownUser) {
			return uuid.Nil, ErrUnknownPlayer
		}
		return uuid.Nil, err
	}
	return id, nil
}

// --------------------------------------------------------------- summaries

// Summary implements playerinfo.Provider.
func (s *Service) Summary(ctx context.Context, userID uuid.UUID) (playerinfo.Summary, error) {
	m, err := s.Summaries(ctx, []uuid.UUID{userID})
	if err != nil {
		return playerinfo.Summary{}, err
	}
	return m[userID], nil
}

// Summaries implements playerinfo.Provider. Accounts without a progression
// row get one lazily; ids that are not accounts (bots) get the starter summary.
func (s *Service) Summaries(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]playerinfo.Summary, error) {
	out := make(map[uuid.UUID]playerinfo.Summary, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	type prog struct {
		xp    int64
		level int
	}
	found := map[uuid.UUID]prog{}
	rows, err := s.pool.Query(ctx, `SELECT user_id, xp, level FROM progression.player_progress WHERE user_id = ANY($1)`, ids)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var id uuid.UUID
		var p prog
		if err := rows.Scan(&id, &p.xp, &p.level); err != nil {
			rows.Close()
			return nil, err
		}
		found[id] = p
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	var missing []uuid.UUID
	var pubs []string
	for _, id := range ids {
		if _, ok := found[id]; !ok {
			missing = append(missing, id)
			pubs = append(pubs, s.profiles.PublicID(id))
		}
	}
	if len(missing) > 0 {
		// Lazily create rows for real accounts only (bots have no wallet,
		// or a bot wallet, which never gets progression rows).
		if _, err := s.pool.Exec(ctx, `
			INSERT INTO progression.player_progress (user_id, public_id)
			SELECT w.user_id, x.pid FROM unnest($1::uuid[], $2::text[]) AS x(uid, pid)
			  JOIN wallet.wallets w ON w.user_id = x.uid AND NOT w.is_bot
			ON CONFLICT DO NOTHING`, missing, pubs); err != nil {
			return nil, err
		}
	}
	loadouts, pics, err := s.loadoutRows(ctx, s.pool, ids)
	if err != nil {
		return nil, err
	}
	for _, id := range ids {
		p, ok := found[id]
		if !ok {
			p = prog{level: 1}
		}
		l := loadouts[id]
		out[id] = playerinfo.Summary{Level: p.level, XP: p.xp, LevelXP: LevelStartXP(p.level),
			NextLevelXP: XPToNext(p.level), Title: l["title"], Loadout: l, Picture: s.pictureRef(pics[id])}
	}
	return out, nil
}

type querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// loadouts returns the effective loadout per account (starter fallback for
// missing slots and for stale rows that no longer match the catalog).
func (s *Service) loadouts(ctx context.Context, q querier, ids []uuid.UUID) (map[uuid.UUID]map[string]string, error) {
	lo, _, err := s.loadoutRows(ctx, q, ids)
	return lo, err
}

// loadoutRows returns loadouts() and, separately, the equipped profile
// picture id per account (loadout slot playerinfo.PictureSlot; never part of
// the Collection loadout).
func (s *Service) loadoutRows(ctx context.Context, q querier, ids []uuid.UUID) (map[uuid.UUID]map[string]string, map[uuid.UUID]string, error) {
	out := make(map[uuid.UUID]map[string]string, len(ids))
	pics := map[uuid.UUID]string{}
	for _, id := range ids {
		out[id] = playerinfo.StarterLoadout()
	}
	rows, err := q.Query(ctx, `SELECT user_id, slot, item_id FROM progression.loadout WHERE user_id = ANY($1)`, ids)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id uuid.UUID
		var slot, item string
		if err := rows.Scan(&id, &slot, &item); err != nil {
			return nil, nil, err
		}
		if slot == playerinfo.PictureSlot {
			pics[id] = item
			continue
		}
		if it := s.catalog.Get(item); it != nil && it.Kind == slot && out[id] != nil {
			out[id][slot] = item
		}
	}
	return out, pics, rows.Err()
}

// ---------------------------------------------------------------- inventory

// Owns implements gameevents.Inventory. Starter items are always owned.
// Store emotes (em_… ids, emotes.go) are answered like the other non-starter
// emotes, from the cached set of owned emotes.
func (s *Service) Owns(ctx context.Context, userID uuid.UUID, itemID string) (bool, error) {
	if assets.ValidEmoteID(itemID) {
		return s.ownsStoreEmote(ctx, userID, itemID)
	}
	it := s.catalog.Get(itemID)
	if it == nil {
		return false, nil
	}
	if it.Starter() {
		return true, nil
	}
	if it.Kind == KindEmote {
		return s.ownsEmote(ctx, userID, itemID) // chat hot path: Redis set (cache.go)
	}
	return s.ownsStored(ctx, userID, itemID)
}

// owned returns the stored (non-starter) items of an account.
func (s *Service) owned(ctx context.Context, q querier, userID uuid.UUID) (map[string]bool, error) {
	rows, err := q.Query(ctx, `SELECT item_id FROM progression.inventory WHERE user_id = $1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out[id] = true
	}
	return out, rows.Err()
}

// grantItemTx adds an item to the inventory; it reports whether it was new.
func grantItemTx(ctx context.Context, tx pgx.Tx, userID uuid.UUID, it *Item) (bool, error) {
	if it == nil || it.Starter() {
		return false, nil
	}
	tag, err := tx.Exec(ctx, `INSERT INTO progression.inventory (user_id, item_id) VALUES ($1, $2)
		ON CONFLICT (user_id, item_id) DO NOTHING`, userID, it.ID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// xpResult is the outcome of an XP grant.
type xpResult struct {
	oldXP, xp       int64
	oldLevel, level int
	unlocked        []*Item // milestone items newly granted
}

// addXPTx adds gained XP to a locked progress row, raises the level and grants
// every milestone item up to the new level (catch-up safe: existing rows are
// skipped by the inventory primary key).
func (s *Service) addXPTx(ctx context.Context, tx pgx.Tx, userID uuid.UUID, oldXP int64, oldLevel int, gained int64) (xpResult, error) {
	r := xpResult{oldXP: oldXP, xp: oldXP + gained, oldLevel: oldLevel, level: oldLevel}
	if gained <= 0 {
		return r, nil
	}
	if l := LevelForXP(r.xp); l > r.level {
		r.level = l
	}
	if _, err := tx.Exec(ctx, `UPDATE progression.player_progress SET xp = $2, level = $3, updated_at = now() WHERE user_id = $1`,
		userID, r.xp, r.level); err != nil {
		return r, err
	}
	if r.level > oldLevel {
		for _, lvl := range s.catalog.MilestoneLevels() {
			if lvl > r.level {
				break
			}
			for _, it := range s.catalog.Milestone(lvl) {
				isNew, err := grantItemTx(ctx, tx, userID, it)
				if err != nil {
					return r, err
				}
				if isNew {
					r.unlocked = append(r.unlocked, it)
				}
			}
		}
	}
	return r, nil
}

// ------------------------------------------------------------- side effects

func (s *Service) notify(ctx context.Context, userID uuid.UUID, msgType string, payload any) {
	if s.notifier == nil {
		return
	}
	s.notifier.NotifyUser(ctx, userID, msgType, payload)
}

// addWeeklyXP feeds the friends leaderboard (ephemeral; best effort).
func (s *Service) addWeeklyXP(ctx context.Context, userID uuid.UUID, at time.Time, xp int64) {
	if xp <= 0 || s.rdb == nil {
		return
	}
	key := LeaderboardKey(WeekKey(at))
	pipe := s.rdb.Pipeline()
	pipe.ZIncrBy(ctx, key, float64(xp), userID.String())
	pipe.Expire(ctx, key, leaderboardTTL)
	if _, err := pipe.Exec(ctx); err != nil {
		s.log.Warn("weekly leaderboard update failed", "error", err.Error())
	}
}

// WalletDelta is the `delta` of a wallet.updated message.
type WalletDelta struct {
	Coins    int64 `json:"coins"`
	Diamonds int64 `json:"diamonds"`
}

// WalletUpdated is the wallet.updated payload.
type WalletUpdated struct {
	Coins    int64       `json:"coins"`
	Diamonds int64       `json:"diamonds"`
	Delta    WalletDelta `json:"delta"`
	Reason   string      `json:"reason"`
}

// MissionProgress is one entry of progression.updated `missions`.
type MissionProgress struct {
	ID        string `json:"id"`
	Progress  int    `json:"progress"`
	Target    int    `json:"target"`
	Completed bool   `json:"completed"`
}

// ProgressionUpdated is the progression.updated payload.
type ProgressionUpdated struct {
	XP       int64             `json:"xp"`
	Level    int               `json:"level"`
	XPGained int64             `json:"xpGained"`
	LevelUp  bool              `json:"levelUp,omitempty"`
	Unlocked []string          `json:"unlocked"`
	Missions []MissionProgress `json:"missions"`
}

func itemIDs(items []*Item) []string {
	out := make([]string, 0, len(items))
	for _, it := range items {
		out = append(out, it.ID)
	}
	return out
}

// ------------------------------------------------------------------- purge

// PurgeResult counts deleted rows.
type PurgeResult struct {
	Receipts, Progress, Claims int64
}

// Purge deletes match receipts older than 14 days and mission progress /
// claims older than 60 days (never rows of a currently running period).
func (s *Service) Purge(ctx context.Context) (PurgeResult, error) {
	now := s.now()
	var active []string
	for _, p := range s.missions.ActivePeriods(now) {
		active = append(active, p.Key)
	}
	var res PurgeResult
	var err error
	if res.Receipts, err = s.purgeBatches(ctx, `DELETE FROM progression.match_receipts WHERE ctid IN (
		SELECT ctid FROM progression.match_receipts WHERE processed_at < $1 LIMIT 5000)`, now.Add(-ReceiptRetention)); err != nil {
		return res, err
	}
	if res.Progress, err = s.purgeBatches(ctx, `DELETE FROM progression.mission_progress WHERE ctid IN (
		SELECT ctid FROM progression.mission_progress WHERE updated_at < $1 AND period_key <> ALL($2) LIMIT 5000)`,
		now.Add(-MissionRetention), active); err != nil {
		return res, err
	}
	if res.Claims, err = s.purgeBatches(ctx, `DELETE FROM progression.mission_claims WHERE ctid IN (
		SELECT ctid FROM progression.mission_claims WHERE claimed_at < $1 AND period_key <> ALL($2) LIMIT 5000)`,
		now.Add(-MissionRetention), active); err != nil {
		return res, err
	}
	return res, nil
}

// waitPlaytime waits for background playtime work, at most d.
func (s *Service) waitPlaytime(d time.Duration) {
	done := make(chan struct{})
	go func() { s.ptWG.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(d):
		s.log.Warn("shutdown: playtime work still running; its intervals may be lost")
	}
}

func (s *Service) purgeBatches(ctx context.Context, sql string, args ...any) (int64, error) {
	var total int64
	for {
		tag, err := s.pool.Exec(ctx, sql, args...)
		if err != nil {
			return total, err
		}
		total += tag.RowsAffected()
		if tag.RowsAffected() < 5000 {
			return total, nil
		}
		if err := ctx.Err(); err != nil {
			return total, err
		}
	}
}

// Run executes the periodic retention purge (and the profile-picture
// catalogue reload) until ctx is cancelled, then waits (up to 5 s) for
// background playtime work. Running it on several instances is harmless.
func (s *Service) Run(ctx context.Context) {
	go s.runCatalogueReload(ctx)
	t := time.NewTimer(time.Minute)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			s.waitPlaytime(5 * time.Second)
			return
		case <-t.C:
		}
		res, err := s.Purge(ctx)
		if err != nil && ctx.Err() == nil {
			s.log.Warn("progression purge failed", "error", err.Error())
		} else if res.Receipts+res.Progress+res.Claims > 0 {
			s.log.Info("progression purge", "receipts", res.Receipts, "missionProgress", res.Progress, "missionClaims", res.Claims)
		}
		t.Reset(s.purgeInt)
	}
}
