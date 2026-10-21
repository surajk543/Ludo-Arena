package iap

import (
	"context"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"ludoroyale/internal/iap/iaptest"
)

const testBundle = "com.ludoroyale.app"

func newTestAppStore(t *testing.T, fake *iaptest.Apple, mut ...func(*AppleConfig)) *AppStore {
	t.Helper()
	cfg := AppleConfig{BundleID: testBundle, AllowSandbox: true, RootCA: fake.RootPEM}
	for _, m := range mut {
		m(&cfg)
	}
	a, err := NewAppStore(cfg)
	if err != nil {
		t.Fatal(err)
	}
	return a
}

// The embedded root is Apple Root CA - G3 (fingerprint documented in apple.go).
func TestEmbeddedAppleRoot(t *testing.T) {
	c, err := x509.ParseCertificate(appleRootG3)
	if err != nil {
		t.Fatal(err)
	}
	if c.Subject.CommonName != "Apple Root CA - G3" || !c.IsCA || c.NotAfter.Year() != 2039 {
		t.Fatalf("unexpected root: %s (CA %t, until %s)", c.Subject, c.IsCA, c.NotAfter)
	}
	if _, err := NewAppStore(AppleConfig{BundleID: testBundle}); err != nil {
		t.Fatal(err)
	}
}

func TestVerifyTransaction(t *testing.T) {
	fake := iaptest.NewApple(t, testBundle)
	a := newTestAppStore(t, fake)
	good := fake.Transaction("2000000123456789", "coins_starter", "7f1c0d8e-5a7b-4c55-9f0e-2d8c3b1a9e44")

	tampered := func() string {
		s := fake.Sign(t, good)
		parts := strings.Split(s, ".")
		var p map[string]any
		raw, _ := base64.RawURLEncoding.DecodeString(parts[1])
		_ = json.Unmarshal(raw, &p)
		p["productId"] = "coins_best_value"
		raw, _ = json.Marshal(p)
		parts[1] = base64.RawURLEncoding.EncodeToString(raw)
		return strings.Join(parts, ".")
	}
	withHeader := func(hdr map[string]any) string {
		parts := strings.Split(fake.Sign(t, good), ".")
		raw, _ := json.Marshal(hdr)
		parts[0] = base64.RawURLEncoding.EncodeToString(raw)
		return strings.Join(parts, ".")
	}
	future := good
	future.SignedDate = time.Now().Add(time.Hour).UnixMilli()
	beforeChain := good
	beforeChain.SignedDate = time.Now().Add(-48 * time.Hour).UnixMilli() // before the test leaf's NotBefore
	badID := good
	badID.TransactionID = "abc"

	cases := []struct {
		name   string
		signed string
		ok     bool
	}{
		{"valid", fake.Sign(t, good), true},
		{"other root", iaptest.NewApple(t, testBundle).Sign(t, good), false},
		{"no apple marker oids", iaptest.NewAppleWithoutMarkers(t, testBundle).Sign(t, good), false},
		{"tampered payload", tampered(), false},
		{"alg none", withHeader(map[string]any{"alg": "none"}), false},
		{"hs256", withHeader(map[string]any{"alg": "HS256", "x5c": []string{"a", "b"}}), false},
		{"no chain", withHeader(map[string]any{"alg": "ES256"}), false},
		{"signed in the future", fake.Sign(t, future), false},
		{"chain not valid at signedDate", fake.Sign(t, beforeChain), false},
		{"non-numeric transaction id", fake.Sign(t, badID), false},
		{"garbage", "a.b.c", false},
		{"not a jws", "eyJhbGciOiJFUzI1NiJ9", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tx, err := a.VerifyTransaction(tc.signed)
			if tc.ok {
				if err != nil {
					t.Fatal(err)
				}
				if tx.TransactionID != good.TransactionID || tx.ProductID != "coins_starter" ||
					tx.AppAccountToken != good.AppAccountToken || tx.Type != AppleConsumable || tx.BundleID != testBundle {
					t.Fatalf("decoded %+v", tx)
				}
				return
			}
			if err == nil || !errors.Is(err, ErrBadSignature) {
				t.Fatalf("err = %v, want ErrBadSignature", err)
			}
		})
	}
}

