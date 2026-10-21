package rooms

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"

	"ludoroyale/internal/assets"
	"ludoroyale/internal/playerinfo"
)

// fakeInventory answers EmoteAsset for Store emotes (em_… ids).
type fakeInventory struct{}

func (fakeInventory) Owns(context.Context, uuid.UUID, string) (bool, error) { return true, nil }

func (fakeInventory) EmoteAsset(id string) (string, string, bool) {
	if strings.HasPrefix(id, "em_") {
		return "emotes/" + strings.TrimPrefix(id, "em_") + ".json", "lottie", true
	}
	return "", "", false
}

// The chat.emote broadcast carries the art of Store emotes only; built-in
// emotes keep their payload exactly as before (no asset key).
func TestEmoteBroadcastCarriesStoreEmoteAsset(t *testing.T) {
	cases := []struct {
		inv   bool
		emote string
		want  string
	}{
		{true, "em_angry", `{"t":"chat.emote","p":{"roomId":"r_1","seat":2,"emote":"em_angry","asset":{"path":"emotes/angry.json","format":"lottie"}}}`},
		{true, "emote_wave", `{"t":"chat.emote","p":{"roomId":"r_1","seat":2,"emote":"emote_wave"}}`},
		{false, "em_angry", `{"t":"chat.emote","p":{"roomId":"r_1","seat":2,"emote":"em_angry"}}`},
	}
	for _, c := range cases {
		s := &Service{}
		if c.inv {
			s.Inventory = fakeInventory{}
		}
		if got := string(s.emoteMsg("r_1", 2, c.emote)); got != c.want {
			t.Errorf("%s (inventory %v):\n got %s\nwant %s", c.emote, c.inv, got, c.want)
		}
	}
}

// storeEmoteItems lists config/emotes.tsv as bot catalogue items.
func storeEmoteItems(t *testing.T) []playerinfo.CatalogItem {
	t.Helper()
	f, err := os.Open("../../config/emotes.tsv")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	rows, err := assets.ReadEmoteManifest(f)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]playerinfo.CatalogItem, 0, len(rows))
	for _, r := range rows {
		out = append(out, playerinfo.CatalogItem{ID: r.ID, Kind: "emote", Purchase: true, StoreEmote: true})
	}
	return out
}

// Bot personas own a few Store emotes, like players who bought some: most
// own none or one or two, never a large part of the shelf, and only ids of
// the catalogue.
func TestPersonaOwnsFewStoreEmotes(t *testing.T) {
	store := storeEmoteItems(t)
	items := append(testCatalog(t), store...)
	known := map[string]bool{}
	for _, it := range store {
		known[it.ID] = true
	}
	rng := seeded(42)
	const n = 3000
	total, none, most := 0, 0, 0
	for i := 0; i < n; i++ {
		p := persona{Level: 1 + rng.IntN(25)}
		p.dress(rng, items)
		k := 0
		for _, e := range p.Emotes {
			if strings.HasPrefix(e, "em_") {
				if !known[e] {
					t.Fatalf("unknown Store emote %s", e)
				}
				k++
			}
		}
		total += k
		most = max(most, k)
		if k == 0 {
			none++
		}
	}
	mean := float64(total) / n
	if mean < 1 || mean > 3 || most > 10 || float64(none)/n < 0.08 || float64(none)/n > 0.3 {
		t.Fatalf("Store emotes per persona: mean %.2f, max %d, none %.0f%%", mean, most, 100*float64(none)/n)
	}
}
