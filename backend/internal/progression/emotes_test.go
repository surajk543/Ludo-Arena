package progression

import (
	"context"
	"errors"
	"sort"
	"testing"

	"github.com/google/uuid"

	"ludoroyale/internal/assets"
	"ludoroyale/internal/wallet"
)

// The seeded Store emote catalogue (config/emotes.tsv).
const seededEmotes = 89

// tempEmote inserts a Store emote row for one test (removed afterwards) and
// reloads the service's snapshot. Its sort order -1 puts it first on the
// shelf. Ids start with em_unit_ (the e2e tests ignore such rows).
func (f *fixture) tempEmote(t *testing.T, active bool, price int64) string {
	t.Helper()
	ctx := context.Background()
	suffix := uuid.NewString()[:8]
	id := "em_unit_" + suffix
	_, err := f.env.Pool.Exec(ctx, `INSERT INTO progression.emotes (id, name, format, path, price_diamonds, sort_order, active)
		VALUES ($1, 'Unit Test', 'lottie', $2, $3, -1, $4)`, id, "emotes/unit-"+suffix+".json", price, active)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = f.env.Pool.Exec(context.Background(), `DELETE FROM progression.inventory WHERE item_id = $1`, id)
		_, _ = f.env.Pool.Exec(context.Background(), `DELETE FROM progression.emotes WHERE id = $1`, id)
	})
	if err := f.svc.ReloadEmotes(ctx); err != nil {
		t.Fatal(err)
	}
	return id
}

func emoteIDs(p EmotePage) map[string]bool {
	out := map[string]bool{}
	for _, it := range p.Items {
		out[it.ID] = true
	}
	return out
}

// walkEmotes pages through a listing with limit and returns every item.
func (f *fixture) walkEmotes(t *testing.T, who uuid.UUID, filter string, excludeOwned bool, limit int) []ShopEmote {
	t.Helper()
	var out []ShopEmote
	cursor := ""
	for pages := 0; pages < 200; pages++ {
		p, err := f.svc.StoreEmotes(context.Background(), who, filter, excludeOwned, limit, cursor)
		if err != nil {
			t.Fatal(err)
		}
		if len(p.Items) > limit {
			t.Fatalf("page of %d items with limit %d", len(p.Items), limit)
		}
		out = append(out, p.Items...)
		if p.NextCursor == nil {
			return out
		}
		cursor = *p.NextCursor
	}
	t.Fatal("pagination did not end")
	return nil
}

func TestStoreEmotesCatalogueLoaded(t *testing.T) {
	f := newFixture(t)
	cat := f.svc.emos.get()
	if len(cat.rows) < seededEmotes || len(cat.active) < seededEmotes {
		t.Fatalf("emote catalogue: %d rows, %d active", len(cat.rows), len(cat.active))
	}
	for _, r := range cat.rows {
		if !assets.ValidEmoteID(r.ID) || r.Price < 1 {
			t.Fatalf("row %+v", r)
		}
	}
	// Built-in emotes and pictures are not Store emotes.
	for _, id := range []string{"emote_wave", "emote_crown", "pp_angry_tortoise", "em_does_not_exist"} {
		if _, _, ok := f.svc.EmoteAsset(id); ok {
			t.Fatalf("EmoteAsset(%s) ok", id)
		}
	}
	path, format, ok := f.svc.EmoteAsset("em_angry")
	if !ok || path != "emotes/angry.json" || format != assets.FormatLottie {
		t.Fatalf("EmoteAsset(em_angry) = %q %q %v", path, format, ok)
	}
}