func TestVerifyNotification(t *testing.T) {
	fake := iaptest.NewApple(t, testBundle)
	a := newTestAppStore(t, fake)
	tx := fake.Sign(t, fake.Transaction("2000000000000001", "coins_popular", ""))
	n, err := a.VerifyNotification(fake.Notification(t, "REFUND", AppleSandbox, tx))
	if err != nil {
		t.Fatal(err)
	}
	if n.NotificationType != "REFUND" || n.Data.SignedTransactionInfo != tx || n.Data.BundleID != testBundle {
		t.Fatalf("decoded %+v", n)
	}
	if _, err := a.VerifyNotification(iaptest.NewApple(t, testBundle).Notification(t, "REFUND", AppleSandbox, tx)); err == nil {
		t.Fatal("notification from another chain accepted")
	}
}

func TestEnvironmentAllowed(t *testing.T) {
	fake := iaptest.NewApple(t, testBundle)
	on := newTestAppStore(t, fake)
	off := newTestAppStore(t, fake, func(c *AppleConfig) { c.AllowSandbox = false })
	for _, tc := range []struct {
		a   *AppStore
		env string
		ok  bool
	}{
		{on, AppleProduction, true}, {on, AppleSandbox, true}, {on, "Xcode", false},
		{off, AppleProduction, true}, {off, AppleSandbox, false},
	} {
		if got := tc.a.EnvironmentAllowed(tc.env); got != tc.ok {
			t.Errorf("allowSandbox=%t env %s: %t, want %t", tc.a.allowSandbox, tc.env, got, tc.ok)
		}
	}
}

func TestAppStoreServerAPI(t *testing.T) {
	fake := iaptest.NewApple(t, testBundle)
	fake.StartAPI(t)
	a := newTestAppStore(t, fake, func(c *AppleConfig) {
		c.KeyID, c.IssuerID, c.KeyFile, c.APIURL = fake.KeyID, fake.IssuerID, fake.KeyFile, fake.API.URL
	})
	if !a.APIConfigured() {
		t.Fatal("API not configured")
	}
	signed := fake.SignTransaction(t, fake.Transaction("2000000000000077", "coins_starter", ""))
	got, err := a.LookupTransaction(context.Background(), AppleSandbox, "2000000000000077")
	if err != nil || got != signed {
		t.Fatalf("lookup = %v", err)
	}
	if _, err := a.LookupTransaction(context.Background(), AppleSandbox, "2000000000000078"); !errors.Is(err, ErrStoreRejected) {
		t.Fatalf("unknown transaction: %v", err)
	}
	fake.FailLookups(1)
	if _, err := a.LookupTransaction(context.Background(), AppleSandbox, "2000000000000077"); !errors.Is(err, ErrStoreUnreachable) {
		t.Fatalf("500: %v", err)
	}
	// A key the fake does not know → 401 → ErrStoreAuth.
	other := iaptest.NewApple(t, testBundle)
	other.StartAPI(t)
	b := newTestAppStore(t, fake, func(c *AppleConfig) {
		c.KeyID, c.IssuerID, c.KeyFile, c.APIURL = fake.KeyID, fake.IssuerID, other.KeyFile, fake.API.URL
	})
	if _, err := b.LookupTransaction(context.Background(), AppleSandbox, "2000000000000077"); !errors.Is(err, ErrStoreAuth) {
		t.Fatalf("wrong key: %v", err)
	}
	if _, err := NewAppStore(AppleConfig{BundleID: testBundle, KeyID: "x"}); err == nil {
		t.Fatal("partial API key accepted")
	}
}
