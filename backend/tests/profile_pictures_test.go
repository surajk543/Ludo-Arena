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
	"ludoarena/internal/rooms"
)

// Profile-picture Store end to end (docs/rest-api.md → Store): production
// wiring, the seeded catalogue (migrations 007/008) and, for signing, a fake
// R2 that verifies every SigV4 signature (internal/assets/r2test).
//
// The test database is shared with the package tests running in parallel:
// internal/progression adds short-lived rows with ids "pp_unit_…". Listings
// are therefore checked against the manifest with those rows ignored.

const catalogueSize = 160 // backend/config/profile_pictures.tsv

// unitRowPrefix marks the temporary rows of internal/progression tests.
const unitRowPrefix = "pp_unit_"

// manifest returns the seeded catalogue (config/profile_pictures.tsv).
func manifest(t *testing.T) []assets.PictureRow {
	t.Helper()
	f, err := os.Open("../config/profile_pictures.tsv")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	rows, err := assets.ReadPictureManifest(f)
	if err != nil || len(rows) != catalogueSize {
		t.Fatalf("manifest: %d rows, %v", len(rows), err)
	}
	return rows
}

// seeded drops other packages' temporary rows from a listing.
func seeded(items []storePicture) []storePicture {
	out := make([]storePicture, 0, len(items))
	for _, it := range items {
		if !strings.HasPrefix(it.ID, unitRowPrefix) {
			out = append(out, it)
		}
	}
	return out
}

type storePicture struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Format string `json:"format"`
	Path   string `json:"path"`
	Price  struct {
		Diamonds int64 `json:"diamonds"`
	} `json:"price"`
	Owned    bool `json:"owned"`
	Equipped bool `json:"equipped"`
}

type storePage struct {
	Items      []storePicture `json:"items"`
	NextCursor *string        `json:"nextCursor"`
	Total      int            `json:"total"`
	Equipped   *string        `json:"equipped"`
}

type playerPicture struct {
	ID     string `json:"id"`
	Format string `json:"format"`
	Path   string `json:"path"`
}

func decode[T any](t *testing.T, r resp) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(r.Raw, &v); err != nil {
		t.Fatalf("decode %s: %v", r.Raw, err)
	}
	return v
}

func (e *env) store(token, query string) (storePage, resp) {
	e.t.Helper()
	r := e.do("GET", "/api/v1/store/profile-pictures"+query, token, nil)
	if r.Status != 200 {
		return storePage{}, r
	}
	return decode[storePage](e.t, r), r
}

// allPictures pages through a filter with the given page size.
func (e *env) allPictures(token, filter string, limit int) []storePicture {
	e.t.Helper()
	return e.walkPictures(token, "filter="+filter, limit)
}

