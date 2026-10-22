package tests

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"ludoarena/internal/assets"
	"ludoarena/internal/assets/r2test"
)

// Store emotes end to end (docs/rest-api.md → Store, docs/websocket-protocol.md
// → chat.emote): production wiring, the seeded catalogue (migrations 010/011),
// a fake R2 for signing, and the room engine. internal/progression adds
// short-lived rows with ids "em_unit_…" to the shared test database; listings
// ignore them.

const emoteCatalogueSize = 89 // backend/config/emotes.tsv

const unitEmotePrefix = "em_unit_"

func emoteManifest(t *testing.T) []assets.EmoteRow {
	t.Helper()
	f, err := os.Open("../config/emotes.tsv")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	rows, err := assets.ReadEmoteManifest(f)
	if err != nil || len(rows) != emoteCatalogueSize {
		t.Fatalf("emote manifest: %d rows, %v", len(rows), err)
	}
	return rows
}

type shopEmote struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Format string `json:"format"`
	Path   string `json:"path"`
	Price  struct {
		Diamonds int64 `json:"diamonds"`
	} `json:"price"`
	Owned bool `json:"owned"`
}

type emotePage struct {
	Items      []shopEmote `json:"items"`
	NextCursor *string     `json:"nextCursor"`
	Total      int         `json:"total"`
}

func seededEmotes(items []shopEmote) []shopEmote {
	out := make([]shopEmote, 0, len(items))
	for _, it := range items {
		if !strings.HasPrefix(it.ID, unitEmotePrefix) {
			out = append(out, it)
		}
	}
	return out
}

func (e *env) emoteShelf(token, query string) (emotePage, resp) {
	e.t.Helper()
	r := e.do("GET", "/api/v1/store/emotes"+query, token, nil)
	if r.Status != 200 {
		return emotePage{}, r
	}
	return decode[emotePage](e.t, r), r
}

// walkEmotes pages through the listing selected by query (filter and
// excludeOwned) with the given page size.
func (e *env) walkEmotes(token, query string, limit int) []shopEmote {
	e.t.Helper()
	var out []shopEmote
	cursor := ""
	for pages := 0; pages < 100; pages++ {
		q := fmt.Sprintf("?%s&limit=%d", query, limit)
		if cursor != "" {
			q += "&cursor=" + cursor
		}
		p, r := e.emoteShelf(token, q)
		if r.Status != 200 {
			e.t.Fatalf("emote page: %d %s", r.Status, r.Raw)
		}
		if len(p.Items) > limit {
			e.t.Fatalf("page of %d items with limit %d", len(p.Items), limit)
		}
		out = append(out, p.Items...)
		if p.NextCursor == nil {
			return out
		}
		cursor = *p.NextCursor
	}
	e.t.Fatal("pagination did not end")
	return nil
}

func (e *env) buyEmote(token, id, key string) resp {
	e.t.Helper()
	var h []string
	if key != "" {
		h = []string{"Idempotency-Key", key}
	}
	return e.do("POST", "/api/v1/store/emotes/"+id+"/purchase", token, nil, h...)
}

// emoteAt returns the first seeded emote with the given price (the manifest
// has 10..40 diamond emotes).
func emoteAt(t *testing.T, items []shopEmote, price int64, skip ...string) shopEmote {
	t.Helper()
next:
	for _, it := range seededEmotes(items) {
		for _, s := range skip {
			if it.ID == s {
				continue next
			}
		}
		if it.Price.Diamonds == price {
			return it
		}
	}
	t.Fatalf("no emote at %d diamonds", price)
	return shopEmote{}
}

