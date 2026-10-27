package httpapi

import (
	"crypto/sha256"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAdminAuthorized(t *testing.T) {
	sum := sha256.Sum256([]byte("operator-key"))
	if !AdminAuthorized(sum[:], "operator-key") {
		t.Fatal("right key refused")
	}
	for _, k := range []string{"", "operator-key ", "Operator-key", "x"} {
		if AdminAuthorized(sum[:], k) {
			t.Fatalf("key %q accepted", k)
		}
	}
	if AdminAuthorized(nil, "operator-key") || AdminAuthorized(sum[:4], "operator-key") {
		t.Fatal("unconfigured hash accepted")
	}
}

func TestAdminGuard(t *testing.T) {
	sum := sha256.Sum256([]byte("operator-key"))
	ok := func(w http.ResponseWriter, _ *http.Request) error {
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	for _, c := range []struct {
		name   string
		hash   []byte
		key    string
		status int // of the returned APIError; 0 = handler ran
	}{
		{"disabled", nil, "operator-key", http.StatusNotFound},
		{"disabled, malformed hash", sum[:16], "operator-key", http.StatusNotFound},
		{"missing key", sum[:], "", http.StatusUnauthorized},
		{"wrong key", sum[:], "operator-kez", http.StatusUnauthorized},
		{"right key", sum[:], "operator-key", 0},
	} {
		t.Run(c.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", "/api/v1/admin/ops/online", nil)
			if c.key != "" {
				r.Header.Set(AdminKeyHeader, c.key)
			}
			w := httptest.NewRecorder()
			err := Admin(c.hash, ok)(w, r)
			var apiErr *APIError
			switch {
			case c.status == 0 && (err != nil || w.Code != http.StatusNoContent):
				t.Fatalf("handler did not run: %v %d", err, w.Code)
			case c.status != 0 && (!errors.As(err, &apiErr) || apiErr.Status != c.status):
				t.Fatalf("err = %v, want status %d", err, c.status)
			case c.status != 0 && w.Code != http.StatusOK: // recorder default: nothing written
				t.Fatalf("handler wrote %d", w.Code)
			}
		})
	}
}
