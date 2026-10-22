package progression

import (
	"context"
	"errors"
	"sort"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/wallet"
)

// tempPicture inserts a catalogue row for one test (removed afterwards) and
// reloads the service's snapshot.
func (f *fixture) tempPicture(t *testing.T, active bool, price int64) string {
	t.Helper()
	ctx := context.Background()
	suffix := uuid.NewString()[:8]
	id := "pp_unit_" + suffix
	_, err := f.env.Pool.Exec(ctx, `INSERT INTO progression.profile_pictures (id, name, format, path, price_diamonds, sort_order, active)
		VALUES ($1, 'Unit Test', 'image', $2, $3, -1, $4)`, id, "profile_pictures/image/unit-"+suffix+".png", price, active)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = f.env.Pool.Exec(context.Background(), `DELETE FROM progression.inventory WHERE item_id = $1`, id)
		_, _ = f.env.Pool.Exec(context.Background(), `DELETE FROM progression.loadout WHERE item_id = $1`, id)
		_, _ = f.env.Pool.Exec(context.Background(), `DELETE FROM progression.profile_pictures WHERE id = $1`, id)
	})
	if err := f.svc.ReloadPictures(ctx); err != nil {
		t.Fatal(err)
	}
	return id
}

func (f *fixture) setActive(t *testing.T, id string, active bool) {
	t.Helper()
	if _, err := f.env.Pool.Exec(context.Background(), `UPDATE progression.profile_pictures SET active = $2 WHERE id = $1`, id, active); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.ReloadPictures(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func pageIDs(p PicturePage) map[string]bool {
	out := map[string]bool{}
	for _, it := range p.Items {
		out[it.ID] = true
	}
	return out
}

func TestRetiredPictureVisibleOnlyToOwners(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	owner, other := f.env.NewAccount(t), f.env.NewAccount(t)
	id := f.tempPicture(t, true, 5) // sort_order -1: first on the shelf
	if _, err := f.svc.PurchasePicture(ctx, owner, id); err != nil {
		t.Fatal(err)
	}
	f.setActive(t, id, false)

	for _, c := range []struct {
		who   uuid.UUID
		see   bool
		total int
	}{{owner, true, 161}, {other, false, 160}} {
		p, err := f.svc.StorePictures(ctx, c.who, FilterAll, false, 5, "")
		if err != nil {
			t.Fatal(err)
		}
		if pageIDs(p)[id] != c.see || p.Total < c.total {
			t.Fatalf("visible %v total %d, want %v ≥%d", pageIDs(p)[id], p.Total, c.see, c.total)
		}
		if p, _ := f.svc.StorePictures(ctx, c.who, FilterStatic, false, 50, ""); pageIDs(p)[id] != c.see {
			t.Fatalf("static filter visibility %v", !c.see)
		}
	}
	owned, _ := f.svc.StorePictures(ctx, owner, FilterOwned, false, 50, "")
	if owned.Total != 1 || owned.Items[0].ID != id {
		t.Fatalf("owned %+v", owned)
	}
	// The Shop listing (excludeOwned) never shows it, not even to its owner.
	for _, who := range []uuid.UUID{owner, other} {
		if p, _ := f.svc.StorePictures(ctx, who, FilterStatic, true, 50, ""); pageIDs(p)[id] {
			t.Fatal("retired picture in the excludeOwned listing")
		}
	}
	// Retired: not for sale, never on a bot, but its owner may apply it.
	if _, err := f.svc.PurchasePicture(ctx, other, id); !errors.Is(err, ErrPictureNotFound) {
		t.Fatalf("buy retired: %v", err)
	}
	for i := 0; i < 500; i++ {
		if p := f.svc.RandomPicture(); p == nil || p.ID == id {
			t.Fatalf("random picture %+v", p)
		}
	}
	eq, err := f.svc.ApplyPicture(ctx, owner, id)
	if err != nil || eq == nil || eq.ID != id {
		t.Fatalf("apply retired owned: %+v %v", eq, err)
	}
	if s := f.seat(t, owner); s.Picture == nil || s.Picture.ID != id {
		t.Fatalf("seat picture %+v", s.Picture)
	}
	sums, err := f.svc.Summaries(ctx, []uuid.UUID{owner, other})
	if err != nil || sums[owner].Picture == nil || sums[owner].Picture.ID != id || sums[other].Picture != nil {
		t.Fatalf("summaries %+v %v", sums, err)
	}
	if _, ok := sums[owner].Loadout["avatar"]; ok {
		t.Fatal("picture in the Collection loadout")
	}
}

func TestPurchasePictureReadsAuthoritativePrice(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	id := f.tempPicture(t, true, 7)
	// The owner raises the price; the snapshot is stale until the next
	// reload, but the purchase charges the PostgreSQL price.
	if _, err := f.env.Pool.Exec(ctx, `UPDATE progression.profile_pictures SET price_diamonds = 11 WHERE id = $1`, id); err != nil {
		t.Fatal(err)
	}
	res, err := f.svc.PurchasePicture(ctx, a, id)
	if err != nil {
		t.Fatal(err)
	}
	if res.Item.Price.Diamonds != 11 || res.Wallet.Diamonds != 50-11 {
		t.Fatalf("purchase %+v", res)
	}
	if len(f.notes.For(a, MsgWalletUpdated)) == 0 {
		t.Fatal("no wallet.updated push")
	}
	// Too expensive: nothing granted.
	dear := f.tempPicture(t, true, 1000)
	if _, err := f.svc.PurchasePicture(ctx, a, dear); !errors.Is(err, wallet.ErrInsufficientFunds) {
		t.Fatalf("insufficient: %v", err)
	}
	if ok, _ := f.svc.ownsStored(ctx, a, dear); ok {
		t.Fatal("granted without payment")
	}
}

func TestStoreCursorIsStableAcrossCatalogueChanges(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	p1, err := f.svc.StorePictures(ctx, a, FilterAll, false, 10, "")
	if err != nil || p1.NextCursor == nil {
		t.Fatalf("page 1: %v", err)
	}
	// A row added before the cursor position does not shift page 2.
	f.tempPicture(t, true, 5)
	p2, err := f.svc.StorePictures(ctx, a, FilterAll, false, 10, *p1.NextCursor)
	if err != nil {
		t.Fatal(err)
	}
	if p2.Items[0].ID == p1.Items[9].ID || pageIDs(p1)[p2.Items[0].ID] {
		t.Fatalf("page 2 repeats page 1: %s", p2.Items[0].ID)
	}
	for _, bad := range []string{"x", "MTI", "YWJjOnBwX3g"} { // "x", "12", "abc:pp_x"
		if _, err := f.svc.StorePictures(ctx, a, FilterAll, false, 10, bad); !errors.Is(err, ErrBadStoreQuery) {
			t.Fatalf("cursor %q: %v", bad, err)
		}
	}
}

// walkStore pages through a listing with limit and returns every item.
func (f *fixture) walkStore(t *testing.T, who uuid.UUID, filter string, excludeOwned bool, limit int) []ProfilePicture {
	t.Helper()
	var out []ProfilePicture
	cursor := ""
	for pages := 0; pages < 500; pages++ {
		p, err := f.svc.StorePictures(context.Background(), who, filter, excludeOwned, limit, cursor)
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

func TestStoreExcludeOwned(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	// Five cheap pictures at the front of the shelf (sort_order -1, then id).
	ids := make([]string, 5)
	for i := range ids {
		ids[i] = f.tempPicture(t, true, 1)
	}
	sort.Strings(ids)
	for _, id := range []string{ids[0], ids[2]} {
		if _, err := f.svc.PurchasePicture(ctx, a, id); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := f.svc.ApplyPicture(ctx, a, ids[0]); err != nil {
		t.Fatal(err)
	}

	full, err := f.svc.StorePictures(ctx, a, FilterAll, false, 50, "")
	if err != nil {
		t.Fatal(err)
	}
	shop, err := f.svc.StorePictures(ctx, a, FilterAll, true, 50, "")
	if err != nil {
		t.Fatal(err)
	}
	if !pageIDs(full)[ids[0]] || !pageIDs(full)[ids[2]] {
		t.Fatal("the default listing lost owned pictures")
	}
	if shop.Total != full.Total-2 || pageIDs(shop)[ids[0]] || pageIDs(shop)[ids[2]] || !pageIDs(shop)[ids[1]] {
		t.Fatalf("excludeOwned total %d (all %d), ids %v", shop.Total, full.Total, pageIDs(shop))
	}
	// The equipped id is still reported although its item is left out.
	if shop.Equipped == nil || *shop.Equipped != ids[0] {
		t.Fatalf("equipped %v", shop.Equipped)
	}

	// Small pages: every picture not owned exactly once, never an owned one.
	for _, c := range []struct {
		filter string
		limit  int
	}{{FilterAll, 2}, {FilterStatic, 3}, {FilterAnimated, 7}} {
		items := f.walkStore(t, a, c.filter, true, c.limit)
		first, err := f.svc.StorePictures(ctx, a, c.filter, true, c.limit, "")
		if err != nil {
			t.Fatal(err)
		}
		seen := map[string]bool{}
		for _, it := range items {
			if it.Owned || it.ID == ids[0] || it.ID == ids[2] || seen[it.ID] {
				t.Fatalf("%s: owned or repeated %+v", c.filter, it)
			}
			seen[it.ID] = true
		}
		if len(items) != first.Total {
			t.Fatalf("%s: walked %d, total %d", c.filter, len(items), first.Total)
		}
		if c.filter != FilterAnimated && !seen[ids[1]] {
			t.Fatalf("%s: unowned picture missing", c.filter)
		}
	}

	// A cursor taken before a purchase: the bought picture is left out of
	// the next page and nothing repeats.
	order := f.walkStore(t, a, FilterAll, true, 50)
	if order[0].ID != ids[1] || order[1].ID != ids[3] || order[2].ID != ids[4] {
		t.Fatalf("shelf order %s %s %s", order[0].ID, order[1].ID, order[2].ID)
	}
	p1, err := f.svc.StorePictures(ctx, a, FilterAll, true, 1, "")
	if err != nil || p1.Items[0].ID != ids[1] || p1.NextCursor == nil {
		t.Fatalf("page 1 %+v %v", p1, err)
	}
	if _, err := f.svc.PurchasePicture(ctx, a, ids[3]); err != nil {
		t.Fatal(err)
	}
	p2, err := f.svc.StorePictures(ctx, a, FilterAll, true, 1, *p1.NextCursor)
	if err != nil || p2.Items[0].ID != ids[4] || p2.Total != shop.Total-1 {
		t.Fatalf("page 2 after a purchase %+v %v", p2, err)
	}

	if _, err := f.svc.StorePictures(ctx, a, FilterOwned, true, 10, ""); !errors.Is(err, ErrBadStoreQuery) {
		t.Fatalf("owned + excludeOwned: %v", err)
	}
	if owned, _ := f.svc.StorePictures(ctx, a, FilterOwned, false, 10, ""); owned.Total != 3 {
		t.Fatalf("owned total %d", owned.Total)
	}
}

type fakeSigner struct{ keys []string }

func (s *fakeSigner) SignAll(keys []string) (map[string]string, time.Time) {
	s.keys = append([]string(nil), keys...)
	out := map[string]string{}
	for _, k := range keys {
		out[k] = "signed:" + k
	}
	return out, time.Unix(0, 0)
}

func TestSignAssetPathsOnlySignsCataloguePaths(t *testing.T) {
	f := newFixture(t)
	if _, _, ok := f.svc.SignAssetPaths([]string{"x"}); ok {
		t.Fatal("signing without a signer")
	}
	sig := &fakeSigner{}
	f.svc.signer = sig
	known := f.svc.pics.get().rows[0].Path
	urls, _, ok := f.svc.SignAssetPaths([]string{known, "profile_pictures/image/evil.png", known, "cards/x.png"})
	if !ok || len(urls) != 1 || len(sig.keys) != 1 || sig.keys[0] != known {
		t.Fatalf("signed %v (asked %v)", urls, sig.keys)
	}
}
