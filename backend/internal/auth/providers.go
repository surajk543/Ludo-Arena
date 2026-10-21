package auth

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
)

// Provider verification errors.
var (
	ErrCredentialInvalid   = errors.New("provider credential invalid")
	ErrProviderUnavailable = errors.New("provider not configured or unreachable")
)

// Identity is a verified provider identity. Only the stable subject is used
// for account matching; names are display hints. Emails are never used to
// match or merge accounts.
type Identity struct {
	Provider string
	Subject  string
	Name     string
}

// GoogleCredential is the body of POST /auth/google.
type GoogleCredential struct {
	IDToken string `json:"idToken"`
}

// FacebookCredential is the body of POST /auth/facebook.
type FacebookCredential struct {
	AccessToken string `json:"accessToken"` // classic login
	IDToken     string `json:"idToken"`     // Limited Login (OIDC)
	Nonce       string `json:"nonce"`
}

// AppleCredential is the body of POST /auth/apple.
type AppleCredential struct {
	IdentityToken string `json:"identityToken"`
	RawNonce      string `json:"rawNonce"`
	GivenName     string `json:"givenName"`
	FamilyName    string `json:"familyName"`
}

// ProviderConfig configures verifiers.
type ProviderConfig struct {
	GoogleClientIDs   []string
	GoogleJWKSURL     string
	AppleAudiences    []string
	AppleJWKSURL      string
	FacebookAppID     string
	FacebookAppSecret string
	FacebookJWKSURL   string
	FacebookGraphURL  string
}

// Verifier verifies provider credentials with each provider's official
// mechanism: Google and Apple ID tokens and Facebook Limited Login tokens are
// OIDC JWTs checked against the provider's published JWKS (signature, issuer,
// audience, expiry, subject, nonce); classic Facebook tokens are checked with
// the Graph API debug_token endpoint using the app access token.
type Verifier struct {
	cfg        ProviderConfig
	google     *oidc.IDTokenVerifier
	apple      *oidc.IDTokenVerifier
	facebook   *oidc.IDTokenVerifier
	httpClient *http.Client
}

const (
	googleIssuer   = "https://accounts.google.com"
	appleIssuer    = "https://appleid.apple.com"
	facebookIssuer = "https://www.facebook.com"
)

// NewVerifier builds verifiers for configured providers.
func NewVerifier(ctx context.Context, cfg ProviderConfig) *Verifier {
	hc := &http.Client{Timeout: 5 * time.Second}
	kctx := oidc.ClientContext(ctx, hc)
	v := &Verifier{cfg: cfg, httpClient: hc}
	// Audiences are checked explicitly below because each provider may have
	// several valid client ids (Android/iOS/web, bundle id vs Services ID).
	vc := &oidc.Config{SkipClientIDCheck: true}
	if len(cfg.GoogleClientIDs) > 0 {
		v.google = oidc.NewVerifier(googleIssuer, oidc.NewRemoteKeySet(kctx, cfg.GoogleJWKSURL), vc)
	}
	if len(cfg.AppleAudiences) > 0 {
		v.apple = oidc.NewVerifier(appleIssuer, oidc.NewRemoteKeySet(kctx, cfg.AppleJWKSURL), vc)
	}
	if cfg.FacebookAppID != "" {
		v.facebook = oidc.NewVerifier(facebookIssuer, oidc.NewRemoteKeySet(kctx, cfg.FacebookJWKSURL), vc)
	}
	return v
}

func audienceAllowed(tokenAud []string, allowed []string) bool {
	for _, a := range tokenAud {
		if slices.Contains(allowed, a) {
			return true
		}
	}
	return false
}

func validJWTShape(raw string) bool {
	return len(raw) > 20 && len(raw) < 8192 && strings.Count(raw, ".") == 2
}

// Google verifies a Google ID token.
func (v *Verifier) Google(ctx context.Context, c GoogleCredential) (Identity, error) {
	if v.google == nil {
		return Identity{}, ErrProviderUnavailable
	}
	if !validJWTShape(c.IDToken) {
		return Identity{}, ErrCredentialInvalid
	}
	tok, err := v.google.Verify(ctx, c.IDToken)
	if err != nil {
		return Identity{}, classify(err)
	}
	if !audienceAllowed(tok.Audience, v.cfg.GoogleClientIDs) || tok.Subject == "" {
		return Identity{}, ErrCredentialInvalid
	}
	var claims struct {
		Name      string `json:"name"`
		GivenName string `json:"given_name"`
	}
	_ = tok.Claims(&claims)
	name := claims.GivenName
	if name == "" {
		name = claims.Name
	}
	return Identity{Provider: "google", Subject: tok.Subject, Name: name}, nil
}

