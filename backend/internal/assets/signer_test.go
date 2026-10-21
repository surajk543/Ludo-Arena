package assets_test

import (
	"context"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"ludoroyale/internal/assets"
	"ludoroyale/internal/assets/r2test"
)

const (
	testBucket  = "ludo-royale"
	testKeyID   = "AKIDTEST0123"
	testSecret  = "test-secret-not-real"
	testAccount = "0123456789abcdef0123456789abcdef"
	lottieKey   = "profile_pictures/lottie_animation/angry-tortoise.json"
)

func fakeConfig(r2 *r2test.Server) assets.Config {
	return assets.Config{AccountID: testAccount, Bucket: testBucket, AccessKeyID: testKeyID,
		SecretAccessKey: testSecret, Endpoint: r2.URL}
}

func get(t *testing.T, u string) (int, []byte) {
	t.Helper()
	res, err := http.Get(u)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	return res.StatusCode, b
}

func TestConfigAllOrNone(t *testing.T) {
	full := assets.Config{AccountID: testAccount, Bucket: testBucket, AccessKeyID: testKeyID, SecretAccessKey: testSecret}
	if err := full.Validate(); err != nil {
		t.Fatalf("full config: %v", err)
	}
	if (assets.Config{}).Configured() {
		t.Fatal("empty config reported as configured")
	}
	cases := []struct {
		name string
		mut  func(*assets.Config)
		want string
	}{
		{"no secret", func(c *assets.Config) { c.SecretAccessKey = "" }, "R2_SECRET_ACCESS_KEY"},
		{"no bucket", func(c *assets.Config) { c.Bucket = "" }, "R2_BUCKET"},
		{"no account", func(c *assets.Config) { c.AccountID = "" }, "R2_ACCOUNT_ID"},
		{"no key id", func(c *assets.Config) { c.AccessKeyID = "" }, "R2_ACCESS_KEY_ID"},
		{"bad account", func(c *assets.Config) { c.AccountID = "not an id!" }, "R2_ACCOUNT_ID"},
		{"bad bucket", func(c *assets.Config) { c.Bucket = "Bad_Bucket" }, "R2_BUCKET"},
		{"bad endpoint", func(c *assets.Config) { c.Endpoint = "ftp://x" }, "R2_ENDPOINT"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			cfg := full
			c.mut(&cfg)
			if !cfg.Configured() {
				t.Fatal("partial config reported as unconfigured")
			}
			err := cfg.Validate()
			if err == nil || !strings.Contains(err.Error(), c.want) {
				t.Fatalf("error %v, want mention of %s", err, c.want)
			}
			if strings.Contains(err.Error(), testSecret) {
				t.Fatal("error leaks the secret")
			}
		})
	}
}

func TestSignerTTLBounds(t *testing.T) {
	cfg := assets.Config{AccountID: testAccount, Bucket: testBucket, AccessKeyID: testKeyID, SecretAccessKey: testSecret}
	for _, ttl := range []time.Duration{30 * time.Second, 2 * time.Hour} {
		if _, err := assets.NewSigner(cfg, ttl, nil); err == nil {
			t.Errorf("ttl %s accepted", ttl)
		}
	}
	s, err := assets.NewSigner(cfg, 0, nil)
	if err != nil || s.TTL() != assets.DefaultURLTTL {
		t.Fatalf("default ttl: %v %v", s, err)
	}
}

