package auth

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"

	"ludoroyale/internal/identity"
	"ludoroyale/internal/profile"
	"ludoroyale/internal/wallet"
)

// Tokens is an issued application session.
type Tokens struct {
	AccessToken           string `json:"accessToken"`
	AccessTokenExpiresAt  int64  `json:"accessTokenExpiresAt"`
	RefreshToken          string `json:"refreshToken"`
	RefreshTokenExpiresAt int64  `json:"refreshTokenExpiresAt"`
}

// Result of a sign-in.
type Result struct {
	Tokens
	UserID      uuid.UUID
	IsNewUser   bool
	Wallet      wallet.Wallet
	GuestSecret string // only for newly created guests
}

// Service implements sign-in, refresh, logout and linking.
type Service struct {
	signer     *Signer
	sessions   *Sessions
	ids        *identity.Store
	profiles   *profile.Service
	verifier   *Verifier
	accessTTL  time.Duration
	refreshTTL time.Duration
	now        func() time.Time
	// OnNewAccount is called after a genuinely new account is created
	// (progression bootstrap, analytics counters). Optional.
	OnNewAccount func(ctx context.Context, userID uuid.UUID)
	// OnSessionReplaced is called after a human sign-in revoked the account's
	// previous session (last sign-in wins); the gateway uses it to close that
	// session's live WebSocket on every instance. Optional.
	OnSessionReplaced func(ctx context.Context, userID uuid.UUID, oldSessionID string)
}

// NewService wires the auth service.
func NewService(signer *Signer, sessions *Sessions, ids *identity.Store, profiles *profile.Service,
	verifier *Verifier, accessTTL, refreshTTL time.Duration) *Service {
	return &Service{signer: signer, sessions: sessions, ids: ids, profiles: profiles, verifier: verifier,
		accessTTL: accessTTL, refreshTTL: refreshTTL, now: time.Now}
}

// Verifier exposes provider verification (used by linking).
func (s *Service) Verifier() *Verifier { return s.verifier }

// issue creates a new human session family for the account. An account has
// one live human session: the previous one (another device) is revoked.
func (s *Service) issue(ctx context.Context, userID uuid.UUID) (Tokens, error) {
	sid, refresh, replaced, err := s.sessions.CreateHuman(ctx, userID)
	if err != nil {
		return Tokens{}, err
	}
	if replaced != "" && s.OnSessionReplaced != nil {
		s.OnSessionReplaced(ctx, userID, replaced)
	}
	return s.access(userID, sid, refresh)
}

func (s *Service) access(userID uuid.UUID, sid, refresh string) (Tokens, error) {
	c := Claims{Kind: KindAccess, SessionID: sid, Actor: ActorHuman}
	c.Subject = userID.String()
	tok, exp, err := s.signer.Sign(c, s.accessTTL)
	if err != nil {
		return Tokens{}, err
	}
	return Tokens{
		AccessToken: tok, AccessTokenExpiresAt: exp.UnixMilli(),
		RefreshToken: refresh, RefreshTokenExpiresAt: s.now().Add(s.refreshTTL).UnixMilli(),
	}, nil
}

// CreateGuest creates a brand-new guest account with a durable guest secret.
func (s *Service) CreateGuest(ctx context.Context) (Result, error) {
	secret := NewSecret("gs_")
	acct, err := s.ids.FindOrCreate(ctx, identity.Guest, HashSecret(secret))
	if err != nil {
		return Result{}, err
	}
	return s.newGuest(ctx, acct, secret)
}

// GuestForDevice signs in to the account bound to the device (deviceSubject
// from identity.DeviceSubject) or, if the device is unbound, creates a new
// guest account bound to it. Only a newly created guest gets a guest secret;
// an existing account never gets a second welcome grant.
func (s *Service) GuestForDevice(ctx context.Context, deviceSubject string) (Result, error) {
	secret := NewSecret("gs_")
	acct, err := s.ids.FindOrCreateDeviceGuest(ctx, deviceSubject, HashSecret(secret))
	if err != nil {
		return Result{}, err
	}
	if !acct.Created {
		return s.signIn(ctx, acct.UserID, false, "")
	}
	return s.newGuest(ctx, acct, secret)
}

// ResumeDevice signs in to the account bound to the device (guest or
// linked). identity.ErrNotFound if no account is bound; never creates one.
func (s *Service) ResumeDevice(ctx context.Context, deviceSubject string) (Result, error) {
	id, err := s.ids.Lookup(ctx, identity.Device, deviceSubject)
	if err != nil {
		return Result{}, err
	}
	return s.signIn(ctx, id, false, "")
}

// newGuest finishes a guest sign-in: profile, session, new-account hook.
func (s *Service) newGuest(ctx context.Context, acct identity.Account, secret string) (Result, error) {
	if _, err := s.saveProfile(ctx, acct.UserID, acct.Created, ""); err != nil {
		return Result{}, err
	}
	toks, err := s.issue(ctx, acct.UserID)
	if err != nil {
		return Result{}, err
	}
	if acct.Created && s.OnNewAccount != nil {
		s.OnNewAccount(ctx, acct.UserID)
	}
	return Result{Tokens: toks, UserID: acct.UserID, IsNewUser: acct.Created, Wallet: acct.Wallet, GuestSecret: secret}, nil
}

