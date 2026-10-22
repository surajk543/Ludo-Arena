package progression

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"ludoarena/internal/metrics"
	"ludoarena/internal/playerinfo"
	"ludoarena/internal/wallet"
)

// AcquisitionView is the API acquisition object.
type AcquisitionView struct {
	Type  string `json:"type"`
	Level int    `json:"level,omitempty"`
	Price *Price `json:"price,omitempty"`
	Label string `json:"label"`
}

// CollectionItem is the API CollectionItem object.
type CollectionItem struct {
	ID          string          `json:"id"`
	Kind        string          `json:"kind"`
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Rarity      string          `json:"rarity"`
	Owned       bool            `json:"owned"`
	Equipped    bool            `json:"equipped"`
	Acquisition AcquisitionView `json:"acquisition"`
}

// CollectionView is the GET /collection response.
type CollectionView struct {
	Items   []CollectionItem  `json:"items"`
	Loadout map[string]string `json:"loadout"`
}

func collectionItem(it *Item, owned bool, loadout map[string]string) CollectionItem {
	a := it.Acquisition
	return CollectionItem{ID: it.ID, Kind: it.Kind, Name: it.Name, Description: it.Description, Rarity: it.Rarity,
		Owned: owned || it.Starter(), Equipped: it.Equippable() && loadout[it.Kind] == it.ID,
		Acquisition: AcquisitionView{Type: a.Type, Level: a.Level, Price: a.Price, Label: a.Label}}
}

// Collection returns every catalog item with ownership and the loadout.
func (s *Service) Collection(ctx context.Context, userID uuid.UUID) (CollectionView, error) {
	owned, err := s.owned(ctx, s.pool, userID)
	if err != nil {
		return CollectionView{}, err
	}
	lo, err := s.loadouts(ctx, s.pool, []uuid.UUID{userID})
	if err != nil {
		return CollectionView{}, err
	}
	loadout := lo[userID]
	out := CollectionView{Loadout: loadout, Items: make([]CollectionItem, 0, len(s.catalog.Items()))}
	for _, it := range s.catalog.Items() {
		out.Items = append(out.Items, collectionItem(it, owned[it.ID], loadout))
	}
	return out, nil
}

// Equip puts an owned item into its slot. An empty itemID (or the slot's
// starter item) resets the slot to the starter item.
func (s *Service) Equip(ctx context.Context, userID uuid.UUID, slot, itemID string) (map[string]string, error) {
	if !isSlot(slot) {
		return nil, ErrUnknownSlot
	}
	if itemID == "" {
		itemID = playerinfo.StarterLoadout()[slot]
	}
	it := s.catalog.Get(itemID)
	if it == nil {
		return nil, ErrItemNotFound
	}
	if it.Kind != slot {
		return nil, ErrWrongSlot
	}
	if it.Starter() {
		// Starter items are implicit: no row means "starter".
		if _, err := s.pool.Exec(ctx, `DELETE FROM progression.loadout WHERE user_id = $1 AND slot = $2`, userID, slot); err != nil {
			return nil, err
		}
	} else {
		tag, err := s.pool.Exec(ctx, `
			INSERT INTO progression.loadout (user_id, slot, item_id)
			SELECT $1, $2, $3 WHERE EXISTS (SELECT 1 FROM progression.inventory WHERE user_id = $1 AND item_id = $3)
			ON CONFLICT (user_id, slot) DO UPDATE SET item_id = EXCLUDED.item_id`, userID, slot, itemID)
		if err != nil {
			return nil, mapFK(err)
		}
		if tag.RowsAffected() == 0 {
			return nil, ErrItemLocked
		}
	}
	s.InvalidateSeat(ctx, userID) // the next room seat shows the new loadout
	metrics.CosmeticEquips.WithLabelValues(slot).Inc()
	lo, err := s.loadouts(ctx, s.pool, []uuid.UUID{userID})
	if err != nil {
		return nil, err
	}
	return lo[userID], nil
}

// PurchaseResult is the purchase response.
type PurchaseResult struct {
	Item   CollectionItem `json:"item"`
	Wallet wallet.Wallet  `json:"wallet"`
}

// Purchase buys a `purchase` item. The inventory row and the wallet debit
// commit together: an existing row (already owned) or a failed debit
// (insufficient funds) rolls everything back, so an item is paid exactly once.
func (s *Service) Purchase(ctx context.Context, userID uuid.UUID, itemID string) (*PurchaseResult, error) {
	it := s.catalog.Get(itemID)
	if it == nil {
		return nil, ErrItemNotFound
	}
	if it.Acquisition.Type != AcqPurchase || it.Acquisition.Price == nil {
		return nil, ErrItemLocked
	}
	price := *it.Acquisition.Price

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if _, _, err := s.lockProgress(ctx, tx, userID); err != nil {
		return nil, err
	}
	isNew, err := grantItemTx(ctx, tx, userID, it)
	if err != nil {
		return nil, err
	}
	if !isNew {
		return nil, ErrAlreadyOwned
	}
	wal, err := wallet.AdjustTx(ctx, tx, userID, -price.Coins, -price.Diamonds)
	if err != nil {
		return nil, err // wallet.ErrInsufficientFunds → rollback, no inventory row
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	// Ownership only (equipping is a separate request that invalidates the
	// seat summary): a purchased emote is usable in chat at once.
	s.cacheGranted(ctx, userID, []*Item{it})

	currency := "coins"
	if price.Diamonds > 0 {
		currency = "diamonds"
	}
	metrics.CosmeticPurchases.WithLabelValues(currency).Inc()
	metrics.CosmeticUnlocks.WithLabelValues("purchase").Inc()
	s.notify(ctx, userID, MsgWalletUpdated, WalletUpdated{Coins: wal.Coins, Diamonds: wal.Diamonds,
		Delta: WalletDelta{Coins: -price.Coins, Diamonds: -price.Diamonds}, Reason: "purchase"})

	lo, err := s.loadouts(ctx, s.pool, []uuid.UUID{userID})
	if err != nil {
		lo = map[uuid.UUID]map[string]string{userID: playerinfo.StarterLoadout()}
	}
	return &PurchaseResult{Item: collectionItem(it, true, lo[userID]), Wallet: wal}, nil
}

// isInsufficient reports a wallet debit failure.
func isInsufficient(err error) bool { return errors.Is(err, wallet.ErrInsufficientFunds) }
