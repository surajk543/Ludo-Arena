package rooms

import (
	"encoding/json"
	"fmt"
	"math"
	mrand "math/rand/v2"
	"slices"
	"strings"
	"testing"

	"ludoarena/internal/playerinfo"
	"ludoarena/internal/progression"
	"ludoarena/internal/protocol"
)

func testCatalog(t *testing.T) []playerinfo.CatalogItem {
	t.Helper()
	c, err := progression.LoadCatalog("../../config/catalog.json")
	if err != nil {
		t.Fatal(err)
	}
	return c.BotItems()
}

func seeded(seed uint64) *mrand.Rand { return mrand.New(mrand.NewPCG(seed, seed^0x9e3779b97f4a7c15)) }

// pictures returns a picker cycling over n catalogue pictures.
func pictures(rng *mrand.Rand, n int) func() *playerinfo.Picture {
	return func() *playerinfo.Picture {
		i := rng.IntN(n)
		return &playerinfo.Picture{ID: fmt.Sprintf("pp_%d", i), Format: "image", Path: fmt.Sprintf("profile_pictures/image/%d.png", i)}
	}
}

func TestRollLevelIsPlausible(t *testing.T) {
	rng := seeded(1)
	const n = 20000
	sum, low, mid := 0, 0, 0
	seen := map[int]bool{}
	for i := 0; i < n; i++ {
		l := rollLevel(rng)
		if l < 1 || l > 25 {
			t.Fatalf("level %d outside 1..25", l)
		}
		sum += l
		seen[l] = true
		switch {
		case l <= 8:
			low++
		case l <= 20:
			mid++
		}
	}
	mean := float64(sum) / n
	if mean < 6 || mean > 12 {
		t.Fatalf("mean level %.1f, want low-mid", mean)
	}
	if float64(low)/n < 0.45 || float64(mid)/n < 0.25 || len(seen) != 25 {
		t.Fatalf("level spread: low %d mid %d distinct %d", low, mid, len(seen))
	}
}

// A persona only shows what a player of its level could own: starter items,
// level unlocks up to its level and Store items — never event or mission
// items, and never an unlock above its level.
func TestPersonaOwnsWhatItsLevelAllows(t *testing.T) {
	items := testCatalog(t)
	byID := map[string]playerinfo.CatalogItem{}
	for _, it := range items {
		byID[it.ID] = it
	}
	allowed := func(id string, level int) bool {
		it, ok := byID[id]
		return ok && (it.Starter || (it.Level > 0 && it.Level <= level) || it.Purchase)
	}
	for _, level := range []int{1, 2, 5, 9, 12, 20, 25, 50} {
		t.Run(fmt.Sprintf("level_%d", level), func(t *testing.T) {
			rng := seeded(uint64(level))
			for i := 0; i < 300; i++ {
				p := persona{Level: level}
				p.dress(rng, items)
				for _, slot := range seatSlots {
					id := p.Cosmetics[slot]
					if !allowed(id, level) || byID[id].Kind != slot {
						t.Fatalf("slot %s: %q not obtainable at level %d", slot, id, level)
					}
				}
				if it := byID[p.Title]; it.Kind != "title" || !earned(it, level) {
					t.Fatalf("title %q not earned at level %d", p.Title, level)
				}
				if len(p.Emotes) == 0 {
					t.Fatal("no emotes")
				}
				for _, e := range p.Emotes {
					if !allowed(e, level) || byID[e].Kind != "emote" {
						t.Fatalf("emote %q not obtainable at level %d", e, level)
					}
				}
			}
		})
	}
}

func TestTitleMatchesLevel(t *testing.T) {
	items := testCatalog(t)
	titles := itemsOf(items, "title")
	cases := []struct {
		level int
		best  string
	}{{1, "title_rookie"}, {4, "title_rookie"}, {5, "title_strategist"}, {14, "title_strategist"},
		{15, "title_dice_master"}, {29, "title_dice_master"}, {30, "title_royal"}}
	for _, c := range cases {
		if got := bestTitle(titles, c.level); got != c.best {
			t.Errorf("bestTitle(%d) = %q, want %q", c.level, got, c.best)
		}
	}
	// Mostly the best title, sometimes an older one.
	rng := seeded(3)
	best := 0
	for i := 0; i < 1000; i++ {
		if pickTitle(rng, titles, 16) == "title_dice_master" {
			best++
		}
	}
	if best < 550 || best > 900 {
		t.Fatalf("best title shown %d/1000", best)
	}
}

