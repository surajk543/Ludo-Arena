package iaptest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Apple's marker extensions (see package iap).
var (
	oidLeaf         = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}
	oidIntermediate = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}
)

// Transaction is a StoreKit 2 JWSTransaction payload.
type Transaction struct {
	TransactionID         string `json:"transactionId"`
	OriginalTransactionID string `json:"originalTransactionId"`
	BundleID              string `json:"bundleId"`
	ProductID             string `json:"productId"`
	Type                  string `json:"type"`
	Quantity              int    `json:"quantity"`
	AppAccountToken       string `json:"appAccountToken,omitempty"`
	PurchaseDate          int64  `json:"purchaseDate"`
	SignedDate            int64  `json:"signedDate"`
	RevocationDate        int64  `json:"revocationDate,omitempty"`
	RevocationReason      *int   `json:"revocationReason,omitempty"`
	Environment           string `json:"environment"`
	Storefront            string `json:"storefront"`
	Currency              string `json:"currency"`
	Price                 int64  `json:"price"`
}

// Apple signs StoreKit 2 data with a test chain and fakes the App Store
// Server API.
type Apple struct {
	Bundle string
	// RootFile is the chain's root certificate (PEM), for APPLE_ROOT_CA_FILE.
	RootFile string
	RootPEM  []byte
	chain    []string // base64 DER: leaf, intermediate, root
	leafKey  *ecdsa.PrivateKey

	// App Store Server API (StartAPI).
	API                      *httptest.Server
	KeyID, IssuerID, KeyFile string
	apiKey                   *ecdsa.PrivateKey
	mu                       sync.Mutex
	txs                      map[string]string // transactionId → signed
	lookups                  int
	failLookups              int
}

func mustKey(t testing.TB) *ecdsa.PrivateKey {
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func marker(oid asn1.ObjectIdentifier) pkix.Extension {
	return pkix.Extension{Id: oid, Value: []byte{0x05, 0x00}} // ASN.1 NULL, as Apple's
}

// NewApple creates a root → intermediate → leaf chain with Apple's marker
// OIDs, valid now.
func NewApple(t testing.TB, bundle string) *Apple {
	t.Helper()
	return newApple(t, bundle, true)
}

// NewAppleWithoutMarkers creates a chain lacking Apple's marker OIDs (a
// valid chain to the same kind of root that Apple never issues).
func NewAppleWithoutMarkers(t testing.TB, bundle string) *Apple {
	t.Helper()
	return newApple(t, bundle, false)
}

func newApple(t testing.TB, bundle string, markers bool) *Apple {
	rootKey, interKey, leafKey := mustKey(t), mustKey(t), mustKey(t)
	now := time.Now()
	mk := func(serial int64, cn string, ca bool, parent *x509.Certificate, parentKey, key *ecdsa.PrivateKey,
		ext []pkix.Extension) *x509.Certificate {
		tpl := &x509.Certificate{
			SerialNumber: big.NewInt(serial), Subject: pkix.Name{CommonName: cn, Organization: []string{"Test Apple"}},
			NotBefore: now.Add(-24 * time.Hour), NotAfter: now.Add(365 * 24 * time.Hour),
			BasicConstraintsValid: true, IsCA: ca, ExtraExtensions: ext,
		}
		if ca {
			tpl.KeyUsage = x509.KeyUsageCertSign | x509.KeyUsageCRLSign
		} else {
			tpl.KeyUsage = x509.KeyUsageDigitalSignature
		}
		if parent == nil {
			parent = tpl
		}
		der, err := x509.CreateCertificate(rand.Reader, tpl, parent, &key.PublicKey, parentKey)
		if err != nil {
			t.Fatal(err)
		}
		c, err := x509.ParseCertificate(der)
		if err != nil {
			t.Fatal(err)
		}
		return c
	}
	var leafExt, interExt []pkix.Extension
	if markers {
		leafExt, interExt = []pkix.Extension{marker(oidLeaf)}, []pkix.Extension{marker(oidIntermediate)}
	}
	root := mk(1, "Test Apple Root CA - G3", true, nil, rootKey, rootKey, nil)
	inter := mk(2, "Test Apple WWDR CA G6", true, root, rootKey, interKey, interExt)
	leaf := mk(3, "Test Prod ECC Mac App Store and iTunes Store Receipt Signing", false, inter, interKey, leafKey, leafExt)
	a := &Apple{Bundle: bundle, leafKey: leafKey, txs: map[string]string{}}
	for _, c := range []*x509.Certificate{leaf, inter, root} {
		a.chain = append(a.chain, base64.StdEncoding.EncodeToString(c.Raw))
	}
	a.RootPEM = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: root.Raw})
	a.RootFile = filepath.Join(t.TempDir(), "root.pem")
	if err := os.WriteFile(a.RootFile, a.RootPEM, 0o600); err != nil {
		t.Fatal(err)
	}
	return a
}

