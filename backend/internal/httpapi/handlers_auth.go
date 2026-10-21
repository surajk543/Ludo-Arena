package httpapi

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"ludoroyale/internal/apppolicy"
	"ludoroyale/internal/auth"
	"ludoroyale/internal/identity"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/playerinfo"
	"ludoroyale/internal/profile"
	"ludoroyale/internal/ratelimit"
	"ludoroyale/internal/wallet"
)

// Account bundles the services the account handlers need.
type Account struct {
	Log         *slog.Logger
	Auth        *auth.Service
	IDs         *identity.Store
	Profiles    *profile.Service
	Progression playerinfo.Provider
	Policy      *apppolicy.Store
	Env         string
	Extra       func() map[string]any // extra /app/config fields (entry fees, versions)
	// DeviceKey keys the device-binding subjects (identity.DeviceKey of
	// PUBLIC_ID_KEY); see handlers_device.go.
	DeviceKey []byte
}

// User is the account JSON returned to its owner.
type User struct {
	ID              string            `json:"id"`
	UID             string            `json:"uid"`
	ActorType       string            `json:"actorType"`
	DisplayName     string            `json:"displayName"`
	Avatar          int               `json:"avatar"`
	IsGuest         bool              `json:"isGuest"`
	LinkedProviders []string          `json:"linkedProviders"`
	Level           int               `json:"level"`
	XP              int64             `json:"xp"`
	LevelXP         int64             `json:"levelXp"`
	NextLevelXP     int64             `json:"nextLevelXp"`
	Title           string            `json:"title"`
	Loadout         map[string]string `json:"loadout"`
}

type authResponse struct {
	auth.Tokens
	IsNewUser   bool          `json:"isNewUser"`
	User        User          `json:"user"`
	Wallet      wallet.Wallet `json:"wallet"`
	GuestSecret string        `json:"guestSecret,omitempty"`
}

// Register adds the account routes.
func (a *Account) Register(rt *Router) {
	gated := func(r Route) Route { r.Gate = true; return r }
	authIP, guestIP, refreshIP := ratelimit.AuthPerIP, ratelimit.GuestCreatePerIP, ratelimit.RefreshPerIP
	link, policyIP := ratelimit.LinkPerUser, ratelimit.PolicyPerIP

	rt.Handle("GET /api/v1/app/config", Route{IPRule: &policyIP}, a.appConfig)
	rt.Handle("POST /api/v1/auth/guest", gated(Route{IPRule: &guestIP}), a.guest)
	rt.Handle("POST /api/v1/auth/guest/resume", gated(Route{IPRule: &authIP}), a.guestResume)
	rt.Handle("POST /api/v1/auth/device/resume", gated(Route{IPRule: &authIP}), a.deviceResume)
	rt.Handle("POST /api/v1/auth/google", gated(Route{IPRule: &authIP}), a.provider(identity.Google))
	rt.Handle("POST /api/v1/auth/facebook", gated(Route{IPRule: &authIP}), a.provider(identity.Facebook))
	rt.Handle("POST /api/v1/auth/apple", gated(Route{IPRule: &authIP}), a.provider(identity.Apple))
	rt.Handle("POST /api/v1/auth/refresh", gated(Route{IPRule: &refreshIP}), a.refresh)
	// Logout accepts the access token OR the current refresh token (the access
	// token is often expired by then), so it authenticates in the handler.
	rt.Handle("POST /api/v1/auth/logout", Route{IPRule: &refreshIP}, a.logout)
	rt.Handle("POST /api/v1/account/link/{provider}", gated(Route{Auth: AuthHuman, UserRule: &link}), a.link)
	rt.Handle("PUT /api/v1/account/device", gated(Route{Auth: AuthHuman, UserRule: &link}), a.bindDevice)
	// Like logout, forgetting the device is never blocked by the version
	// gate: it only removes data.
	rt.Handle("DELETE /api/v1/account/device", Route{Auth: AuthHuman, UserRule: &link}, a.unbindDevice)
	rt.Handle("GET /api/v1/me", gated(Route{Auth: AuthHuman}), a.me)
	profileRule := ratelimit.ProfilePerUser
	rt.Handle("PATCH /api/v1/me", gated(Route{Auth: AuthHuman, UserRule: &profileRule}), a.updateMe)
	rt.Handle("GET /api/v1/wallet", gated(Route{Auth: AuthHuman}), a.wallet)
}