// A signed URL is path-style on the account endpoint, expires TTL after it
// was handed out, and carries the secret nowhere.
func TestSignedURLShape(t *testing.T) {
	now := time.Date(2026, 10, 21, 12, 0, 0, 500_000_000, time.UTC)
	cfg := assets.Config{AccountID: testAccount, Bucket: testBucket, AccessKeyID: testKeyID, SecretAccessKey: testSecret}
	s, err := assets.NewSigner(cfg, 10*time.Minute, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	urls, exp := s.SignAll([]string{lottieKey, "../etc/passwd", "profile_pictures/a b.png", ""})
	if len(urls) != 1 {
		t.Fatalf("signed %d urls, want only the valid key: %v", len(urls), urls)
	}
	u, err := url.Parse(urls[lottieKey])
	if err != nil {
		t.Fatal(err)
	}
	if u.Scheme != "https" || u.Host != testAccount+".r2.cloudflarestorage.com" || u.Path != "/"+testBucket+"/"+lottieKey {
		t.Fatalf("url %s", u.Redacted())
	}
	q := u.Query()
	if q.Get("X-Amz-Date") != "20261021T115900Z" || !strings.HasPrefix(q.Get("X-Amz-Credential"), testKeyID+"/20261021/auto/s3/") {
		t.Fatalf("scope %v", q)
	}
	expires, _ := strconv.Atoi(q.Get("X-Amz-Expires"))
	if expires != 661 { // 10 min + 60.5 s back-dating, rounded up
		t.Fatalf("X-Amz-Expires %d", expires)
	}
	if d := exp.Sub(now); d < 10*time.Minute || d > 10*time.Minute+time.Second {
		t.Fatalf("expiresAt is %s after now", d)
	}
	if strings.Contains(urls[lottieKey], testSecret) {
		t.Fatal("signed URL contains the secret")
	}
}

// The independent verifier in r2test accepts the presigned URL, serves the
// object, and refuses a tampered or expired one.
func TestPresignedURLVerifiedByFakeR2(t *testing.T) {
	r2 := r2test.New(t, testBucket, testKeyID, testSecret)
	r2.Seed(lottieKey, []byte(`{"v":"5.7.4"}`), "application/json", assets.ImmutableCacheControl)
	s, err := assets.NewSigner(fakeConfig(r2), 10*time.Minute, nil)
	if err != nil {
		t.Fatal(err)
	}
	urls, _ := s.SignAll([]string{lottieKey})
	status, body := get(t, urls[lottieKey])
	if status != 200 || string(body) != `{"v":"5.7.4"}` {
		t.Fatalf("GET signed url: %d %s", status, body)
	}
	tampered := strings.Replace(urls[lottieKey], "angry-tortoise", "other", 1)
	if status, _ := get(t, tampered); status != 403 {
		t.Fatalf("tampered url: %d", status)
	}
	unsigned := strings.SplitN(urls[lottieKey], "?", 2)[0]
	if status, _ := get(t, unsigned); status != 403 {
		t.Fatalf("unsigned url: %d", status)
	}
	r2.SetNow(func() time.Time { return time.Now().Add(12 * time.Minute) })
	if status, _ := get(t, urls[lottieKey]); status != 403 {
		t.Fatalf("expired url: %d", status)
	}
	wrong, _ := assets.NewSigner(assets.Config{AccountID: testAccount, Bucket: testBucket, AccessKeyID: testKeyID,
		SecretAccessKey: "wrong-secret", Endpoint: r2.URL}, 0, nil)
	r2.SetNow(time.Now)
	bad, _ := wrong.SignAll([]string{lottieKey})
	if status, _ := get(t, bad[lottieKey]); status != 403 {
		t.Fatalf("wrong secret: %d", status)
	}
}

func TestSignerConcurrentUse(t *testing.T) {
	r2 := r2test.New(t, testBucket, testKeyID, testSecret)
	r2.Seed(lottieKey, []byte("{}"), "application/json", "")
	s, err := assets.NewSigner(fakeConfig(r2), 0, nil)
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			urls, _ := s.SignAll([]string{lottieKey})
			if status, _ := get(t, urls[lottieKey]); status != 200 {
				t.Errorf("concurrent GET %d", status)
			}
		}()
	}
	wg.Wait()
}

func TestBucketPutHeadAgainstFakeR2(t *testing.T) {
	r2 := r2test.New(t, testBucket, testKeyID, testSecret)
	b, err := assets.NewBucket(fakeConfig(r2), nil)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if _, found, err := b.Head(ctx, lottieKey); err != nil || found {
		t.Fatalf("head missing: %v %v", found, err)
	}
	body := []byte(`{"layers":[]}`)
	if err := b.Put(ctx, lottieKey, body, "application/json", assets.ImmutableCacheControl); err != nil {
		t.Fatal(err)
	}
	o, ok := r2.Object(lottieKey)
	if !ok || string(o.Body) != string(body) || o.ContentType != "application/json" || o.CacheControl != assets.ImmutableCacheControl {
		t.Fatalf("stored %+v %v", o, ok)
	}
	info, found, err := b.Head(ctx, lottieKey)
	if err != nil || !found || info.Size != int64(len(body)) || info.ContentType != "application/json" ||
		info.CacheControl != assets.ImmutableCacheControl {
		t.Fatalf("head: %+v %v %v", info, found, err)
	}
	if r2.Denied() != 0 {
		t.Fatalf("%d requests refused", r2.Denied())
	}

	wrong := fakeConfig(r2)
	wrong.SecretAccessKey = "wrong-secret"
	bw, _ := assets.NewBucket(wrong, nil)
	err = bw.Put(ctx, lottieKey, body, "application/json", assets.ImmutableCacheControl)
	if err == nil || !strings.Contains(err.Error(), "SignatureDoesNotMatch") {
		t.Fatalf("wrong secret put: %v", err)
	}
	if strings.Contains(err.Error(), "wrong-secret") {
		t.Fatal("error leaks the secret")
	}
	if err := b.Put(ctx, "../x", body, "application/json", ""); err == nil {
		t.Fatal("invalid key accepted")
	}
}

func TestManifestFileIsValid(t *testing.T) {
	f, err := os.Open("../../config/profile_pictures.tsv")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	rows, err := assets.ReadPictureManifest(f)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 160 {
		t.Fatalf("%d rows, want 160", len(rows))
	}
	for _, r := range rows {
		if r.PriceDiamonds < 5 || r.PriceDiamonds > 50 {
			t.Errorf("%s: price %d outside 5..50", r.ID, r.PriceDiamonds)
		}
	}
}

