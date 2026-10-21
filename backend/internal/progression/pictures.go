package progression

// Profile-picture Store (docs/cosmetics-catalog.md → Profile pictures,
// docs/rest-api.md → Store).
//
// The catalogue is progression.profile_pictures (migrations 007/008). It is
// small (~160 rows) and read on hot paths (room seats, friend lists, asset
// signing), so every instance keeps an immutable in-memory snapshot: loaded
// when the service starts and reloaded every PictureReload (1 min) by Run,
// and at once after a purchase or apply names a row the snapshot does not
// have yet. An operator's UPDATE (price, name, order, active) therefore
// reaches every instance within a minute. Purchases and applies read the
// authoritative row in PostgreSQL inside their own statement, so a stale
// snapshot can never sell an inactive picture or charge an old price.
//
// Ownership is progression.inventory (item_id = picture id, forever) and the
// equipped picture is progression.loadout slot "avatar"
// (playerinfo.PictureSlot). The seat cache (cache.go) carries the equipped
// id, so a room join reads no PostgreSQL for it.

import (
	"context"
	"encoding/base64"
	"errors"
	"math/rand/v2"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"ludoroyale/internal/assets"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/playerinfo"
	"ludoroyale/internal/wallet"
)

// Store errors.
var (
	ErrPictureNotFound = errors.New("profile picture not found")
	ErrBadStoreQuery   = errors.New("bad store query")
)

// Store filters.
const (
	FilterAll      = "all"
	FilterAnimated = "animated" // lottie
	FilterStatic   = "static"   // image
	FilterOwned    = "owned"
)

// Store page sizes.
const (
	DefaultStorePageSize = 24
	MaxStorePageSize     = 50
)

// PictureReload is how often Run reloads the in-memory catalogue.
const PictureReload = time.Minute

// AssetSigner presigns object paths (assets.Signer).
type AssetSigner interface {
	SignAll(keys []string) (urls map[string]string, expiresAt time.Time)
}

// pictureRow is one catalogue row.
type pictureRow struct {
	ID        string
	Name      string
	Format    string
	Path      string
	Price     int64
	SortOrder int
	Active    bool
}

func (r *pictureRow) public() *playerinfo.Picture {
	return &playerinfo.Picture{ID: r.ID, Format: r.Format, Path: r.Path}
}

// after reports whether r sorts after the position (sortOrder, id).
func (r *pictureRow) after(sortOrder int, id string) bool {
	return r.SortOrder > sortOrder || (r.SortOrder == sortOrder && r.ID > id)
}

// pictureCatalog is an immutable snapshot of the catalogue.
type pictureCatalog struct {
	rows   []*pictureRow // sort_order, id
	active []*pictureRow
	byID   map[string]*pictureRow
	byPath map[string]*pictureRow
}

// pictures holds the current snapshot.
type pictures struct {
	cur    atomic.Pointer[pictureCatalog]
	loadMu sync.Mutex
}

func (p *pictures) get() *pictureCatalog {
	if c := p.cur.Load(); c != nil {
		return c
	}
	return &pictureCatalog{byID: map[string]*pictureRow{}, byPath: map[string]*pictureRow{}}
}

// loadCatalogue reads a catalogue table into an immutable snapshot. table
// is a constant: progression.profile_pictures or progression.emotes (the
// Store emotes, emotes.go), which have the same columns.
func (s *Service) loadCatalogue(ctx context.Context, table string) (*pictureCatalog, error) {
	rows, err := s.pool.Query(ctx, `SELECT id, name, format, path, price_diamonds, sort_order, active
		FROM `+table+` ORDER BY sort_order, id`)
	if err != nil {
		return nil, err
	}
	list, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (*pictureRow, error) {
		var r pictureRow
		err := row.Scan(&r.ID, &r.Name, &r.Format, &r.Path, &r.Price, &r.SortOrder, &r.Active)
		return &r, err
	})
	if err != nil {
		return nil, err
	}
	c := &pictureCatalog{rows: list, byID: make(map[string]*pictureRow, len(list)), byPath: make(map[string]*pictureRow, len(list))}
	for _, r := range list {
		c.byID[r.ID], c.byPath[r.Path] = r, r
		if r.Active {
			c.active = append(c.active, r)
		}
	}
	return c, nil
}

