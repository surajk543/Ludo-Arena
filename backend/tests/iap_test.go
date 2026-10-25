package tests

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/iap/iaptest"
)

// Coin packs (docs/in-app-purchases.md) against fake stores: Google Play's
// Android Publisher API and StoreKit 2 signing with a test certificate chain.

// appPackage is the Android (Google Play) package, appBundle the iOS bundle id.
const (
	appPackage = "com.sungamestudio.ludoarena"
	appBundle  = "com.ludoarena.app"
)

var iosHeaders = []string{"X-App-Platform", "ios"}

type coinPacks struct {
	Packs []struct {
		ID, ProductID, Label string
		Coins, Diamonds      int64
		FallbackPrice        struct {
			Currency string
			Amount   int64
		}
		Badge *string
	}
	PurchasesAvailable bool
	AccountToken       string
}

func (e *env) coinPacks(token string, headers ...string) coinPacks {
	e.t.Helper()
	r := e.do("GET", "/api/v1/store/coin-packs", token, nil, headers...)
	if r.Status != 200 {
		e.t.Fatalf("coin packs: %d %s", r.Status, r.Raw)
	}
	var out coinPacks
	if err := json.Unmarshal(r.Raw, &out); err != nil {
		e.t.Fatal(err)
	}
	return out
}

type purchaseResp struct {
	Wallet   struct{ Coins, Diamonds int64 }
	Granted  struct{ Coins, Diamonds int64 }
	Pack     struct{ ID, ProductID string }
	Replayed bool
}

