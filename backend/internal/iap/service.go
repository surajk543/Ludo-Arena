// Package iap sells coin packs for real money through Google Play and the
// App Store (docs/in-app-purchases.md, docs/rest-api.md → Coin packs).
//
// The server is authoritative: a purchase is verified with the store
// (Google: Android Publisher API; Apple: the StoreKit 2 signed transaction,
// optionally re-read from the App Store Server API), then ONE PostgreSQL
// transaction inserts the progression.purchases row and credits the coins and
// diamonds of the pack from the server's configuration (never from the
// client). UNIQUE (store, transaction_id) makes the grant exactly-once: a
// replayed or concurrent submission of the same purchase returns the
// original grant. Each purchase is bound to the buying account through the
// account token (Google obfuscatedExternalAccountId / Apple
// appAccountToken), so another account can never redeem it.
//
// Refunds (Google voided purchases, Apple REFUND / REVOKE notifications)
// mark the row refunded and take the granted coins and diamonds back, never
// below zero, exactly once.
package iap

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/gameevents"
	"ludoarena/internal/metrics"
	"ludoarena/internal/wallet"
)

// Stores as stored in progression.purchases.store.
const (
	StoreGooglePlay = "google_play"
	StoreAppStore   = "app_store"
)

// wallet.updated reasons.
const (
	ReasonPurchase = "purchase"
	ReasonRefund   = "refund"
)

// MaxQuantity is the largest multi-quantity purchase accepted (Play Console
// "multi-quantity" is off for the packs, so stores send 1).
const MaxQuantity = 10

// Service errors (mapped to HTTP in http.go).
var (
	// ErrUnavailable: verification for that store is not configured.
	ErrUnavailable = errors.New("iap: store verification not configured")
	// ErrInvalid: not a valid, completed purchase of a known pack for this
	// app and account.
	ErrInvalid = errors.New("iap: purchase invalid")
	// ErrPending: the store has not received the payment yet.
	ErrPending = errors.New("iap: purchase pending")
	// ErrBadRequest: malformed request fields.
	ErrBadRequest = errors.New("iap: bad request")
	// ErrUnknownAccount: the wallet no longer exists (account deleted).
	ErrUnknownAccount = errors.New("iap: unknown account")
)

// Options configure the Service.
type Options struct {
	// TokenKey derives account tokens (HMAC-SHA256); required.
	TokenKey []byte
	// Google / Apple are nil when not configured (purchases → 503).
	Google *GooglePlay
	Apple  *AppStore
	// VoidedInterval is how often RunVoided polls Google's voided purchases
	// (0 disables); VoidedLookback is how far back each poll looks.
	VoidedInterval, VoidedLookback time.Duration
	// Now is the clock (default time.Now).
	Now func() time.Time
}

// Service grants and refunds coin packs.
type Service struct {
	pool     *pgxpool.Pool
	rdb      *redis.Client
	notifier gameevents.Notifier
	log      *slog.Logger
	packs    *Catalog
	opts     Options
}

// New returns a Service. notifier may be nil (no pushes).
func New(pool *pgxpool.Pool, rdb *redis.Client, notifier gameevents.Notifier, log *slog.Logger,
	packs *Catalog, opts Options) *Service {
	if log == nil {
		log = slog.Default()
	}
	if opts.Now == nil {
		opts.Now = time.Now
	}
	if opts.VoidedLookback <= 0 {
		opts.VoidedLookback = 7 * 24 * time.Hour
	}
	return &Service{pool: pool, rdb: rdb, notifier: notifier, log: log, packs: packs, opts: opts}
}

// Catalog returns the pack catalogue.
func (s *Service) Catalog() *Catalog { return s.packs }

// Available reports whether purchases on platform can be verified.
func (s *Service) Available(platform string) bool {
	switch platform {
	case PlatformAndroid:
		return s.opts.Google != nil
	case PlatformIOS:
		return s.opts.Apple != nil
	}
	return false
}