// ReloadPictures replaces the in-memory catalogue from PostgreSQL.
func (s *Service) ReloadPictures(ctx context.Context) error {
	s.pics.loadMu.Lock()
	defer s.pics.loadMu.Unlock()
	c, err := s.loadCatalogue(ctx, "progression.profile_pictures")
	if err != nil {
		metrics.ProfilePictureCatalogReloads.WithLabelValues("error").Inc()
		return err
	}
	s.pics.cur.Store(c)
	metrics.ProfilePictureCatalogReloads.WithLabelValues("ok").Inc()
	return nil
}

// ensurePicture reloads the snapshot when it does not know id yet (a row
// added since the last reload). Best effort.
func (s *Service) ensurePicture(ctx context.Context, id string) {
	if _, ok := s.pics.get().byID[id]; ok {
		return
	}
	if err := s.ReloadPictures(ctx); err != nil {
		s.log.Warn("profile picture catalogue reload failed", "error", err.Error())
	}
}

// runCatalogueReload reloads the profile-picture and Store emote catalogues
// every PictureReload until ctx ends.
func (s *Service) runCatalogueReload(ctx context.Context) {
	t := time.NewTicker(s.picReload)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		if err := s.ReloadPictures(ctx); err != nil && ctx.Err() == nil {
			s.log.Warn("profile picture catalogue reload failed; keeping the previous one", "error", err.Error())
		}
		if err := s.ReloadEmotes(ctx); err != nil && ctx.Err() == nil {
			s.log.Warn("emote catalogue reload failed; keeping the previous one", "error", err.Error())
		}
	}
}

// pictureRef is the public picture of a catalogue id (active or retired: an
// owner keeps a retired picture), or nil.
func (s *Service) pictureRef(id string) *playerinfo.Picture {
	if id == "" {
		return nil
	}
	if r := s.pics.get().byID[id]; r != nil {
		return r.public()
	}
	return nil
}

// RandomPicture implements playerinfo.PictureSource: a random active picture
// for a bot seat (no ownership, no wallet), or nil.
func (s *Service) RandomPicture() *playerinfo.Picture {
	active := s.pics.get().active
	if len(active) == 0 {
		return nil
	}
	return active[rand.IntN(len(active))].public()
}

var _ playerinfo.PictureSource = (*Service)(nil)

// ---------------------------------------------------------------- API types

// PicturePrice is the price object of a ProfilePicture.
type PicturePrice struct {
	Diamonds int64 `json:"diamonds"`
}

// ProfilePicture is the API ProfilePicture object.
type ProfilePicture struct {
	ID       string       `json:"id"`
	Name     string       `json:"name"`
	Format   string       `json:"format"`
	Path     string       `json:"path"`
	Price    PicturePrice `json:"price"`
	Owned    bool         `json:"owned"`
	Equipped bool         `json:"equipped"`
}

func (r *pictureRow) view(owned, equipped bool) ProfilePicture {
	return ProfilePicture{ID: r.ID, Name: r.Name, Format: r.Format, Path: r.Path,
		Price: PicturePrice{Diamonds: r.Price}, Owned: owned, Equipped: equipped}
}

// PicturePage is the GET /store/profile-pictures response.
type PicturePage struct {
	Items      []ProfilePicture `json:"items"`
	NextCursor *string          `json:"nextCursor"`
	Total      int              `json:"total"`
	Equipped   *string          `json:"equipped"`
}

// PicturePurchase is the purchase response.
type PicturePurchase struct {
	Item   ProfilePicture `json:"item"`
	Wallet wallet.Wallet  `json:"wallet"`
}

// EquippedPicture is the PUT /me/profile-picture response.
type EquippedPicture struct {
	Equipped *ProfilePicture `json:"equipped"`
}

// ------------------------------------------------------------------ cursor

func encodeCursor(r *pictureRow) string {
	return base64.RawURLEncoding.EncodeToString([]byte(strconv.Itoa(r.SortOrder) + ":" + r.ID))
}

// decodeCursor parses a shelf cursor whose id must satisfy validID (the
// catalogue's id shape).
func decodeCursor(c string, validID func(string) bool) (sortOrder int, id string, err error) {
	raw, err := base64.RawURLEncoding.DecodeString(c)
	if err != nil {
		return 0, "", ErrBadStoreQuery
	}
	so, id, ok := strings.Cut(string(raw), ":")
	n, err := strconv.Atoi(so)
	if !ok || err != nil || !validID(id) {
		return 0, "", ErrBadStoreQuery
	}
	return n, id, nil
}

// ------------------------------------------------------------------- store