func TestStoreEmotesListPaging(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()

	first, r := e.emoteShelf(a.Token, "")
	if r.Status != 200 {
		t.Fatalf("GET store/emotes: %d %s", r.Status, r.Raw)
	}
	if len(first.Items) != 24 || first.Total < emoteCatalogueSize || first.NextCursor == nil {
		t.Fatalf("default page: %d items, total %d, next %v", len(first.Items), first.Total, first.NextCursor)
	}
	for _, k := range []string{`"nextCursor"`, `"total"`, `"price":{"diamonds":`, `"owned":false`, `"path":"emotes/`} {
		if !strings.Contains(string(r.Raw), k) {
			t.Errorf("body lacks %s", k)
		}
	}
	if strings.Contains(string(r.Raw), `"equipped"`) {
		t.Error("emotes are owned, not equipped")
	}

	all := e.walkEmotes(a.Token, "filter=all", 50)
	if len(all) != first.Total {
		t.Fatalf("paged %d emotes, total says %d", len(all), first.Total)
	}
	// Exactly the manifest, in shelf order (sort_order, id), with its data.
	rows, got := emoteManifest(t), seededEmotes(all)
	if len(got) != len(rows) {
		t.Fatalf("listed %d seeded emotes, manifest has %d", len(got), len(rows))
	}
	for i, m := range rows {
		p := got[i]
		if p.ID != m.ID || p.Name != m.Name || p.Format != m.Format || p.Path != m.Path ||
			p.Price.Diamonds != int64(m.PriceDiamonds) || p.Owned {
			t.Fatalf("item %d: %+v, manifest %+v", i, p, m)
		}
	}
	// Smaller pages walk the same order, never repeating an item.
	small := e.walkEmotes(a.Token, "filter=all", 7)
	seen := map[string]bool{}
	for i, it := range small {
		if seen[it.ID] || i >= len(all) || all[i].ID != it.ID {
			t.Fatalf("limit 7: item %d is %s", i, it.ID)
		}
		seen[it.ID] = true
	}
	if len(small) != len(all) {
		t.Fatalf("limit 7 walked %d emotes", len(small))
	}
	if owned, _ := e.emoteShelf(a.Token, "?filter=owned"); owned.Total != 0 || len(owned.Items) != 0 || owned.NextCursor != nil {
		t.Fatalf("owned before buying: %+v", owned)
	}
	if shop, _ := e.emoteShelf(a.Token, "?excludeOwned=true"); shop.Total != first.Total {
		t.Fatalf("excludeOwned with nothing owned: %d, want %d", shop.Total, first.Total)
	}

	for _, q := range []string{"?filter=animated", "?filter=gif", "?limit=0", "?limit=51", "?limit=x", "?cursor=!!!",
		"?cursor=bm9wZQ", "?filter=owned&excludeOwned=true", "?excludeOwned=yes"} {
		if _, r := e.emoteShelf(a.Token, q); r.Status != 400 || errCode(r) != "bad_request" {
			t.Errorf("GET store/emotes%s: %d %s", q, r.Status, r.Raw)
		}
	}
	// A picture shelf cursor is refused on the emote shelf.
	pics, _ := e.store(a.Token, "?limit=1")
	if _, r := e.emoteShelf(a.Token, "?cursor="+*pics.NextCursor); r.Status != 400 {
		t.Fatalf("picture cursor on the emote shelf: %d", r.Status)
	}
	if r := e.do("GET", "/api/v1/store/emotes", "", nil); r.Status != 401 {
		t.Fatalf("anonymous: %d", r.Status)
	}
}

func TestStoreEmotePurchase(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()
	if a.Diamonds != 50 {
		t.Fatalf("welcome diamonds %d", a.Diamonds)
	}
	all := e.walkEmotes(a.Token, "filter=all", 50)
	cheap := emoteAt(t, all, 10)
	ws := e.mustDial("a", a)

	key := "emo-" + runID + "-a"
	r := e.buyEmote(a.Token, cheap.ID, key)
	if r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}
	res := decode[struct {
		Item   shopEmote `json:"item"`
		Wallet struct {
			Coins, Diamonds int64
		} `json:"wallet"`
	}](t, r)
	if res.Item.ID != cheap.ID || !res.Item.Owned || res.Item.Path != cheap.Path || res.Wallet.Diamonds != 40 || res.Wallet.Coins != a.Coins {
		t.Fatalf("purchase response %s", r.Raw)
	}
	waitFor(t, 3*time.Second, "wallet.updated", func() bool { return ws.count("wallet.updated") >= 1 })
	ws.mu.Lock()
	msgs := append([]msg(nil), ws.all...)
	ws.mu.Unlock()
	for _, m := range msgs {
		if m.T == "wallet.updated" && (!strings.Contains(string(m.P), `"reason":"purchase"`) || !strings.Contains(string(m.P), `"diamonds":-10`)) {
			t.Fatalf("wallet.updated %s", m.P)
		}
	}

	// Idempotent replay: same body, replay header, no second charge.
	again := e.buyEmote(a.Token, cheap.ID, key)
	if again.Status != 200 || again.Header.Get("Idempotent-Replayed") != "true" || string(again.Raw) != string(r.Raw) {
		t.Fatalf("replay: %d %s %s", again.Status, again.Header.Get("Idempotent-Replayed"), again.Raw)
	}
	if got := e.diamonds(a.Token); got != 40 {
		t.Fatalf("diamonds after replay %d", got)
	}
	other := emoteAt(t, all, 40)
	if r := e.buyEmote(a.Token, other.ID, key); r.Status != 422 || errCode(r) != "idempotency_key_reused" {
		t.Fatalf("reused key: %d %s", r.Status, r.Raw)
	}
	if r := e.buyEmote(a.Token, cheap.ID, "emo-"+runID+"-b"); r.Status != 409 || errCode(r) != "already_owned" {
		t.Fatalf("already owned: %d %s", r.Status, r.Raw)
	}
	// 40 left: a 40-diamond emote empties the wallet, then nothing is
	// affordable and nothing is granted or charged.
	if r := e.buyEmote(a.Token, other.ID, ""); r.Status != 200 {
		t.Fatalf("second purchase: %d %s", r.Status, r.Raw)
	}
	third := emoteAt(t, all, 10, cheap.ID)
	if r := e.buyEmote(a.Token, third.ID, ""); r.Status != 422 || errCode(r) != "insufficient_funds" {
		t.Fatalf("insufficient: %d %s", r.Status, r.Raw)
	}
	if e.diamonds(a.Token) != 0 {
		t.Fatal("failed purchase charged diamonds")
	}
	for _, id := range []string{"em_does_not_exist", "emote_crown", "pp_angry_tortoise", "EM_BAD"} {
		if r := e.buyEmote(a.Token, id, ""); r.Status != 404 || errCode(r) != "not_found" {
			t.Fatalf("purchase %s: %d %s", id, r.Status, r.Raw)
		}
	}
	// The bought emotes leave the Shop shelf and fill the owned shelf.
	owned := e.walkEmotes(a.Token, "filter=owned", 1)
	if len(owned) != 2 || !owned[0].Owned || !owned[1].Owned {
		t.Fatalf("owned after purchase: %+v", owned)
	}
	shop := e.walkEmotes(a.Token, "filter=all&excludeOwned=true", 20)
	if len(shop) != len(all)-2 {
		t.Fatalf("Shop shelf %d, want %d", len(shop), len(all)-2)
	}
	for _, it := range shop {
		if it.ID == cheap.ID || it.ID == other.ID || it.Owned {
			t.Fatalf("Shop shelf lists owned %+v", it)
		}
	}
	// Owning a Store emote is not owning a picture or a Collection item.
	if p, _ := e.store(a.Token, "?filter=owned"); p.Total != 0 {
		t.Fatalf("owned pictures %d", p.Total)
	}
	if r := e.do("GET", "/api/v1/collection", a.Token, nil); r.Status != 200 || strings.Contains(string(r.Raw), cheap.ID) {
		t.Fatalf("collection lists the Store emote: %d", r.Status)
	}
}