func TestPersonasVary(t *testing.T) {
	items := testCatalog(t)
	rng := seeded(4)
	o := wardrobeOpts{Share: 0.3, KeepMin: 2, KeepMax: 5, Pick: pictures(rng, 8)}
	levels, avatars, ids := map[int]bool{}, map[int]bool{}, map[string]bool{}
	slotItems := map[string]map[string]bool{}
	wearing := 0
	for i := 0; i < 300; i++ {
		p := newPersona(rng, items, o)
		levels[p.Level], avatars[p.Avatar], ids[p.ID.String()] = true, true, true
		for _, slot := range seatSlots {
			if slotItems[slot] == nil {
				slotItems[slot] = map[string]bool{}
			}
			slotItems[slot][p.Cosmetics[slot]] = true
		}
		if p.Picture != nil {
			wearing++
		}
	}
	if len(levels) < 15 || len(avatars) != 12 || len(ids) != 300 {
		t.Fatalf("levels %d avatars %d ids %d", len(levels), len(avatars), len(ids))
	}
	for slot, seen := range slotItems {
		if len(seen) < 2 {
			t.Fatalf("slot %s always %v", slot, seen)
		}
	}
	if wearing < 50 || wearing > 130 {
		t.Fatalf("%d/300 new personas wear a picture, want about 30%%", wearing)
	}
}

// The wardrobe keeps a picture for exactly N matches, then changes it.
func TestWardrobeKeepsPictureForNMatches(t *testing.T) {
	items := testCatalog(t)
	for _, n := range []int{1, 2, 3, 5} {
		t.Run(fmt.Sprintf("keep_%d", n), func(t *testing.T) {
			rng := seeded(uint64(n))
			// Share 1: always wearing, so every change is a new picture.
			o := wardrobeOpts{Share: 1, KeepMin: n, KeepMax: n, Pick: pictures(rng, 6)}
			p := newPersona(rng, items, o)
			var shown []string
			for match := 0; match < 6*n; match++ {
				p.nextMatch(rng, items, o)
				if p.Picture == nil {
					t.Fatalf("match %d: no picture with share 1", match)
				}
				shown = append(shown, p.Picture.ID)
			}
			for i := range shown {
				same := i%n != 0 // a change exactly every n matches
				if i > 0 && (shown[i] == shown[i-1]) != same {
					t.Fatalf("pictures %v: change at %d does not follow keep %d", shown, i, n)
				}
			}
		})
	}
	// Within the keep window the persona is unchanged; with keep 2..5 every
	// run length is in range.
	rng := seeded(9)
	o := wardrobeOpts{Share: 1, KeepMin: 2, KeepMax: 5, Pick: pictures(rng, 50)}
	p := newPersona(rng, items, o)
	run, prev := 0, ""
	for match := 0; match < 400; match++ {
		p.nextMatch(rng, items, o)
		switch {
		case match == 0 || p.Picture.ID == prev:
			run++
		default:
			if run < 2 || run > 5 {
				t.Fatalf("kept a picture %d matches, want 2..5", run)
			}
			run = 1
		}
		prev = p.Picture.ID
	}
}

func TestPictureRatesKeepTheShare(t *testing.T) {
	for _, share := range []float64{0, 0.05, 0.3, 0.5, 0.8, 0.95, 1} {
		on, off := pictureRates(share)
		if on < 0 || on > 1 || off < 0 || off > 1 {
			t.Fatalf("share %.2f: rates %.3f %.3f", share, on, off)
		}
		if share > 0 && share < 1 {
			if got := on / (on + off); math.Abs(got-share) > 1e-9 {
				t.Fatalf("share %.2f: stationary %.4f", share, got)
			}
			if off == 0 || on == 0 {
				t.Fatalf("share %.2f: a persona could never change (%v, %v)", share, on, off)
			}
		}
	}
}

// Over many personas and matches the share of bot seats wearing a picture
// stays around BOT_PICTURE_SHARE.
func TestWardrobeRespectsPictureShare(t *testing.T) {
	items := testCatalog(t)
	for _, share := range []float64{0, 0.1, 0.3, 0.6, 1} {
		t.Run(fmt.Sprintf("share_%.1f", share), func(t *testing.T) {
			rng := seeded(uint64(share*100) + 7)
			o := wardrobeOpts{Share: share, KeepMin: 2, KeepMax: 5, Pick: pictures(rng, 20)}
			seats, wearing, changes, backToNone := 0, 0, 0, 0
			for i := 0; i < 1500; i++ {
				p := newPersona(rng, items, o)
				prev := ""
				for match := 0; match < 30; match++ {
					p.nextMatch(rng, items, o)
					seats++
					cur := ""
					if p.Picture != nil {
						wearing++
						cur = p.Picture.ID
					}
					if match > 0 && cur != prev {
						changes++
						if cur == "" {
							backToNone++
						}
					}
					prev = cur
				}
			}
			got := float64(wearing) / float64(seats)
			if math.Abs(got-share) > 0.04 {
				t.Fatalf("share of seats wearing a picture %.3f, want %.2f", got, share)
			}
			if share > 0 && share < 1 && (changes == 0 || backToNone == 0 || backToNone*2 > changes) {
				t.Fatalf("changes %d, back to none %d: pictures must change, occasionally to none", changes, backToNone)
			}
		})
	}
}

func TestWardrobeWithoutPictures(t *testing.T) {
	items := testCatalog(t)
	rng := seeded(5)
	o := wardrobeOpts{Share: 1, KeepMin: 1, KeepMax: 1} // no picker: the catalogue is empty
	p := newPersona(rng, items, o)
	for i := 0; i < 20; i++ {
		p.nextMatch(rng, items, o)
		if p.Picture != nil || p.Wearing {
			t.Fatal("a picture without a catalogue")
		}
	}
}