func decodePurchase(t *testing.T, r resp) purchaseResp {
	t.Helper()
	if r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}
	var out purchaseResp
	if err := json.Unmarshal(r.Raw, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func (e *env) buyAndroid(token, productID, purchaseToken string) resp {
	return e.do("POST", "/api/v1/store/purchases", token,
		map[string]any{"platform": "android", "productId": productID, "purchaseToken": purchaseToken})
}

func (e *env) buyIOS(token, productID, txID, signed string) resp {
	body := map[string]any{"platform": "ios", "productId": productID}
	if txID != "" {
		body["transactionId"] = txID
	}
	if signed != "" {
		body["signedTransaction"] = signed
	}
	return e.do("POST", "/api/v1/store/purchases", token, body, iosHeaders...)
}

// walletPushes returns the wallet.updated payloads with reason.
func walletPushes(c *client, reason string) []map[string]any {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []map[string]any
	for _, m := range c.all {
		if m.T != "wallet.updated" {
			continue
		}
		var p map[string]any
		if json.Unmarshal(m.P, &p) == nil && p["reason"] == reason {
			out = append(out, p)
		}
	}
	return out
}

func purchaseRows(t *testing.T, e *env, userID string) (n int, refunded int) {
	t.Helper()
	if err := e.app.PG.QueryRow(context.Background(), `SELECT count(*), count(*) FILTER (WHERE status = 'refunded')
		FROM progression.purchases WHERE user_id = $1`, userID).Scan(&n, &refunded); err != nil {
		t.Fatal(err)
	}
	return n, refunded
}

func uniq(name string) string { return fmt.Sprintf("%s-%s-%s", name, runID, uuid.NewString()[:8]) }

// appleTxID is a fresh numeric App Store transaction id.
func appleTxID() string {
	return fmt.Sprint(2_000_000_000_000_000 + time.Now().UnixNano()%1_000_000_000_000)
}

// Without store configuration the Shop still lists the packs and every
// purchase answers 503 iap_unavailable.
func TestCoinPacksUnconfigured(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()
	for _, hdr := range [][]string{nil, iosHeaders} {
		p := e.coinPacks(a.Token, hdr...)
		if len(p.Packs) != 4 || p.PurchasesAvailable {
			t.Fatalf("packs = %d, available = %t", len(p.Packs), p.PurchasesAvailable)
		}
		if _, err := uuid.Parse(p.AccountToken); err != nil || p.AccountToken == a.UserID {
			t.Fatalf("account token %q", p.AccountToken)
		}
	}
	p := e.coinPacks(a.Token)
	first, last := p.Packs[0], p.Packs[3]
	if first.ID != "coins_starter" || first.ProductID != "coins_starter" || first.Coins != 5_000_000 ||
		first.Diamonds != 5 || first.FallbackPrice.Amount != 199 || first.FallbackPrice.Currency != "INR" ||
		first.Badge != nil || last.ID != "coins_best_value" || last.Badge == nil || *last.Badge != "best_value" {
		t.Fatalf("packs %+v", p.Packs)
	}
	if r := e.buyAndroid(a.Token, "coins_starter", uniq("tok")); r.Status != 503 || errCode(r) != "iap_unavailable" {
		t.Fatalf("android: %d %s", r.Status, r.Raw)
	}
	if r := e.buyIOS(a.Token, "coins_starter", "", "eyJhbGciOiJFUzI1NiJ9.e30.sig"); r.Status != 503 || errCode(r) != "iap_unavailable" {
		t.Fatalf("ios: %d %s", r.Status, r.Raw)
	}
	if r := e.do("GET", "/api/v1/store/coin-packs", "", nil); r.Status != 401 {
		t.Fatalf("anonymous: %d", r.Status)
	}
	if r := e.do("POST", "/api/v1/iap/apple/notifications", "", map[string]any{"signedPayload": "x.y.z"}); r.Status != 503 {
		t.Fatalf("apple notifications without apple: %d %s", r.Status, r.Raw)
	}
}

func TestGooglePlayPurchase(t *testing.T) {
	g := iaptest.NewGoogle(t, appPackage)
	e := newEnv(t, envOpts{google: g, proxyHops: 1})
	a := e.guestFromFreshIP()
	ca := e.mustDial("A", a)
	packs := e.coinPacks(a.Token)
	if !packs.PurchasesAvailable {
		t.Fatal("google play not available")
	}
	if ios := e.coinPacks(a.Token, iosHeaders...); ios.PurchasesAvailable {
		t.Fatal("app store available without configuration")
	}
	coins0, gems0 := e.coins(a.Token), e.diamonds(a.Token)

	// A verified purchase credits the pack once and pushes wallet.updated.
	tok := uniq("tok-a")
	g.Add("coins_starter", tok, iaptest.GooglePurchase{AccountToken: packs.AccountToken, OrderID: "GPA.3301-" + runID})
	res := decodePurchase(t, e.buyAndroid(a.Token, "coins_starter", tok))
	if res.Replayed || res.Granted.Coins != 5_000_000 || res.Granted.Diamonds != 5 || res.Pack.ID != "coins_starter" ||
		res.Wallet.Coins != coins0+5_000_000 || res.Wallet.Diamonds != gems0+5 {
		t.Fatalf("first grant %+v (before %d/%d)", res, coins0, gems0)
	}
	waitFor(t, 5*time.Second, "wallet.updated purchase", func() bool { return len(walletPushes(ca, "purchase")) == 1 })
	push := walletPushes(ca, "purchase")[0]
	if d := push["delta"].(map[string]any); d["coins"].(float64) != 5_000_000 || d["diamonds"].(float64) != 5 {
		t.Fatalf("push %v", push)
	}
	if g.Consumes("coins_starter", tok) != 1 {
		t.Fatal("not consumed server-side")
	}
	var stored, order string
	if err := e.app.PG.QueryRow(context.Background(), `SELECT transaction_id, order_id FROM progression.purchases
		WHERE user_id = $1`, a.UserID).Scan(&stored, &order); err != nil {
		t.Fatal(err)
	}
	if stored == tok || len(stored) != 64 || order != "GPA.3301-"+runID {
		t.Fatalf("stored transaction %q order %q: the raw token must not be stored", stored, order)
	}

	// Replays return the original grant without a store call or a credit.
	gets := g.Gets()
	for range 2 {
		again := decodePurchase(t, e.buyAndroid(a.Token, "coins_starter", tok))
		if !again.Replayed || again.Granted != res.Granted || again.Wallet != res.Wallet {
			t.Fatalf("replay %+v", again)
		}
	}
	if g.Gets() != gets {
		t.Fatal("replay called the store")
	}
	time.Sleep(100 * time.Millisecond)
	if n := len(walletPushes(ca, "purchase")); n != 1 {
		t.Fatalf("%d purchase pushes, want 1", n)
	}

	// Concurrent duplicate submissions of a new purchase grant once.
	tok2 := uniq("tok-a2")
	g.Add("coins_popular", tok2, iaptest.GooglePurchase{AccountToken: packs.AccountToken, OrderID: "GPA.3302-" + runID})
	var wg sync.WaitGroup
	results := make([]resp, 8)
	for i := range results {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i] = e.buyAndroid(a.Token, "coins_popular", tok2)
		}(i)
	}
	wg.Wait()
	fresh := 0
	for _, r := range results {
		if decodePurchase(t, r).Replayed == false {
			fresh++
		}
	}
	if fresh != 1 {
		t.Fatalf("%d concurrent submissions granted, want 1", fresh)
	}
	if c := e.coins(a.Token); c != coins0+5_000_000+8_000_000 {
		t.Fatalf("coins %d after concurrent duplicates, want %d", c, coins0+13_000_000)
	}
	if n, _ := purchaseRows(t, e, a.UserID); n != 2 {
		t.Fatalf("%d purchase rows, want 2", n)
	}

	// Refused purchases change nothing.
	b := e.guestFromFreshIP()
	bPacks := e.coinPacks(b.Token)
	canceled, pending, foreign := uniq("tok-cancel"), uniq("tok-pending"), uniq("tok-foreign")
	g.Add("coins_starter", canceled, iaptest.GooglePurchase{State: 1, AccountToken: bPacks.AccountToken})
	g.Add("coins_starter", pending, iaptest.GooglePurchase{State: 2, AccountToken: bPacks.AccountToken})
	g.Add("coins_starter", foreign, iaptest.GooglePurchase{AccountToken: packs.AccountToken}) // bought by A
	noAcct := uniq("tok-noacct")
	g.Add("coins_starter", noAcct, iaptest.GooglePurchase{})
	bCoins := e.coins(b.Token)
	cases := []struct {
		name, product, token string
		status               int
		code                 string
	}{
		{"another account's granted purchase", "coins_starter", tok, 422, "purchase_invalid"},
		{"purchase bound to another account", "coins_starter", foreign, 422, "purchase_invalid"},
		{"purchase without account binding", "coins_starter", noAcct, 422, "purchase_invalid"},
		{"not purchased (canceled)", "coins_starter", canceled, 422, "purchase_invalid"},
		{"unknown token (another package or never bought)", "coins_starter", uniq("tok-unknown"), 422, "purchase_invalid"},
		{"wrong product", "coins_popular", canceled, 422, "purchase_invalid"},
		{"product not sold", "coins_mega", canceled, 422, "purchase_invalid"},
		{"pending payment", "coins_starter", pending, 409, "purchase_pending"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := e.buyAndroid(b.Token, tc.product, tc.token)
			if r.Status != tc.status || errCode(r) != tc.code {
				t.Fatalf("%d %s, want %d %s", r.Status, r.Raw, tc.status, tc.code)
			}
		})
	}
	if e.coins(b.Token) != bCoins {
		t.Fatal("a refused purchase credited coins")
	}
	for _, body := range []map[string]any{
		{"platform": "android", "productId": "coins_starter"},
		{"platform": "web", "productId": "coins_starter", "purchaseToken": uniq("t")},
		{"platform": "android", "productId": "coins_starter", "purchaseToken": uniq("t"), "coins": 999},
		{"platform": "android", "productId": "coins_starter", "purchaseToken": "short"},
		{"platform": "android", "productId": "Coins Starter!", "purchaseToken": uniq("t")},
	} {
		if r := e.do("POST", "/api/v1/store/purchases", b.Token, body); r.Status != 400 || errCode(r) != "bad_request" {
			t.Fatalf("%v: %d %s", body, r.Status, r.Raw)
		}
	}

	// The pending payment completes: now it is granted.
	g.SetState("coins_starter", pending, 0)
	if got := decodePurchase(t, e.buyAndroid(b.Token, "coins_starter", pending)); got.Replayed || got.Granted.Coins != 5_000_000 {
		t.Fatalf("completed pending purchase %+v", got)
	}
	// A store outage is 502 store_unreachable (the app retries); nothing is
	// recorded, and the retry is granted.
	outage := uniq("tok-outage")
	g.Add("coins_starter", outage, iaptest.GooglePurchase{AccountToken: bPacks.AccountToken})
	g.FailGets(1)
	if r := e.buyAndroid(b.Token, "coins_starter", outage); r.Status != 502 || errCode(r) != "store_unreachable" {
		t.Fatalf("outage: %d %s", r.Status, r.Raw)
	}
	if got := decodePurchase(t, e.buyAndroid(b.Token, "coins_starter", outage)); got.Replayed {
		t.Fatal("retry after an outage replayed")
	}
}

