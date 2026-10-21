package httpapi

import (
	"errors"
	"net/http"

	"ludoroyale/internal/identity"
	"ludoroyale/internal/metrics"
)

// Device binding endpoints: restore an account after an app update or
// reinstall from the platform device id (docs/authentication.md "Device
// binding"). The raw device id is only used to derive the stored HMAC
// subject; it is never stored or logged.

var errInvalidDevice = Errf(http.StatusBadRequest, "bad_request",
	"deviceId must be 16-64 characters [A-Za-z0-9-] and X-App-Platform android or ios.")

type deviceBody struct {
	DeviceID string `json:"deviceId"`
}

// deviceSubject validates deviceID and the request's platform (X-App-Platform,
// parsed by the version gate) and returns the binding subject.
func (a *Account) deviceSubject(r *http.Request, deviceID string) (string, error) {
	c, ok := ClientFrom(r.Context())
	if !ok {
		return "", errInvalidDevice
	}
	sub, err := identity.DeviceSubject(a.DeviceKey, string(c.Platform), deviceID)
	if errors.Is(err, identity.ErrInvalidDevice) {
		return "", errInvalidDevice
	}
	return sub, err
}

// deviceGuest is POST /auth/guest with a deviceId: 200 sign-in to the
// device's guest, or 201 for a new guest bound to the device (also after the
// device's previous guest was linked to a provider or deleted).
func (a *Account) deviceGuest(w http.ResponseWriter, r *http.Request, deviceID string) error {
	sub, err := a.deviceSubject(r, deviceID)
	if err != nil {
		metrics.AuthLogins.WithLabelValues("device", "rejected").Inc()
		return err
	}
	res, err := a.Auth.GuestForDevice(r.Context(), sub)
	if err != nil {
		metrics.AuthLogins.WithLabelValues("guest", "error").Inc()
		return err
	}
	if !res.IsNewUser {
		metrics.AuthLogins.WithLabelValues("device", "ok").Inc()
		return a.writeAuth(w, r, http.StatusOK, res)
	}
	metrics.AuthLogins.WithLabelValues("guest", "ok").Inc()
	metrics.AuthAccounts.WithLabelValues("guest").Inc()
	return a.writeAuth(w, r, http.StatusCreated, res)
}

// deviceResume is POST /auth/device/resume: 200 sign-in to the device's
// guest, 404 if the device has none (a linked account is reached only
// through its provider). Never creates an account.
func (a *Account) deviceResume(w http.ResponseWriter, r *http.Request) error {
	var body deviceBody
	if err := DecodeJSON(r, &body); err != nil {
		return err
	}
	sub, err := a.deviceSubject(r, body.DeviceID)
	if err != nil {
		metrics.AuthLogins.WithLabelValues("device", "rejected").Inc()
		return err
	}
	res, err := a.Auth.ResumeDevice(r.Context(), sub)
	if errors.Is(err, identity.ErrNotFound) {
		metrics.AuthLogins.WithLabelValues("device", "not_found").Inc()
		return Errf(http.StatusNotFound, "not_found", "No game profile is linked to this device.")
	}
	if err != nil {
		metrics.AuthLogins.WithLabelValues("device", "error").Inc()
		return err
	}
	metrics.AuthLogins.WithLabelValues("device", "ok").Inc()
	return a.writeAuth(w, r, http.StatusOK, res)
}

// bindDevice is PUT /account/device: binds the device to the caller's guest
// account (replacing the account's previous device). 200 {}; 409
// identity_conflict if the device belongs to another guest; 409 not_a_guest
// if the caller's account is linked (only guests are bound).
func (a *Account) bindDevice(w http.ResponseWriter, r *http.Request) error {
	p, _ := PrincipalFrom(r.Context())
	var body deviceBody
	if err := DecodeJSON(r, &body); err != nil {
		return err
	}
	sub, err := a.deviceSubject(r, body.DeviceID)
	if err != nil {
		metrics.AuthLinks.WithLabelValues("device", "rejected").Inc()
		return err
	}
	if err := a.IDs.BindDevice(r.Context(), p.UserID, sub); err != nil {
		switch {
		case errors.Is(err, identity.ErrConflict):
			metrics.AuthLinks.WithLabelValues("device", "conflict").Inc()
			return Errf(http.StatusConflict, "identity_conflict",
				"This device is already linked to a different game profile. Nothing was merged or moved.")
		case errors.Is(err, identity.ErrNotGuest):
			metrics.AuthLinks.WithLabelValues("device", "not_guest").Inc()
			return Errf(http.StatusConflict, "not_a_guest",
				"Only guest profiles are kept on a device. This profile is reached by signing in with its linked account.")
		}
		return err
	}
	metrics.AuthLinks.WithLabelValues("device", "ok").Inc()
	WriteJSON(w, http.StatusOK, struct{}{})
	return nil
}

// unbindDevice is DELETE /account/device: 204, and the binding is kept.
// App versions before guest persistence call it on a guest sign-out
// ("forget this guest"); a device guest now ends only when it is linked to a
// provider or deleted, so for them too "Play as guest" (POST /auth/guest with
// the device id) brings the same guest back (docs/authentication.md "Guest
// persistence").
func (a *Account) unbindDevice(w http.ResponseWriter, _ *http.Request) error {
	metrics.AuthLinks.WithLabelValues("device", "unbind_ignored").Inc()
	w.WriteHeader(http.StatusNoContent)
	return nil
}