func TestLevelUpKeepsTheLookConsistent(t *testing.T) {
	items := testCatalog(t)
	rng := seeded(6)
	p := persona{Level: 4}
	p.dress(rng, items)
	for p.Level < 30 {
		p.levelUp(rng, items)
		for _, e := range earnedEmotes(items, p.Level) {
			if !slices.Contains(p.Emotes, e) {
				t.Fatalf("level %d: earned emote %s missing", p.Level, e)
			}
		}
	}
	p.Level = personaMaxLevel
	p.levelUp(rng, items)
	if p.Level != personaMaxLevel {
		t.Fatalf("level above max: %d", p.Level)
	}
}

func TestBotSessionRecord(t *testing.T) {
	cases := []struct {
		raw  string
		want botSessionInfo
		ok   bool
	}{
		{"s1|b1|r_1|botlease:public:abc:0|a_1", botSessionInfo{"s1", "b1", "r_1", "botlease:public:abc:0", "a_1"}, true},
		{botSessionRecord("s2", "b2", "", "", ""), botSessionInfo{"s2", "b2", "", "", ""}, true},
		{"s3|b3|r_3", botSessionInfo{"s3", "b3", "r_3", "", ""}, true}, // older servers
		{"garbage", botSessionInfo{}, false},
	}
	for _, c := range cases {
		got, ok := parseBotSession(c.raw)
		if ok != c.ok || got != c.want {
			t.Errorf("parseBotSession(%q) = %+v %v", c.raw, got, ok)
		}
	}
}

func TestPersonaKeysArePerPoolAndName(t *testing.T) {
	if personaKey(poolPublic, "Asha", 0) != personaKey(poolPublic, " asha ", 0) {
		t.Fatal("names are case-insensitive")
	}
	if personaKey(poolPublic, "Asha", 0) == personaKey(poolKnown, "Asha", 0) ||
		personaKey(poolPublic, "Asha", 0) == personaKey(poolPublic, "Ravi", 0) ||
		personaKey(poolPublic, "Asha", 0) == personaKey(poolPublic, "Asha", 1) {
		t.Fatal("persona keys collide")
	}
	if poolFor("public_fill") != poolPublic || poolFor("practice") != poolKnown || poolFor("private") != poolKnown {
		t.Fatal("pools")
	}
}

// hasKey reports whether decoded JSON v contains key at any depth.
func hasKey(v any, key string) bool {
	switch x := v.(type) {
	case map[string]any:
		for k, e := range x {
			if k == key || hasKey(e, key) {
				return true
			}
		}
	case []any:
		for _, e := range x {
			if hasKey(e, key) {
				return true
			}
		}
	}
	return false
}

func mustHaveNoBotKey(t *testing.T, what string, raw []byte) {
	t.Helper()
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("%s: %v", what, err)
	}
	if hasKey(v, "bot") || strings.Contains(strings.ToLower(string(raw)), `"bot":`) {
		t.Fatalf("%s carries a bot key: %s", what, raw)
	}
}

// No client payload (snapshots, every delta of a whole game with full
// snapshots attached, chat) says which seats are bots. Practice and private
// rooms list their chosen computer seats; public rooms never do.
func TestClientPayloadsNeverMarkBots(t *testing.T) {
	h := newStrikeHarness(t, 2)
	h.s.FullSnaps = true
	h.r.Players[1].Bot, h.r.Players[1].BotEmotes, h.r.Players[1].BotSID = true, []string{"emote_wave"}, "sid"
	h.r.PendingBots = 1
	view, _ := json.Marshal(h.r.View())
	mustHaveNoBotKey(t, "public snapshot", view)
	if v := h.r.View(); v.PendingBots != 0 || v.ComputerSeats != nil {
		t.Fatalf("public view reveals bots: pending %d seats %v", v.PendingBots, v.ComputerSeats)
	}
	h.r.PendingBots = 0
	for i := 0; i < 400 && h.r.Status == StatusPlaying; i++ {
		evs := h.act()
		if i%7 == 3 {
			evs = append(evs, h.timeout()...) // strikes, auto moves and a forfeit
		}
		for _, e := range evs {
			mustHaveNoBotKey(t, e.T, e.P)
		}
	}
	if h.r.Status != StatusFinished {
		t.Fatalf("game did not finish: %s", h.r.Status)
	}
	chat := protocol.Encode(protocol.TChatEmote, "", map[string]any{"roomId": h.r.ID, "seat": 1, "emote": "emote_wave"})
	mustHaveNoBotKey(t, "chat.emote", chat)

	for _, mode := range []string{ModePractice, ModePrivate} {
		h.r.Mode = mode
		v := h.r.View()
		raw, _ := json.Marshal(v)
		mustHaveNoBotKey(t, mode+" snapshot", raw)
		if !slices.Equal(v.ComputerSeats, []int{1}) {
			t.Fatalf("%s computer seats %v", mode, v.ComputerSeats)
		}
	}
}
