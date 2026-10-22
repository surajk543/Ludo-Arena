package httpapi

import (
	"errors"
	"fmt"
	"net/http"

	"ludoarena/internal/metrics"
	"ludoarena/internal/profile"
)

// nameMessages are the human-readable messages of invalid_name, by reason.
// Clients localize from details.reason.
var nameMessages = map[string]string{
	profile.ReasonTooShort: fmt.Sprintf("Your name must be at least %d characters long.", profile.NameMinRunes),
	profile.ReasonTooLong:  fmt.Sprintf("Your name can be at most %d characters long.", profile.NameMaxRunes),
	profile.ReasonInvalidCharacters: "Use letters, numbers, spaces, '_', '.' or '-' only, " +
		"with at least one letter. Emoji and symbols are not allowed.",
	profile.ReasonReserved:      "This name is reserved. Please choose another one.",
	profile.ReasonInappropriate: "This name is not allowed. Please choose another one.",
}

// updateMe changes the caller's display name (PATCH /me). The response is
// the same as GET /me.
func (a *Account) updateMe(w http.ResponseWriter, r *http.Request) error {
	p, _ := PrincipalFrom(r.Context())
	var body struct {
		DisplayName *string `json:"displayName"`
	}
	if err := DecodeJSON(r, &body); err != nil {
		return err
	}
	if body.DisplayName == nil {
		return Errf(http.StatusBadRequest, "bad_request", "displayName is required.")
	}
	_, changed, err := a.Profiles.ChangeName(r.Context(), p.UserID, *body.DisplayName)
	var nameErr *profile.NameError
	var limitErr *profile.LimitError
	switch {
	case errors.As(err, &nameErr):
		metrics.ProfileNameChanges.WithLabelValues(nameErr.Reason).Inc()
		e := Errf(http.StatusBadRequest, "invalid_name", nameMessages[nameErr.Reason])
		e.Details = map[string]string{"reason": nameErr.Reason}
		return e
	case errors.As(err, &limitErr):
		metrics.ProfileNameChanges.WithLabelValues("rate_limited").Inc()
		e := Errf(http.StatusTooManyRequests, "rate_limited",
			fmt.Sprintf("You can change your name %d times per day. Please try again later.", limitErr.Limit))
		e.Retry = limitErr.RetryAfter
		e.Details = map[string]any{"reason": "name_change_limit", "limit": limitErr.Limit}
		return e
	case err != nil:
		metrics.ProfileNameChanges.WithLabelValues("error").Inc()
		return err
	}
	if changed {
		metrics.ProfileNameChanges.WithLabelValues("changed").Inc()
	} else {
		metrics.ProfileNameChanges.WithLabelValues("unchanged").Inc()
	}
	return a.writeMe(w, r, p.UserID)
}