func TestStoreEmotesPagingFiltersAndExcludeOwned(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	ids := make([]string, 4)
	for i := range ids {
		ids[i] = f.tempEmote(t, true, 1)
	}
	sort.Strings(ids)

	all := f.walkEmotes(t, a, FilterAll, false, 50)
	first, err := f.svc.StoreEmotes(ctx, a, "", false, 0, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Items) != DefaultStorePageSize || first.NextCursor == nil || first.Total != len(all) || len(all) < seededEmotes+4 {
		t.Fatalf("default page: %d items, total %d, walked %d", len(first.Items), first.Total, len(all))
	}
	// Shelf order: sort_order, then id; other page sizes walk the same order.
	for i, id := range ids {
		if all[i].ID != id {
			t.Fatalf("shelf position %d: %s, want %s", i, all[i].ID, id)
		}
	}
	small := f.walkEmotes(t, a, FilterAll, false, 7)
	if len(small) != len(all) {
		t.Fatalf("limit 7 walked %d, limit 50 %d", len(small), len(all))
	}
	seen := map[string]bool{}
	for i := range all {
		if small[i].ID != all[i].ID || seen[all[i].ID] {
			t.Fatalf("order differs or repeats at %d", i)
		}
		seen[all[i].ID] = true
	}

	for _, id := range []string{ids[0], ids[2]} {
		if _, err := f.svc.PurchaseEmote(ctx, a, id); err != nil {
			t.Fatal(err)
		}
	}
	shop := f.walkEmotes(t, a, FilterAll, true, 3)
	if len(shop) != len(all)-2 {
		t.Fatalf("excludeOwned walked %d, want %d", len(shop), len(all)-2)
	}
	for _, it := range shop {
		if it.Owned || it.ID == ids[0] || it.ID == ids[2] {
			t.Fatalf("excludeOwned lists owned %+v", it)
		}
	}
	owned, err := f.svc.StoreEmotes(ctx, a, FilterOwned, false, 50, "")
	if err != nil || owned.Total != 2 || !emoteIDs(owned)[ids[0]] || !emoteIDs(owned)[ids[2]] || !owned.Items[0].Owned {
		t.Fatalf("owned %+v %v", owned, err)
	}

	// A cursor taken before a purchase: the bought emote is left out of the
	// next page and nothing repeats.
	p1, err := f.svc.StoreEmotes(ctx, a, FilterAll, true, 1, "")
	if err != nil || p1.Items[0].ID != ids[1] || p1.NextCursor == nil {
		t.Fatalf("page 1 %+v %v", p1, err)
	}
	if _, err := f.svc.PurchaseEmote(ctx, a, ids[3]); err != nil {
		t.Fatal(err)
	}
	p2, err := f.svc.StoreEmotes(ctx, a, FilterAll, true, 1, *p1.NextCursor)
	if err != nil || p2.Items[0].ID == ids[3] || p2.Items[0].ID == ids[1] || p2.Total != len(all)-3 {
		t.Fatalf("page 2 after a purchase %+v %v", p2, err)
	}

	for _, c := range []struct {
		filter, cursor string
		exclude        bool
		limit          int
	}{
		{FilterOwned, "", true, 10}, {FilterAnimated, "", false, 10}, {"gif", "", false, 10},
		{FilterAll, "", false, 51}, {FilterAll, "", false, -1}, {FilterAll, "x", false, 10},
		// A profile-picture cursor is not an emote cursor.
		{FilterAll, encodeCursor(&pictureRow{ID: "pp_bear", SortOrder: 1}), false, 10},
	} {
		if _, err := f.svc.StoreEmotes(ctx, a, c.filter, c.exclude, c.limit, c.cursor); !errors.Is(err, ErrBadStoreQuery) {
			t.Fatalf("%+v: %v", c, err)
		}
	}
}

func TestPurchaseEmote(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	id := f.tempEmote(t, true, 7)
	// The owner raises the price; the snapshot is stale until the next
	// reload, but the purchase charges the PostgreSQL price.
	if _, err := f.env.Pool.Exec(ctx, `UPDATE progression.emotes SET price_diamonds = 11 WHERE id = $1`, id); err != nil {
		t.Fatal(err)
	}
	res, err := f.svc.PurchaseEmote(ctx, a, id)
	if err != nil {
		t.Fatal(err)
	}
	if res.Item.ID != id || !res.Item.Owned || res.Item.Price.Diamonds != 11 || res.Wallet.Diamonds != 50-11 {
		t.Fatalf("purchase %+v", res)
	}
	if len(f.notes.For(a, MsgWalletUpdated)) == 0 {
		t.Fatal("no wallet.updated push")
	}
	if _, err := f.svc.PurchaseEmote(ctx, a, id); !errors.Is(err, ErrAlreadyOwned) {
		t.Fatalf("second purchase: %v", err)
	}
	// Too expensive: nothing granted, nothing charged.
	dear := f.tempEmote(t, true, 1000)
	if _, err := f.svc.PurchaseEmote(ctx, a, dear); !errors.Is(err, wallet.ErrInsufficientFunds) {
		t.Fatalf("insufficient: %v", err)
	}
	if ok, _ := f.svc.ownsStored(ctx, a, dear); ok {
		t.Fatal("granted without payment")
	}
	// Retired, unknown and non-emote ids are not for sale.
	retired := f.tempEmote(t, false, 1)
	for _, bad := range []string{retired, "em_does_not_exist", "emote_crown", "pp_angry_tortoise", "EM_X", ""} {
		if _, err := f.svc.PurchaseEmote(ctx, a, bad); !errors.Is(err, ErrEmoteNotFound) {
			t.Fatalf("purchase %q: %v", bad, err)
		}
	}
	if got, _ := wallet.GetTx(ctx, f.env.Pool, a); got.Diamonds != 50-11 {
		t.Fatalf("diamonds %d", got.Diamonds)
	}
}

