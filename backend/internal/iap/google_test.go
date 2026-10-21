package iap

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"ludoroyale/internal/iap/iaptest"
)

func newTestGoogle(t *testing.T, fake *iaptest.Google, pkg string) *GooglePlay {
	t.Helper()
	g, err := NewGooglePlay(GoogleConfig{ServiceAccountFile: fake.KeyFile, PackageName: pkg, APIURL: fake.URL})
	if err != nil {
		t.Fatal(err)
	}
	return g
}

func TestGoogleProduct(t *testing.T) {
	ctx := context.Background()
	fake := iaptest.NewGoogle(t, testBundle)
	fake.Add("coins_starter", "tok-purchased", iaptest.GooglePurchase{State: GooglePurchased,
		AccountToken: "acct", OrderID: "GPA.3300-0000-0000-00001"})
	fake.Add("coins_starter", "tok-pending", iaptest.GooglePurchase{State: GooglePending, AccountToken: "acct"})
	fake.Add("coins_starter", "tok-sparse", iaptest.GooglePurchase{AccountToken: "acct", OmitZero: true})
	g := newTestGoogle(t, fake, testBundle)

	p, err := g.Product(ctx, "coins_starter", "tok-purchased")
	if err != nil {
		t.Fatal(err)
	}
	if *p.PurchaseState != GooglePurchased || p.OrderID != "GPA.3300-0000-0000-00001" ||
		p.ObfuscatedExternalAccountID != "acct" || p.ConsumptionState != 0 {
		t.Fatalf("product %+v", p)
	}
	if p, err := g.Product(ctx, "coins_starter", "tok-pending"); err != nil || *p.PurchaseState != GooglePending {
		t.Fatalf("pending: %+v %v", p, err)
	}
	if p, err := g.Product(ctx, "coins_starter", "tok-sparse"); err != nil || *p.PurchaseState != GooglePurchased {
		t.Fatalf("purchase without zero-valued fields: %+v %v", p, err)
	}
	cases := []struct {
		name, product, token string
		g                    *GooglePlay
		want                 error
	}{
		{"unknown token", "coins_starter", "tok-unknown", g, ErrStoreRejected},
		{"other product", "coins_popular", "tok-purchased", g, ErrStoreRejected},
		{"other package", "coins_starter", "tok-purchased", newTestGoogle(t, fake, "com.other.app"), ErrStoreRejected},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := tc.g.Product(ctx, tc.product, tc.token); !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
		})
	}
	fake.FailGets(1)
	if _, err := g.Product(ctx, "coins_starter", "tok-purchased"); !errors.Is(err, ErrStoreUnreachable) {
		t.Fatalf("503: %v", err)
	}
	if err := g.Consume(ctx, "coins_starter", "tok-purchased"); err != nil {
		t.Fatal(err)
	}
	if n := fake.Consumes("coins_starter", "tok-purchased"); n != 1 {
		t.Fatalf("consumes = %d", n)
	}
	if p, _ := g.Product(ctx, "coins_starter", "tok-purchased"); p.ConsumptionState != 1 {
		t.Fatal("not consumed")
	}
}

// One OAuth token serves many calls until it nearly expires.
func TestGoogleTokenCache(t *testing.T) {
	fake := iaptest.NewGoogle(t, testBundle)
	fake.Add("coins_starter", "t1", iaptest.GooglePurchase{})
	now := time.Now()
	g, err := NewGooglePlay(GoogleConfig{ServiceAccountFile: fake.KeyFile, PackageName: testBundle,
		APIURL: fake.URL, Now: func() time.Time { return now }})
	if err != nil {
		t.Fatal(err)
	}
	first, err := g.token(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for range 3 {
		if _, err := g.Product(context.Background(), "coins_starter", "t1"); err != nil {
			t.Fatal(err)
		}
	}
	if tok, _ := g.token(context.Background()); tok != first {
		t.Fatal("token not cached")
	}
	now = now.Add(time.Hour)
	if tok, _ := g.token(context.Background()); tok == first {
		t.Fatal("expired token reused")
	}
}

func TestGoogleVoidedPages(t *testing.T) {
	fake := iaptest.NewGoogle(t, testBundle)
	for _, tok := range []string{"v1", "v2", "v3", "v4", "v5"} {
		fake.Void(tok, "GPA."+tok)
	}
	g := newTestGoogle(t, fake, testBundle)
	var got []string
	page := ""
	for {
		list, next, err := g.Voided(context.Background(), time.Now().Add(-time.Hour), page)
		if err != nil {
			t.Fatal(err)
		}
		for _, v := range list {
			got = append(got, v.PurchaseToken)
		}
		if next == "" {
			break
		}
		page = next
	}
	if len(got) != 5 || got[0] != "v1" || got[4] != "v5" {
		t.Fatalf("voided = %v", got)
	}
}

func TestNewGooglePlayRejectsBadKeys(t *testing.T) {
	dir := t.TempDir()
	bad := filepath.Join(dir, "bad.json")
	if err := os.WriteFile(bad, []byte(`{"type":"authorized_user","client_email":"x","private_key":"y"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	notKey := filepath.Join(dir, "nokey.json")
	if err := os.WriteFile(notKey, []byte(`{"type":"service_account","client_email":"x","private_key":"not pem"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	fake := iaptest.NewGoogle(t, testBundle)
	for _, tc := range []struct{ name, file, pkg string }{
		{"missing file", filepath.Join(dir, "missing.json"), testBundle},
		{"not a service account", bad, testBundle},
		{"unparsable key", notKey, testBundle},
		{"bad package", fake.KeyFile, "not a package"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := NewGooglePlay(GoogleConfig{ServiceAccountFile: tc.file, PackageName: tc.pkg})
			if err == nil {
				t.Fatal("accepted")
			}
			if filepath.IsAbs(tc.file) && len(tc.file) > 1 && strings.Contains(err.Error(), tc.file) {
				t.Fatalf("error reveals the key path: %v", err)
			}
		})
	}
}
