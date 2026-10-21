package progression

// Store emotes (docs/cosmetics-catalog.md → Store emotes, docs/rest-api.md →
// Store).
//
// The catalogue is progression.emotes (migrations 010/011), shaped like the
// profile pictures and kept the same way: an immutable in-memory snapshot per
// instance, loaded at start, reloaded every PictureReload by Run and at once
// after a purchase names a row the snapshot does not have yet. Purchases read
// the authoritative row in PostgreSQL inside their own transaction.
//
// Ownership is progression.inventory (item_id = emote id, forever). Emotes
// are owned, not equipped: an owned Store emote is sent with chat.emote like
// the catalogue emotes, and its ownership check uses the same Redis set
// (emotes:{userId}, cache.go), so PostgreSQL stays off the chat hot path. The
// room engine adds the emote's art (path, format) to the chat.emote broadcast
// so every receiver can download and cache it (EmoteAsset).

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"ludoroyale/internal/assets"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/wallet"
)

// ErrEmoteNotFound: no active Store emote with that id.
var ErrEmoteNotFound = errors.New("emote not found")

// ReloadEmotes replaces the in-memory Store emote catalogue from PostgreSQL.
func (s *Service) ReloadEmotes(ctx context.Context) error {
	s.emos.loadMu.Lock()
	defer s.emos.loadMu.Unlock()
	c, err := s.loadCatalogue(ctx, "progression.emotes")
	if err != nil {
		metrics.StoreEmoteCatalogReloads.WithLabelValues("error").Inc()
		return err
	}
	s.emos.cur.Store(c)
	metrics.StoreEmoteCatalogReloads.WithLabelValues("ok").Inc()
	return nil
}

// ensureEmote reloads the snapshot when it does not know id yet (a row added
// since the last reload). Best effort.
func (s *Service) ensureEmote(ctx context.Context, id string) {
	if _, ok := s.emos.get().byID[id]; ok {
		return
	}
	if err := s.ReloadEmotes(ctx); err != nil {
		s.log.Warn("emote catalogue reload failed", "error", err.Error())
	}
}

// EmoteAsset implements gameevents.Inventory: the art of a Store emote
// (active or retired: owners keep a retired emote), or ok false for any other
// id (catalogue emotes are drawn by the app itself).
func (s *Service) EmoteAsset(itemID string) (path, format string, ok bool) {
	if r := s.emos.get().byID[itemID]; r != nil {
		return r.Path, r.Format, true
	}
	return "", "", false
}

// ownsStoreEmote answers Owns for an em_… id from the cached set of owned
// emotes (cache.go). An owned id the snapshot does not know yet (added on
// another instance less than a reload ago) reloads it, so the broadcast can
// carry its art; ids nobody owns never trigger a reload.
func (s *Service) ownsStoreEmote(ctx context.Context, userID uuid.UUID, itemID string) (bool, error) {
	ok, err := s.ownsEmote(ctx, userID, itemID)
	if err == nil && ok {
		s.ensureEmote(ctx, itemID)
	}
	return ok, err
}

// ---------------------------------------------------------------- API types

// ShopEmote is the API ShopEmote object.
type ShopEmote struct {
	ID     string       `json:"id"`
	Name   string       `json:"name"`
	Format string       `json:"format"`
	Path   string       `json:"path"`
	Price  PicturePrice `json:"price"`
	Owned  bool         `json:"owned"`
}

func emoteView(r *pictureRow, owned bool) ShopEmote {
	return ShopEmote{ID: r.ID, Name: r.Name, Format: r.Format, Path: r.Path,
		Price: PicturePrice{Diamonds: r.Price}, Owned: owned}
}

// EmotePage is the GET /store/emotes response.
type EmotePage struct {
	Items      []ShopEmote `json:"items"`
	NextCursor *string     `json:"nextCursor"`
	Total      int         `json:"total"`
}

// EmotePurchase is the purchase response.
type EmotePurchase struct {
	Item   ShopEmote     `json:"item"`
	Wallet wallet.Wallet `json:"wallet"`
}