func TestManifestRejectsBadRows(t *testing.T) {
	const ok = "pp_a\tA\tlottie\tprofile_pictures/a.json\tprofile_pictures/lottie_animation/a.json\t10\t1"
	cases := map[string]string{
		"bad header":  "id\tname\n" + ok,
		"few fields":  assets.ManifestHeader + "\npp_a\tA\tlottie",
		"bad id":      assets.ManifestHeader + "\nPP_A\tA\tlottie\tprofile_pictures/a.json\tprofile_pictures/lottie_animation/a.json\t10\t1",
		"bad format":  assets.ManifestHeader + "\npp_a\tA\tgif\tprofile_pictures/a.json\tprofile_pictures/lottie_animation/a.json\t10\t1",
		"format/path": assets.ManifestHeader + "\npp_a\tA\timage\tprofile_pictures/a.json\tprofile_pictures/lottie_animation/a.json\t10\t1",
		"zero price":  assets.ManifestHeader + "\npp_a\tA\tlottie\tprofile_pictures/a.json\tprofile_pictures/lottie_animation/a.json\t0\t1",
		"dup id":      assets.ManifestHeader + "\n" + ok + "\n" + ok,
		"dup path":    assets.ManifestHeader + "\n" + ok + "\npp_b\tB\tlottie\tprofile_pictures/b.json\tprofile_pictures/lottie_animation/a.json\t10\t2",
		"traversal":   assets.ManifestHeader + "\npp_a\tA\tlottie\tprofile_pictures/../a.json\tprofile_pictures/lottie_animation/a.json\t10\t1",
		"empty":       "",
	}
	for name, in := range cases {
		if _, err := assets.ReadPictureManifest(strings.NewReader(in)); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
	if rows, err := assets.ReadPictureManifest(strings.NewReader(assets.ManifestHeader + "\n" + ok + "\n")); err != nil || len(rows) != 1 {
		t.Fatalf("valid manifest: %v %v", rows, err)
	}
}

func TestEmoteManifestFileIsValid(t *testing.T) {
	f, err := os.Open("../../config/emotes.tsv")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	rows, err := assets.ReadEmoteManifest(f)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 89 {
		t.Fatalf("%d rows, want 89", len(rows))
	}
	for _, r := range rows {
		// Owner-approved prices: fixed per emote, 10..40 diamonds.
		if r.PriceDiamonds < 10 || r.PriceDiamonds > 40 || r.Format != assets.FormatLottie || !assets.ValidEmoteID(r.ID) {
			t.Errorf("%s: price %d, format %s", r.ID, r.PriceDiamonds, r.Format)
		}
	}
}

func TestEmoteManifestRules(t *testing.T) {
	const ok = "em_a\tA\tlottie\temojis/a.json\temotes/a.json\t10\t1"
	cases := map[string]string{
		"picture id":     assets.ManifestHeader + "\npp_a\tA\tlottie\temojis/a.json\temotes/a.json\t10\t1",
		"picture path":   assets.ManifestHeader + "\nem_a\tA\tlottie\temojis/a.json\tprofile_pictures/lottie_animation/a.json\t10\t1",
		"nested path":    assets.ManifestHeader + "\nem_a\tA\tlottie\temojis/a.json\temotes/x/a.json\t10\t1",
		"format/path":    assets.ManifestHeader + "\nem_a\tA\timage\temojis/a.json\temotes/a.json\t10\t1",
		"upper-case id":  assets.ManifestHeader + "\nEM_A\tA\tlottie\temojis/a.json\temotes/a.json\t10\t1",
		"dup id":         assets.ManifestHeader + "\n" + ok + "\n" + ok,
		"negative price": assets.ManifestHeader + "\nem_a\tA\tlottie\temojis/a.json\temotes/a.json\t-1\t1",
	}
	for name, in := range cases {
		if _, err := assets.ReadEmoteManifest(strings.NewReader(in)); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
	if rows, err := assets.ReadEmoteManifest(strings.NewReader(assets.ManifestHeader + "\n" + ok + "\n")); err != nil || len(rows) != 1 {
		t.Fatalf("valid manifest: %v %v", rows, err)
	}
	// An emote row is not a picture row.
	if _, err := assets.ReadPictureManifest(strings.NewReader(assets.ManifestHeader + "\n" + ok + "\n")); err == nil {
		t.Fatal("picture manifest accepted an emote row")
	}
	for id, want := range map[string]bool{"em_angry": true, "em_": false, "pp_bear": false, "em_Bad": false, "emote_crown": false} {
		if assets.ValidEmoteID(id) != want {
			t.Errorf("ValidEmoteID(%q) != %v", id, want)
		}
	}
}