func TestStoreEmoteConcurrentPurchaseChargesOnce(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()
	em := emoteAt(t, e.walkEmotes(a.Token, "filter=all", 50), 25)

	const n = 8
	statuses := make([]int, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			key := ""
			if i%2 == 0 {
				key = fmt.Sprintf("emo-%s-c%d", runID, i)
			}
			statuses[i] = e.buyEmote(a.Token, em.ID, key).Status
		}(i)
	}
	wg.Wait()
	ok, conflict := 0, 0
	for _, s := range statuses {
		switch s {
		case 200:
			ok++
		case 409:
			conflict++
		}
	}
	if ok != 1 || conflict != n-1 {
		t.Fatalf("concurrent purchases: %v", statuses)
	}
	if got := e.diamonds(a.Token); got != 50-em.Price.Diamonds {
		t.Fatalf("diamonds %d, want %d (charged once)", got, 50-em.Price.Diamonds)
	}

	// The same Idempotency-Key concurrently: one execution, identical bodies.
	b := e.guest()
	key := "emo-" + runID + "-same"
	bodies := make([]string, 4)
	for i := range bodies {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			r := e.buyEmote(b.Token, em.ID, key)
			bodies[i] = fmt.Sprintf("%d %s", r.Status, r.Raw)
		}(i)
	}
	wg.Wait()
	for _, body := range bodies[1:] {
		if body != bodies[0] || !strings.HasPrefix(body, "200 ") {
			t.Fatalf("same-key responses differ: %q", bodies)
		}
	}
	if got := e.diamonds(b.Token); got != 50-em.Price.Diamonds {
		t.Fatalf("same-key diamonds %d", got)
	}
}

func TestAssetSignEmotePaths(t *testing.T) {
	r2 := r2test.New(t, testR2Bucket, testR2KeyID, testR2Secret)
	e := newEnv(t, envOpts{r2: r2})
	a := e.guest()
	em := seededEmotes(e.walkEmotes(a.Token, "filter=all", 50))[5]
	pic := seeded(e.allPictures(a.Token, "all", 50))[0]
	body := `{"v":"5.7.4","layers":[]}`
	r2.Seed(em.Path, []byte(body), "application/json", "private, max-age=31536000, immutable")

	r := e.do("POST", "/api/v1/assets/sign", a.Token, map[string]any{"paths": []string{
		em.Path, pic.Path, "emotes/not-in-catalogue.json", "emotes/../profile_pictures/x.json"}})
	if r.Status != 200 {
		t.Fatalf("sign: %d %s", r.Status, r.Raw)
	}
	res := decode[struct {
		URLs map[string]string `json:"urls"`
	}](t, r)
	if len(res.URLs) != 2 || res.URLs[em.Path] == "" || res.URLs[pic.Path] == "" {
		t.Fatalf("signed %v, want the emote and the picture only", res.URLs)
	}
	got, err := http.Get(res.URLs[em.Path])
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := io.ReadAll(got.Body)
	got.Body.Close()
	if got.StatusCode != 200 || string(raw) != body || r2.Denied() != 0 {
		t.Fatalf("GET signed emote URL: %d %s (denied %d)", got.StatusCode, raw, r2.Denied())
	}
}

