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

// deviceGuest is POST /auth/guest with a deviceId: 200 sign-in to the bound
// account, or 201 for a new guest bound to the device.
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

// deviceResume is POST /auth/device/resume: 200 sign-in to the bound
// account, 404 if the device is not bound. Never creates an account.
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

// bindDevice is PUT /account/device: binds the device to the caller's
// account (replacing the account's previous device). 200 {}; 409
// identity_conflict if the device belongs to another account.
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
		if errors.Is(err, identity.ErrConflict) {
			metrics.AuthLinks.WithLabelValues("device", "conflict").Inc()
			return Errf(http.StatusConflict, "identity_conflict",
				"This device is already linked to a different game profile. Nothing was merged or moved.")
		}
		return err
	}
	metrics.AuthLinks.WithLabelValues("device", "ok").Inc()
	WriteJSON(w, http.StatusOK, struct{}{})
	return nil
}

// unbindDevice is DELETE /account/device: removes the caller's device
// binding. 204, idempotent.
func (a *Account) unbindDevice(w http.ResponseWriter, r *http.Request) error {
	p, _ := PrincipalFrom(r.Context())
	if err := a.IDs.UnbindDevice(r.Context(), p.UserID); err != nil {
		return err
	}
	metrics.AuthLinks.WithLabelValues("device", "removed").Inc()
	w.WriteHeader(http.StatusNoContent)
	return nil
}