func (a *Account) appConfig(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	pick := func(param, header string) string {
		if v := q.Get(param); v != "" {
			return v
		}
		return r.Header.Get(header)
	}
	c, err := apppolicy.ParseClient(pick("platform", "X-App-Platform"), pick("version", "X-App-Version"), pick("build", "X-App-Build"))
	if err != nil {
		return Errf(http.StatusBadRequest, "client_version_required", "platform, version and build are required.")
	}
	if env := q.Get("environment"); env != "" && env != a.Env {
		return Errf(http.StatusBadRequest, "environment_mismatch", "This build targets a different environment.")
	}
	d := a.Policy.Evaluate(c, Locale(r))
	body := map[string]any{}
	// Flatten the decision plus server extras into one documented object.
	for k, v := range structToMap(d) {
		body[k] = v
	}
	if a.Extra != nil {
		for k, v := range a.Extra() {
			body[k] = v
		}
	}
	body["serverTime"] = time.Now().UnixMilli()
	WriteJSON(w, http.StatusOK, body)
	return nil
}

// guest creates a guest account (201), or, with a deviceId, signs in to the
// account bound to that device (200) / creates a guest bound to it (201).
func (a *Account) guest(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		DeviceID *string `json:"deviceId"`
	}
	if err := decodeOptionalJSON(r, &body); err != nil {
		return err
	}
	if body.DeviceID != nil {
		return a.deviceGuest(w, r, *body.DeviceID)
	}
	res, err := a.Auth.CreateGuest(r.Context())
	if err != nil {
		metrics.AuthLogins.WithLabelValues("guest", "error").Inc()
		return err
	}
	metrics.AuthLogins.WithLabelValues("guest", "ok").Inc()
	if res.IsNewUser {
		metrics.AuthAccounts.WithLabelValues("guest").Inc()
	}
	return a.writeAuth(w, r, http.StatusCreated, res)
}

func (a *Account) guestResume(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		GuestSecret string `json:"guestSecret"`
	}
	if err := DecodeJSON(r, &body); err != nil {
		return err
	}
	res, err := a.Auth.ResumeGuest(r.Context(), body.GuestSecret)
	if err != nil {
		metrics.AuthLogins.WithLabelValues("guest_resume", "rejected").Inc()
		return mapAuthErr(err)
	}
	metrics.AuthLogins.WithLabelValues("guest_resume", "ok").Inc()
	return a.writeAuth(w, r, http.StatusOK, res)
}

// verify decodes the provider credential body and verifies it.
func (a *Account) verify(r *http.Request, provider string) (auth.Identity, error) {
	v := a.Auth.Verifier()
	ctx := r.Context()
	switch provider {
	case identity.Google:
		var c auth.GoogleCredential
		if err := DecodeJSON(r, &c); err != nil {
			return auth.Identity{}, err
		}
		return v.Google(ctx, c)
	case identity.Facebook:
		var c auth.FacebookCredential
		if err := DecodeJSON(r, &c); err != nil {
			return auth.Identity{}, err
		}
		return v.Facebook(ctx, c)
	case identity.Apple:
		var c auth.AppleCredential
		if err := DecodeJSON(r, &c); err != nil {
			return auth.Identity{}, err
		}
		return v.Apple(ctx, c)
	}
	return auth.Identity{}, ErrNotFound
}

func (a *Account) provider(provider string) HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		ident, err := a.verify(r, provider)
		if err != nil {
			metrics.AuthLogins.WithLabelValues(provider, "rejected").Inc()
			return mapAuthErr(err)
		}
		res, err := a.Auth.SignInWithProvider(r.Context(), ident)
		if err != nil {
			metrics.AuthLogins.WithLabelValues(provider, "error").Inc()
			return err
		}
		metrics.AuthLogins.WithLabelValues(provider, "ok").Inc()
		if res.IsNewUser {
			metrics.AuthAccounts.WithLabelValues(provider).Inc()
		}
		return a.writeAuth(w, r, http.StatusOK, res)
	}
}