// Google voided purchases take the grant back (clamped at zero) exactly once.
func TestGooglePlayRefunds(t *testing.T) {
	g := iaptest.NewGoogle(t, appPackage)
	e := newEnv(t, envOpts{google: g, proxyHops: 1, voidedPoll: "1s"})
	a, b := e.guestFromFreshIP(), e.guestFromFreshIP()
	ca := e.mustDial("A", a)
	aTok, bTok := uniq("tok-a"), uniq("tok-b")
	g.Add("coins_great_value", aTok, iaptest.GooglePurchase{AccountToken: e.coinPacks(a.Token).AccountToken})
	g.Add("coins_best_value", bTok, iaptest.GooglePurchase{AccountToken: e.coinPacks(b.Token).AccountToken})
	before := e.coins(a.Token)
	granted := decodePurchase(t, e.buyAndroid(a.Token, "coins_great_value", aTok))
	decodePurchase(t, e.buyAndroid(b.Token, "coins_best_value", bTok))
	// B spent most of it: the refund can only take back what is left.
	if _, err := e.app.PG.Exec(context.Background(),
		`UPDATE wallet.wallets SET coins = 1000, diamonds = 3 WHERE user_id = $1`, b.UserID); err != nil {
		t.Fatal(err)
	}

	g.Void(aTok, "GPA.voided-a")
	g.Void(bTok, "GPA.voided-b")
	g.Void(uniq("tok-not-ours"), "GPA.other")
	waitFor(t, 10*time.Second, "refunds applied", func() bool {
		_, ra := purchaseRows(t, e, a.UserID)
		_, rb := purchaseRows(t, e, b.UserID)
		return ra == 1 && rb == 1
	})
	if c, d := e.coins(a.Token), e.diamonds(a.Token); c != before || d != granted.Wallet.Diamonds-100 {
		t.Fatalf("A after refund: %d coins %d diamonds, want %d and %d", c, d, before, granted.Wallet.Diamonds-100)
	}
	if c, d := e.coins(b.Token), e.diamonds(b.Token); c != 0 || d != 0 {
		t.Fatalf("B after refund: %d coins %d diamonds, want 0 and 0 (clamped)", c, d)
	}
	waitFor(t, 5*time.Second, "wallet.updated refund", func() bool { return len(walletPushes(ca, "refund")) == 1 })
	if d := walletPushes(ca, "refund")[0]["delta"].(map[string]any); d["coins"].(float64) != -15_000_000 || d["diamonds"].(float64) != -100 {
		t.Fatalf("refund push delta %v", d)
	}
	// Later polls (every second) see the same voided purchases: no second take.
	time.Sleep(2500 * time.Millisecond)
	if c := e.coins(a.Token); c != before {
		t.Fatalf("A coins %d after more polls, want %d", c, before)
	}
	if n := len(walletPushes(ca, "refund")); n != 1 {
		t.Fatalf("%d refund pushes, want 1", n)
	}
	// A replay of the refunded purchase grants nothing.
	if r := decodePurchase(t, e.buyAndroid(a.Token, "coins_great_value", aTok)); !r.Replayed || e.coins(a.Token) != before {
		t.Fatalf("replay after refund %+v", r)
	}
}

