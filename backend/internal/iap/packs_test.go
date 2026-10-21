package iap

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

// The shipped configuration is the owner's price list (22 Oct 2026).
func TestShippedCoinPacks(t *testing.T) {
	raw, err := os.ReadFile("../../config/coin_packs.json")
	if err != nil {
		t.Fatal(err)
	}
	p, err := ParsePacks(raw)
	if err != nil {
		t.Fatal(err)
	}
	want := []struct {
		id, label       string
		coins, diamonds int64
		price           int64
		badge           string
	}{
		{"coins_starter", "Starter", 5_000_000, 5, 199, ""},
		{"coins_popular", "Popular", 8_000_000, 8, 299, BadgePopular},
		{"coins_great_value", "Great Value", 15_000_000, 100, 499, ""},
		{"coins_best_value", "Best Value", 35_000_000, 250, 999, BadgeBestValue},
	}
	if len(p.List()) != len(want) {
		t.Fatalf("packs = %d, want %d", len(p.List()), len(want))
	}
	for i, w := range want {
		got := p.List()[i]
		badge := ""
		if got.Badge != nil {
			badge = *got.Badge
		}
		if got.ID != w.id || got.Label != w.label || got.Coins != w.coins || got.Diamonds != w.diamonds ||
			got.FallbackPrice != (Price{"INR", w.price}) || badge != w.badge {
			t.Errorf("pack %d = %+v (badge %q), want %+v", i, got, badge, w)
		}
		for _, plat := range []string{PlatformAndroid, PlatformIOS} {
			if got.ProductIDs[plat] != w.id {
				t.Errorf("%s product id on %s = %q, want %q", w.id, plat, got.ProductIDs[plat], w.id)
			}
			if pk, ok := p.ByProduct(plat, w.id); !ok || pk != got {
				t.Errorf("ByProduct(%s, %s) = %v %v", plat, w.id, pk, ok)
			}
		}
	}
}

func packJSON(mut func(string) string) string {
	base := `{"configVersion":1,"packs":[
		{"id":"a","label":"A","productIds":{"android":"pa","ios":"ia"},"coins":10,"diamonds":1,
		 "fallbackPrice":{"currency":"INR","amount":199},"badge":null,"sortOrder":2},
		{"id":"b","label":"B","productIds":{"android":"pb","ios":"ib"},"coins":20,"diamonds":2,
		 "fallbackPrice":{"currency":"INR","amount":299},"badge":"popular","sortOrder":1}]}`
	if mut == nil {
		return base
	}
	return mut(base)
}

func TestParsePacksValidation(t *testing.T) {
	cases := []struct {
		name string
		mut  func(string) string
		err  string // "" = valid
	}{
		{"valid", nil, ""},
		{"zero coins", func(s string) string { return strings.Replace(s, `"coins":10`, `"coins":0`, 1) }, "coins"},
		{"negative diamonds", func(s string) string { return strings.Replace(s, `"diamonds":1`, `"diamonds":-1`, 1) }, "diamonds"},
		{"zero diamonds", func(s string) string { return strings.Replace(s, `"diamonds":2`, `"diamonds":0`, 1) }, "diamonds"},
		{"zero price", func(s string) string { return strings.Replace(s, `"amount":199`, `"amount":0`, 1) }, "fallbackPrice.amount"},
		{"bad currency", func(s string) string { return strings.Replace(s, `"INR","amount":199`, `"inr","amount":199`, 1) }, "currency"},
		{"duplicate id", func(s string) string { return strings.Replace(s, `"id":"b"`, `"id":"a"`, 1) }, "duplicate id"},
		{"duplicate android product", func(s string) string { return strings.Replace(s, `"android":"pb"`, `"android":"pa"`, 1) }, "used by another pack"},
		{"duplicate ios product", func(s string) string { return strings.Replace(s, `"ios":"ib"`, `"ios":"ia"`, 1) }, "used by another pack"},
		{"missing ios", func(s string) string { return strings.Replace(s, `,"ios":"ia"`, ``, 1) }, "productIds"},
		{"extra platform", func(s string) string { return strings.Replace(s, `"ios":"ia"`, `"ios":"ia","web":"wa"`, 1) }, "productIds"},
		{"bad product id", func(s string) string { return strings.Replace(s, `"android":"pa"`, `"android":"Pa-1"`, 1) }, "productIds.android"},
		{"unknown badge", func(s string) string { return strings.Replace(s, `"badge":"popular"`, `"badge":"hot"`, 1) }, "badge"},
		{"empty label", func(s string) string { return strings.Replace(s, `"label":"A"`, `"label":""`, 1) }, "label"},
		{"unknown field", func(s string) string { return strings.Replace(s, `"sortOrder":2`, `"sortOrder":2,"price":5`, 1) }, "unknown field"},
		{"bad id", func(s string) string { return strings.Replace(s, `"id":"a"`, `"id":"A B"`, 1) }, "id must match"},
		{"no packs", func(string) string { return `{"configVersion":1,"packs":[]}` }, "1 to"},
		{"no version", func(s string) string { return strings.Replace(s, `"configVersion":1`, `"configVersion":0`, 1) }, "configVersion"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			p, err := ParsePacks([]byte(packJSON(tc.mut)))
			if tc.err == "" {
				if err != nil {
					t.Fatal(err)
				}
				if p.List()[0].ID != "b" || p.List()[1].ID != "a" {
					t.Fatalf("not sorted by sortOrder: %s, %s", p.List()[0].ID, p.List()[1].ID)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), tc.err) {
				t.Fatalf("err = %v, want it to mention %q", err, tc.err)
			}
		})
	}
}