func (a *Account) refresh(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		RefreshToken string `json:"refreshToken"`
	}
	if err := DecodeJSON(r, &body); err != nil {
		return err
	}
	toks, uid, err := a.Auth.Refresh(r.Context(), body.RefreshToken)
	if err != nil {
		metrics.AuthRefresh.WithLabelValues(refreshResult(err)).Inc()
		return mapAuthErr(err)
	}
	metrics.AuthRefresh.WithLabelValues("ok").Inc()
	wal, err := a.IDs.Wallet(r.Context(), uid)
	if err != nil {
		return err
	}
	user, err := a.user(r.Context(), uid)
	if err != nil {
		return err
	}
	WriteJSON(w, http.StatusOK, authResponse{Tokens: toks, User: user, Wallet: wal})
	return nil
}

func refreshResult(err error) string {
	switch {
	case errors.Is(err, auth.ErrRefreshReused):
		return "reused"
	case errors.Is(err, auth.ErrSessionReplaced):
		return "replaced"
	case errors.Is(err, auth.ErrRefreshInvalid):
		return "invalid"
	}
	return "error"
}

// logout ends the caller's session. A valid bearer access token identifies
// the session; otherwise the body's refreshToken does, and only if it is the
// session's current refresh token. The response is 204 whether or not a
// session was found (idempotent; nothing about the token is revealed).
func (a *Account) logout(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		RefreshToken string `json:"refreshToken"`
	}
	if err := decodeOptionalJSON(r, &body); err != nil {
		return err
	}
	ctx := r.Context()
	if tok, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer "); ok && strings.TrimSpace(tok) != "" {
		p, err := a.Auth.Authenticate(ctx, strings.TrimSpace(tok))
		switch {
		case err == nil && p.Kind != auth.KindAccess:
			return ErrForbidden
		case err == nil:
			if err := a.Auth.Logout(ctx, p); err != nil {
				return err
			}
			w.WriteHeader(http.StatusNoContent)
			return nil
		case !errors.Is(err, auth.ErrInvalidToken) && !errors.Is(err, auth.ErrRevoked) &&
			!errors.Is(err, auth.ErrSessionReplaced):
			return err // infrastructure failure, not a credential problem
		}
		// Expired/invalid/dead access token: fall back to the refresh token.
	}
	if body.RefreshToken == "" {
		return Errf(http.StatusUnauthorized, "unauthorized", "A valid access token or the refreshToken is required.")
	}
	if err := a.Auth.LogoutRefresh(ctx, body.RefreshToken); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (a *Account) link(w http.ResponseWriter, r *http.Request) error {
	p, _ := PrincipalFrom(r.Context())
	provider := r.PathValue("provider")
	switch provider {
	case identity.Google, identity.Facebook, identity.Apple:
	default:
		return ErrNotFound
	}
	ident, err := a.verify(r, provider)
	if err != nil {
		metrics.AuthLinks.WithLabelValues(provider, "rejected").Inc()
		return mapAuthErr(err)
	}
	if err := a.Auth.Link(r.Context(), p.UserID, ident); err != nil {
		switch {
		case errors.Is(err, identity.ErrConflict):
			metrics.AuthLinks.WithLabelValues(provider, "conflict").Inc()
			e := Errf(http.StatusConflict, "identity_conflict",
				"This account is already connected to a different game profile. Nothing was merged or moved.")
			e.Details = map[string]string{"provider": provider}
			return e
		case errors.Is(err, identity.ErrProviderTaken):
			metrics.AuthLinks.WithLabelValues(provider, "already_linked").Inc()
			return Errf(http.StatusConflict, "provider_already_linked",
				"Your game profile is already connected to a different account of this provider.")
		}
		return err
	}
	metrics.AuthLinks.WithLabelValues(provider, "ok").Inc()
	return a.writeMe(w, r, p.UserID)
}

func (a *Account) me(w http.ResponseWriter, r *http.Request) error {
	p, _ := PrincipalFrom(r.Context())
	return a.writeMe(w, r, p.UserID)
}