func TestAppStorePurchase(t *testing.T) {
	apple := iaptest.NewApple(t, appBundle)
	e := newEnv(t, envOpts{apple: apple, proxyHops: 1})
	a, b := e.guestFromFreshIP(), e.guestFromFreshIP()
	ca := e.mustDial("A", a)
	packs := e.coinPacks(a.Token, iosHeaders...)
	if !packs.PurchasesAvailable {
		t.Fatal("app store not available")
	}
	if android := e.coinPacks(a.Token); android.PurchasesAvailable {
		t.Fatal("google play available without configuration")
	}
	coins0 := e.coins(a.Token)

	id := appleTxID()
	tx := apple.Transaction(id, "coins_popular", strings.ToUpper(packs.AccountToken)) // UUID case is irrelevant
	signed := apple.Sign(t, tx)
	res := decodePurchase(t, e.buyIOS(a.Token, "coins_popular", id, signed))
	if res.Replayed || res.Granted.Coins != 8_000_000 || res.Granted.Diamonds != 8 || res.Wallet.Coins != coins0+8_000_000 {
		t.Fatalf("grant %+v", res)
	}
	waitFor(t, 5*time.Second, "wallet.updated purchase", func() bool { return len(walletPushes(ca, "purchase")) == 1 })
	// Replays: with and without the transaction id.
	for _, r := range []resp{e.buyIOS(a.Token, "coins_popular", id, signed), e.buyIOS(a.Token, "coins_popular", "", signed)} {
		if got := decodePurchase(t, r); !got.Replayed || got.Wallet.Coins != coins0+8_000_000 {
			t.Fatalf("replay %+v", got)
		}
	}
	// B cannot redeem A's transaction.
	if r := e.buyIOS(b.Token, "coins_popular", id, signed); r.Status != 422 || errCode(r) != "purchase_invalid" {
		t.Fatalf("B replays A: %d %s", r.Status, r.Raw)
	}

	bTok := e.coinPacks(b.Token, iosHeaders...).AccountToken
	bad := func(mut func(*iaptest.Transaction)) (string, string) {
		id := appleTxID()
		tx := apple.Transaction(id, "coins_starter", bTok)
		mut(&tx)
		return id, apple.Sign(t, tx)
	}
	type tcase struct {
		name, product, id, signed string
		status                    int
		code                      string
	}
	var cases []tcase
	add := func(name string, mut func(*iaptest.Transaction)) {
		id, s := bad(mut)
		cases = append(cases, tcase{name, "coins_starter", id, s, 422, "purchase_invalid"})
	}
	add("wrong bundle", func(tx *iaptest.Transaction) { tx.BundleID = "com.other.app" })
	add("wrong product", func(tx *iaptest.Transaction) { tx.ProductID = "coins_best_value" })
	add("not consumable", func(tx *iaptest.Transaction) { tx.Type = "Non-Consumable" })
	add("revoked", func(tx *iaptest.Transaction) { tx.RevocationDate = time.Now().UnixMilli() })
	add("another account", func(tx *iaptest.Transaction) { tx.AppAccountToken = packs.AccountToken })
	add("no account binding", func(tx *iaptest.Transaction) { tx.AppAccountToken = "" })
	add("unknown environment", func(tx *iaptest.Transaction) { tx.Environment = "Xcode" })
	otherID := appleTxID()
	cases = append(cases,
		tcase{"other certificate chain", "coins_starter", otherID,
			iaptest.NewApple(t, appBundle).Sign(t, apple.Transaction(otherID, "coins_starter", bTok)), 422, "purchase_invalid"},
		tcase{"transaction id mismatch", "coins_starter", appleTxID(), apple.Sign(t, apple.Transaction(appleTxID()+"1", "coins_starter", bTok)),
			422, "purchase_invalid"},
		tcase{"product not sold", "coins_mega", "", apple.Sign(t, apple.Transaction(appleTxID(), "coins_mega", bTok)), 422, "purchase_invalid"},
		tcase{"no signed transaction (no server api)", "coins_starter", appleTxID(), "", 400, "bad_request"},
		tcase{"unsigned jws", "coins_starter", "", "eyJhbGciOiJub25lIn0.eyJ0cmFuc2FjdGlvbklkIjoiMSJ9.", 422, "purchase_invalid"},
		tcase{"too short", "coins_starter", "", "a.b.c", 400, "bad_request"},
	)
	bCoins := e.coins(b.Token)
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := e.buyIOS(b.Token, tc.product, tc.id, tc.signed)
			if r.Status != tc.status || errCode(r) != tc.code {
				t.Fatalf("%d %s, want %d %s", r.Status, r.Raw, tc.status, tc.code)
			}
		})
	}
	if e.coins(b.Token) != bCoins {
		t.Fatal("a refused purchase credited coins")
	}

	// App Store Server Notifications: REFUND takes the grant back once.
	notify := func(payload string) resp {
		return e.do("POST", "/api/v1/iap/apple/notifications", "", map[string]any{"signedPayload": payload})
	}
	if r := notify(apple.Notification(t, "TEST", "Sandbox", "")); r.Status != 200 || r.Body["result"] != "ignored" {
		t.Fatalf("TEST: %d %s", r.Status, r.Raw)
	}
	refund := apple.Notification(t, "REFUND", "Sandbox", signed)
	if r := notify(refund); r.Status != 200 || r.Body["result"] != "refunded" {
		t.Fatalf("REFUND: %d %s", r.Status, r.Raw)
	}
	if c := e.coins(a.Token); c != coins0 {
		t.Fatalf("coins %d after refund, want %d", c, coins0)
	}
	if r := notify(refund); r.Status != 200 || r.Body["result"] != "already_refunded" {
		t.Fatalf("REFUND again: %d %s", r.Status, r.Raw)
	}
	if c := e.coins(a.Token); c != coins0 {
		t.Fatalf("coins %d after a repeated refund, want %d", c, coins0)
	}
	waitFor(t, 5*time.Second, "wallet.updated refund", func() bool { return len(walletPushes(ca, "refund")) == 1 })
	unknown := apple.Notification(t, "REVOKE", "Sandbox", apple.Sign(t, apple.Transaction(appleTxID(), "coins_starter", "")))
	if r := notify(unknown); r.Status != 200 || r.Body["result"] != "unknown" {
		t.Fatalf("unknown transaction: %d %s", r.Status, r.Raw)
	}
	forged := iaptest.NewApple(t, appBundle).Notification(t, "REFUND", "Sandbox", signed)
	if r := notify(forged); r.Status != 400 {
		t.Fatalf("forged notification: %d %s", r.Status, r.Raw)
	}
}