// Sign signs any payload as a StoreKit 2 JWS (ES256, x5c chain).
func (a *Apple) Sign(t testing.TB, payload any) string {
	t.Helper()
	hdr, _ := json.Marshal(map[string]any{"alg": "ES256", "x5c": a.chain})
	body, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	in := base64.RawURLEncoding.EncodeToString(hdr) + "." + base64.RawURLEncoding.EncodeToString(body)
	sum := sha256.Sum256([]byte(in))
	r, s, err := ecdsa.Sign(rand.Reader, a.leafKey, sum[:])
	if err != nil {
		t.Fatal(err)
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return in + "." + base64.RawURLEncoding.EncodeToString(sig)
}

// Transaction fills the usual fields of a consumable purchase.
func (a *Apple) Transaction(id, productID, accountToken string) Transaction {
	now := time.Now().UnixMilli()
	return Transaction{TransactionID: id, OriginalTransactionID: id, BundleID: a.Bundle, ProductID: productID,
		Type: "Consumable", Quantity: 1, AppAccountToken: accountToken, PurchaseDate: now, SignedDate: now,
		Environment: "Sandbox", Storefront: "IND", Currency: "INR", Price: 199000}
}

// SignTransaction signs tx and remembers it for the App Store Server API.
func (a *Apple) SignTransaction(t testing.TB, tx Transaction) string {
	t.Helper()
	s := a.Sign(t, tx)
	a.mu.Lock()
	a.txs[tx.TransactionID] = s
	a.mu.Unlock()
	return s
}

// Notification signs an App Store Server Notification V2 for signedTx.
func (a *Apple) Notification(t testing.TB, notificationType, env, signedTx string) string {
	t.Helper()
	return a.Sign(t, map[string]any{
		"notificationType": notificationType, "notificationUUID": "3e1d5c1a-0000-4000-8000-000000000001",
		"version": "2.0", "signedDate": time.Now().UnixMilli(),
		"data": map[string]any{"appAppleId": 1234567890, "bundleId": a.Bundle, "bundleVersion": "1",
			"environment": env, "signedTransactionInfo": signedTx},
	})
}

// StartAPI starts the fake App Store Server API ("Get Transaction Info")
// and writes its .p8 key.
func (a *Apple) StartAPI(t testing.TB) {
	t.Helper()
	a.apiKey = mustKey(t)
	a.KeyID, a.IssuerID = "TESTKEY123", "57246542-96fe-1a63-e053-0824d011072a"
	der, err := x509.MarshalPKCS8PrivateKey(a.apiKey)
	if err != nil {
		t.Fatal(err)
	}
	a.KeyFile = filepath.Join(t.TempDir(), "SubscriptionKey_TESTKEY123.p8")
	if err := os.WriteFile(a.KeyFile, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
	a.API = httptest.NewServer(http.HandlerFunc(a.serveAPI))
	t.Cleanup(a.API.Close)
}

// Lookups is how many Get Transaction Info calls were served.
func (a *Apple) Lookups() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.lookups
}

// FailLookups makes the next n lookups answer 500.
func (a *Apple) FailLookups(n int) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.failLookups = n
}

// Forget drops a transaction from the API (it then answers 404).
func (a *Apple) Forget(id string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	delete(a.txs, id)
}

func (a *Apple) serveAPI(w http.ResponseWriter, r *http.Request) {
	tok, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	claims := jwt.MapClaims{}
	parsed, err := jwt.ParseWithClaims(tok, claims, func(*jwt.Token) (any, error) { return &a.apiKey.PublicKey, nil },
		jwt.WithValidMethods([]string{"ES256"}), jwt.WithAudience("appstoreconnect-v1"), jwt.WithIssuer(a.IssuerID))
	if err != nil || parsed.Header["kid"] != a.KeyID || claims["bid"] != a.Bundle {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	id, ok := strings.CutPrefix(r.URL.Path, "/inApps/v1/transactions/")
	if !ok || r.Method != http.MethodGet {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	a.lookups++
	if a.failLookups > 0 {
		a.failLookups--
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	signed, ok := a.txs[id]
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		_ = json.NewEncoder(w).Encode(map[string]any{"errorCode": 4040010, "errorMessage": "Transaction id not found."})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"signedTransactionInfo": signed})
}
