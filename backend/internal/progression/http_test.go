package progression

import (
	"bytes"
	"context"
	"net/http"
	"strings"
	"sync"
	"testing"

	"ludoroyale/internal/progression/progtest"
)

func TestHTTPProgressionAuthAndShape(t *testing.T) {
	f := newFixture(t)
	rt, srv := f.env.Router(t)
	f.svc.Register(rt)
	uid, tok := f.env.Guest(t)

	if r := progtest.Do(t, srv, "GET", "/api/v1/progression", "", nil, nil); r.Status != http.StatusUnauthorized {
		t.Fatalf("no token: %d %s", r.Status, r.Body)
	}
	req, _ := http.NewRequest("GET", srv.URL+"/api/v1/progression", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	if resp, err := srv.Client().Do(req); err != nil || resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("missing app headers must be rejected by the gate: %v %v", resp.StatusCode, err)
	}

	r := progtest.Do(t, srv, "GET", "/api/v1/progression", tok, nil, nil)
	if r.Status != http.StatusOK {
		t.Fatalf("GET /progression: %d %s", r.Status, r.Body)
	}
	var v struct {
		Level, XP, LevelXP, NextLevelXP, MaxLevel int
		Milestones                                []struct {
			Level   int
			Reached bool
			Rewards []ItemRef
		}
	}
	r.JSON(t, &v)
	if v.Level != 1 || v.NextLevelXP != 100 || v.MaxLevel != 50 || len(v.Milestones) != 11 ||
		v.Milestones[0].Level != 2 || v.Milestones[0].Rewards[0].ID != "frame_bronze" || v.Milestones[0].Reached {
		t.Fatalf("progression body %s", r.Body)
	}
	for _, k := range []string{`"levelXp"`, `"nextLevelXp"`, `"milestones"`, `"reached"`} {
		if !bytes.Contains(r.Body, []byte(k)) {
			t.Errorf("missing %s in %s", k, r.Body)
		}
	}
	if bytes.Contains(r.Body, []byte(uid.String())) {
		t.Fatal("account id leaked")
	}
}

