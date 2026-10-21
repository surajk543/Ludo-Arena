package tests

import (
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
)

// The open-source notices page is public: no auth, no X-App-* headers, no
// version gate (it opens in the external browser), served as locked-down HTML.
func TestLegalNoticesRoute(t *testing.T) {
	page := "<!doctype html><title>Ludo Royale — Open-source notices</title><pre>license text</pre>"
	path := filepath.Join(t.TempDir(), "open-source-notices.html")
	writeFile(t, path, page)
	t.Setenv("LEGAL_NOTICES_FILE", path)
	e := newEnv(t, envOpts{})

	// Even with maintenance on, the legal page stays reachable.
	writeFile(t, e.flag, "maintenance")
	if err := e.app.Policy.Reload(); err != nil {
		t.Fatal(err)
	}
	if r := e.do("POST", "/api/v1/auth/guest", "", map[string]any{}); r.Status != http.StatusServiceUnavailable {
		t.Fatalf("maintenance not active: %d", r.Status)
	}

	res, err := http.Get(e.srv.URL + "/legal/open-source") // transport adds gzip and decodes
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(res.Body)
	_ = res.Body.Close()
	if res.StatusCode != http.StatusOK || string(body) != page {
		t.Fatalf("status %d body %q", res.StatusCode, body)
	}
	if !res.Uncompressed {
		t.Error("expected a gzip-encoded response for a gzip-capable client")
	}
	for k, want := range map[string]string{
		"Content-Type":            "text/html; charset=utf-8",
		"X-Content-Type-Options":  "nosniff",
		"Cache-Control":           "public, max-age=3600",
		"Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'",
	} {
		if got := res.Header.Get(k); !strings.HasPrefix(got, want) {
			t.Errorf("%s = %q, want prefix %q", k, got, want)
		}
	}
}

func TestLegalNoticesMissingFile(t *testing.T) {
	t.Setenv("LEGAL_NOTICES_FILE", filepath.Join(t.TempDir(), "missing.html"))
	e := newEnv(t, envOpts{})
	res, err := http.Get(e.srv.URL + "/legal/open-source")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(res.Body)
	_ = res.Body.Close()
	if res.StatusCode != http.StatusNotFound || !strings.Contains(string(body), `"not_found"`) {
		t.Fatalf("missing file: %d %s", res.StatusCode, body)
	}
}