// walkPictures pages through the listing selected by query (filter and
// excludeOwned, without limit and cursor) with the given page size.
func (e *env) walkPictures(token, query string, limit int) []storePicture {
	e.t.Helper()
	var out []storePicture
	cursor := ""
	for pages := 0; pages < 100; pages++ {
		q := fmt.Sprintf("?%s&limit=%d", query, limit)
		if cursor != "" {
			q += "&cursor=" + cursor
		}
		p, r := e.store(token, q)
		if r.Status != 200 {
			e.t.Fatalf("store page: %d %s", r.Status, r.Raw)
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

func (e *env) diamonds(token string) int64 {
	e.t.Helper()
	r := e.do("GET", "/api/v1/wallet", token, nil)
	if r.Status != 200 {
		e.t.Fatalf("wallet: %d %s", r.Status, r.Raw)
	}
	return int64(r.Body["diamonds"].(float64))
}

// cheapest returns the cheapest seeded picture of a format.
func cheapest(t *testing.T, items []storePicture, format string) storePicture {
	t.Helper()
	var best *storePicture
	items = seeded(items)
	for i := range items {
		if items[i].Format == format && (best == nil || items[i].Price.Diamonds < best.Price.Diamonds) {
			best = &items[i]
		}
	}
	if best == nil {
		t.Fatalf("no %s picture", format)
	}
	return *best
}

func (e *env) buyPicture(token, id string, key string) resp {
	e.t.Helper()
	var h []string
	if key != "" {
		h = []string{"Idempotency-Key", key}
	}
	return e.do("POST", "/api/v1/store/profile-pictures/"+id+"/purchase", token, nil, h...)
}

func TestStoreListPagingAndFilters(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()

	first, r := e.store(a.Token, "")
	if r.Status != 200 {
		t.Fatalf("GET store: %d %s", r.Status, r.Raw)
	}
	if len(first.Items) != 24 || first.Total < catalogueSize || first.NextCursor == nil || first.Equipped != nil {
		t.Fatalf("default page: %d items, total %d, next %v, equipped %v", len(first.Items), first.Total, first.NextCursor, first.Equipped)
	}
	for _, k := range []string{`"nextCursor"`, `"total"`, `"equipped":null`, `"price":{"diamonds":`, `"owned":false`} {
		if !strings.Contains(string(r.Raw), k) {
			t.Errorf("store body lacks %s", k)
		}
	}

	all := e.allPictures(a.Token, "all", 50)
	if len(all) != first.Total {
		t.Fatalf("paged %d pictures, total says %d", len(all), first.Total)
	}
	seen := map[string]bool{}
	for i, p := range all {
		if seen[p.ID] {
			t.Fatalf("duplicate %s across pages", p.ID)
		}
		seen[p.ID] = true
		if i < len(first.Items) && first.Items[i].ID != p.ID {
			t.Fatalf("order differs between page sizes at %d: %s vs %s", i, first.Items[i].ID, p.ID)
		}
	}
	// Exactly the manifest, in shelf order (sort_order, id), with its data.
	rows, got := manifest(t), seeded(all)
	if len(got) != len(rows) {
		t.Fatalf("listed %d seeded pictures, manifest has %d", len(got), len(rows))
	}
	for i, m := range rows {
		p := got[i]
		if p.ID != m.ID || p.Name != m.Name || p.Format != m.Format || p.Path != m.Path ||
			p.Price.Diamonds != int64(m.PriceDiamonds) || p.Owned || p.Equipped {
			t.Fatalf("item %d: %+v, manifest %+v", i, p, m)
		}
	}
	// Smaller pages walk the same order.
	if small := e.allPictures(a.Token, "all", 7); len(small) != len(all) || small[100].ID != all[100].ID {
		t.Fatalf("limit 7 walked %d pictures", len(small))
	}

	for _, c := range []struct {
		filter, format, prefix string
		want                   int
	}{{"animated", "lottie", "profile_pictures/lottie_animation/", 145}, {"static", "image", "profile_pictures/image/", 15}} {
		items := e.allPictures(a.Token, c.filter, 50)
		p, _ := e.store(a.Token, "?filter="+c.filter)
		if len(seeded(items)) != c.want || p.Total != len(items) {
			t.Fatalf("%s: %d items, total %d, want %d", c.filter, len(items), p.Total, c.want)
		}
		for _, it := range items {
			if it.Format != c.format || !strings.HasPrefix(it.Path, c.prefix) {
				t.Fatalf("%s: item %+v", c.filter, it)
			}
		}
	}
	if owned, _ := e.store(a.Token, "?filter=owned"); owned.Total != 0 || len(owned.Items) != 0 || owned.NextCursor != nil {
		t.Fatalf("owned before buying: %+v", owned)
	}

	for _, q := range []string{"?filter=gif", "?limit=0", "?limit=51", "?limit=x", "?cursor=!!!", "?cursor=bm9wZQ"} {
		if _, r := e.store(a.Token, q); r.Status != 400 || errCode(r) != "bad_request" {
			t.Errorf("GET store%s: %d %s", q, r.Status, r.Raw)
		}
	}
	// Authenticated humans only, behind the version gate.
	if r := e.do("GET", "/api/v1/store/profile-pictures", "", nil); r.Status != 401 {
		t.Fatalf("anonymous store: %d", r.Status)
	}
}

func TestStorePurchase(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()
	if a.Diamonds != 50 {
		t.Fatalf("welcome diamonds %d", a.Diamonds)
	}
	all := e.allPictures(a.Token, "all", 50)
	pic := cheapest(t, all, "lottie")
	ws := e.mustDial("a", a)

	key := "pfp-" + runID + "-a"
	r := e.buyPicture(a.Token, pic.ID, key)
	if r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}
	res := decode[struct {
		Item   storePicture `json:"item"`
		Wallet struct {
			Coins, Diamonds int64
		} `json:"wallet"`
	}](t, r)
	if res.Item.ID != pic.ID || !res.Item.Owned || res.Item.Equipped || res.Item.Path != pic.Path ||
		res.Wallet.Diamonds != 50-pic.Price.Diamonds || res.Wallet.Coins != a.Coins {
		t.Fatalf("purchase response %s", r.Raw)
	}
	waitFor(t, 3*time.Second, "wallet.updated", func() bool { return ws.count("wallet.updated") >= 1 })
	ws.mu.Lock()
	msgs := append([]msg(nil), ws.all...)
	ws.mu.Unlock()
	for _, m := range msgs {
		if m.T == "wallet.updated" && (!strings.Contains(string(m.P), `"reason":"purchase"`) ||
			!strings.Contains(string(m.P), fmt.Sprintf(`"diamonds":%d`, -pic.Price.Diamonds))) {
			t.Fatalf("wallet.updated %s", m.P)
		}
	}

	// Idempotent replay: same body, replay header, no second charge.
	again := e.buyPicture(a.Token, pic.ID, key)
	if again.Status != 200 || again.Header.Get("Idempotent-Replayed") != "true" || string(again.Raw) != string(r.Raw) {
		t.Fatalf("replay: %d %s %s", again.Status, again.Header.Get("Idempotent-Replayed"), again.Raw)
	}
	if got := e.diamonds(a.Token); got != 50-pic.Price.Diamonds {
		t.Fatalf("diamonds after replay %d", got)
	}
	// The same key on another route is refused.
	other := cheapest(t, all, "image")
	if r := e.buyPicture(a.Token, other.ID, key); r.Status != 422 || errCode(r) != "idempotency_key_reused" {
		t.Fatalf("reused key: %d %s", r.Status, r.Raw)
	}
	// A new request for an owned picture.
	if r := e.buyPicture(a.Token, pic.ID, "pfp-"+runID+"-b"); r.Status != 409 || errCode(r) != "already_owned" {
		t.Fatalf("already owned: %d %s", r.Status, r.Raw)
	}
	// Not enough diamonds: nothing granted, nothing charged.
	left := e.diamonds(a.Token)
	var dear storePicture
	for _, p := range seeded(all) {
		if p.Price.Diamonds > left {
			dear = p
			break
		}
	}
	if r := e.buyPicture(a.Token, dear.ID, ""); r.Status != 422 || errCode(r) != "insufficient_funds" {
		t.Fatalf("insufficient: %d %s", r.Status, r.Raw)
	}
	if e.diamonds(a.Token) != left {
		t.Fatal("failed purchase charged diamonds")
	}
	for _, id := range []string{"pp_does_not_exist", "emote_crown", "PP_BAD"} {
		if r := e.buyPicture(a.Token, id, ""); r.Status != 404 || errCode(r) != "not_found" {
			t.Fatalf("purchase %s: %d %s", id, r.Status, r.Raw)
		}
	}
	owned, _ := e.store(a.Token, "?filter=owned")
	if owned.Total != 1 || owned.Items[0].ID != pic.ID || !owned.Items[0].Owned {
		t.Fatalf("owned after purchase: %+v", owned)
	}
	// Owning a picture is not owning a Collection item, and vice versa.
	if r := e.do("GET", "/api/v1/collection", a.Token, nil); r.Status != 200 || strings.Contains(string(r.Raw), pic.ID) {
		t.Fatalf("collection lists the picture: %d", r.Status)
	}
}

// The app's Shop lists only pictures the player does not own yet
// (excludeOwned=true); the default listing is unchanged.
func TestStoreExcludeOwned(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()
	type listing struct {
		filter string
		total  int
		seeded int
	}
	count := func(filter, extra string) listing {
		t.Helper()
		p, r := e.store(a.Token, "?filter="+filter+extra)
		if r.Status != 200 {
			t.Fatalf("store ?filter=%s%s: %d %s", filter, extra, r.Status, r.Raw)
		}
		return listing{filter, p.Total, len(seeded(e.walkPictures(a.Token, "filter="+filter+extra, 50)))}
	}
	filters := []string{"all", "animated", "static"}
	before := map[string]listing{}
	for _, f := range filters {
		before[f] = count(f, "&excludeOwned=true")
		if dflt := count(f, ""); dflt != before[f] {
			t.Fatalf("%s: nothing owned yet, excludeOwned %+v vs default %+v", f, before[f], dflt)
		}
	}

	pic := cheapest(t, e.allPictures(a.Token, "all", 50), "image")
	if r := e.buyPicture(a.Token, pic.ID, "pfp-"+runID+"-excl"); r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}
	for _, f := range filters {
		// One fewer picture where the bought one was listed, paged with a
		// small page size: it is never on any page.
		want := before[f]
		if f != "animated" {
			want.total--
			want.seeded--
		}
		if got := count(f, "&excludeOwned=true"); got != want {
			t.Fatalf("%s excludeOwned after buying: %+v, want %+v", f, got, want)
		}
		for _, it := range e.walkPictures(a.Token, "filter="+f+"&excludeOwned=true", 20) {
			if it.ID == pic.ID || it.Owned {
				t.Fatalf("%s excludeOwned lists owned %+v", f, it)
			}
		}
	}
	// excludeOwned=false is the default listing: the picture is there, owned.
	found := false
	for _, it := range e.walkPictures(a.Token, "filter=static&excludeOwned=false", 50) {
		if it.ID == pic.ID {
			found = it.Owned
		}
	}
	if !found {
		t.Fatal("excludeOwned=false hides the owned picture")
	}

	for _, q := range []string{"?filter=owned&excludeOwned=true", "?excludeOwned=yes", "?excludeOwned=1", "?excludeOwned=TRUE"} {
		if _, r := e.store(a.Token, q); r.Status != 400 || errCode(r) != "bad_request" {
			t.Errorf("GET store%s: %d %s", q, r.Status, r.Raw)
		}
	}
	if owned, r := e.store(a.Token, "?filter=owned&excludeOwned=false"); r.Status != 200 || owned.Total != 1 {
		t.Fatalf("owned with excludeOwned=false: %d %+v", r.Status, owned)
	}
}

func TestStoreConcurrentPurchaseChargesOnce(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()
	pic := cheapest(t, e.allPictures(a.Token, "all", 50), "image")

	// Different keys (or none): exactly one succeeds.
	const n = 8
	statuses := make([]int, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			key := ""
			if i%2 == 0 {
				key = fmt.Sprintf("pfp-%s-c%d", runID, i)
			}
			statuses[i] = e.buyPicture(a.Token, pic.ID, key).Status
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
	if got := e.diamonds(a.Token); got != 50-pic.Price.Diamonds {
		t.Fatalf("diamonds %d, want %d (charged once)", got, 50-pic.Price.Diamonds)
	}

	// The same Idempotency-Key concurrently: one execution, identical bodies.
	b := e.guest()
	key := "pfp-" + runID + "-same"
	bodies := make([]string, 4)
	for i := range bodies {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			r := e.buyPicture(b.Token, pic.ID, key)
			bodies[i] = fmt.Sprintf("%d %s", r.Status, r.Raw)
		}(i)
	}
	wg.Wait()
	for _, body := range bodies[1:] {
		if body != bodies[0] || !strings.HasPrefix(body, "200 ") {
			t.Fatalf("same-key responses differ: %q", bodies)
		}
	}
	if got := e.diamonds(b.Token); got != 50-pic.Price.Diamonds {
		t.Fatalf("same-key diamonds %d", got)
	}
}

func TestApplyProfilePicture(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()
	all := e.allPictures(a.Token, "all", 50)
	pic, notOwned := cheapest(t, all, "lottie"), cheapest(t, all, "image")
	apply := func(body any) resp { return e.do("PUT", "/api/v1/me/profile-picture", a.Token, body) }

	if r := apply(map[string]any{"id": notOwned.ID}); r.Status != 422 || errCode(r) != "item_locked" {
		t.Fatalf("apply not owned: %d %s", r.Status, r.Raw)
	}
	if r := apply(map[string]any{"id": "pp_unknown_picture"}); r.Status != 404 || errCode(r) != "not_found" {
		t.Fatalf("apply unknown: %d %s", r.Status, r.Raw)
	}
	for _, body := range []any{map[string]any{}, map[string]any{"id": ""}, map[string]any{"id": 7}, map[string]any{"pictureId": pic.ID}} {
		if r := apply(body); r.Status != 400 {
			t.Fatalf("apply %v: %d %s", body, r.Status, r.Raw)
		}
	}
	if r := e.buyPicture(a.Token, pic.ID, ""); r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}
	r := apply(map[string]any{"id": pic.ID})
	if r.Status != 200 {
		t.Fatalf("apply: %d %s", r.Status, r.Raw)
	}
	eq := decode[struct {
		Equipped *storePicture `json:"equipped"`
	}](t, r)
	if eq.Equipped == nil || eq.Equipped.ID != pic.ID || !eq.Equipped.Owned || !eq.Equipped.Equipped {
		t.Fatalf("apply response %s", r.Raw)
	}
	me := e.do("GET", "/api/v1/me", a.Token, nil)
	user := decode[struct {
		User struct {
			Picture *playerPicture    `json:"picture"`
			Loadout map[string]string `json:"loadout"`
		} `json:"user"`
	}](t, me)
	if p := user.User.Picture; p == nil || p.ID != pic.ID || p.Format != "lottie" || p.Path != pic.Path {
		t.Fatalf("GET /me picture: %s", me.Raw)
	}
	if _, ok := user.User.Loadout["avatar"]; ok {
		t.Fatal("the picture leaked into the Collection loadout")
	}
	page, _ := e.store(a.Token, "?filter=owned")
	if page.Equipped == nil || *page.Equipped != pic.ID || !page.Items[0].Equipped {
		t.Fatalf("store equipped: %+v", page)
	}

	// null: back to the built-in avatar.
	r = apply(map[string]any{"id": nil})
	if r.Status != 200 || !strings.Contains(string(r.Raw), `"equipped":null`) {
		t.Fatalf("apply null: %d %s", r.Status, r.Raw)
	}
	me = e.do("GET", "/api/v1/me", a.Token, nil)
	if !strings.Contains(string(me.Raw), `"picture":null`) {
		t.Fatalf("GET /me after null: %s", me.Raw)
	}
	if page, _ := e.store(a.Token, ""); page.Equipped != nil {
		t.Fatalf("store equipped after null: %v", *page.Equipped)
	}
}