// pictureState returns the account's owned picture ids and its equipped one
// (one PostgreSQL round trip).
func (s *Service) pictureState(ctx context.Context, userID uuid.UUID) (owned map[string]bool, equipped string, err error) {
	rows, err := s.pool.Query(ctx, `
		SELECT item_id, FALSE FROM progression.inventory WHERE user_id = $1 AND item_id LIKE 'pp\_%'
		UNION ALL
		SELECT item_id, TRUE FROM progression.loadout WHERE user_id = $1 AND slot = $2`, userID, playerinfo.PictureSlot)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()
	owned = map[string]bool{}
	for rows.Next() {
		var id string
		var isEquipped bool
		if err := rows.Scan(&id, &isEquipped); err != nil {
			return nil, "", err
		}
		if isEquipped {
			equipped = id
		} else {
			owned[id] = true
		}
	}
	return owned, equipped, rows.Err()
}

// StorePictures returns one page of the Store shelf for an account. filter
// is all | animated | static | owned (default all); limit 1..50 (0 = 24);
// cursor is the previous page's nextCursor. Retired (inactive) pictures are
// listed only to their owners. excludeOwned leaves out every picture the
// account owns (the app's Shop sells only what is not owned yet); it is not
// allowed with filter owned. Paging stays position based (sort_order, id),
// so a purchase between two pages never repeats or skips an item.
func (s *Service) StorePictures(ctx context.Context, userID uuid.UUID, filter string, excludeOwned bool, limit int, cursor string) (PicturePage, error) {
	if filter == "" {
		filter = FilterAll
	}
	switch filter {
	case FilterAll, FilterAnimated, FilterStatic:
	case FilterOwned:
		if excludeOwned {
			return PicturePage{}, ErrBadStoreQuery
		}
	default:
		return PicturePage{}, ErrBadStoreQuery
	}
	if limit == 0 {
		limit = DefaultStorePageSize
	}
	if limit < 1 || limit > MaxStorePageSize {
		return PicturePage{}, ErrBadStoreQuery
	}
	var (
		afterSort int
		afterID   string
	)
	if cursor != "" {
		var err error
		if afterSort, afterID, err = decodeCursor(cursor, assets.ValidPictureID); err != nil {
			return PicturePage{}, err
		}
	}
	owned, equipped, err := s.pictureState(ctx, userID)
	if err != nil {
		return PicturePage{}, err
	}
	cat := s.pics.get()
	page := PicturePage{Items: []ProfilePicture{}}
	if _, ok := cat.byID[equipped]; ok && owned[equipped] {
		page.Equipped = &equipped
	}
	var last *pictureRow
	for _, r := range cat.rows {
		visible := r.Active || owned[r.ID]
		switch filter {
		case FilterAnimated:
			visible = visible && r.Format == assets.FormatLottie
		case FilterStatic:
			visible = visible && r.Format == assets.FormatImage
		case FilterOwned:
			visible = owned[r.ID]
		}
		if excludeOwned && owned[r.ID] {
			visible = false
		}
		if !visible {
			continue
		}
		page.Total++
		if cursor != "" && !r.after(afterSort, afterID) {
			continue
		}
		if len(page.Items) < limit {
			page.Items = append(page.Items, r.view(owned[r.ID], page.Equipped != nil && *page.Equipped == r.ID))
			last = r
		} else if page.NextCursor == nil {
			next := encodeCursor(last)
			page.NextCursor = &next
		}
	}
	return page, nil
}

// PurchasePicture buys a picture with diamonds. Like the Collection purchase
// (collection.go), the progression row is locked first, then the inventory
// row is inserted and the wallet debited in the same transaction: an
// existing row (already owned) or a failed debit (insufficient diamonds)
// rolls everything back, so a picture is paid exactly once. The price and
// the active flag are read from PostgreSQL inside the transaction.
func (s *Service) PurchasePicture(ctx context.Context, userID uuid.UUID, id string) (*PicturePurchase, error) {
	if !assets.ValidPictureID(id) {
		return nil, ErrPictureNotFound
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if _, _, err := s.lockProgress(ctx, tx, userID); err != nil {
		return nil, err
	}
	r := pictureRow{ID: id}
	err = tx.QueryRow(ctx, `SELECT name, format, path, price_diamonds, sort_order, active
		FROM progression.profile_pictures WHERE id = $1`, id).
		Scan(&r.Name, &r.Format, &r.Path, &r.Price, &r.SortOrder, &r.Active)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && !r.Active) {
		return nil, ErrPictureNotFound
	}
	if err != nil {
		return nil, err
	}
	tag, err := tx.Exec(ctx, `INSERT INTO progression.inventory (user_id, item_id) VALUES ($1, $2)
		ON CONFLICT (user_id, item_id) DO NOTHING`, userID, id)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrAlreadyOwned
	}
	wal, err := wallet.AdjustTx(ctx, tx, userID, 0, -r.Price)
	if err != nil {
		return nil, err // wallet.ErrInsufficientFunds → rollback, no inventory row
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	s.ensurePicture(ctx, id)
	metrics.ProfilePicturePurchases.WithLabelValues(r.Format).Inc()
	s.notify(ctx, userID, MsgWalletUpdated, WalletUpdated{Coins: wal.Coins, Diamonds: wal.Diamonds,
		Delta: WalletDelta{Diamonds: -r.Price}, Reason: "purchase"})
	// A just-bought picture cannot be equipped yet (apply is separate).
	return &PicturePurchase{Item: r.view(true, false), Wallet: wal}, nil
}

