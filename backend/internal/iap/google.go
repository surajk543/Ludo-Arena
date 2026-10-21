package iap

// Google Play verification through the Android Publisher API v3
// (https://developers.google.com/android-publisher), authenticated as a
// service account with the OAuth 2.0 JWT bearer grant (RFC 7523). This needs
// only an RS256 signature (golang-jwt, already a dependency) and two HTTPS
// calls, so no Google SDK is pulled in: the full client libraries would add
// dozens of modules for three REST endpoints.
//
//   - purchases.products.get     verifies one purchase token
//   - purchases.products.consume consumes it after the grant
//   - purchases.voidedpurchases.list lists refunded / charged-back purchases
//
// The service account key never leaves this process and is never logged;
// access tokens are cached until a minute before they expire.

import (
	"context"
	"crypto/rsa"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Default endpoints and scope.
const (
	GoogleAPIURL     = "https://androidpublisher.googleapis.com"
	googleTokenURL   = "https://oauth2.googleapis.com/token"
	androidPublisher = "https://www.googleapis.com/auth/androidpublisher"
)

var androidPackageRe = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$`)

// Store errors shared by both verifiers.
var (
	// ErrStoreRejected: the store does not know this purchase for this app
	// and product (unknown, malformed or foreign token / transaction).
	ErrStoreRejected = errors.New("iap: purchase not recognised by the store")
	// ErrStoreUnreachable: the store did not answer (network, 5xx, 429).
	ErrStoreUnreachable = errors.New("iap: store unreachable")
	// ErrStoreAuth: the store refused our credentials or permissions
	// (service account roles, App Store Connect key).
	ErrStoreAuth = errors.New("iap: store credentials refused")
)

// GoogleConfig configures GooglePlay.
type GoogleConfig struct {
	// ServiceAccountFile is the service account JSON key
	// (GOOGLE_PLAY_SERVICE_ACCOUNT_FILE). It is read once at startup.
	ServiceAccountFile string
	// PackageName is the app's package (GOOGLE_PLAY_PACKAGE_NAME).
	PackageName string
	// APIURL overrides GoogleAPIURL (tests only).
	APIURL string
	// HTTPClient defaults to a client with a 10 s timeout.
	HTTPClient *http.Client
	Now        func() time.Time
}

type serviceAccount struct {
	Type        string `json:"type"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
}

// GooglePlay calls the Android Publisher API.
type GooglePlay struct {
	pkg, apiURL string
	email       string
	key         *rsa.PrivateKey
	tokenURL    string
	hc          *http.Client
	now         func() time.Time

	mu     sync.Mutex
	access string
	expiry time.Time
}

// NewGooglePlay reads the service account key file.
func NewGooglePlay(cfg GoogleConfig) (*GooglePlay, error) {
	if !androidPackageRe.MatchString(cfg.PackageName) {
		return nil, errors.New("GOOGLE_PLAY_PACKAGE_NAME is not a valid Android package name")
	}
	raw, err := os.ReadFile(cfg.ServiceAccountFile)
	if err != nil {
		// The path may be private: say which variable, not the path.
		return nil, errors.New("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE cannot be read")
	}
	var sa serviceAccount
	if err := json.Unmarshal(raw, &sa); err != nil || sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, errors.New("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE is not a service account JSON key")
	}
	if sa.Type != "" && sa.Type != "service_account" {
		return nil, errors.New("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE is not a service account JSON key")
	}
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(sa.PrivateKey))
	if err != nil {
		return nil, errors.New("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE: the private key cannot be parsed")
	}
	if sa.TokenURI == "" {
		sa.TokenURI = googleTokenURL
	}
	g := &GooglePlay{pkg: cfg.PackageName, apiURL: strings.TrimRight(cfg.APIURL, "/"), email: sa.ClientEmail,
		key: key, tokenURL: sa.TokenURI, hc: cfg.HTTPClient, now: cfg.Now}
	if g.apiURL == "" {
		g.apiURL = GoogleAPIURL
	}
	if g.hc == nil {
		g.hc = &http.Client{Timeout: 10 * time.Second}
	}
	if g.now == nil {
		g.now = time.Now
	}
	return g, nil
}

// PackageName is the verified app package.
func (g *GooglePlay) PackageName() string { return g.pkg }

// token returns a cached OAuth access token.
func (g *GooglePlay) token(ctx context.Context) (string, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	now := g.now()
	if g.access != "" && now.Before(g.expiry) {
		return g.access, nil
	}
	claims := jwt.MapClaims{"iss": g.email, "scope": androidPublisher, "aud": g.tokenURL,
		"iat": now.Unix(), "exp": now.Add(time.Hour).Unix()}
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, claims).SignedString(g.key)
	if err != nil {
		return "", err
	}
	form := url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"}, "assertion": {assertion}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, g.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := g.hc.Do(req)
	if err != nil {
		return "", fmt.Errorf("%w: token: %s", ErrStoreUnreachable, redactErr(err))
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 64<<10))
	switch {
	case res.StatusCode == http.StatusBadRequest || res.StatusCode == http.StatusUnauthorized ||
		res.StatusCode == http.StatusForbidden:
		return "", fmt.Errorf("%w: token endpoint answered %d", ErrStoreAuth, res.StatusCode)
	case res.StatusCode != http.StatusOK:
		return "", fmt.Errorf("%w: token endpoint answered %d", ErrStoreUnreachable, res.StatusCode)
	}
	var tok struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &tok); err != nil || tok.AccessToken == "" {
		return "", fmt.Errorf("%w: malformed token response", ErrStoreUnreachable)
	}
	if tok.ExpiresIn <= 0 {
		tok.ExpiresIn = 3600
	}
	g.access = tok.AccessToken
	g.expiry = now.Add(time.Duration(tok.ExpiresIn)*time.Second - time.Minute)
	return g.access, nil
}