// AccountToken is the account's opaque purchase token: a UUID derived from
// the account id with HMAC-SHA256 (one-way; stable per account). The app
// passes it to the store (Google obfuscatedAccountId / Apple appAccountToken)
// and the store returns it in the verified purchase.
func AccountToken(key []byte, userID uuid.UUID) string {
	m := hmac.New(sha256.New, key)
	m.Write([]byte("ludoarena/iap-account-token/v1:"))
	m.Write(userID[:])
	var u uuid.UUID
	copy(u[:], m.Sum(nil)[:16])
	u[6] = (u[6] & 0x0f) | 0x40 // version 4 layout
	u[8] = (u[8] & 0x3f) | 0x80 // RFC 4122 variant
	return u.String()
}

// AccountToken returns userID's token.
func (s *Service) AccountToken(userID uuid.UUID) string { return AccountToken(s.opts.TokenKey, userID) }

// TokenHash is the stored transaction id of a Google purchase token.
func TokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// PurchaseRequest is the POST /store/purchases body.
type PurchaseRequest struct {
	Platform          string `json:"platform"`
	ProductID         string `json:"productId"`
	PurchaseToken     string `json:"purchaseToken,omitempty"`
	TransactionID     string `json:"transactionId,omitempty"`
	SignedTransaction string `json:"signedTransaction,omitempty"`
}

// Granted is what a purchase credited.
type Granted struct {
	Coins    int64 `json:"coins"`
	Diamonds int64 `json:"diamonds"`
}

// PurchaseResult is the POST /store/purchases answer.
type PurchaseResult struct {
	Wallet  wallet.Wallet `json:"wallet"`
	Granted Granted       `json:"granted"`
	Pack    PackView      `json:"pack"`
	// Replayed: this purchase had already been granted (no second credit).
	Replayed bool `json:"replayed"`
}

// verified is a store purchase that passed every check.
type verified struct {
	store, productID, txID, orderID string
	quantity                        int
	// consume is the Google token to consume after the grant ("" for Apple).
	consume string
}

// Purchase verifies a store purchase and grants its pack once.
func (s *Service) Purchase(ctx context.Context, userID uuid.UUID, req PurchaseRequest) (*PurchaseResult, error) {
	res, store, err := s.purchase(ctx, userID, req)
	s.count(store, err, res)
	return res, err
}

func (s *Service) purchase(ctx context.Context, userID uuid.UUID, req PurchaseRequest) (*PurchaseResult, string, error) {
	store, err := s.precheck(req)
	if err != nil {
		return nil, store, err
	}
	// key is the stored transaction id.
	var key string
	var appleTx *AppleTransaction
	if store == StoreGooglePlay {
		key = TokenHash(req.PurchaseToken)
	} else {
		key = req.TransactionID
		if req.SignedTransaction != "" {
			t, err := s.opts.Apple.VerifyTransaction(req.SignedTransaction)
			if err != nil {
				return nil, store, fmt.Errorf("%w: %s", ErrInvalid, err.Error())
			}
			if key != "" && key != t.TransactionID {
				return nil, store, fmt.Errorf("%w: transactionId does not match the signed transaction", ErrInvalid)
			}
			key, appleTx = t.TransactionID, t
		}
	}
	// A purchase already granted needs no store call: the row is the proof
	// (also for a pack removed from the configuration since).
	if res, err := s.replay(ctx, userID, store, key, req.Platform); !errors.Is(err, pgx.ErrNoRows) {
		return res, store, err
	}
	pack, ok := s.packs.Packs().ByProduct(req.Platform, req.ProductID)
	if !ok {
		return nil, store, fmt.Errorf("%w: unknown product", ErrInvalid)
	}
	var v *verified
	if store == StoreGooglePlay {
		v, err = s.verifyGoogle(ctx, userID, req)
	} else {
		v, err = s.verifyApple(ctx, userID, req, appleTx)
	}
	if err != nil {
		return nil, store, err
	}
	res, err := s.grant(ctx, userID, pack, v, req.Platform)
	return res, store, err
}

