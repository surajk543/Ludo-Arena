package iap

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"regexp"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// Platforms of the product ids in a pack.
const (
	PlatformAndroid = "android"
	PlatformIOS     = "ios"
)

// Badges a pack may show.
const (
	BadgePopular   = "popular"
	BadgeBestValue = "best_value"
)

// Limits of config/coin_packs.json.
const (
	MaxPacks       = 20
	MaxPackCoins   = 1_000_000_000_000
	MaxPackGems    = 1_000_000
	MaxPriceAmount = 1_000_000
)

var (
	packIDRe = regexp.MustCompile(`^[a-z0-9][a-z0-9_]{0,63}$`)
	// Google Play: lowercase letters, digits, "_" and "."; it starts with a
	// letter or digit. The App Store accepts the same characters.
	productIDRe = regexp.MustCompile(`^[a-z0-9][a-z0-9_.]{0,99}$`)
	currencyRe  = regexp.MustCompile(`^[A-Z]{3}$`)
)

// Price is a pack's fallback display price in major units (INR 199), shown
// until the store reports its localized price.
type Price struct {
	Currency string `json:"currency"`
	Amount   int64  `json:"amount"`
}

// Pack is one coin pack of config/coin_packs.json. The amounts granted are
// always this server-side configuration, never anything a client sends.
type Pack struct {
	ID            string            `json:"id"`
	Label         string            `json:"label"`
	ProductIDs    map[string]string `json:"productIds"`
	Coins         int64             `json:"coins"`
	Diamonds      int64             `json:"diamonds"`
	FallbackPrice Price             `json:"fallbackPrice"`
	Badge         *string           `json:"badge"`
	SortOrder     int               `json:"sortOrder"`
}

// PackView is a pack as one platform's client sees it (GET /store/coin-packs).
type PackView struct {
	ID            string  `json:"id"`
	ProductID     string  `json:"productId"`
	Label         string  `json:"label"`
	Coins         int64   `json:"coins"`
	Diamonds      int64   `json:"diamonds"`
	FallbackPrice Price   `json:"fallbackPrice"`
	Badge         *string `json:"badge"`
	SortOrder     int     `json:"sortOrder"`
}

// View returns the pack for platform's client.
func (p *Pack) View(platform string) PackView {
	return PackView{ID: p.ID, ProductID: p.ProductIDs[platform], Label: p.Label, Coins: p.Coins,
		Diamonds: p.Diamonds, FallbackPrice: p.FallbackPrice, Badge: p.Badge, SortOrder: p.SortOrder}
}

// Packs is a validated, immutable pack list.
type Packs struct {
	ConfigVersion int
	list          []*Pack // sortOrder, id
	byProduct     map[string]map[string]*Pack
	sha256        string
}

// List returns the packs in display order.
func (p *Packs) List() []*Pack { return p.list }

// ByProduct finds the pack sold as productID on platform.
func (p *Packs) ByProduct(platform, productID string) (*Pack, bool) {
	pk, ok := p.byProduct[platform][productID]
	return pk, ok
}

type packFile struct {
	ConfigVersion int     `json:"configVersion"`
	Packs         []*Pack `json:"packs"`
}