// call performs an authenticated request and decodes a JSON answer into out
// (when not nil).
func (g *GooglePlay) call(ctx context.Context, method, path string, q url.Values, out any) error {
	tok, err := g.token(ctx)
	if err != nil {
		return err
	}
	u := g.apiURL + path
	if len(q) > 0 {
		u += "?" + q.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, method, u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Accept", "application/json")
	res, err := g.hc.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %s", ErrStoreUnreachable, redactErr(err))
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	switch {
	case res.StatusCode == http.StatusUnauthorized:
		g.mu.Lock()
		g.access = "" // fetch a fresh token next time
		g.mu.Unlock()
		return fmt.Errorf("%w: android publisher answered 401", ErrStoreAuth)
	case res.StatusCode == http.StatusForbidden:
		return fmt.Errorf("%w: android publisher answered 403 (service account permissions)", ErrStoreAuth)
	case res.StatusCode == http.StatusNotFound || res.StatusCode == http.StatusGone ||
		res.StatusCode == http.StatusBadRequest:
		return fmt.Errorf("%w (android publisher answered %d)", ErrStoreRejected, res.StatusCode)
	case res.StatusCode == http.StatusTooManyRequests || res.StatusCode >= 500:
		return fmt.Errorf("%w: android publisher answered %d", ErrStoreUnreachable, res.StatusCode)
	case res.StatusCode < 200 || res.StatusCode > 299:
		return fmt.Errorf("%w (android publisher answered %d)", ErrStoreRejected, res.StatusCode)
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("%w: malformed answer", ErrStoreUnreachable)
	}
	return nil
}

// GoogleProduct is a purchases.products resource (the fields we use).
type GoogleProduct struct {
	PurchaseState               *int   `json:"purchaseState"`    // 0 purchased, 1 canceled, 2 pending
	ConsumptionState            int    `json:"consumptionState"` // 0 yet to be consumed, 1 consumed
	AcknowledgementState        int    `json:"acknowledgementState"`
	OrderID                     string `json:"orderId"`
	ProductID                   string `json:"productId"`
	Quantity                    int    `json:"quantity"`
	PurchaseType                *int   `json:"purchaseType"` // 0 test (license tester), 1 promo, 2 rewarded
	ObfuscatedExternalAccountID string `json:"obfuscatedExternalAccountId"`
	PurchaseTimeMillis          string `json:"purchaseTimeMillis"`
}

// Google purchase states.
const (
	GooglePurchased = 0
	GoogleCanceled  = 1
	GooglePending   = 2
)

func (g *GooglePlay) productPath(productID, token string) string {
	return "/androidpublisher/v3/applications/" + url.PathEscape(g.pkg) + "/purchases/products/" +
		url.PathEscape(productID) + "/tokens/" + url.PathEscape(token)
}

// Product verifies a purchase token for productID of this package. A token of
// another package or product is answered 400/404 by Google (ErrStoreRejected).
func (g *GooglePlay) Product(ctx context.Context, productID, token string) (*GoogleProduct, error) {
	var p GoogleProduct
	if err := g.call(ctx, http.MethodGet, g.productPath(productID, token), nil, &p); err != nil {
		return nil, err
	}
	if p.PurchaseState == nil {
		// JSON may leave out zero values: a purchase resource without a
		// state is a purchased one (0); anything else is not an answer.
		if p.PurchaseTimeMillis == "" {
			return nil, fmt.Errorf("%w: answer is not a product purchase", ErrStoreUnreachable)
		}
		p.PurchaseState = new(int)
	}
	return &p, nil
}

// Consume marks the purchase consumed so the player can buy the pack again
// (the app consumes it too; whichever comes second is a harmless no-op).
func (g *GooglePlay) Consume(ctx context.Context, productID, token string) error {
	return g.call(ctx, http.MethodPost, g.productPath(productID, token)+":consume", nil, nil)
}

// VoidedPurchase is one entry of purchases.voidedpurchases.list.
type VoidedPurchase struct {
	PurchaseToken    string `json:"purchaseToken"`
	OrderID          string `json:"orderId"`
	VoidedTimeMillis string `json:"voidedTimeMillis"`
	VoidedSource     int    `json:"voidedSource"`
	VoidedReason     int    `json:"voidedReason"`
}

// Voided lists in-app purchases voided since `since` (at most 30 days back),
// one page at a time (pageToken "" first; next "" when done).
func (g *GooglePlay) Voided(ctx context.Context, since time.Time, pageToken string) ([]VoidedPurchase, string, error) {
	q := url.Values{"startTime": {strconv.FormatInt(since.UnixMilli(), 10)}, "type": {"0"}, "maxResults": {"1000"}}
	if pageToken != "" {
		q.Set("token", pageToken)
	}
	var out struct {
		VoidedPurchases []VoidedPurchase `json:"voidedPurchases"`
		TokenPagination struct {
			NextPageToken string `json:"nextPageToken"`
		} `json:"tokenPagination"`
	}
	path := "/androidpublisher/v3/applications/" + url.PathEscape(g.pkg) + "/purchases/voidedpurchases"
	if err := g.call(ctx, http.MethodGet, path, q, &out); err != nil {
		return nil, "", err
	}
	return out.VoidedPurchases, out.TokenPagination.NextPageToken, nil
}

// redactErr keeps a transport error loggable without the request URL, which
// carries a purchase token.
func redactErr(err error) string {
	var ue *url.Error
	if errors.As(err, &ue) {
		return ue.Op + ": " + ue.Err.Error()
	}
	return err.Error()
}