func (s *Service) precheck(req PurchaseRequest) (string, error) {
	var store string
	switch req.Platform {
	case PlatformAndroid:
		store = StoreGooglePlay
	case PlatformIOS:
		store = StoreAppStore
	default:
		return "", fmt.Errorf("%w: platform must be android or ios", ErrBadRequest)
	}
	if !productIDRe.MatchString(req.ProductID) {
		return store, fmt.Errorf("%w: productId", ErrBadRequest)
	}
	switch store {
	case StoreGooglePlay:
		if !printable(req.PurchaseToken, 10, 4096) || req.TransactionID != "" || req.SignedTransaction != "" {
			return store, fmt.Errorf("%w: android needs purchaseToken only", ErrBadRequest)
		}
		if s.opts.Google == nil {
			return store, ErrUnavailable
		}
	case StoreAppStore:
		if req.PurchaseToken != "" ||
			(req.TransactionID != "" && !appleTxIDRe.MatchString(req.TransactionID)) ||
			(req.SignedTransaction != "" && !printable(req.SignedTransaction, 20, 32<<10)) {
			return store, fmt.Errorf("%w: ios needs signedTransaction and/or transactionId", ErrBadRequest)
		}
		if s.opts.Apple == nil {
			return store, ErrUnavailable
		}
		if req.SignedTransaction == "" && (req.TransactionID == "" || !s.opts.Apple.APIConfigured()) {
			return store, fmt.Errorf("%w: signedTransaction is required", ErrBadRequest)
		}
	}
	return store, nil
}

func printable(s string, minLen, maxLen int) bool {
	if len(s) < minLen || len(s) > maxLen {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < 0x21 || s[i] > 0x7e {
			return false
		}
	}
	return true
}

func (s *Service) verifyGoogle(ctx context.Context, userID uuid.UUID, req PurchaseRequest) (*verified, error) {
	g := s.opts.Google
	p, err := g.Product(ctx, req.ProductID, req.PurchaseToken)
	if err != nil {
		return nil, s.storeErr(StoreGooglePlay, err)
	}
	switch *p.PurchaseState {
	case GooglePurchased:
	case GooglePending:
		return nil, ErrPending
	default:
		return nil, fmt.Errorf("%w: purchase state %d", ErrInvalid, *p.PurchaseState)
	}
	if p.ProductID != "" && p.ProductID != req.ProductID {
		return nil, fmt.Errorf("%w: product mismatch", ErrInvalid)
	}
	if p.ObfuscatedExternalAccountID != s.AccountToken(userID) {
		return nil, fmt.Errorf("%w: purchase belongs to another account", ErrInvalid)
	}
	q := p.Quantity
	if q == 0 {
		q = 1
	}
	if q < 1 || q > MaxQuantity {
		return nil, fmt.Errorf("%w: quantity %d", ErrInvalid, q)
	}
	v := &verified{store: StoreGooglePlay, productID: req.ProductID, txID: TokenHash(req.PurchaseToken),
		orderID: p.OrderID, quantity: q}
	if len(v.orderID) > 128 {
		v.orderID = v.orderID[:128]
	}
	if p.ConsumptionState == 0 {
		v.consume = req.PurchaseToken
	}
	return v, nil
}