// With the App Store Server API configured, the transaction is re-read from
// Apple: a revocation the app's copy does not show is refused, an id alone
// suffices, and an Apple outage falls back to the verified signed copy.
func TestAppStoreServerAPI(t *testing.T) {
	apple := iaptest.NewApple(t, appBundle)
	apple.StartAPI(t)
	e := newEnv(t, envOpts{apple: apple, proxyHops: 1})
	a := e.guestFromFreshIP()
	tok := e.coinPacks(a.Token, iosHeaders...).AccountToken

	// Only the id.
	id := appleTxID()
	apple.SignTransaction(t, apple.Transaction(id, "coins_starter", tok))
	lookups := apple.Lookups()
	if got := decodePurchase(t, e.buyIOS(a.Token, "coins_starter", id, "")); got.Replayed || got.Granted.Coins != 5_000_000 {
		t.Fatalf("id-only grant %+v", got)
	}
	if apple.Lookups() <= lookups {
		t.Fatal("the App Store Server API was not called")
	}

	// The app holds an older copy; Apple's answer shows the refund.
	id2 := appleTxID()
	appCopy := apple.Sign(t, apple.Transaction(id2, "coins_starter", tok))
	revoked := apple.Transaction(id2, "coins_starter", tok)
	revoked.RevocationDate = time.Now().UnixMilli()
	apple.SignTransaction(t, revoked)
	if r := e.buyIOS(a.Token, "coins_starter", id2, appCopy); r.Status != 422 || errCode(r) != "purchase_invalid" {
		t.Fatalf("revoked at Apple: %d %s", r.Status, r.Raw)
	}
	// Unknown to Apple.
	id3 := appleTxID()
	if r := e.buyIOS(a.Token, "coins_starter", id3, ""); r.Status != 422 {
		t.Fatalf("unknown id: %d %s", r.Status, r.Raw)
	}
	// Apple down: the verified signed copy is enough.
	id4 := appleTxID()
	s4 := apple.SignTransaction(t, apple.Transaction(id4, "coins_starter", tok))
	apple.FailLookups(1)
	if got := decodePurchase(t, e.buyIOS(a.Token, "coins_starter", id4, s4)); got.Replayed {
		t.Fatal("fallback grant replayed")
	}
}