// Store emotes share the chat hot path of the catalogue emotes: the cached
// set of owned emotes, written through on purchase.
func TestStoreEmoteOwnershipUsesTheEmoteCache(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	first, id := f.tempEmote(t, true, 3), f.tempEmote(t, true, 3)
	key := EmotesKey(a)

	if f.owns(t, a, id) {
		t.Fatal("unbought Store emote owned")
	}
	// The first owned emote fills the set from PostgreSQL.
	if _, err := f.svc.PurchaseEmote(ctx, a, first); err != nil {
		t.Fatal(err)
	}
	if !f.owns(t, a, first) || !f.inSet(t, key, first) {
		t.Fatal("the lookup did not fill the set with the Store emote")
	}
	if _, err := f.svc.PurchaseEmote(ctx, a, id); err != nil {
		t.Fatal(err)
	}
	if !f.inSet(t, key, id) {
		t.Fatal("purchase not written through to the cached set")
	}
	hit0 := lookups("emotes", "hit")
	if !f.owns(t, a, id) || lookups("emotes", "hit")-hit0 != 1 {
		t.Fatal("owned Store emote was not a cache hit")
	}
	// A cold set is filled with the Store emotes too.
	if err := f.env.RDB.Del(ctx, key).Err(); err != nil {
		t.Fatal(err)
	}
	if !f.owns(t, a, id) || !f.inSet(t, key, id) {
		t.Fatal("refill lost the Store emote")
	}
	if f.owns(t, b, id) {
		t.Fatal("another account owns it")
	}
	// Retired: no longer sold, still owned and still drawn.
	if _, err := f.env.Pool.Exec(ctx, `UPDATE progression.emotes SET active = FALSE WHERE id = $1`, id); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.ReloadEmotes(ctx); err != nil {
		t.Fatal(err)
	}
	if !f.owns(t, a, id) {
		t.Fatal("retired emote no longer owned")
	}
	if _, _, ok := f.svc.EmoteAsset(id); !ok {
		t.Fatal("retired emote has no art")
	}
	if p, _ := f.svc.StoreEmotes(ctx, b, FilterAll, false, 50, ""); emoteIDs(p)[id] {
		t.Fatal("retired emote listed to a non-owner")
	}
	if p, _ := f.svc.StoreEmotes(ctx, a, FilterAll, false, 50, ""); !emoteIDs(p)[id] {
		t.Fatal("retired emote hidden from its owner")
	}
}

// A row added on another instance is unknown to this snapshot until the
// next reload; its owner can still send it, and the snapshot catches up.
func TestOwnedEmoteMissingFromSnapshotReloads(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	id := f.tempEmote(t, true, 1)
	other := f.newService(t) // loaded with the row
	if _, err := other.PurchaseEmote(ctx, a, id); err != nil {
		t.Fatal(err)
	}
	stale := f.newService(t)
	cur := stale.emos.get()
	trimmed := &pictureCatalog{byID: map[string]*pictureRow{}, byPath: map[string]*pictureRow{}}
	for _, r := range cur.rows {
		if r.ID != id {
			trimmed.rows = append(trimmed.rows, r)
			trimmed.byID[r.ID], trimmed.byPath[r.Path] = r, r
		}
	}
	stale.emos.cur.Store(trimmed)
	if ok, err := stale.Owns(ctx, a, id); err != nil || !ok {
		t.Fatalf("owns %v %v", ok, err)
	}
	if _, _, ok := stale.EmoteAsset(id); !ok {
		t.Fatal("snapshot did not catch up")
	}
}

func TestSignAssetPathsSignsEmotePaths(t *testing.T) {
	f := newFixture(t)
	sig := &fakeSigner{}
	f.svc.signer = sig
	pic := f.svc.pics.get().rows[0].Path
	urls, _, ok := f.svc.SignAssetPaths([]string{"emotes/angry.json", pic, "emotes/not-in-catalogue.json", "emotes/../x.json"})
	if !ok || len(urls) != 2 || urls["emotes/angry.json"] == "" || urls[pic] == "" {
		t.Fatalf("signed %v (asked %v)", urls, sig.keys)
	}
}

// Bot personas may own Store emotes like players who bought them: active
// ones only, marked as Store emotes.
func TestCatalogItemsIncludeActiveStoreEmotes(t *testing.T) {
	f := newFixture(t)
	retired := f.tempEmote(t, false, 1)
	store := 0
	for _, it := range f.svc.CatalogItems() {
		if !assets.ValidEmoteID(it.ID) {
			if it.StoreEmote {
				t.Fatalf("%s marked as a Store emote", it.ID)
			}
			continue
		}
		if it.ID == retired || it.Kind != KindEmote || !it.Purchase || !it.StoreEmote || it.Starter || it.Level != 0 {
			t.Fatalf("item %+v", it)
		}
		store++
	}
	if store < seededEmotes {
		t.Fatalf("%d Store emotes", store)
	}
}
