// Package legal serves the static open-source notices page
// (GET /legal/open-source). The page is generated from the app's bundled
// license notices by frontend/tool/export_oss_notices.dart and committed as
// config/legal/open-source-notices.html; the app's "Legal notices" entry
// opens it in the external browser.
package legal

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/ratelimit"
)

// Path is the public route of the notices page (outside /api/v1).
const Path = "/legal/open-source"

// MaxFileSize bounds the notices file read into memory.
const MaxFileSize = 16 << 20

// Response headers of the page. The page is static HTML with inline styles
// only: no scripts, images, fonts, frames or forms.
const (
	ContentType  = "text/html; charset=utf-8"
	CSP          = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
	CacheControl = "public, max-age=3600"
)

type page struct {
	raw     []byte
	gz      []byte
	etag    string // strong, quoted; identity encoding
	gzETag  string // strong, quoted; gzip encoding
	modTime time.Time
}

// Notices holds the current page; a missing or unreadable file serves 404.
type Notices struct {
	path string
	log  *slog.Logger
	cur  atomic.Pointer[page]
}

// New loads path. A missing or invalid file is logged (not fatal): the route
// answers 404 until a later Reload succeeds.
func New(path string, log *slog.Logger) *Notices {
	n := &Notices{path: path, log: log}
	if err := n.Reload(); err != nil {
		log.Warn("legal notices unavailable", "file", path, "error", err.Error())
	}
	return n
}

// Loaded reports whether a page is being served.
func (n *Notices) Loaded() bool { return n.cur.Load() != nil }

// Reload re-reads the file. On failure the previously loaded page (if any)
// stays in service.
func (n *Notices) Reload() error {
	p, err := load(n.path)
	if err != nil {
		return err
	}
	n.cur.Store(p)
	return nil
}

func load(path string) (*page, error) {
	if strings.TrimSpace(path) == "" {
		return nil, errors.New("no file configured")
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, err
	}
	if !st.Mode().IsRegular() {
		return nil, errors.New("not a regular file")
	}
	raw, err := io.ReadAll(io.LimitReader(f, MaxFileSize+1))
	if err != nil {
		return nil, err
	}
	if len(raw) == 0 {
		return nil, errors.New("file is empty")
	}
	if len(raw) > MaxFileSize {
		return nil, fmt.Errorf("file exceeds %d bytes", MaxFileSize)
	}
	var buf bytes.Buffer
	zw, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	if _, err := zw.Write(raw); err != nil {
		return nil, err
	}
	if err := zw.Close(); err != nil {
		return nil, err
	}
	sum := sha256.Sum256(raw)
	tag := hex.EncodeToString(sum[:16])
	return &page{raw: raw, gz: buf.Bytes(), etag: `"` + tag + `"`, gzETag: `"` + tag + `-gz"`,
		modTime: st.ModTime().UTC().Truncate(time.Second)}, nil
}

// Run reloads the page on SIGHUP until ctx ends.
func (n *Notices) Run(ctx context.Context) {
	hup := make(chan os.Signal, 1)
	signal.Notify(hup, syscall.SIGHUP)
	defer signal.Stop(hup)
	for {
		select {
		case <-ctx.Done():
			return
		case <-hup:
			if err := n.Reload(); err != nil {
				n.log.Warn("SIGHUP: legal notices reload failed", "file", n.path, "error", err.Error())
			} else {
				n.log.Info("SIGHUP: reloaded legal notices")
			}
		}
	}
}

// Register adds GET (and HEAD) /legal/open-source: no auth, no version gate,
// rate-limited per client IP.
func (n *Notices) Register(rt *httpapi.Router) {
	ip := ratelimit.LegalPerIP
	rt.Handle("GET "+Path, httpapi.Route{Auth: httpapi.AuthNone, IPRule: &ip}, n.serve)
}

func (n *Notices) serve(w http.ResponseWriter, r *http.Request) error {
	p := n.cur.Load()
	if p == nil {
		return httpapi.ErrNotFound
	}
	body, etag := p.raw, p.etag
	h := w.Header()
	h.Set("Vary", "Accept-Encoding")
	if acceptsGzip(r.Header.Get("Accept-Encoding")) {
		body, etag = p.gz, p.gzETag
		h.Set("Content-Encoding", "gzip")
	}
	h.Set("Content-Type", ContentType)
	h.Set("Content-Security-Policy", CSP)
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("Cache-Control", CacheControl)
	h.Set("ETag", etag)
	// ServeContent handles If-None-Match (304), HEAD and ranges.
	http.ServeContent(w, r, "", p.modTime, bytes.NewReader(body))
	return nil
}

// acceptsGzip reports whether an Accept-Encoding value allows gzip: an
// explicit "gzip"/"x-gzip" coding decides; otherwise "*" does; q=0 refuses.
func acceptsGzip(header string) bool {
	explicit, wildcard := -1.0, -1.0
	for _, part := range strings.Split(header, ",") {
		coding, params, _ := strings.Cut(part, ";")
		q := 1.0
		if k, v, ok := strings.Cut(strings.TrimSpace(params), "="); ok && strings.EqualFold(strings.TrimSpace(k), "q") {
			f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
			if err != nil {
				continue
			}
			q = f
		}
		switch strings.ToLower(strings.TrimSpace(coding)) {
		case "gzip", "x-gzip":
			explicit = max(explicit, q)
		case "*":
			wildcard = max(wildcard, q)
		}
	}
	if explicit >= 0 {
		return explicit > 0
	}
	return wildcard > 0
}
