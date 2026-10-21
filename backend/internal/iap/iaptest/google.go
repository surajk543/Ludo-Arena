// Package iaptest fakes the stores for tests: a Google Play Android Publisher
// API (OAuth token endpoint, purchases.products get / consume, voided
// purchases) and Apple's StoreKit 2 signing (a test-generated root,
// intermediate and leaf chain with Apple's marker OIDs) plus the App Store
// Server API. Never used by production code.
package iaptest

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/golang-jwt/jwt/v5"
)

// GooglePurchase is one purchase the fake Play knows.
type GooglePurchase struct {
	State        int    // 0 purchased, 1 canceled, 2 pending
	AccountToken string // obfuscatedExternalAccountId
	OrderID      string
	Quantity     int
	Consumed     bool
	// OmitZero leaves zero-valued fields out of the JSON (as proto3 JSON may).
	OmitZero bool
}

// Google is a fake Android Publisher API.
type Google struct {
	*httptest.Server
	Package string
	// KeyFile is a service account JSON key whose token_uri is this server.
	KeyFile string
	email   string
	key     *rsa.PrivateKey

	mu        sync.Mutex
	purchases map[string]*GooglePurchase // productID/token
	voided    []map[string]any
	access    map[string]bool
	gets      int
	consumes  map[string]int
	failGets  int // next product gets answered 503
}

// NewGoogle starts a fake for package pkg.
func NewGoogle(t testing.TB, pkg string) *Google {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	g := &Google{Package: pkg, key: key, email: "iap-verifier@test-project.iam.gserviceaccount.com",
		purchases: map[string]*GooglePurchase{}, access: map[string]bool{}, consumes: map[string]int{}}
	g.Server = httptest.NewServer(http.HandlerFunc(g.serve))
	t.Cleanup(g.Close)
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	sa, _ := json.Marshal(map[string]string{
		"type": "service_account", "project_id": "test-project", "client_email": g.email,
		"private_key": string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})),
		"token_uri":   g.URL + "/token",
	})
	g.KeyFile = filepath.Join(t.TempDir(), "service-account.json")
	if err := os.WriteFile(g.KeyFile, sa, 0o600); err != nil {
		t.Fatal(err)
	}
	return g
}

// Add registers a purchase token for productID.
func (g *Google) Add(productID, token string, p GooglePurchase) {
	g.mu.Lock()
	defer g.mu.Unlock()
	cp := p
	g.purchases[productID+"/"+token] = &cp
}

// SetState changes a known purchase's state (e.g. pending → purchased).
func (g *Google) SetState(productID, token string, state int) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if p := g.purchases[productID+"/"+token]; p != nil {
		p.State = state
	}
}

// Void lists the purchase token as voided (refunded).
func (g *Google) Void(token, orderID string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.voided = append(g.voided, map[string]any{"kind": "androidpublisher#voidedPurchase",
		"purchaseToken": token, "orderId": orderID, "voidedTimeMillis": "1792588328065",
		"voidedSource": 1, "voidedReason": 1})
}

// Gets is how many purchases.products.get calls were served.
func (g *Google) Gets() int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.gets
}

// Consumes is how many consume calls the token received.
func (g *Google) Consumes(productID, token string) int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.consumes[productID+"/"+token]
}

// FailGets makes the next n product gets answer 503.
func (g *Google) FailGets(n int) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.failGets = n
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{"code": status, "message": msg}})
}

func (g *Google) serve(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/token" {
		g.serveToken(w, r)
		return
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	auth, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !g.access[auth] {
		writeErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	prefix := "/androidpublisher/v3/applications/" + g.Package + "/purchases/"
	rest, ok := strings.CutPrefix(r.URL.Path, prefix)
	if !ok {
		// Another package: Google answers 404 for an app the account cannot see.
		writeErr(w, http.StatusNotFound, "No application was found for the given package name.")
		return
	}
	if rest == "voidedpurchases" && r.Method == http.MethodGet {
		g.serveVoided(w, r)
		return
	}
	// products/{productId}/tokens/{token}[:consume]
	parts := strings.Split(rest, "/")
	if len(parts) != 4 || parts[0] != "products" || parts[2] != "tokens" {
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	product, token := parts[1], parts[3]
	consume := false
	if t, ok := strings.CutSuffix(token, ":consume"); ok {
		token, consume = t, true
	}
	p := g.purchases[product+"/"+token]
	switch {
	case consume && r.Method == http.MethodPost:
		if p == nil {
			writeErr(w, http.StatusBadRequest, "Invalid Value")
			return
		}
		p.Consumed = true
		g.consumes[product+"/"+token]++
		w.WriteHeader(http.StatusNoContent)
	case !consume && r.Method == http.MethodGet:
		g.gets++
		if g.failGets > 0 {
			g.failGets--
			writeErr(w, http.StatusServiceUnavailable, "backend error")
			return
		}
		if p == nil {
			writeErr(w, http.StatusBadRequest, "Invalid Value") // what Play answers for an unknown token
			return
		}
		consumed := 0
		if p.Consumed {
			consumed = 1
		}
		body := map[string]any{"kind": "androidpublisher#productPurchase", "purchaseTimeMillis": "1792588328065",
			"purchaseState": p.State, "consumptionState": consumed, "orderId": p.OrderID,
			"purchaseType": 0, "acknowledgementState": consumed, "regionCode": "IN"}
		if p.AccountToken != "" {
			body["obfuscatedExternalAccountId"] = p.AccountToken
		}
		if p.OmitZero {
			for k, v := range body {
				if v == 0 {
					delete(body, k)
				}
			}
		}
		if p.Quantity > 0 {
			body["quantity"] = p.Quantity
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(body)
	default:
		writeErr(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

// serveVoided pages two entries at a time to exercise pagination.
func (g *Google) serveVoided(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("startTime") == "" || r.URL.Query().Get("type") != "0" {
		writeErr(w, http.StatusBadRequest, "startTime and type required")
		return
	}
	start, _ := strconv.Atoi(r.URL.Query().Get("token"))
	end := min(start+2, len(g.voided))
	body := map[string]any{"voidedPurchases": g.voided[start:end]}
	if end < len(g.voided) {
		body["tokenPagination"] = map[string]string{"nextPageToken": strconv.Itoa(end)}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(body)
}

func (g *Google) serveToken(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil || r.PostForm.Get("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" {
		writeErr(w, http.StatusBadRequest, "unsupported_grant_type")
		return
	}
	claims := jwt.MapClaims{}
	_, err := jwt.ParseWithClaims(r.PostForm.Get("assertion"), claims, func(*jwt.Token) (any, error) {
		return &g.key.PublicKey, nil
	}, jwt.WithValidMethods([]string{"RS256"}), jwt.WithAudience(g.URL+"/token"), jwt.WithIssuer(g.email))
	if err != nil || claims["scope"] != "https://www.googleapis.com/auth/androidpublisher" {
		writeErr(w, http.StatusBadRequest, "invalid_grant")
		return
	}
	g.mu.Lock()
	tok := fmt.Sprintf("ya29.fake-%d", len(g.access)+1)
	g.access[tok] = true
	g.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"access_token": tok, "expires_in": 3599, "token_type": "Bearer"})
}
