package legal

import (
	"bytes"
	"compress/gzip"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ludoarena/internal/httpapi"
)

const pageV1 = "<!doctype html><title>Open-source notices</title><pre>MIT License</pre>"

func newServer(t *testing.T, path string) (*Notices, *httptest.Server) {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	n := New(path, log)
	rt := httpapi.NewRouter(log, nil, nil, nil, 0)
	n.Register(rt)
	srv := httptest.NewServer(rt.Mux())
	t.Cleanup(srv.Close)
	return n, srv
}

func get(t *testing.T, url string, headers ...string) (*http.Response, []byte) {
	t.Helper()
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	// The transport would add Accept-Encoding: gzip and decode transparently;
	// an explicit header keeps the raw body under test control.
	if req.Header.Get("Accept-Encoding") == "" {
		req.Header.Set("Accept-Encoding", "identity")
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	return res, body
}

func writePage(t *testing.T, path, body string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestServesPageWithSecurityHeaders(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notices.html")
	writePage(t, path, pageV1)
	_, srv := newServer(t, path)

	res, body := get(t, srv.URL+Path)
	if res.StatusCode != http.StatusOK || string(body) != pageV1 {
		t.Fatalf("status %d body %q", res.StatusCode, body)
	}
	for k, want := range map[string]string{
		"Content-Type":            "text/html; charset=utf-8",
		"Content-Security-Policy": CSP,
		"X-Content-Type-Options":  "nosniff",
		"Referrer-Policy":         "no-referrer",
		"Cache-Control":           "public, max-age=3600",
		"Vary":                    "Accept-Encoding",
	} {
		if got := res.Header.Get(k); got != want {
			t.Errorf("%s = %q, want %q", k, got, want)
		}
	}
	if !strings.HasPrefix(CSP, "default-src 'none'; style-src 'unsafe-inline'") {
		t.Fatalf("CSP too loose: %s", CSP)
	}
	if res.Header.Get("Content-Encoding") != "" || res.Header.Get("ETag") == "" || res.Header.Get("Last-Modified") == "" {
		t.Fatalf("identity response headers: %v", res.Header)
	}

	// HEAD: same headers, no body.
	req, _ := http.NewRequest(http.MethodHead, srv.URL+Path, nil)
	req.Header.Set("Accept-Encoding", "identity")
	head, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = head.Body.Close()
	if head.StatusCode != http.StatusOK || head.Header.Get("Content-Type") != ContentType {
		t.Fatalf("HEAD: %d %v", head.StatusCode, head.Header)
	}
	// Other methods are not routed.
	post, err := http.Post(srv.URL+Path, "text/plain", strings.NewReader("x"))
	if err != nil {
		t.Fatal(err)
	}
	_ = post.Body.Close()
	if post.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("POST: %d", post.StatusCode)
	}
}

func TestGzipVariantAndConditionalRequests(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notices.html")
	page := strings.Repeat(pageV1, 50)
	writePage(t, path, page)
	_, srv := newServer(t, path)

	res, body := get(t, srv.URL+Path, "Accept-Encoding", "br, gzip;q=0.8")
	if res.StatusCode != http.StatusOK || res.Header.Get("Content-Encoding") != "gzip" {
		t.Fatalf("gzip: %d %v", res.StatusCode, res.Header)
	}
	zr, err := gzip.NewReader(bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	plain, _ := io.ReadAll(zr)
	if string(plain) != page || len(body) >= len(plain) {
		t.Fatalf("gzip body: %d compressed, %d plain", len(body), len(plain))
	}
	gzTag := res.Header.Get("ETag")

	idRes, _ := get(t, srv.URL+Path)
	idTag := idRes.Header.Get("ETag")
	if gzTag == "" || idTag == "" || gzTag == idTag {
		t.Fatalf("ETags must differ per encoding: %q %q", gzTag, idTag)
	}

	if res, body := get(t, srv.URL+Path, "If-None-Match", idTag); res.StatusCode != http.StatusNotModified || len(body) != 0 {
		t.Fatalf("If-None-Match: %d (%d bytes)", res.StatusCode, len(body))
	}
	if res, _ := get(t, srv.URL+Path, "Accept-Encoding", "gzip", "If-None-Match", gzTag); res.StatusCode != http.StatusNotModified {
		t.Fatalf("If-None-Match (gzip): %d", res.StatusCode)
	}
	if res, _ := get(t, srv.URL+Path, "If-None-Match", `"other"`); res.StatusCode != http.StatusOK {
		t.Fatalf("stale ETag: %d", res.StatusCode)
	}
	if res, _ := get(t, srv.URL+Path, "Accept-Encoding", "gzip;q=0"); res.Header.Get("Content-Encoding") != "" {
		t.Fatal("q=0 must refuse gzip")
	}
}

func TestMissingFileServes404UntilReload(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notices.html")
	n, srv := newServer(t, path)
	if n.Loaded() {
		t.Fatal("missing file reported as loaded")
	}
	res, body := get(t, srv.URL+Path)
	if res.StatusCode != http.StatusNotFound || !strings.Contains(string(body), `"not_found"`) {
		t.Fatalf("missing: %d %s", res.StatusCode, body)
	}

	writePage(t, path, pageV1)
	if err := n.Reload(); err != nil {
		t.Fatal(err)
	}
	if res, body := get(t, srv.URL+Path); res.StatusCode != http.StatusOK || string(body) != pageV1 {
		t.Fatalf("after reload: %d %q", res.StatusCode, body)
	}

	// A new version replaces the page; a failed reload keeps the last good one.
	writePage(t, path, "<p>v2</p>")
	if err := n.Reload(); err != nil {
		t.Fatal(err)
	}
	if _, body := get(t, srv.URL+Path); string(body) != "<p>v2</p>" {
		t.Fatalf("v2 not served: %q", body)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := n.Reload(); err == nil {
		t.Fatal("reload of a missing file must fail")
	}
	if res, body := get(t, srv.URL+Path); res.StatusCode != http.StatusOK || string(body) != "<p>v2</p>" {
		t.Fatalf("last good page dropped: %d %q", res.StatusCode, body)
	}
}

func TestRejectsEmptyOversizedAndDirectory(t *testing.T) {
	dir := t.TempDir()
	empty := filepath.Join(dir, "empty.html")
	writePage(t, empty, "")
	big := filepath.Join(dir, "big.html")
	f, err := os.Create(big)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.Truncate(MaxFileSize + 1); err != nil {
		t.Fatal(err)
	}
	_ = f.Close()
	for _, p := range []string{"", dir, empty, big, filepath.Join(dir, "missing.html")} {
		if _, err := load(p); err == nil {
			t.Errorf("load(%q) succeeded", p)
		}
	}
}

func TestAcceptsGzip(t *testing.T) {
	cases := map[string]bool{
		"":                   false,
		"identity":           false,
		"gzip":               true,
		"GZIP":               true,
		"deflate, gzip;q=1":  true,
		"br;q=1, gzip;q=0.5": true,
		"gzip;q=0":           false,
		"gzip; q=0.000":      false,
		"*":                  true,
		"*;q=0":              false,
		"gzip;q=0, *":        false,
		"x-gzip":             true,
	}
	for in, want := range cases {
		if got := acceptsGzip(in); got != want {
			t.Errorf("acceptsGzip(%q) = %v, want %v", in, got, want)
		}
	}
}
