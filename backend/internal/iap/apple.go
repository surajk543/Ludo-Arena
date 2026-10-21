package iap

// App Store verification of StoreKit 2 signed data (JWS, ES256 with an x5c
// certificate chain). Every signed transaction and every App Store Server
// Notification is verified locally against Apple Root CA - G3, the same
// checks as Apple's App Store Server Library:
//
//  1. the header is ES256 with an x5c chain [leaf, intermediate(, root)];
//  2. the leaf carries Apple's receipt-signing marker OID
//     1.2.840.113635.100.6.11.1 and the intermediate the WWDR marker OID
//     1.2.840.113635.100.6.2.1;
//  3. the chain verifies to the embedded root at the payload's signedDate
//     (Apple rotates leaf certificates, so an older transaction stays
//     verifiable), which must not lie in the future;
//  4. the ES256 signature verifies with the leaf key.
//
// The root certificate AppleRootCA-G3.cer is embedded from
// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer (Apple PKI,
// https://www.apple.com/certificateauthority/), SHA-256 fingerprint
// 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79,
// valid until 2039-04-30.
//
// Optionally (APPLE_IAP_KEY_ID / APPLE_IAP_ISSUER_ID / APPLE_IAP_KEY_FILE),
// the App Store Server API "Get Transaction Info" re-reads the transaction
// from Apple before a grant; its answer is a signed transaction verified the
// same way (and shows a revocation even if the app's copy predates it).

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	_ "embed"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

//go:embed AppleRootCA-G3.cer
var appleRootG3 []byte

// App Store Server API hosts.
const (
	AppleAPIProduction = "https://api.storekit.itunes.apple.com"
	AppleAPISandbox    = "https://api.storekit-sandbox.itunes.apple.com"
)

// Apple environments in signed payloads.
const (
	AppleProduction = "Production"
	AppleSandbox    = "Sandbox"
)

// AppleConsumable is the transaction type of a consumable product.
const AppleConsumable = "Consumable"

var (
	oidAppleLeaf         = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}
	oidAppleIntermediate = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}
	appleTxIDRe          = regexp.MustCompile(`^[0-9]{1,40}$`)
)

// ErrBadSignature: signed data that does not verify to Apple's root.
var ErrBadSignature = errors.New("iap: signed data does not verify")

// AppleConfig configures AppStore.
type AppleConfig struct {
	BundleID string
	// AllowSandbox accepts Sandbox transactions (TestFlight, App Review,
	// sandbox testers). Apple's review uses the sandbox against the
	// production server, so it is on by default.
	AllowSandbox bool
	// RootCA overrides the embedded Apple Root CA - G3 (PEM or DER; tests).
	RootCA []byte
	// App Store Server API credentials (all or none).
	KeyID, IssuerID string
	KeyFile         string
	// APIURL overrides both App Store Server API hosts (tests only).
	APIURL     string
	HTTPClient *http.Client
	Now        func() time.Time
}

// AppStore verifies StoreKit 2 signed data.
type AppStore struct {
	bundleID     string
	allowSandbox bool
	roots        *x509.CertPool
	now          func() time.Time

	// App Store Server API (nil key: not configured).
	keyID, issuerID string
	key             *ecdsa.PrivateKey
	apiURL          string
	hc              *http.Client
	mu              sync.Mutex
	jwt             string
	jwtExp          time.Time
}

