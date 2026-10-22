package main

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"ludoarena/internal/assets"
	"ludoarena/internal/assets/r2test"
)

const (
	secret = "import-test-secret-value"
	keyID  = "AKIDIMPORT"
)

var testManifest = assets.ManifestHeader + "\n" +
	"pp_one\tOne\tlottie\tprofile_pictures/one.json\tprofile_pictures/lottie_animation/one.json\t10\t10\n" +
	"pp_two\tTwo\tlottie\tprofile_pictures/two.json\tprofile_pictures/lottie_animation/two.json\t20\t20\n" +
	"pp_three\tThree\timage\tprofile_pictures/three.png\tprofile_pictures/image/three.png\t5\t30\n"

// source is a fake public copy (King Teen Patti's CDN).
type source struct {
	*httptest.Server
	mu    sync.Mutex
	files map[string][]byte
	gets  int
}

func newSource(t *testing.T) *source {
	s := &source{files: map[string][]byte{
		"/profile_pictures/one.json":  []byte(`{"v":"5.7.4","layers":[]}`),
		"/profile_pictures/two.json":  []byte(`{"v":"5.7.4","layers":[{"ty":4}]}`),
		"/profile_pictures/three.png": append([]byte("\x89PNG\r\n\x1a\n"), bytes.Repeat([]byte{1}, 40)...),
	}}
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		b, ok := s.files[r.URL.Path]
		if r.Method == http.MethodGet {
			s.gets++
		}
		s.mu.Unlock()
		if !ok {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Length", strconv.Itoa(len(b)))
		if r.Method == http.MethodGet {
			_, _ = w.Write(b)
		}
	}))
	t.Cleanup(s.Close)
	return s
}

func (s *source) set(path string, b []byte) { s.mu.Lock(); s.files[path] = b; s.mu.Unlock() }

func (s *source) getCount() int { s.mu.Lock(); defer s.mu.Unlock(); return s.gets }

func TestMain(m *testing.M) {
	retryDelay = time.Millisecond
	os.Exit(m.Run())
}

func setup(t *testing.T, manifest string) (options, *r2test.Server, *source) {
	t.Helper()
	r2 := r2test.New(t, "ludo-arena", keyID, secret)
	src := newSource(t)
	path := filepath.Join(t.TempDir(), "profile_pictures.tsv")
	if err := os.WriteFile(path, []byte(manifest), 0o600); err != nil {
		t.Fatal(err)
	}
	return options{Manifest: path, Source: src.URL, Concurrency: 2,
		R2: assets.Config{AccountID: "0123456789abcdef0123456789abcdef", Bucket: "ludo-arena",
			AccessKeyID: keyID, SecretAccessKey: secret, Endpoint: r2.URL}}, r2, src
}

func runOK(t *testing.T, o options) (summary, string) {
	t.Helper()
	var out bytes.Buffer
	sum, err := run(context.Background(), o, &out)
	if err != nil {
		t.Fatalf("run: %v\n%s", err, out.String())
	}
	if strings.Contains(out.String(), secret) {
		t.Fatal("output contains the secret")
	}
	return sum, out.String()
}

func TestImportUploadsVerifiesAndSkipsOnRerun(t *testing.T) {
	o, r2, src := setup(t, testManifest)

	// Dry run: nothing written.
	dry := o
	dry.DryRun = true
	sum, out := runOK(t, dry)
	if sum.WouldUpload != 3 || sum.Uploaded != 0 || sum.Failed != 0 || r2.Count(http.MethodPut) != 0 {
		t.Fatalf("dry run %+v puts %d\n%s", sum, r2.Count(http.MethodPut), out)
	}

	sum, out = runOK(t, o)
	if sum.Uploaded != 3 || sum.Failed != 0 {
		t.Fatalf("import %+v\n%s", sum, out)
	}
	for _, c := range []struct{ key, src, ct string }{
		{"profile_pictures/lottie_animation/one.json", "/profile_pictures/one.json", "application/json"},
		{"profile_pictures/lottie_animation/two.json", "/profile_pictures/two.json", "application/json"},
		{"profile_pictures/image/three.png", "/profile_pictures/three.png", "image/png"},
	} {
		obj, ok := r2.Object(c.key)
		if !ok || !bytes.Equal(obj.Body, src.files[c.src]) || obj.ContentType != c.ct ||
			obj.CacheControl != "private, max-age=31536000, immutable" {
			t.Fatalf("%s stored %+v %v", c.key, obj, ok)
		}
	}
	if r2.Denied() != 0 {
		t.Fatalf("%d requests refused by the fake R2's signature check", r2.Denied())
	}

	// Re-run: same sizes → skipped without downloading or uploading.
	puts, gets := r2.Count(http.MethodPut), src.getCount()
	sum, out = runOK(t, o)
	if sum.Skipped != 3 || sum.Uploaded != 0 || r2.Count(http.MethodPut) != puts || src.getCount() != gets {
		t.Fatalf("rerun %+v puts %d→%d gets %d→%d\n%s", sum, puts, r2.Count(http.MethodPut), gets, src.getCount(), out)
	}

	// A truncated object (different size) is replaced.
	r2.Seed("profile_pictures/lottie_animation/two.json", []byte(`{"v"`), "application/json", "")
	sum, out = runOK(t, o)
	if sum.Uploaded != 1 || sum.Skipped != 2 || !strings.Contains(out, "replaces 4 B") {
		t.Fatalf("repair %+v\n%s", sum, out)
	}
}