func (a *Account) wallet(w http.ResponseWriter, r *http.Request) error {
	p, _ := PrincipalFrom(r.Context())
	wal, err := a.IDs.Wallet(r.Context(), p.UserID)
	if err != nil {
		return err
	}
	WriteJSON(w, http.StatusOK, wal)
	return nil
}

func (a *Account) writeMe(w http.ResponseWriter, r *http.Request, uid uuid.UUID) error {
	user, err := a.user(r.Context(), uid)
	if err != nil {
		return err
	}
	wal, err := a.IDs.Wallet(r.Context(), uid)
	if err != nil {
		return err
	}
	WriteJSON(w, http.StatusOK, map[string]any{"user": user, "wallet": wal})
	return nil
}

func (a *Account) writeAuth(w http.ResponseWriter, r *http.Request, status int, res auth.Result) error {
	ctx := r.Context()
	if res.IsNewUser {
		ctx = context.WithValue(ctx, newAccountKey{}, true)
	}
	user, err := a.user(ctx, res.UserID)
	if err != nil {
		return err
	}
	WriteJSON(w, status, authResponse{Tokens: res.Tokens, IsNewUser: res.IsNewUser, User: user,
		Wallet: res.Wallet, GuestSecret: res.GuestSecret})
	return nil
}

// user assembles the owner's User view.
func (a *Account) user(ctx context.Context, uid uuid.UUID) (User, error) {
	providers, err := a.IDs.Providers(ctx, uid)
	if err != nil {
		return User{}, err
	}
	if providers == nil {
		providers = []string{}
	}
	isGuest := true
	for _, p := range providers {
		if p != identity.Guest {
			isGuest = false
		}
	}
	prof := a.Profiles.Get(ctx, uid)
	sum, err := a.summary(ctx, uid)
	if err != nil {
		a.Log.Warn("progression summary unavailable", "error", err.Error())
		sum = playerinfo.Starter()
	}
	return User{
		ID: uid.String(), UID: prof.UID, ActorType: auth.ActorHuman, DisplayName: prof.Name,
		Avatar: prof.Avatar, IsGuest: isGuest, LinkedProviders: providers,
		Level: sum.Level, XP: sum.XP, LevelXP: sum.LevelXP, NextLevelXP: sum.NextLevelXP,
		Title: sum.Title, Loadout: sum.Loadout,
	}, nil
}

// newAccountKey marks a request context whose account this request created.
type newAccountKey struct{}

// summary returns the account's progression summary. An account created by
// this very request has the starter summary by definition, so the sign-up
// response skips PostgreSQL; its progression row is created off the request
// path (OnNewAccount) or lazily by the first progression read or write.
func (a *Account) summary(ctx context.Context, uid uuid.UUID) (playerinfo.Summary, error) {
	if created, _ := ctx.Value(newAccountKey{}).(bool); created {
		return playerinfo.Starter(), nil
	}
	return a.Progression.Summary(ctx, uid)
}

// decodeOptionalJSON is DecodeJSON for endpoints whose body may be empty.
func decodeOptionalJSON(r *http.Request, v any) error {
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		return err
	}
	if len(bytes.TrimSpace(raw)) == 0 {
		return nil
	}
	r.Body = io.NopCloser(bytes.NewReader(raw))
	return DecodeJSON(r, v)
}

func mapAuthErr(err error) error {
	var apiErr *APIError
	switch {
	case errors.As(err, &apiErr):
		return apiErr
	case errors.Is(err, auth.ErrProviderUnavailable):
		return Errf(http.StatusServiceUnavailable, "provider_unavailable",
			"This sign-in method is unavailable right now. Please try again or use another method.")
	case errors.Is(err, auth.ErrRefreshReused):
		return Errf(http.StatusUnauthorized, "refresh_reused", "Your session has ended. Please sign in again.")
	case errors.Is(err, auth.ErrSessionReplaced):
		return ErrSessionReplaced
	case errors.Is(err, auth.ErrCredentialInvalid), errors.Is(err, auth.ErrRefreshInvalid):
		return Errf(http.StatusUnauthorized, "invalid_credential", "The sign-in credential is invalid or has expired.")
	}
	return err
}