func TestHTTPMissionsClaimAndIdempotency(t *testing.T) {
	f := newFixture(t)
	rt, srv := f.env.Router(t)
	f.svc.Register(rt)
	uid, tok := f.env.Guest(t)
	other := f.env.NewAccount(t)
	day := DayKey(testNow)

	r := progtest.Do(t, srv, "GET", "/api/v1/missions", tok, nil, nil)
	if r.Status != http.StatusOK {
		t.Fatalf("GET /missions: %d %s", r.Status, r.Body)
	}
	var mv MissionsView
	r.JSON(t, &mv)
	if mv.Daily.PeriodKey != day || mv.Daily.ResetsAtUTC != "2026-10-22T00:00:00Z" || len(mv.Daily.Missions) != 5 ||
		mv.Weekly.PeriodKey != "w2026-W43" || mv.Weekly.ResetsAtUTC != "2026-10-26T00:00:00Z" ||
		len(mv.Events) != 1 || mv.Events[0].PeriodKey != "e-autumn_cup" || mv.Events[0].EndsAtUTC != "2026-11-02T00:00:00Z" {
		t.Fatalf("missions body %s", r.Body)
	}
	if m := missionIn(mv.Weekly, "weekly_ten_matches"); m.Game != "any" || len(m.Reward.Items) != 2 || m.Reward.Diamonds != 5 {
		t.Fatalf("weekly mission %+v", m)
	}

	claim := "/api/v1/missions/" + day + "/t_win/claim"
	if r := progtest.Do(t, srv, "POST", claim, tok, nil, nil); r.Status != http.StatusUnprocessableEntity || r.ErrorCode() != "not_completed" {
		t.Fatalf("claim before completion: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "POST", "/api/v1/missions/d2020-01-01/t_win/claim", tok, nil, nil); r.Status != http.StatusNotFound {
		t.Fatalf("past period: %d %s", r.Status, r.Body)
	}
	if err := f.svc.RecordMatch(context.Background(), match("ludo", "classic", "private", testNow, human(uid, true), human(other, false))); err != nil {
		t.Fatal(err)
	}
	before := f.wallet(t, uid)
	key := map[string]string{"Idempotency-Key": "claim-key-0001"}
	first := progtest.Do(t, srv, "POST", claim, tok, nil, key)
	if first.Status != http.StatusOK {
		t.Fatalf("claim: %d %s", first.Status, first.Body)
	}
	var cr ClaimResult
	first.JSON(t, &cr)
	if cr.Wallet.Coins != before.Coins+2000 || !cr.Mission.Claimed || cr.Progression.XP != 35+30 || cr.Granted == nil {
		t.Fatalf("claim body %s", first.Body)
	}
	replay := progtest.Do(t, srv, "POST", claim, tok, nil, key)
	if replay.Status != http.StatusOK || !bytes.Equal(replay.Body, first.Body) || replay.Header.Get("Idempotent-Replayed") != "true" {
		t.Fatalf("replay: %d %s (header %q)", replay.Status, replay.Body, replay.Header.Get("Idempotent-Replayed"))
	}
	if r := progtest.Do(t, srv, "POST", claim, tok, nil, nil); r.Status != http.StatusConflict || r.ErrorCode() != "already_claimed" {
		t.Fatalf("second claim without key: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "POST", claim, tok, nil, map[string]string{"Idempotency-Key": "claim-key-0002"}); r.Status != http.StatusConflict {
		t.Fatalf("second claim with a new key: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "POST", "/api/v1/collection/items/emote_crown/purchase", tok, nil, key); r.Status != http.StatusUnprocessableEntity ||
		r.ErrorCode() != "idempotency_key_reused" {
		t.Fatalf("key reuse on another route: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "POST", claim, tok, nil, map[string]string{"Idempotency-Key": "short"}); r.Status != http.StatusBadRequest {
		t.Fatalf("invalid key: %d %s", r.Status, r.Body)
	}
	if got := f.wallet(t, uid).Coins; got != before.Coins+2000 {
		t.Fatalf("coins = %d, want %d (credited once)", got, before.Coins+2000)
	}
	if n := len(f.notes.For(uid, MsgWalletUpdated)); n != 1 {
		t.Fatalf("wallet.updated sent %d times", n)
	}
}

func TestHTTPConcurrentClaims(t *testing.T) {
	f := newFixture(t)
	rt, srv := f.env.Router(t)
	f.svc.Register(rt)
	ctx := context.Background()

	run := func(tok string, path string, headers map[string]string) []progtest.Response {
		var wg sync.WaitGroup
		out := make([]progtest.Response, 20)
		for i := range out {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				out[i] = progtest.Do(t, srv, "POST", path, tok, nil, headers)
			}(i)
		}
		wg.Wait()
		return out
	}

	// Without a key: exactly one 200, the rest 409 already_claimed.
	u1, tok1 := f.env.Guest(t)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(u1, true), human(f.env.NewAccount(t), false))); err != nil {
		t.Fatal(err)
	}
	w1 := f.wallet(t, u1)
	ok, conflict := 0, 0
	for _, r := range run(tok1, "/api/v1/missions/"+DayKey(testNow)+"/t_win/claim", nil) {
		switch {
		case r.Status == http.StatusOK:
			ok++
		case r.Status == http.StatusConflict && r.ErrorCode() == "already_claimed":
			conflict++
		default:
			t.Errorf("unexpected %d %s", r.Status, r.Body)
		}
	}
	if ok != 1 || conflict != 19 || f.wallet(t, u1).Coins != w1.Coins+2000 {
		t.Fatalf("ok=%d conflict=%d coins=%d", ok, conflict, f.wallet(t, u1).Coins)
	}

	// Same Idempotency-Key concurrently: everyone gets the original 200.
	u2, tok2 := f.env.Guest(t)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(u2, true), human(f.env.NewAccount(t), false))); err != nil {
		t.Fatal(err)
	}
	w2 := f.wallet(t, u2)
	res := run(tok2, "/api/v1/missions/"+DayKey(testNow)+"/t_ludo/claim", map[string]string{"Idempotency-Key": "same-key-123"})
	for _, r := range res {
		if r.Status != http.StatusOK || !bytes.Equal(r.Body, res[0].Body) {
			t.Fatalf("same-key response %d %s vs %s", r.Status, r.Body, res[0].Body)
		}
	}
	if f.wallet(t, u2).Coins != w2.Coins+500 {
		t.Fatalf("coins = %d, want %d", f.wallet(t, u2).Coins, w2.Coins+500)
	}
}

