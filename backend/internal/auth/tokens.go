// Package auth owns application authentication: provider credential
// verification (Google, Facebook, Apple), guest accounts, application access
// and refresh tokens, refresh-token rotation, revocation, account linking and
// bot-service sessions. Firebase Authentication is not used anywhere.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// Actor types (server-determined; clients cannot claim them).
const (
	ActorHuman = "human"
	ActorBot   = "bot"
)

// Token kinds.
const (
	KindAccess        = "access"
	KindBot           = "bot"
	KindBotController = "bot_controller"
)

// Claims are the application access-token claims.
type Claims struct {
	jwt.RegisteredClaims
	Kind      string `json:"knd"`
	SessionID string `json:"sid"`
	Actor     string `json:"act"`
	RoomID    string `json:"rid,omitempty"` // bot sessions: the only room the bot may play in
	LoadTest  bool   `json:"lt,omitempty"`  // bot sessions in the isolated load-test pool
	BotName   string `json:"bnm,omitempty"`
	Profile   string `json:"bpr,omitempty"`
}

// Principal is an authenticated caller.
type Principal struct {
	UserID    uuid.UUID
	SessionID string
	Actor     string
	Kind      string
	RoomID    string
	LoadTest  bool
	BotName   string
}

// IsBot reports whether the caller is a bot player session.
func (p Principal) IsBot() bool { return p.Kind == KindBot }

// Errors.
var (
	ErrInvalidToken = errors.New("invalid token")
	ErrRevoked      = errors.New("session revoked")
	// ErrSessionReplaced: the session was revoked because the same account
	// signed in again (normally on another device). Clients surface it as
	// "signed in on another device" and do not silently re-authenticate.
	ErrSessionReplaced = errors.New("session replaced by a newer sign-in")
)

// Signer issues and verifies HS256 application tokens.
type Signer struct {
	key    []byte
	issuer string
	now    func() time.Time
}

// NewSigner returns a Signer.
func NewSigner(key []byte, issuer string) *Signer {
	return &Signer{key: key, issuer: issuer, now: time.Now}
}

// Sign issues a token with the given claims and TTL.
func (s *Signer) Sign(c Claims, ttl time.Duration) (string, time.Time, error) {
	now := s.now()
	exp := now.Add(ttl)
	c.Issuer = s.issuer
	c.IssuedAt = jwt.NewNumericDate(now)
	c.NotBefore = jwt.NewNumericDate(now.Add(-5 * time.Second))
	c.ExpiresAt = jwt.NewNumericDate(exp)
	c.ID = randomID(12)
	tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(s.key)
	return tok, exp, err
}

// Parse verifies signature, algorithm, issuer and expiry.
func (s *Signer) Parse(raw string) (*Claims, error) {
	c := &Claims{}
	_, err := jwt.ParseWithClaims(raw, c, func(t *jwt.Token) (any, error) {
		return s.key, nil
	},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(s.issuer),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(s.now),
		jwt.WithLeeway(5*time.Second),
	)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}
	if c.SessionID == "" || c.Subject == "" {
		return nil, ErrInvalidToken
	}
	switch c.Kind {
	case KindAccess, KindBot, KindBotController:
	default:
		return nil, ErrInvalidToken
	}
	return c, nil
}

// randomID returns n random bytes as URL-safe base64.
func randomID(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err) // crypto/rand never fails on supported platforms
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// NewSecret returns a high-entropy opaque secret with a prefix.
func NewSecret(prefix string) string { return prefix + randomID(32) }

// HashSecret returns hex(sha256(secret)); only hashes are stored server-side.
func HashSecret(secret string) string {
	sum := sha256.Sum256([]byte(secret))
	return hex.EncodeToString(sum[:])
}