// verifyApple checks an App Store transaction; tx is the app's signed copy,
// already verified (nil when only transactionId was sent).
func (s *Service) verifyApple(ctx context.Context, userID uuid.UUID, req PurchaseRequest, tx *AppleTransaction) (*verified, error) {
	a := s.opts.Apple
	if a.APIConfigured() {
		var signed string
		var err error
		if tx != nil {
			signed, err = a.LookupTransaction(ctx, tx.Environment, tx.TransactionID)
		} else {
			// Only the id: production first, then the sandbox.
			signed, err = a.LookupTransaction(ctx, AppleProduction, req.TransactionID)
			if errors.Is(err, ErrStoreRejected) && a.EnvironmentAllowed(AppleSandbox) {
				signed, err = a.LookupTransaction(ctx, AppleSandbox, req.TransactionID)
			}
		}
		if err == nil {
			metrics.IAPAppleLookups.WithLabelValues("ok").Inc()
			if tx, err = a.VerifyTransaction(signed); err != nil {
				return nil, s.storeErr(StoreAppStore, err)
			}
		} else if tx == nil || !errors.Is(err, ErrStoreUnreachable) && !errors.Is(err, ErrStoreAuth) {
			return nil, s.storeErr(StoreAppStore, err)
		} else {
			// The app's signed copy verified; Apple's API is only a second
			// opinion, so an outage does not block the grant.
			s.log.Warn("app store server api lookup failed; using the verified signed transaction",
				"error", err.Error())
			metrics.IAPAppleLookups.WithLabelValues("fallback").Inc()
		}
	}
	switch {
	case tx.BundleID != a.BundleID():
		return nil, fmt.Errorf("%w: bundle id", ErrInvalid)
	case tx.ProductID != req.ProductID:
		return nil, fmt.Errorf("%w: product mismatch", ErrInvalid)
	case tx.Type != AppleConsumable:
		return nil, fmt.Errorf("%w: not a consumable", ErrInvalid)
	case tx.RevocationDate != 0:
		return nil, fmt.Errorf("%w: revoked", ErrInvalid)
	case !a.EnvironmentAllowed(tx.Environment):
		return nil, fmt.Errorf("%w: environment %q not accepted", ErrInvalid, tx.Environment)
	case !strings.EqualFold(tx.AppAccountToken, s.AccountToken(userID)):
		return nil, fmt.Errorf("%w: purchase belongs to another account", ErrInvalid)
	}
	q := tx.Quantity
	if q == 0 {
		q = 1
	}
	if q < 1 || q > MaxQuantity {
		return nil, fmt.Errorf("%w: quantity %d", ErrInvalid, q)
	}
	return &verified{store: StoreAppStore, productID: req.ProductID, txID: tx.TransactionID, quantity: q}, nil
}

// storeErr maps a verifier error to a service error, logging what operators
// must fix.
func (s *Service) storeErr(store string, err error) error {
	switch {
	case errors.Is(err, ErrStoreRejected), errors.Is(err, ErrBadSignature):
		return fmt.Errorf("%w: %s", ErrInvalid, err.Error())
	case errors.Is(err, ErrStoreAuth):
		s.log.Error("store verification credentials refused", "store", store, "error", err.Error())
		return fmt.Errorf("%w: %s", ErrUnavailable, err.Error())
	}
	return err // ErrStoreUnreachable or another transient error
}

// grant inserts the purchase row and credits the wallet in one transaction.
// On a unique conflict (the same purchase granted meanwhile) it returns the
// existing grant instead.
func (s *Service) grant(ctx context.Context, userID uuid.UUID, pack *Pack, v *verified, platform string) (*PurchaseResult, error) {
	coins, diamonds := pack.Coins*int64(v.quantity), pack.Diamonds*int64(v.quantity)
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	var order *string
	if v.orderID != "" {
		order = &v.orderID
	}
	// A person's wallet only (bot wallets, is_bot, are not accounts), locked
	// first: the lock order of refunds and account deletion.
	var one int
	err = tx.QueryRow(ctx, `SELECT 1 FROM wallet.wallets WHERE user_id = $1 AND NOT is_bot FOR UPDATE`, userID).Scan(&one)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUnknownAccount
	}
	if err != nil {
		return nil, err
	}
	var id uuid.UUID
	err = tx.QueryRow(ctx, `
		INSERT INTO progression.purchases (user_id, store, product_id, transaction_id, order_id, coins, diamonds)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (store, transaction_id) DO NOTHING
		RETURNING id`, userID, v.store, v.productID, v.txID, order, coins, diamonds).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		_ = tx.Rollback(ctx)
		return s.replay(ctx, userID, v.store, v.txID, platform)
	}
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23503" {
			return nil, ErrUnknownAccount
		}
		return nil, err
	}
	wal, err := wallet.AdjustTx(ctx, tx, userID, coins, diamonds)
	if errors.Is(err, wallet.ErrNotFound) {
		return nil, ErrUnknownAccount
	}
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	metrics.IAPCurrencyGranted.WithLabelValues(v.store, "coins").Add(float64(coins))
	metrics.IAPCurrencyGranted.WithLabelValues(v.store, "diamonds").Add(float64(diamonds))
	s.push(ctx, userID, wal, coins, diamonds, ReasonPurchase)
	if v.consume != "" && s.opts.Google != nil {
		cctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
		if err := s.opts.Google.Consume(cctx, v.productID, v.consume); err != nil {
			// The app consumes too; an unconsumed purchase only blocks
			// buying the same pack again until it is.
			s.log.Warn("google play consume failed (the app consumes it too)", "error", err.Error())
			metrics.IAPConsumes.WithLabelValues("error").Inc()
		} else {
			metrics.IAPConsumes.WithLabelValues("ok").Inc()
		}
		cancel()
	}
	return &PurchaseResult{Wallet: wal, Granted: Granted{Coins: coins, Diamonds: diamonds},
		Pack: pack.View(platform)}, nil
}