func TestImportFailsBadSourcesWithoutUploading(t *testing.T) {
	o, r2, src := setup(t, testManifest)
	src.set("/profile_pictures/one.json", []byte(`<html>not json</html>`))
	src.set("/profile_pictures/three.png", []byte(`GIF89a`))
	src.mu.Lock()
	delete(src.files, "/profile_pictures/two.json")
	src.mu.Unlock()
	sum, out := runOK(t, o)
	if sum.Failed != 3 || sum.Uploaded != 0 || r2.Count(http.MethodPut) != 0 {
		t.Fatalf("bad sources %+v puts %d\n%s", sum, r2.Count(http.MethodPut), out)
	}
	for _, want := range []string{"not a JSON object", "not a PNG", "HTTP 404"} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
}

func TestImportRefusesBadConfig(t *testing.T) {
	o, _, _ := setup(t, testManifest)
	var out bytes.Buffer

	partial := o
	partial.R2.SecretAccessKey = ""
	if _, err := run(context.Background(), partial, &out); err == nil || !strings.Contains(err.Error(), "R2_SECRET_ACCESS_KEY") {
		t.Fatalf("partial config: %v", err)
	}
	none := o
	none.R2 = assets.Config{}
	if _, err := run(context.Background(), none, &out); err == nil || !strings.Contains(err.Error(), "not configured") {
		t.Fatalf("no config: %v", err)
	}
	// A dry run needs no credentials.
	none.DryRun = true
	if sum, err := run(context.Background(), none, &out); err != nil || sum.WouldUpload != 3 {
		t.Fatalf("dry run without R2: %+v %v", sum, err)
	}
	wrong := o
	wrong.R2.SecretAccessKey = "not-the-secret"
	sum, err := run(context.Background(), wrong, &out)
	if err != nil || sum.Failed != 3 || strings.Contains(out.String(), "not-the-secret") {
		t.Fatalf("wrong secret: %+v %v", sum, err)
	}
	badManifest := o
	badManifest.Manifest = filepath.Join(t.TempDir(), "missing.tsv")
	if _, err := run(context.Background(), badManifest, &out); err == nil {
		t.Fatal("missing manifest accepted")
	}
}

func TestOnlyFilter(t *testing.T) {
	o, r2, _ := setup(t, testManifest)
	o.Only = map[string]bool{"pp_two": true}
	sum, _ := runOK(t, o)
	if sum.Uploaded != 1 || len(r2.Keys()) != 1 {
		t.Fatalf("only: %+v keys %v", sum, r2.Keys())
	}
}

// The committed manifest is importable (dry run against a source that has
// every file; no network).
func TestCommittedManifestDryRun(t *testing.T) {
	f, err := os.Open("../../config/profile_pictures.tsv")
	if err != nil {
		t.Fatal(err)
	}
	rows, err := assets.ReadPictureManifest(f)
	f.Close()
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".png") {
			_, _ = w.Write([]byte("\x89PNG\r\n\x1a\nxx"))
			return
		}
		_, _ = w.Write([]byte(`{"layers":[]}`))
	}))
	defer srv.Close()
	var out bytes.Buffer
	sum, err := run(context.Background(), options{Manifest: "../../config/profile_pictures.tsv", Source: srv.URL,
		DryRun: true, Concurrency: 8}, &out)
	if err != nil || sum.WouldUpload != len(rows) || sum.Failed != 0 {
		t.Fatalf("dry run %+v %v\n%s", sum, err, out.String())
	}
}