// emoteEvent is a chat.emote broadcast as a client sees it.
type emoteEvent struct {
	RoomID string `json:"roomId"`
	Seat   int    `json:"seat"`
	Emote  string `json:"emote"`
	Asset  *struct {
		Path   string `json:"path"`
		Format string `json:"format"`
	} `json:"asset"`
}

// emotesSeen returns the chat.emote events a client received, raw and decoded.
func emotesSeen(t *testing.T, c *client) ([]emoteEvent, []string) {
	t.Helper()
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []emoteEvent
	var raws []string
	for _, m := range c.all {
		if m.T != "chat.emote" {
			continue
		}
		var ev emoteEvent
		if err := json.Unmarshal(m.P, &ev); err != nil {
			t.Fatalf("chat.emote %s: %v", m.P, err)
		}
		out = append(out, ev)
		raws = append(raws, string(m.P))
	}
	return out, raws
}

// A bought Store emote is sent like a built-in one and reaches the other
// players with its art; an emote the sender does not own is refused.
func TestStoreEmoteInRoom(t *testing.T) {
	e := newEnv(t, envOpts{})
	a, b, c := e.guest(), e.guest(), e.guest()
	all := e.walkEmotes(a.Token, "filter=all", 50)
	em := emoteAt(t, all, 10)
	if r := e.buyEmote(a.Token, em.ID, ""); r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}

	ac, bc, cc := e.mustDial("a", a), e.mustDial("b", b), e.mustDial("c", c)
	if r := ac.call("room.create", map[string]any{"game": "ludo", "capacity": 4}); r.T != "room.updated" {
		t.Fatalf("create: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "lobby", func() bool { s := ac.snapshot(); return s != nil && s.Code != "" })
	room := ac.snapshot()
	for _, cl := range []*client{bc, cc} {
		if r := cl.call("room.join", map[string]any{"code": room.Code}); r.T != "room.updated" {
			t.Fatalf("join: %s %s", r.T, r.P)
		}
	}
	waitFor(t, 3*time.Second, "three seated", func() bool { s := ac.snapshot(); return s != nil && len(s.Players) == 3 })

	// Right after the purchase (written through to the owned-emote cache).
	if m := ac.call("chat.emote", map[string]any{"roomId": room.ID, "emote": em.ID}); m.T != "ack" {
		t.Fatalf("owned Store emote: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "b receives the emote", func() bool { return bc.count("chat.emote") == 1 })
	evs, raws := emotesSeen(t, bc)
	ev := evs[0]
	if ev.RoomID != room.ID || ev.Seat != seatIn(room, a.UID) || ev.Emote != em.ID || ev.Asset == nil ||
		ev.Asset.Path != em.Path || ev.Asset.Format != "lottie" {
		t.Fatalf("b got %s", raws[0])
	}
	waitFor(t, 3*time.Second, "everyone receives it", func() bool { return ac.count("chat.emote") == 1 && cc.count("chat.emote") == 1 })

	// b does not own it: refused, nothing broadcast.
	if m := bc.call("chat.emote", map[string]any{"roomId": room.ID, "emote": em.ID}); m.T != "error" || errOf(m) != "item_not_owned" {
		t.Fatalf("unowned Store emote: %s %s", m.T, m.P)
	}
	for _, bad := range []string{"em_does_not_exist", strings.Repeat("e", 65)} {
		if m := cc.call("chat.emote", map[string]any{"roomId": room.ID, "emote": bad}); m.T != "error" {
			t.Fatalf("emote %q: %s %s", bad, m.T, m.P)
		}
	}
	// A built-in emote carries no asset.
	time.Sleep(3100 * time.Millisecond) // c's chat budget: 1 per 3 s
	if m := cc.call("chat.emote", map[string]any{"roomId": room.ID, "emote": "emote_wave"}); m.T != "ack" {
		t.Fatalf("built-in emote: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "built-in emote", func() bool { return ac.count("chat.emote") == 2 })
	evs, raws = emotesSeen(t, ac)
	if evs[1].Emote != "emote_wave" || evs[1].Asset != nil || strings.Contains(raws[1], `"asset"`) {
		t.Fatalf("built-in emote payload %s", raws[1])
	}
	if bc.count("chat.emote") != 2 {
		t.Fatalf("b saw %d emotes (a refused one was broadcast?)", bc.count("chat.emote"))
	}
}