func TestHTTPCollectionPurchaseAndLoadout(t *testing.T) {
	f := newFixture(t)
	rt, srv := f.env.Router(t)
	f.svc.Register(rt)
	uid, tok := f.env.Guest(t)

	r := progtest.Do(t, srv, "GET", "/api/v1/collection", tok, nil, nil)
	var col CollectionView
	r.JSON(t, &col)
	if r.Status != http.StatusOK || len(col.Items) != 37 || col.Loadout["ludo_board"] != "ludo_board_classic" {
		t.Fatalf("collection %d %s", r.Status, r.Body)
	}
	if !strings.Contains(string(r.Body), `"acquisition":{"type":"purchase","price":{"diamonds":40},"label":"40 diamonds"}`) ||
		!strings.Contains(string(r.Body), `"acquisition":{"type":"level","level":5,"label":"Reach level 5"}`) {
		t.Fatalf("acquisition shape: %s", r.Body)
	}

	put := func(body any) progtest.Response {
		return progtest.Do(t, srv, "PUT", "/api/v1/collection/loadout", tok, body, nil)
	}
	if r := put(map[string]any{"slot": "dice", "itemId": "dice_golden"}); r.Status != http.StatusUnprocessableEntity || r.ErrorCode() != "item_locked" {
		t.Fatalf("locked equip: %d %s", r.Status, r.Body)
	}
	if r := put(map[string]any{"slot": "token", "itemId": "dice_classic"}); r.Status != http.StatusBadRequest {
		t.Fatalf("wrong slot: %d %s", r.Status, r.Body)
	}
	if r := put(map[string]any{"slot": "dice", "itemId": "dice_classic", "extra": 1}); r.Status != http.StatusBadRequest {
		t.Fatalf("unknown field: %d %s", r.Status, r.Body)
	}

	buy := func(item string, headers map[string]string) progtest.Response {
		return progtest.Do(t, srv, "POST", "/api/v1/collection/items/"+item+"/purchase", tok, nil, headers)
	}
	key := map[string]string{"Idempotency-Key": "buy-dice-golden-1"}
	first := buy("dice_golden", key)
	var pr PurchaseResult
	first.JSON(t, &pr)
	if first.Status != http.StatusOK || pr.Item.ID != "dice_golden" || !pr.Item.Owned || pr.Wallet.Diamonds != progtest.WelcomeDiamonds-40 {
		t.Fatalf("purchase %d %s", first.Status, first.Body)
	}
	if r := buy("dice_golden", key); r.Status != http.StatusOK || !bytes.Equal(r.Body, first.Body) {
		t.Fatalf("purchase replay %d %s", r.Status, r.Body)
	}
	if r := buy("dice_golden", nil); r.Status != http.StatusConflict || r.ErrorCode() != "already_owned" {
		t.Fatalf("already owned: %d %s", r.Status, r.Body)
	}
	if r := buy("frame_royal", nil); r.Status != http.StatusUnprocessableEntity || r.ErrorCode() != "insufficient_funds" {
		t.Fatalf("insufficient: %d %s", r.Status, r.Body)
	}
	if r := buy("dice_neon", nil); r.Status != http.StatusUnprocessableEntity || r.ErrorCode() != "item_locked" {
		t.Fatalf("level item: %d %s", r.Status, r.Body)
	}
	if r := buy("dice_nope", nil); r.Status != http.StatusNotFound {
		t.Fatalf("unknown item: %d %s", r.Status, r.Body)
	}
	if w := f.wallet(t, uid); w.Diamonds != progtest.WelcomeDiamonds-40 || w.Coins != progtest.WelcomeCoins {
		t.Fatalf("wallet %+v", w)
	}

	r = put(map[string]any{"slot": "dice", "itemId": "dice_golden"})
	var lo struct{ Loadout map[string]string }
	r.JSON(t, &lo)
	if r.Status != http.StatusOK || lo.Loadout["dice"] != "dice_golden" || len(lo.Loadout) != 8 {
		t.Fatalf("equip %d %s", r.Status, r.Body)
	}
	r = put(map[string]any{"slot": "dice", "itemId": nil})
	r.JSON(t, &lo)
	if r.Status != http.StatusOK || lo.Loadout["dice"] != "dice_classic" {
		t.Fatalf("unequip %d %s", r.Status, r.Body)
	}
}