// ApplyPicture equips an owned picture, or (id "") goes back to the built-in
// avatar. It takes effect for the next room join (the seat summary is
// invalidated; a seat already taken keeps its picture). A retired picture
// that the account owns can still be applied.
func (s *Service) ApplyPicture(ctx context.Context, userID uuid.UUID, id string) (*ProfilePicture, error) {
	if id == "" {
		if _, err := s.pool.Exec(ctx, `DELETE FROM progression.loadout WHERE user_id = $1 AND slot = $2`,
			userID, playerinfo.PictureSlot); err != nil {
			return nil, err
		}
		s.InvalidateSeat(ctx, userID)
		metrics.ProfilePictureEquips.WithLabelValues("remove").Inc()
		return nil, nil
	}
	if !assets.ValidPictureID(id) {
		return nil, ErrPictureNotFound
	}
	// One statement: the row must exist (404) and be owned (422).
	var exists, owned bool
	var r pictureRow
	err := s.pool.QueryRow(ctx, `
		WITH pic AS (
			SELECT id, name, format, path, price_diamonds, sort_order, active
			FROM progression.profile_pictures WHERE id = $2
		), own AS (
			SELECT 1 FROM progression.inventory WHERE user_id = $1 AND item_id = $2
		), ins AS (
			INSERT INTO progression.loadout (user_id, slot, item_id)
			SELECT $1, $3, $2 WHERE EXISTS (SELECT 1 FROM pic) AND EXISTS (SELECT 1 FROM own)
			ON CONFLICT (user_id, slot) DO UPDATE SET item_id = EXCLUDED.item_id
			RETURNING 1
		)
		SELECT EXISTS (SELECT 1 FROM pic), EXISTS (SELECT 1 FROM own),
		       coalesce((SELECT name FROM pic), ''), coalesce((SELECT format FROM pic), ''),
		       coalesce((SELECT path FROM pic), ''), coalesce((SELECT price_diamonds FROM pic), 0),
		       coalesce((SELECT sort_order FROM pic), 0), coalesce((SELECT active FROM pic), FALSE),
		       (SELECT count(*) FROM ins)`, userID, id, playerinfo.PictureSlot).
		Scan(&exists, &owned, &r.Name, &r.Format, &r.Path, &r.Price, &r.SortOrder, &r.Active, new(int64))
	if err != nil {
		return nil, mapFK(err)
	}
	switch {
	case !exists:
		return nil, ErrPictureNotFound
	case !owned:
		return nil, ErrItemLocked
	}
	r.ID = id
	s.InvalidateSeat(ctx, userID) // the next room seat shows the picture
	s.ensurePicture(ctx, id)
	metrics.ProfilePictureEquips.WithLabelValues("equip").Inc()
	v := r.view(true, true)
	return &v, nil
}

// SignAssetPaths presigns the catalogue paths among paths: profile pictures
// and Store emotes (unknown paths are left out, never signed). ok is false
// when no signer is configured.
func (s *Service) SignAssetPaths(paths []string) (urls map[string]string, expiresAt time.Time, ok bool) {
	if s.signer == nil {
		return nil, time.Time{}, false
	}
	pics, emos := s.pics.get(), s.emos.get()
	known := make([]string, 0, len(paths))
	seen := make(map[string]bool, len(paths))
	for _, p := range paths {
		_, isPic := pics.byPath[p]
		_, isEmote := emos.byPath[p]
		if in := isPic || isEmote; in && !seen[p] {
			seen[p] = true
			known = append(known, p)
		}
	}
	sort.Strings(known)
	urls, expiresAt = s.signer.SignAll(known)
	return urls, expiresAt, true
}