// ParsePacks strictly decodes and validates a coin_packs.json document:
// unique pack ids, unique product ids per platform, positive amounts and
// prices, known badges.
func ParsePacks(raw []byte) (*Packs, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	var f packFile
	if err := dec.Decode(&f); err != nil {
		return nil, fmt.Errorf("coin packs: %w", err)
	}
	if dec.More() {
		return nil, errors.New("coin packs: trailing data")
	}
	if f.ConfigVersion < 1 {
		return nil, errors.New("coin packs: configVersion must be >= 1")
	}
	if len(f.Packs) == 0 || len(f.Packs) > MaxPacks {
		return nil, fmt.Errorf("coin packs: 1 to %d packs required", MaxPacks)
	}
	out := &Packs{ConfigVersion: f.ConfigVersion, byProduct: map[string]map[string]*Pack{
		PlatformAndroid: {}, PlatformIOS: {}}}
	ids := map[string]bool{}
	for i, p := range f.Packs {
		if p == nil {
			return nil, fmt.Errorf("coin packs: pack %d is null", i)
		}
		where := fmt.Sprintf("coin packs: pack %q", p.ID)
		switch {
		case !packIDRe.MatchString(p.ID):
			return nil, fmt.Errorf("coin packs: pack %d: id must match %s", i, packIDRe)
		case ids[p.ID]:
			return nil, fmt.Errorf("%s: duplicate id", where)
		case strings.TrimSpace(p.Label) != p.Label || len([]rune(p.Label)) < 1 || len([]rune(p.Label)) > 40:
			return nil, fmt.Errorf("%s: label must be 1-40 characters without outer spaces", where)
		case p.Coins <= 0 || p.Coins > MaxPackCoins:
			return nil, fmt.Errorf("%s: coins must be between 1 and %d", where, int64(MaxPackCoins))
		case p.Diamonds <= 0 || p.Diamonds > MaxPackGems:
			return nil, fmt.Errorf("%s: diamonds must be between 1 and %d", where, MaxPackGems)
		case !currencyRe.MatchString(p.FallbackPrice.Currency):
			return nil, fmt.Errorf("%s: fallbackPrice.currency must be an ISO 4217 code", where)
		case p.FallbackPrice.Amount <= 0 || p.FallbackPrice.Amount > MaxPriceAmount:
			return nil, fmt.Errorf("%s: fallbackPrice.amount must be between 1 and %d", where, MaxPriceAmount)
		case p.Badge != nil && *p.Badge != BadgePopular && *p.Badge != BadgeBestValue:
			return nil, fmt.Errorf("%s: badge must be null, %q or %q", where, BadgePopular, BadgeBestValue)
		case len(p.ProductIDs) != 2:
			return nil, fmt.Errorf("%s: productIds must name exactly android and ios", where)
		}
		ids[p.ID] = true
		for _, plat := range []string{PlatformAndroid, PlatformIOS} {
			pid, ok := p.ProductIDs[plat]
			if !ok || !productIDRe.MatchString(pid) {
				return nil, fmt.Errorf("%s: productIds.%s must match %s", where, plat, productIDRe)
			}
			if _, dup := out.byProduct[plat][pid]; dup {
				return nil, fmt.Errorf("%s: productIds.%s %q is used by another pack", where, plat, pid)
			}
			out.byProduct[plat][pid] = p
		}
		out.list = append(out.list, p)
	}
	sort.SliceStable(out.list, func(i, j int) bool {
		a, b := out.list[i], out.list[j]
		if a.SortOrder != b.SortOrder {
			return a.SortOrder < b.SortOrder
		}
		return a.ID < b.ID
	})
	sum := sha256.Sum256(raw)
	out.sha256 = hex.EncodeToString(sum[:8])
	return out, nil
}

// Catalog holds the active pack list and reloads config/coin_packs.json when
// it changes (like the app policy: a poll of the file's modification time,
// plus SIGHUP). An invalid file is rejected and the previous list stays.
type Catalog struct {
	path    string
	log     *slog.Logger
	cur     atomic.Pointer[Packs]
	mu      sync.Mutex
	modTime time.Time
}

// LoadCatalog loads path once; it fails if the file is missing or invalid.
func LoadCatalog(path string, log *slog.Logger) (*Catalog, error) {
	if log == nil {
		log = slog.Default()
	}
	c := &Catalog{path: path, log: log}
	if err := c.reload(true); err != nil {
		return nil, err
	}
	return c, nil
}

// NewStaticCatalog wraps an already parsed list (tests).
func NewStaticCatalog(p *Packs) *Catalog {
	c := &Catalog{log: slog.Default()}
	c.cur.Store(p)
	return c
}

// Packs returns the active list.
func (c *Catalog) Packs() *Packs { return c.cur.Load() }

// Reload re-reads the file now.
func (c *Catalog) Reload() error { return c.reload(true) }

func (c *Catalog) reload(force bool) error {
	if c.path == "" {
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	info, err := os.Stat(c.path)
	if err != nil {
		return fmt.Errorf("coin packs: %w", err)
	}
	if !force && info.ModTime().Equal(c.modTime) {
		return nil
	}
	c.modTime = info.ModTime() // a bad file is reported once, not every poll
	raw, err := os.ReadFile(c.path)
	if err == nil {
		var p *Packs
		if p, err = ParsePacks(raw); err == nil {
			prev := c.cur.Load()
			c.cur.Store(p)
			if prev == nil || prev.sha256 != p.sha256 {
				c.log.Info("coin packs loaded", "configVersion", p.ConfigVersion, "packs", len(p.list), "sha256", p.sha256)
			}
			return nil
		}
	}
	if c.cur.Load() != nil {
		c.log.Error("coin packs rejected; keeping the previous list", "error", err.Error())
	}
	return err
}

// Run polls the file every interval and reloads on SIGHUP until ctx ends.
func (c *Catalog) Run(ctx context.Context, interval time.Duration) {
	if c.path == "" {
		return
	}
	if interval <= 0 {
		interval = 5 * time.Second
	}
	hup := make(chan os.Signal, 1)
	signal.Notify(hup, syscall.SIGHUP)
	defer signal.Stop(hup)
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-hup:
			_ = c.reload(true)
		case <-t.C:
			_ = c.reload(false)
		}
	}
}