// Deleting the account deletes its purchase records; a later refund of
// such a purchase finds nothing to take back.
func TestDeleteAccountRemovesPurchases(t *testing.T) {
	apple := iaptest.NewApple(t, appBundle)
	e := newEnv(t, envOpts{apple: apple, proxyHops: 1})
	a := e.guestFromFreshIP()
	id := appleTxID()
	signed := apple.Sign(t, apple.Transaction(id, "coins_starter", e.coinPacks(a.Token, iosHeaders...).AccountToken))
	decodePurchase(t, e.buyIOS(a.Token, "coins_starter", id, signed))
	if n, _ := purchaseRows(t, e, a.UserID); n != 1 {
		t.Fatalf("%d rows before deletion", n)
	}
	if r := e.do("DELETE", "/api/v1/account", a.Token, map[string]any{"confirm": "DELETE"}); r.Status != 204 {
		t.Fatalf("delete: %d %s", r.Status, r.Raw)
	}
	if n, _ := purchaseRows(t, e, a.UserID); n != 0 {
		t.Fatalf("%d purchase rows after deletion", n)
	}
	r := e.do("POST", "/api/v1/iap/apple/notifications", "", map[string]any{
		"signedPayload": apple.Notification(t, "REFUND", "Sandbox", signed)})
	if r.Status != 200 || r.Body["result"] != "unknown" {
		t.Fatalf("refund after deletion: %d %s", r.Status, r.Raw)
	}
}