// NewAppStore builds the verifier.
func NewAppStore(cfg AppleConfig) (*AppStore, error) {
	if strings.TrimSpace(cfg.BundleID) == "" {
		return nil, errors.New("APPLE_BUNDLE_ID is required for App Store purchases")
	}
	root := cfg.RootCA
	if len(root) == 0 {
		root = appleRootG3
	}
	if b, _ := pem.Decode(root); b != nil {
		root = b.Bytes
	}
	cert, err := x509.ParseCertificate(root)
	if err != nil {
		return nil, fmt.Errorf("apple root certificate: %w", err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(cert)
	a := &AppStore{bundleID: cfg.BundleID, allowSandbox: cfg.AllowSandbox, roots: roots, now: cfg.Now,
		apiURL: strings.TrimRight(cfg.APIURL, "/"), hc: cfg.HTTPClient}
	if a.now == nil {
		a.now = time.Now
	}
	if a.hc == nil {
		a.hc = &http.Client{Timeout: 10 * time.Second}
	}
	if cfg.KeyID != "" || cfg.IssuerID != "" || cfg.KeyFile != "" {
		if cfg.KeyID == "" || cfg.IssuerID == "" || cfg.KeyFile == "" {
			return nil, errors.New("APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID and APPLE_IAP_KEY_FILE: set all three or none")
		}
		raw, err := os.ReadFile(cfg.KeyFile)
		if err != nil {
			return nil, errors.New("APPLE_IAP_KEY_FILE cannot be read")
		}
		key, err := jwt.ParseECPrivateKeyFromPEM(raw)
		if err != nil {
			return nil, errors.New("APPLE_IAP_KEY_FILE is not an App Store Connect .p8 key")
		}
		a.keyID, a.issuerID, a.key = cfg.KeyID, cfg.IssuerID, key
	}
	return a, nil
}

// BundleID is the verified app bundle id.
func (a *AppStore) BundleID() string { return a.bundleID }

// APIConfigured reports whether the App Store Server API is used.
func (a *AppStore) APIConfigured() bool { return a.key != nil }

// AppleTransaction is a decoded JWSTransaction (the fields we use).
type AppleTransaction struct {
	TransactionID         string `json:"transactionId"`
	OriginalTransactionID string `json:"originalTransactionId"`
	BundleID              string `json:"bundleId"`
	ProductID             string `json:"productId"`
	Type                  string `json:"type"`
	Quantity              int    `json:"quantity"`
	AppAccountToken       string `json:"appAccountToken"`
	PurchaseDate          int64  `json:"purchaseDate"`
	SignedDate            int64  `json:"signedDate"`
	RevocationDate        int64  `json:"revocationDate"`
	RevocationReason      *int   `json:"revocationReason"`
	Environment           string `json:"environment"`
}

// AppleNotification is a decoded App Store Server Notification V2 payload.
type AppleNotification struct {
	NotificationType string `json:"notificationType"`
	Subtype          string `json:"subtype"`
	NotificationUUID string `json:"notificationUUID"`
	Version          string `json:"version"`
	SignedDate       int64  `json:"signedDate"`
	Data             struct {
		BundleID              string `json:"bundleId"`
		Environment           string `json:"environment"`
		SignedTransactionInfo string `json:"signedTransactionInfo"`
	} `json:"data"`
}

// EnvironmentAllowed reports whether a payload's environment is accepted.
func (a *AppStore) EnvironmentAllowed(env string) bool {
	return env == AppleProduction || (a.allowSandbox && env == AppleSandbox)
}

// VerifyTransaction verifies a signed transaction (JWS) and decodes it. It
// checks the signature chain only; the caller checks bundle, product, type,
// revocation and environment (CheckTransaction).
func (a *AppStore) VerifyTransaction(signed string) (*AppleTransaction, error) {
	var tx AppleTransaction
	if err := a.verifyJWS(signed, &tx, func() int64 { return tx.SignedDate }); err != nil {
		return nil, err
	}
	if !appleTxIDRe.MatchString(tx.TransactionID) {
		return nil, fmt.Errorf("%w: transactionId", ErrBadSignature)
	}
	return &tx, nil
}

// VerifyNotification verifies an App Store Server Notification V2
// signedPayload and decodes it.
func (a *AppStore) VerifyNotification(signedPayload string) (*AppleNotification, error) {
	var n AppleNotification
	if err := a.verifyJWS(signedPayload, &n, func() int64 { return n.SignedDate }); err != nil {
		return nil, err
	}
	return &n, nil
}

type jwsHeader struct {
	Alg string   `json:"alg"`
	X5C []string `json:"x5c"`
}

// verifyJWS checks the signature with the leaf key, decodes the payload into
// out, then verifies the chain at signedDate() (read from the decoded,
// signature-checked payload).
func (a *AppStore) verifyJWS(token string, out any, signedDate func() int64) error {
	parts := strings.Split(token, ".")
	if len(parts) != 3 || len(token) > 64<<10 {
		return fmt.Errorf("%w: not a compact JWS", ErrBadSignature)
	}
	rawHdr, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return fmt.Errorf("%w: header", ErrBadSignature)
	}
	var hdr jwsHeader
	if err := json.Unmarshal(rawHdr, &hdr); err != nil || hdr.Alg != "ES256" || len(hdr.X5C) < 2 || len(hdr.X5C) > 3 {
		return fmt.Errorf("%w: header must be ES256 with an x5c chain", ErrBadSignature)
	}
	certs := make([]*x509.Certificate, len(hdr.X5C))
	for i, c := range hdr.X5C {
		der, err := base64.StdEncoding.DecodeString(c)
		if err != nil {
			return fmt.Errorf("%w: x5c[%d]", ErrBadSignature, i)
		}
		if certs[i], err = x509.ParseCertificate(der); err != nil {
			return fmt.Errorf("%w: x5c[%d]", ErrBadSignature, i)
		}
	}
	leaf, inter := certs[0], certs[1]
	if !hasExtension(leaf, oidAppleLeaf) || !hasExtension(inter, oidAppleIntermediate) {
		return fmt.Errorf("%w: not an App Store signing chain", ErrBadSignature)
	}
	pub, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok || pub.Curve != elliptic.P256() {
		return fmt.Errorf("%w: leaf key is not P-256", ErrBadSignature)
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return fmt.Errorf("%w: signature", ErrBadSignature)
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(pub, digest[:], r, s) {
		return fmt.Errorf("%w: signature", ErrBadSignature)
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return fmt.Errorf("%w: payload", ErrBadSignature)
	}
	if err := json.Unmarshal(payload, out); err != nil {
		return fmt.Errorf("%w: payload", ErrBadSignature)
	}
	at := time.UnixMilli(signedDate())
	if signedDate() <= 0 || at.After(a.now().Add(5*time.Minute)) {
		return fmt.Errorf("%w: signedDate", ErrBadSignature)
	}
	inters := x509.NewCertPool()
	for _, c := range certs[1:] {
		inters.AddCert(c)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{Roots: a.roots, Intermediates: inters, CurrentTime: at,
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}}); err != nil {
		return fmt.Errorf("%w: chain: %s", ErrBadSignature, err.Error())
	}
	return nil
}

func hasExtension(c *x509.Certificate, oid asn1.ObjectIdentifier) bool {
	for _, e := range c.Extensions {
		if e.Id.Equal(oid) {
			return true
		}
	}
	return false
}

// apiToken returns a cached App Store Server API bearer token (ES256, at most
// one hour; renewed after 50 minutes).
func (a *AppStore) apiToken() (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	now := a.now()
	if a.jwt != "" && now.Before(a.jwtExp) {
		return a.jwt, nil
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{"iss": a.issuerID, "iat": now.Unix(),
		"exp": now.Add(time.Hour).Unix(), "aud": "appstoreconnect-v1", "bid": a.bundleID})
	tok.Header["kid"] = a.keyID
	s, err := tok.SignedString(a.key)
	if err != nil {
		return "", err
	}
	a.jwt, a.jwtExp = s, now.Add(50*time.Minute)
	return s, nil
}

// LookupTransaction reads a transaction from the App Store Server API ("Get
// Transaction Info") in env (Production or Sandbox) and returns its signed
// form. ErrStoreRejected when Apple does not know it.
func (a *AppStore) LookupTransaction(ctx context.Context, env, transactionID string) (string, error) {
	if a.key == nil {
		return "", errors.New("iap: App Store Server API not configured")
	}
	if !appleTxIDRe.MatchString(transactionID) {
		return "", ErrStoreRejected
	}
	base := a.apiURL
	if base == "" {
		base = AppleAPIProduction
		if env == AppleSandbox {
			base = AppleAPISandbox
		}
	}
	tok, err := a.apiToken()
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		base+"/inApps/v1/transactions/"+url.PathEscape(transactionID), nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+tok)
	res, err := a.hc.Do(req)
	if err != nil {
		return "", fmt.Errorf("%w: %s", ErrStoreUnreachable, redactErr(err))
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 256<<10))
	switch {
	case res.StatusCode == http.StatusUnauthorized:
		a.mu.Lock()
		a.jwt = ""
		a.mu.Unlock()
		return "", fmt.Errorf("%w: app store server api answered 401", ErrStoreAuth)
	case res.StatusCode == http.StatusNotFound || res.StatusCode == http.StatusBadRequest:
		return "", fmt.Errorf("%w (app store server api answered %d)", ErrStoreRejected, res.StatusCode)
	case res.StatusCode != http.StatusOK:
		return "", fmt.Errorf("%w: app store server api answered %d", ErrStoreUnreachable, res.StatusCode)
	}
	var out struct {
		SignedTransactionInfo string `json:"signedTransactionInfo"`
	}
	if err := json.NewDecoder(bytes.NewReader(body)).Decode(&out); err != nil || out.SignedTransactionInfo == "" {
		return "", fmt.Errorf("%w: malformed answer", ErrStoreUnreachable)
	}
	return out.SignedTransactionInfo, nil
}