// ResumeGuest signs a guest back in with the guest secret.
func (s *Service) ResumeGuest(ctx context.Context, secret string) (Result, error) {
	if len(secret) < 16 || len(secret) > 128 {
		return Result{}, ErrCredentialInvalid
	}
	id, err := s.ids.Lookup(ctx, identity.Guest, HashSecret(secret))
	if errors.Is(err, identity.ErrNotFound) {
		return Result{}, ErrCredentialInvalid
	}
	if err != nil {
		return Result{}, err
	}
	return s.signIn(ctx, id, false, "")
}

// SignInWithProvider resolves a verified identity to an account (creating it
// with the welcome grant only if it is genuinely new) and issues a session.
func (s *Service) SignInWithProvider(ctx context.Context, ident Identity) (Result, error) {
	acct, err := s.ids.FindOrCreate(ctx, ident.Provider, ident.Subject)
	if err != nil {
		return Result{}, err
	}
	if acct.Created && s.OnNewAccount != nil {
		s.OnNewAccount(ctx, acct.UserID)
	}
	return s.signIn(ctx, acct.UserID, acct.Created, ident.Name)
}

func (s *Service) signIn(ctx context.Context, userID uuid.UUID, created bool, name string) (Result, error) {
	// name is the provider's name ("" for guest/device sign-ins); a name the
	// player chose (PATCH /me) always wins over it (profile.Save).
	if _, err := s.saveProfile(ctx, userID, created, name); err != nil {
		return Result{}, err
	}
	toks, err := s.issue(ctx, userID)
	if err != nil {
		return Result{}, err
	}
	w, err := s.ids.Wallet(ctx, userID)
	if err != nil {
		return Result{}, err
	}
	return Result{Tokens: toks, UserID: userID, IsNewUser: created, Wallet: w}, nil
}

// Refresh rotates a refresh token and issues a new access token.
func (s *Service) Refresh(ctx context.Context, refresh string) (Tokens, uuid.UUID, error) {
	sid, uid, actor, newRefresh, err := s.sessions.Rotate(ctx, refresh)
	if err != nil {
		return Tokens{}, uuid.Nil, err
	}
	if actor != ActorHuman {
		return Tokens{}, uuid.Nil, ErrRefreshInvalid
	}
	toks, err := s.access(uid, sid, newRefresh)
	return toks, uid, err
}

// Logout revokes the caller's session family (not reported as replaced).
func (s *Service) Logout(ctx context.Context, p Principal) error {
	return s.sessions.EndHuman(ctx, p.UserID, p.SessionID)
}

// LogoutRefresh revokes the session whose current refresh token is refresh;
// used when the client no longer holds a valid access token. Old (rotated) or
// unknown tokens are ignored without error, so callers cannot probe tokens.
func (s *Service) LogoutRefresh(ctx context.Context, refresh string) error {
	return s.sessions.EndByRefresh(ctx, refresh)
}

// Authenticate validates an access token and that its session is active.
// A dead session yields ErrSessionReplaced (newer sign-in of the account) or
// ErrRevoked (logout, refresh reuse, expiry).
func (s *Service) Authenticate(ctx context.Context, raw string) (Principal, error) {
	c, err := s.signer.Parse(raw)
	if err != nil {
		return Principal{}, err
	}
	if err := s.sessions.Check(ctx, c.SessionID); err != nil {
		return Principal{}, err
	}
	uid, err := uuid.Parse(c.Subject)
	if err != nil {
		return Principal{}, ErrInvalidToken
	}
	return Principal{UserID: uid, SessionID: c.SessionID, Actor: c.Actor, Kind: c.Kind,
		RoomID: c.RoomID, LoadTest: c.LoadTest, BotName: c.BotName}, nil
}

// CheckSession is used by long-lived connections to re-check revocation:
// nil, ErrSessionReplaced, ErrRevoked or a Redis error.
func (s *Service) CheckSession(ctx context.Context, sid string) error {
	return s.sessions.Check(ctx, sid)
}

// Link attaches a verified provider identity to the caller's account. The
// account id, wallet, XP and collection never change and no welcome bonus is
// granted. Conflicts are reported, never merged.
func (s *Service) Link(ctx context.Context, userID uuid.UUID, ident Identity) error {
	if err := s.ids.Link(ctx, userID, ident.Provider, ident.Subject); err != nil {
		return err
	}
	if ident.Name != "" {
		// Adopts the provider's name unless the player chose one.
		_, _ = s.profiles.Save(ctx, userID, ident.Name)
	}
	return nil
}

// saveProfile refreshes the display profile at sign-in; a brand-new account
// has no chosen name, so it skips the PostgreSQL lookup.
func (s *Service) saveProfile(ctx context.Context, userID uuid.UUID, created bool, name string) (profile.Profile, error) {
	if created {
		return s.profiles.SaveNew(ctx, userID, name)
	}
	return s.profiles.Save(ctx, userID, name)
}
