package auth

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"time"

	"github.com/google/uuid"
)

// botControllerID is the fixed subject of bot-service controller tokens.
var botControllerID = uuid.MustParse("00000000-0000-4000-8000-00000000b075")

// BotAuth authenticates the separate bot-play service. The service presents a
// shared key (stored only as its SHA-256 here) to obtain short-lived
// controller tokens, and the backend issues per-bot session tokens scoped to
// one room assignment (or the isolated load-test pool). Bot status is derived
// from these server-issued tokens, never from client-supplied fields.
type BotAuth struct {
	keyHash  []byte
	signer   *Signer
	sessions *Sessions
}

// NewBotAuth returns a BotAuth; keyHash empty disables the bot boundary.
func NewBotAuth(keyHash []byte, signer *Signer, sessions *Sessions) *BotAuth {
	return &BotAuth{keyHash: keyHash, signer: signer, sessions: sessions}
}

// Enabled reports whether a service key is configured.
func (b *BotAuth) Enabled() bool { return len(b.keyHash) == sha256.Size }

// VerifyServiceKey checks the presented key in constant time.
func (b *BotAuth) VerifyServiceKey(key string) bool {
	if !b.Enabled() || len(key) < 32 || len(key) > 256 {
		return false
	}
	sum := sha256.Sum256([]byte(key))
	return subtle.ConstantTimeCompare(sum[:], b.keyHash) == 1
}

// IssueController returns a 15-minute controller token.
func (b *BotAuth) IssueController(ctx context.Context) (string, time.Time, error) {
	sid, err := b.sessions.CreateBot(ctx, botControllerID, 16*time.Minute, map[string]any{"kind": KindBotController})
	if err != nil {
		return "", time.Time{}, err
	}
	c := Claims{Kind: KindBotController, SessionID: sid, Actor: ActorBot}
	c.Subject = botControllerID.String()
	return b.signer.Sign(c, 15*time.Minute)
}

// BotSession describes an issued bot player session.
type BotSession struct {
	BotID     uuid.UUID
	SessionID string
	Token     string
	ExpiresAt time.Time
}

// IssueBot creates a bot player session scoped to roomID (or the load-test
// pool when loadTest is true) for bot user id botID (uuid.Nil: a new random
// id). The rooms engine passes a bot persona's stable id, leased to one live
// session at a time.
func (b *BotAuth) IssueBot(ctx context.Context, botID uuid.UUID, roomID string, loadTest bool, name, profile string, ttl time.Duration) (BotSession, error) {
	if botID == uuid.Nil {
		botID = uuid.New()
	}
	sid, err := b.sessions.CreateBot(ctx, botID, ttl, map[string]any{"kind": KindBot, "room": roomID})
	if err != nil {
		return BotSession{}, err
	}
	c := Claims{Kind: KindBot, SessionID: sid, Actor: ActorBot, RoomID: roomID, LoadTest: loadTest, BotName: name, Profile: profile}
	c.Subject = botID.String()
	tok, exp, err := b.signer.Sign(c, ttl)
	if err != nil {
		return BotSession{}, err
	}
	return BotSession{BotID: botID, SessionID: sid, Token: tok, ExpiresAt: exp}, nil
}

// Revoke ends a bot or controller session.
func (b *BotAuth) Revoke(ctx context.Context, sid string) error { return b.sessions.Revoke(ctx, sid) }
