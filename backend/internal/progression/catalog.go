package progression

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"regexp"
	"sort"

	"ludoroyale/internal/playerinfo"
)

// Item kinds.
const (
	KindDice        = "dice"
	KindToken       = "token"
	KindLudoBoard   = "ludo_board"
	KindSnakesBoard = "snakes_board"
	KindFrame       = "frame"
	KindTitle       = "title"
	KindBadge       = "badge"
	KindEmote       = "emote"
	KindVictory     = "victory"
	KindTrail       = "trail"
)

// Acquisition types.
const (
	AcqStarter  = "starter"
	AcqLevel    = "level"
	AcqMission  = "mission"
	AcqEvent    = "event"
	AcqPurchase = "purchase"
)

// FirstWinBadge is granted automatically on a player's first eligible win.
const FirstWinBadge = "badge_first_win"

var (
	validKinds = map[string]bool{KindDice: true, KindToken: true, KindLudoBoard: true, KindSnakesBoard: true,
		KindFrame: true, KindTitle: true, KindBadge: true, KindEmote: true, KindVictory: true, KindTrail: true}
	validRarities = map[string]bool{"common": true, "rare": true, "epic": true, "legendary": true}
	idPattern     = regexp.MustCompile(`^[a-z0-9_]{1,48}$`)
)

// Price is a fixed purchase price in exactly one currency.
type Price struct {
	Coins    int64 `json:"coins,omitempty"`
	Diamonds int64 `json:"diamonds,omitempty"`
}

// Acquisition describes how an item is obtained.
type Acquisition struct {
	Type    string `json:"type"`
	Level   int    `json:"level,omitempty"`
	Price   *Price `json:"price,omitempty"`
	Label   string `json:"label"`
	Mission string `json:"mission,omitempty"` // config only: granting mission id
	Event   string `json:"event,omitempty"`   // config only: granting event id
}

// Item is one catalog entry.
type Item struct {
	ID          string      `json:"id"`
	Kind        string      `json:"kind"`
	Name        string      `json:"name"`
	Description string      `json:"description"`
	Rarity      string      `json:"rarity"`
	Acquisition Acquisition `json:"acquisition"`
}

// Starter reports whether every account owns the item implicitly.
func (it *Item) Starter() bool { return it.Acquisition.Type == AcqStarter }

// Equippable reports whether the item goes into a loadout slot.
func (it *Item) Equippable() bool { return isSlot(it.Kind) }

// ItemRef is the compact item reference used in API responses.
type ItemRef struct {
	ID     string `json:"id"`
	Kind   string `json:"kind"`
	Name   string `json:"name"`
	Rarity string `json:"rarity"`
}

// Ref returns the item's ItemRef.
func (it *Item) Ref() ItemRef {
	return ItemRef{ID: it.ID, Kind: it.Kind, Name: it.Name, Rarity: it.Rarity}
}

// Catalog is the validated, immutable cosmetics catalog.
type Catalog struct {
	Version    int
	items      []*Item
	byID       map[string]*Item
	milestones map[int][]*Item // level -> items granted on reaching it
	levels     []int           // milestone levels, ascending
}

type catalogFile struct {
	Version int     `json:"version"`
	Items   []*Item `json:"items"`
}

// LoadCatalog reads and validates a catalog file.
func LoadCatalog(path string) (*Catalog, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read catalog: %w", err)
	}
	return ParseCatalog(raw)
}

// ParseCatalog validates catalog JSON.
func ParseCatalog(raw []byte) (*Catalog, error) {
	var f catalogFile
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&f); err != nil {
		return nil, fmt.Errorf("parse catalog: %w", err)
	}
	c := &Catalog{Version: f.Version, byID: map[string]*Item{}, milestones: map[int][]*Item{}}
	var errs []error
	bad := func(format string, args ...any) { errs = append(errs, fmt.Errorf(format, args...)) }
	if len(f.Items) == 0 {
		bad("catalog has no items")
	}
	for i, it := range f.Items {
		if it == nil {
			bad("item %d is null", i)
			continue
		}
		if !idPattern.MatchString(it.ID) {
			bad("item %d: invalid id %q", i, it.ID)
		}
		if c.byID[it.ID] != nil {
			bad("duplicate item id %q", it.ID)
		}
		if !validKinds[it.Kind] {
			bad("item %s: invalid kind %q", it.ID, it.Kind)
		}
		if !validRarities[it.Rarity] {
			bad("item %s: invalid rarity %q", it.ID, it.Rarity)
		}
		if it.Name == "" || it.Acquisition.Label == "" {
			bad("item %s: name and acquisition.label are required", it.ID)
		}
		a := it.Acquisition
		switch a.Type {
		case AcqStarter:
		case AcqLevel:
			if a.Level < 2 || a.Level > MaxLevel {
				bad("item %s: level must be 2..%d", it.ID, MaxLevel)
			} else {
				c.milestones[a.Level] = append(c.milestones[a.Level], it)
			}
		case AcqPurchase:
			if a.Price == nil || a.Price.Coins < 0 || a.Price.Diamonds < 0 ||
				(a.Price.Coins > 0) == (a.Price.Diamonds > 0) {
				bad("item %s: purchase price must be positive in exactly one currency", it.ID)
			}
		case AcqMission:
			if a.Mission == "" {
				bad("item %s: mission acquisition needs a mission id", it.ID)
			}
		case AcqEvent:
			if a.Event == "" {
				bad("item %s: event acquisition needs an event id", it.ID)
			}
		default:
			bad("item %s: invalid acquisition type %q", it.ID, a.Type)
		}
		if a.Type != AcqPurchase && a.Price != nil {
			bad("item %s: only purchase items have a price", it.ID)
		}
		if a.Type != AcqLevel && a.Level != 0 {
			bad("item %s: only level items have a level", it.ID)
		}
		c.items = append(c.items, it)
		c.byID[it.ID] = it
	}
	for slot, id := range playerinfo.StarterLoadout() {
		it := c.byID[id]
		if it == nil || !it.Starter() || it.Kind != slot {
			bad("starter item %q for slot %s must exist with kind %s and acquisition starter", id, slot, slot)
		}
	}
	if fw := c.byID[FirstWinBadge]; fw == nil || fw.Kind != KindBadge {
		bad("catalog must contain the badge %s", FirstWinBadge)
	}
	if len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	for l := range c.milestones {
		c.levels = append(c.levels, l)
	}
	sort.Ints(c.levels)
	return c, nil
}

// Get returns an item or nil.
func (c *Catalog) Get(id string) *Item { return c.byID[id] }

// Items returns every item in catalog order.
func (c *Catalog) Items() []*Item { return c.items }

// MilestoneLevels returns the levels that grant items, ascending.
func (c *Catalog) MilestoneLevels() []int { return c.levels }

// Milestone returns the items granted on reaching level.
func (c *Catalog) Milestone(level int) []*Item { return c.milestones[level] }

func isSlot(kind string) bool {
	for _, s := range playerinfo.Slots {
		if s == kind {
			return true
		}
	}
	return false
}