func TestAssetSign(t *testing.T) {
	r2 := r2test.New(t, testR2Bucket, testR2KeyID, testR2Secret)
	e := newEnv(t, envOpts{r2: r2})
	a := e.guest()
	all := seeded(e.allPictures(a.Token, "all", 50))
	known := all[3].Path
	r2.Seed(known, []byte(`{"v":"5.7.4","layers":[]}`), "application/json", "private, max-age=31536000, immutable")

	sign := func(paths any) resp {
		return e.do("POST", "/api/v1/assets/sign", a.Token, map[string]any{"paths": paths})
	}
	before := time.Now()
	r := sign([]string{known, "profile_pictures/image/not-in-catalogue.png", known, "../../etc/passwd"})
	if r.Status != 200 {
		t.Fatalf("sign: %d %s", r.Status, r.Raw)
	}
	res := decode[struct {
		URLs      map[string]string `json:"urls"`
		ExpiresAt int64             `json:"expiresAt"`
	}](t, r)
	if len(res.URLs) != 1 || res.URLs[known] == "" {
		t.Fatalf("signed %v, want only the catalogue path", res.URLs)
	}
	exp := time.UnixMilli(res.ExpiresAt)
	if exp.Before(before.Add(10*time.Minute-time.Second)) || exp.After(time.Now().Add(10*time.Minute+2*time.Second)) {
		t.Fatalf("expiresAt %s is not ~10 min from now", exp)
	}
	if !strings.HasPrefix(res.URLs[known], r2.URL+"/"+testR2Bucket+"/"+known+"?X-Amz-Algorithm=AWS4-HMAC-SHA256") ||
		strings.Contains(res.URLs[known], testR2Secret) {
		t.Fatal("signed URL has an unexpected shape")
	}
	// The fake R2 verifies the signature and serves the object.
	got, err := http.Get(res.URLs[known])
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(got.Body)
	got.Body.Close()
	if got.StatusCode != 200 || string(body) != `{"v":"5.7.4","layers":[]}` || r2.Denied() != 0 {
		t.Fatalf("GET signed URL: %d %s (denied %d)", got.StatusCode, body, r2.Denied())
	}
	// The bucket itself is private.
	if res, err := http.Get(r2.URL + "/" + testR2Bucket + "/" + known); err != nil || res.StatusCode != 403 {
		t.Fatalf("unsigned GET: %v %v", res, err)
	}

	// Unknown paths only: an empty map, never a signature.
	if r := sign([]string{"profile_pictures/image/nope.png"}); r.Status != 200 || !strings.Contains(string(r.Raw), `"urls":{}`) {
		t.Fatalf("unknown only: %d %s", r.Status, r.Raw)
	}
	many := make([]string, 51)
	for i := range many {
		many[i] = all[i].Path
	}
	for _, bad := range []any{[]string{}, nil, many, []string{""}, []string{strings.Repeat("a", 256)}} {
		if r := sign(bad); r.Status != 400 || errCode(r) != "bad_request" {
			t.Fatalf("sign %v: %d %s", bad, r.Status, r.Raw)
		}
	}
	if r := sign(many[:50]); r.Status != 200 {
		t.Fatalf("50 paths: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/assets/sign", "", map[string]any{"paths": []string{known}}); r.Status != 401 {
		t.Fatalf("anonymous sign: %d", r.Status)
	}
}

func TestAssetSignUnavailableWithoutR2(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()
	r := e.do("POST", "/api/v1/assets/sign", a.Token, map[string]any{"paths": []string{"profile_pictures/image/bear.png"}})
	if r.Status != 503 || errCode(r) != "assets_unavailable" {
		t.Fatalf("sign without R2: %d %s", r.Status, r.Raw)
	}
	// The Store itself works without R2.
	if p, r := e.store(a.Token, "?limit=1"); r.Status != 200 || p.Total < catalogueSize {
		t.Fatalf("store without R2: %d %s", r.Status, r.Raw)
	}
}

// seatPictures returns the raw "picture" of every seat in the client's last
// room snapshot, by uid.
func seatPictures(t *testing.T, c *client) map[string]json.RawMessage {
	t.Helper()
	c.mu.Lock()
	defer c.mu.Unlock()
	for i := len(c.all) - 1; i >= 0; i-- {
		m := c.all[i]
		if m.T != "room.updated" && m.T != "game.started" && m.T != "game.state" {
			continue
		}
		var p struct {
			Room *struct {
				Players []map[string]json.RawMessage `json:"players"`
			} `json:"room"`
		}
		if json.Unmarshal(m.P, &p) != nil || p.Room == nil {
			continue
		}
		out := map[string]json.RawMessage{}
		for _, pl := range p.Room.Players {
			var uid string
			_ = json.Unmarshal(pl["uid"], &uid)
			pic, ok := pl["picture"]
			if !ok {
				t.Fatalf("seat %s has no picture key", uid)
			}
			out[uid] = pic
		}
		return out
	}
	return nil
}

func TestSeatPictureVisibleToOtherPlayers(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(5)})
	a, b := e.guest(), e.guest()
	pic := cheapest(t, e.allPictures(a.Token, "all", 50), "lottie")
	if r := e.buyPicture(a.Token, pic.ID, ""); r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}
	// Join once before applying, so the seat cache is warm with no picture:
	// applying must invalidate it.
	ca := e.mustDial("a", a)
	if m := ca.call("matchmaking.join", map[string]any{"game": "ludo", "capacity": 2}); m.T != "matchmaking.status" {
		t.Fatalf("join: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "a lobby", func() bool { return ca.snapshot() != nil })
	if m := ca.call("matchmaking.cancel", map[string]any{}); m.T == "error" {
		t.Fatalf("cancel: %s", m.P)
	}
	if r := e.do("PUT", "/api/v1/me/profile-picture", a.Token, map[string]any{"id": pic.ID}); r.Status != 200 {
		t.Fatalf("apply: %d %s", r.Status, r.Raw)
	}

	cb := e.mustDial("b", b)
	ca.call("matchmaking.join", map[string]any{"game": "ludo", "capacity": 2})
	cb.call("matchmaking.join", map[string]any{"game": "ludo", "capacity": 2})
	waitFor(t, 5*time.Second, "both seated", func() bool {
		s := cb.snapshot()
		return s != nil && len(s.Players) == 2
	})
	pics := seatPictures(t, cb)
	var seen playerPicture
	if err := json.Unmarshal(pics[a.UID], &seen); err != nil || seen.ID != pic.ID || seen.Format != "lottie" || seen.Path != pic.Path {
		t.Fatalf("b sees a's seat picture %s", pics[a.UID])
	}
	if string(pics[b.UID]) != "null" {
		t.Fatalf("b's own seat picture %s, want null", pics[b.UID])
	}
	waitFor(t, 3*time.Second, "a sees both", func() bool {
		s := ca.snapshot()
		return s != nil && len(s.Players) == 2
	})
	if got := seatPictures(t, ca); string(got[b.UID]) != "null" || string(got[a.UID]) == "null" {
		t.Fatalf("a's view %v", got)
	}

	// Friend requests, friend lists and the leaderboard show it too.
	fr := e.do("POST", "/api/v1/friends/requests", b.Token, map[string]any{"friendCode": a.UID})
	if fr.Status != 201 || !strings.Contains(string(fr.Raw), `"picture":{"id":"`+pic.ID+`"`) {
		t.Fatalf("friend request: %d %s", fr.Status, fr.Raw)
	}
	if r := e.do("GET", "/api/v1/friends", a.Token, nil); r.Status != 200 || !strings.Contains(string(r.Raw), `"picture":null`) {
		t.Fatalf("a's friends (b has no picture): %d %s", r.Status, r.Raw)
	}
	if r := e.do("GET", "/api/v1/friends", b.Token, nil); r.Status != 200 || !strings.Contains(string(r.Raw), `"picture":{"id":"`+pic.ID+`"`) {
		t.Fatalf("b's friends: %d %s", r.Status, r.Raw)
	}
	if r := e.do("GET", "/api/v1/leaderboards/friends", a.Token, nil); r.Status != 200 || !strings.Contains(string(r.Raw), `"picture":{"id":"`+pic.ID+`"`) {
		t.Fatalf("leaderboard: %d %s", r.Status, r.Raw)
	}
}

func TestBotPictureShare(t *testing.T) {
	for _, c := range []struct {
		share string
		want  bool
	}{{"1", true}, {"0", false}} {
		t.Run("share="+c.share, func(t *testing.T) {
			e := newEnv(t, envOpts{dice: rooms.NewSeededDice(9), botPictureShare: c.share})
			active := map[string]storePicture{}
			human := e.guest()
			for _, p := range e.allPictures(human.Token, "all", 50) { // the server's own snapshot
				active[p.ID] = p
			}
			ctl := e.botController(t)
			hc := e.mustDial("human", human)
			if m := hc.call("practice.start", map[string]any{"game": "ludo", "variant": "quick", "bots": 3}); m.T != "room.updated" {
				t.Fatalf("practice.start: %s %s", m.T, m.P)
			}
			e.spawnBots(t, ctl, 3)
			waitFor(t, 10*time.Second, "bots seated", func() bool {
				s := hc.snapshot()
				return s != nil && len(s.Players) == 4
			})
			pics := seatPictures(t, hc)
			if len(pics) != 4 {
				t.Fatalf("%d seats in the snapshot", len(pics))
			}
			for uid, raw := range pics {
				if uid == human.UID {
					if string(raw) != "null" {
						t.Fatalf("human picture %s", raw)
					}
					continue
				}
				if !c.want {
					if string(raw) != "null" {
						t.Fatalf("share 0: bot %s wears %s", uid, raw)
					}
					continue
				}
				var p playerPicture
				if err := json.Unmarshal(raw, &p); err != nil || active[p.ID].Path != p.Path || p.Path == "" {
					t.Fatalf("share 1: bot %s wears %s", uid, raw)
				}
			}
		})
	}
}