// Purchases credit and refunds debit people's wallets only: a bot wallet
// (wallet.wallets.is_bot, migration 012) is never touched.
func TestPurchasesNeverTouchBotWallets(t *testing.T) {
	apple := iaptest.NewApple(t, appBundle)
	e := newEnv(t, envOpts{apple: apple, proxyHops: 1})
	ctx := context.Background()
	a := e.guestFromFreshIP()
	tok := e.coinPacks(a.Token, iosHeaders...).AccountToken
	// A grant to a row flagged as a bot wallet is refused and records nothing.
	if _, err := e.app.PG.Exec(ctx, `UPDATE wallet.wallets SET is_bot = TRUE WHERE user_id = $1`, a.UserID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { // the test database persists between runs
		_, _ = e.app.PG.Exec(context.Background(), `DELETE FROM progression.purchases WHERE user_id = $1`, a.UserID)
		_, _ = e.app.PG.Exec(context.Background(), `UPDATE wallet.wallets SET is_bot = FALSE WHERE user_id = $1`, a.UserID)
	})
	id := appleTxID()
	signed := apple.Sign(t, apple.Transaction(id, "coins_starter", tok))
	if r := e.buyIOS(a.Token, "coins_starter", id, signed); r.Status != 401 {
		t.Fatalf("grant to a bot wallet: %d %s", r.Status, r.Raw)
	}
	var coins int64
	if err := e.app.PG.QueryRow(ctx, `SELECT coins FROM wallet.wallets WHERE user_id = $1`, a.UserID).Scan(&coins); err != nil {
		t.Fatal(err)
	}
	if n, _ := purchaseRows(t, e, a.UserID); n != 0 || coins != a.Coins {
		t.Fatalf("bot wallet credited: %d rows, %d coins (was %d)", n, coins, a.Coins)
	}
	// A purchase row pointing at a bot wallet is never debited by a refund.
	if _, err := e.app.PG.Exec(ctx, `INSERT INTO progression.purchases (user_id, store, product_id, transaction_id, coins, diamonds)
		VALUES ($1, 'app_store', 'coins_starter', $2, 5000000, 5)`, a.UserID, id); err != nil {
		t.Fatal(err)
	}
	r := e.do("POST", "/api/v1/iap/apple/notifications", "", map[string]any{
		"signedPayload": apple.Notification(t, "REFUND", "Sandbox", signed)})
	if r.Status != 200 || r.Body["result"] != "unknown" {
		t.Fatalf("refund against a bot wallet: %d %s", r.Status, r.Raw)
	}
	if err := e.app.PG.QueryRow(ctx, `SELECT coins FROM wallet.wallets WHERE user_id = $1`, a.UserID).Scan(&coins); err != nil {
		t.Fatal(err)
	}
	if coins != a.Coins {
		t.Fatalf("bot wallet debited: %d coins, want %d", coins, a.Coins)
	}
}