// Apple verifies a Sign in with Apple identity token and its nonce.
func (v *Verifier) Apple(ctx context.Context, c AppleCredential) (Identity, error) {
	if v.apple == nil {
		return Identity{}, ErrProviderUnavailable
	}
	if !validJWTShape(c.IdentityToken) || len(c.RawNonce) < 16 || len(c.RawNonce) > 256 {
		return Identity{}, ErrCredentialInvalid
	}
	tok, err := v.apple.Verify(ctx, c.IdentityToken)
	if err != nil {
		return Identity{}, classify(err)
	}
	if !audienceAllowed(tok.Audience, v.cfg.AppleAudiences) || tok.Subject == "" {
		return Identity{}, ErrCredentialInvalid
	}
	sum := sha256.Sum256([]byte(c.RawNonce))
	if subtle.ConstantTimeCompare([]byte(tok.Nonce), []byte(hex.EncodeToString(sum[:]))) != 1 {
		return Identity{}, ErrCredentialInvalid
	}
	// Apple sends the name only on the first authorization, from the client.
	return Identity{Provider: "apple", Subject: tok.Subject, Name: strings.TrimSpace(c.GivenName)}, nil
}

// Facebook verifies a Limited Login ID token or a classic access token.
func (v *Verifier) Facebook(ctx context.Context, c FacebookCredential) (Identity, error) {
	if v.cfg.FacebookAppID == "" {
		return Identity{}, ErrProviderUnavailable
	}
	if c.IDToken != "" {
		if !validJWTShape(c.IDToken) || c.Nonce == "" {
			return Identity{}, ErrCredentialInvalid
		}
		tok, err := v.facebook.Verify(ctx, c.IDToken)
		if err != nil {
			return Identity{}, classify(err)
		}
		if !audienceAllowed(tok.Audience, []string{v.cfg.FacebookAppID}) || tok.Subject == "" {
			return Identity{}, ErrCredentialInvalid
		}
		if subtle.ConstantTimeCompare([]byte(tok.Nonce), []byte(c.Nonce)) != 1 {
			return Identity{}, ErrCredentialInvalid
		}
		var claims struct {
			Name string `json:"name"`
		}
		_ = tok.Claims(&claims)
		return Identity{Provider: "facebook", Subject: tok.Subject, Name: firstName(claims.Name)}, nil
	}
	if v.cfg.FacebookAppSecret == "" {
		return Identity{}, ErrProviderUnavailable
	}
	if len(c.AccessToken) < 20 || len(c.AccessToken) > 4096 {
		return Identity{}, ErrCredentialInvalid
	}
	return v.facebookClassic(ctx, c.AccessToken)
}

func (v *Verifier) facebookClassic(ctx context.Context, userToken string) (Identity, error) {
	q := url.Values{
		"input_token":  {userToken},
		"access_token": {v.cfg.FacebookAppID + "|" + v.cfg.FacebookAppSecret},
	}
	var dbg struct {
		Data struct {
			AppID   string `json:"app_id"`
			IsValid bool   `json:"is_valid"`
			UserID  string `json:"user_id"`
			Expires int64  `json:"expires_at"`
		} `json:"data"`
	}
	if err := v.getJSON(ctx, v.cfg.FacebookGraphURL+"/debug_token?"+q.Encode(), &dbg); err != nil {
		return Identity{}, err
	}
	d := dbg.Data
	if !d.IsValid || d.AppID != v.cfg.FacebookAppID || d.UserID == "" ||
		(d.Expires != 0 && time.Unix(d.Expires, 0).Before(time.Now())) {
		return Identity{}, ErrCredentialInvalid
	}
	var me struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	mq := url.Values{"fields": {"id,name"}, "access_token": {userToken}}
	if err := v.getJSON(ctx, v.cfg.FacebookGraphURL+"/me?"+mq.Encode(), &me); err != nil || me.ID != d.UserID {
		// The identity is already verified by debug_token; the name is optional.
		me.Name = ""
	}
	return Identity{Provider: "facebook", Subject: d.UserID, Name: firstName(me.Name)}, nil
}

func (v *Verifier) getJSON(ctx context.Context, u string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return err
	}
	resp, err := v.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrProviderUnavailable, redactURLError(err))
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return ErrProviderUnavailable
	}
	if resp.StatusCode >= 500 {
		return ErrProviderUnavailable
	}
	if resp.StatusCode != http.StatusOK {
		return ErrCredentialInvalid
	}
	return json.Unmarshal(body, out)
}

// redactURLError strips query strings (which carry tokens) from URL errors.
func redactURLError(err error) string {
	var ue *url.Error
	if errors.As(err, &ue) {
		return ue.Op + ": " + ue.Err.Error()
	}
	return "request failed"
}

func firstName(full string) string {
	full = strings.TrimSpace(full)
	if i := strings.IndexByte(full, ' '); i > 0 {
		return full[:i]
	}
	return full
}

// classify maps go-oidc errors: key-fetch problems are provider outages,
// everything else is an invalid credential.
func classify(err error) error {
	msg := err.Error()
	if strings.Contains(msg, "fetching keys") || strings.Contains(msg, "failed to verify id token signature") && strings.Contains(msg, "fetch") {
		return ErrProviderUnavailable
	}
	return fmt.Errorf("%w: %v", ErrCredentialInvalid, err)
}