// A rejected edit keeps the previous list; a valid edit replaces it.
func TestCatalogReloadKeepsPreviousOnError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "coin_packs.json")
	write := func(body string, at time.Time) {
		t.Helper()
		if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(path, at, at); err != nil {
			t.Fatal(err)
		}
	}
	now := time.Now()
	write(packJSON(nil), now.Add(-time.Hour))
	c, err := LoadCatalog(path, nil)
	if err != nil {
		t.Fatal(err)
	}
	write(strings.Replace(packJSON(nil), `"coins":10`, `"coins":-5`, 1), now.Add(-time.Minute))
	if err := c.reload(false); err == nil {
		t.Fatal("invalid file accepted")
	}
	if pk, _ := c.Packs().ByProduct(PlatformAndroid, "pa"); pk.Coins != 10 {
		t.Fatalf("coins = %d after a rejected reload, want 10", pk.Coins)
	}
	write(strings.Replace(packJSON(nil), `"coins":10`, `"coins":11`, 1), now)
	if err := c.reload(false); err != nil {
		t.Fatal(err)
	}
	if pk, _ := c.Packs().ByProduct(PlatformAndroid, "pa"); pk.Coins != 11 {
		t.Fatalf("coins = %d after reload, want 11", pk.Coins)
	}
	if _, err := LoadCatalog(filepath.Join(t.TempDir(), "missing.json"), nil); err == nil {
		t.Fatal("missing file accepted")
	}
}

func TestAccountToken(t *testing.T) {
	key := []byte(strings.Repeat("k", 40))
	u1, u2 := uuid.New(), uuid.New()
	a, b := AccountToken(key, u1), AccountToken(key, u1)
	if a != b {
		t.Fatal("not deterministic")
	}
	parsed, err := uuid.Parse(a)
	if err != nil || parsed.Version() != 4 || parsed.Variant() != uuid.RFC4122 || a != strings.ToLower(a) {
		t.Fatalf("token %q is not a lowercase RFC 4122 v4 UUID (%v)", a, err)
	}
	if a == AccountToken(key, u2) || a == AccountToken([]byte(strings.Repeat("j", 40)), u1) {
		t.Fatal("token does not depend on account and key")
	}
	if a == u1.String() {
		t.Fatal("token reveals the account id")
	}
}

func TestTokenHash(t *testing.T) {
	h := TokenHash("opaque-token")
	if len(h) != 64 || h != strings.ToLower(h) || strings.Contains(h, "opaque") {
		t.Fatalf("hash %q", h)
	}
	if TokenHash("opaque-token") != h || TokenHash("opaque-token2") == h {
		t.Fatal("hash not stable / not distinct")
	}
}