// purchaseRow is a stored purchase.
type purchaseRow struct {
	userID          uuid.UUID
	productID       string
	coins, diamonds int64
	status          string
}

func (s *Service) findPurchase(ctx context.Context, store, txID string) (*purchaseRow, error) {
	var r purchaseRow
	err := s.pool.QueryRow(ctx, `SELECT user_id, product_id, coins, diamonds, status
		FROM progression.purchases WHERE store = $1 AND transaction_id = $2`, store, txID).
		Scan(&r.userID, &r.productID, &r.coins, &r.diamonds, &r.status)
	if err != nil {
		return nil, err
	}
	return &r, nil
}

// replay answers a purchase that already has a row: the original grant for
// its owner, purchase_invalid for anyone else. pgx.ErrNoRows when unknown.
func (s *Service) replay(ctx context.Context, userID uuid.UUID, store, txID, platform string) (*PurchaseResult, error) {
	r, err := s.findPurchase(ctx, store, txID)
	if err != nil {
		return nil, err
	}
	if r.userID != userID {
		return nil, fmt.Errorf("%w: purchase belongs to another account", ErrInvalid)
	}
	wal, err := wallet.GetTx(ctx, s.pool, userID)
	if errors.Is(err, wallet.ErrNotFound) {
		return nil, ErrUnknownAccount
	}
	if err != nil {
		return nil, err
	}
	var view PackView
	if pk, ok := s.packs.Packs().ByProduct(platform, r.productID); ok {
		view = pk.View(platform)
	} else {
		// A pack removed from the configuration since: what was granted.
		view = PackView{ID: r.productID, ProductID: r.productID, Label: r.productID, Coins: r.coins, Diamonds: r.diamonds}
	}
	return &PurchaseResult{Wallet: wal, Granted: Granted{Coins: r.coins, Diamonds: r.diamonds}, Pack: view,
		Replayed: true}, nil
}

func (s *Service) push(ctx context.Context, userID uuid.UUID, w wallet.Wallet, coins, diamonds int64, reason string) {
	if s.notifier == nil {
		return
	}
	s.notifier.NotifyUser(context.WithoutCancel(ctx), userID, "wallet.updated", map[string]any{
		"coins": w.Coins, "diamonds": w.Diamonds,
		"delta":  map[string]int64{"coins": coins, "diamonds": diamonds},
		"reason": reason,
	})
}

// count records a purchase outcome (bounded labels).
func (s *Service) count(store string, err error, res ...*PurchaseResult) {
	if store == "" {
		store = "unknown"
	}
	result := "error"
	switch {
	case err == nil && len(res) > 0 && res[0] != nil && res[0].Replayed:
		result = "replayed"
	case err == nil:
		result = "granted"
	case errors.Is(err, ErrBadRequest):
		result = "bad_request"
	case errors.Is(err, ErrUnavailable):
		result = "unavailable"
	case errors.Is(err, ErrInvalid):
		result = "invalid"
	case errors.Is(err, ErrPending):
		result = "pending"
	case errors.Is(err, ErrStoreUnreachable):
		result = "unreachable"
	}
	metrics.IAPPurchases.WithLabelValues(store, result).Inc()
}