// ------------------------------------------------------------------- store

// ownedStoreEmotes returns the account's Store emote ids (one PostgreSQL
// round trip).
func (s *Service) ownedStoreEmotes(ctx context.Context, userID uuid.UUID) (map[string]bool, error) {
	rows, err := s.pool.Query(ctx, `SELECT item_id FROM progression.inventory WHERE user_id = $1 AND item_id LIKE 'em\_%'`, userID)
	if err != nil {
		return nil, err
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, err
	}
	owned := make(map[string]bool, len(ids))
	for _, id := range ids {
		owned[id] = true
	}
	return owned, nil
}

// StoreEmotes returns one page of the Store emote shelf for an account.
// filter is all | owned (default all); limit 1..50 (0 = 24); cursor is the
// previous page's nextCursor. Retired (inactive) emotes are listed only to
// their owners. excludeOwned leaves out every emote the account owns (the
// app's Shop sells only what is not owned yet); it is not allowed with
// filter owned. Paging is position based (sort_order, id), so a purchase
// between two pages never repeats or skips an item.
func (s *Service) StoreEmotes(ctx context.Context, userID uuid.UUID, filter string, excludeOwned bool, limit int, cursor string) (EmotePage, error) {
	if filter == "" {
		filter = FilterAll
	}
	if (filter != FilterAll && filter != FilterOwned) || (filter == FilterOwned && excludeOwned) {
		return EmotePage{}, ErrBadStoreQuery
	}
	if limit == 0 {
		limit = DefaultStorePageSize
	}
	if limit < 1 || limit > MaxStorePageSize {
		return EmotePage{}, ErrBadStoreQuery
	}
	var (
		afterSort int
		afterID   string
	)
	if cursor != "" {
		var err error
		if afterSort, afterID, err = decodeCursor(cursor, assets.ValidEmoteID); err != nil {
			return EmotePage{}, err
		}
	}
	owned, err := s.ownedStoreEmotes(ctx, userID)
	if err != nil {
		return EmotePage{}, err
	}
	page := EmotePage{Items: []ShopEmote{}}
	var last *pictureRow
	for _, r := range s.emos.get().rows {
		visible := r.Active || owned[r.ID]
		if filter == FilterOwned {
			visible = owned[r.ID]
		}
		if !visible || (excludeOwned && owned[r.ID]) {
			continue
		}
		page.Total++
		if cursor != "" && !r.after(afterSort, afterID) {
			continue
		}
		if len(page.Items) < limit {
			page.Items = append(page.Items, emoteView(r, owned[r.ID]))
			last = r
		} else if page.NextCursor == nil {
			next := encodeCursor(last)
			page.NextCursor = &next
		}
	}
	return page, nil
}

// PurchaseEmote buys a Store emote with diamonds, like PurchasePicture: the
// progression row is locked first, then the inventory row is inserted and
// the wallet debited in the same transaction, so an emote is paid exactly
// once. The price and the active flag are read from PostgreSQL inside the
// transaction. After the commit the emote is written through to the cached
// set of owned emotes, so it can be sent in a match at once.
func (s *Service) PurchaseEmote(ctx context.Context, userID uuid.UUID, id string) (*EmotePurchase, error) {
	if !assets.ValidEmoteID(id) {
		return nil, ErrEmoteNotFound
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
		FROM progression.emotes WHERE id = $1`, id).
		Scan(&r.Name, &r.Format, &r.Path, &r.Price, &r.SortOrder, &r.Active)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && !r.Active) {
		return nil, ErrEmoteNotFound
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
	s.addEmotes(ctx, userID, []string{id}) // usable in chat at once
	s.ensureEmote(ctx, id)
	metrics.StoreEmotePurchases.WithLabelValues(r.Format).Inc()
	s.notify(ctx, userID, MsgWalletUpdated, WalletUpdated{Coins: wal.Coins, Diamonds: wal.Diamonds,
		Delta: WalletDelta{Diamonds: -r.Price}, Reason: "purchase"})
	return &EmotePurchase{Item: emoteView(&r, true), Wallet: wal}, nil
}
