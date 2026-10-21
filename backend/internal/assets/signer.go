// Package assets serves the profile-picture art kept in a PRIVATE Cloudflare
// R2 bucket (docs/cosmetics-catalog.md → Profile pictures).
//
// The bucket has no public access (no custom domain, no r2.dev). The app
// never holds R2 credentials: it asks the backend to sign the catalogue paths
// it needs (POST /api/v1/assets/sign) and receives SigV4 query-presigned GET
// URLs valid for ASSET_URL_TTL (default 10 minutes), downloads each object
// once and keeps it on disk. Objects are immutable: new art is a new path.
//
// Everything here is standard library only:
//
//   - Signer presigns GETs (path-style https://<account>.r2.cloudflarestorage.com/<bucket>/<key>,
//     region "auto", service "s3");
//   - Bucket signs PUT and HEAD requests in the Authorization header (the
//     import tool, cmd/r2-import-pictures);
//   - ReadPictureManifest parses config/profile_pictures.tsv;
//   - r2test is a fake R2 that verifies both signature forms.
//
// Secrets and signed URLs are never logged: errors name the variable or the
// object key, never a credential or a signature.
package assets

import (
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"
)

const (
	// DefaultURLTTL is how long a signed URL stays valid (ASSET_URL_TTL).
	DefaultURLTTL = 10 * time.Minute
	// MaxURLTTL bounds ASSET_URL_TTL.
	MaxURLTTL = time.Hour
	// MinURLTTL bounds ASSET_URL_TTL from below (a download must fit).
	MinURLTTL = time.Minute
	// skew: URLs are signed a minute in the past (X-Amz-Date) and valid a
	// minute longer, so a server clock slightly ahead of Cloudflare's never
	// hands out a URL that is not valid yet; it still expires TTL after it
	// was handed out.
	skew = time.Minute
	// region and service are what R2 expects in the SigV4 scope.
	region  = "auto"
	service = "s3"
)

// Config is the R2 bucket and the API token's key pair (R2_ACCOUNT_ID,
// R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY). Endpoint overrides the
// account endpoint for tests (R2_ENDPOINT, refused in production).
type Config struct {
	AccountID       string
	Bucket          string
	AccessKeyID     string
	SecretAccessKey string
	Endpoint        string
}

var (
	accountPattern = regexp.MustCompile(`^[a-z0-9]{1,64}$`)
	bucketPattern  = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$`)
	// keyPattern is the shape of every key this package signs or writes:
	// lower-case folder segments and a file name of [A-Za-z0-9_.-]; no
	// spaces, no escapes, no empty segment. ".." is refused separately.
	keyPattern = regexp.MustCompile(`^[a-z0-9_-]+(?:/[A-Za-z0-9_.-]+)+$`)
)

// ValidKey reports whether key is an object key this package will sign or
// write.
func ValidKey(key string) bool {
	return len(key) <= 255 && keyPattern.MatchString(key) && !strings.Contains(key, "..")
}

// endpoint is a validated bucket endpoint.
type endpoint struct {
	scheme, host, bucket, accessKeyID, secret string
}

// Configured reports whether any of the four R2 variables is set.
func (c Config) Configured() bool {
	return c.AccountID != "" || c.Bucket != "" || c.AccessKeyID != "" || c.SecretAccessKey != ""
}

// Validate checks that all four values are present and usable. Messages name
// variables, never secret values.
func (c Config) Validate() error {
	_, err := c.endpoint()
	return err
}

func (c Config) endpoint() (endpoint, error) {
	account := strings.ToLower(strings.TrimSpace(c.AccountID))
	bucket := strings.TrimSpace(c.Bucket)
	id, secret := strings.TrimSpace(c.AccessKeyID), strings.TrimSpace(c.SecretAccessKey)
	var missing []string
	for _, v := range []struct{ name, val string }{
		{"R2_ACCOUNT_ID", account}, {"R2_BUCKET", bucket}, {"R2_ACCESS_KEY_ID", id}, {"R2_SECRET_ACCESS_KEY", secret},
	} {
		if v.val == "" {
			missing = append(missing, v.name)
		}
	}
	if len(missing) > 0 {
		return endpoint{}, fmt.Errorf("R2 is partially configured: set all of R2_ACCOUNT_ID, R2_BUCKET, "+
			"R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY or none (missing %s)", strings.Join(missing, ", "))
	}
	if !accountPattern.MatchString(account) {
		return endpoint{}, errors.New("R2_ACCOUNT_ID must be the Cloudflare account id (lower-case letters and digits)")
	}
	if !bucketPattern.MatchString(bucket) {
		return endpoint{}, errors.New("R2_BUCKET must be an R2 bucket name (3-63 lower-case letters, digits and hyphens)")
	}
	if strings.ContainsAny(id, " /\t\r\n") {
		return endpoint{}, errors.New("R2_ACCESS_KEY_ID is malformed")
	}
	ep := endpoint{scheme: "https", host: account + ".r2.cloudflarestorage.com", bucket: bucket,
		accessKeyID: id, secret: secret}
	if raw := strings.TrimSpace(c.Endpoint); raw != "" {
		u, err := url.Parse(raw)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" ||
			(u.Path != "" && u.Path != "/") || u.RawQuery != "" || u.User != nil {
			return endpoint{}, errors.New("R2_ENDPOINT must be a bare http(s)://host[:port] URL")
		}
		ep.scheme, ep.host = u.Scheme, u.Host
	}
	return ep, nil
}

// objectPath is the unencoded path-style path of key.
func (e endpoint) objectPath(key string) string { return "/" + e.bucket + "/" + key }

// Signer presigns GETs of one bucket's objects. Safe for concurrent use.
type Signer struct {
	ep  endpoint
	ttl time.Duration
	now func() time.Time

	mu      sync.Mutex
	keyDate string // YYYYMMDD of key
	key     []byte // derived signing key for keyDate
}

// NewSigner returns a Signer for cfg whose URLs stay valid for ttl
// (DefaultURLTTL when 0). now is the clock (time.Now when nil).
func NewSigner(cfg Config, ttl time.Duration, now func() time.Time) (*Signer, error) {
	ep, err := cfg.endpoint()
	if err != nil {
		return nil, err
	}
	if ttl == 0 {
		ttl = DefaultURLTTL
	}
	if ttl < MinURLTTL || ttl > MaxURLTTL {
		return nil, fmt.Errorf("ASSET_URL_TTL must be between %s and %s", MinURLTTL, MaxURLTTL)
	}
	if now == nil {
		now = time.Now
	}
	return &Signer{ep: ep, ttl: ttl, now: now}, nil
}

// TTL is how long signed URLs stay valid.
func (s *Signer) TTL() time.Duration { return s.ttl }

// signingKey returns the derived key for date, cached for the day.
func (s *Signer) signingKey(date string) []byte {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.keyDate != date {
		s.key, s.keyDate = signingKeyFor(s.ep.secret, date, region, service), date
	}
	return s.key
}

// SignAll presigns a GET for every valid key on one reading of the clock, so
// all URLs expire together at expiresAt (≈ now + TTL). Invalid keys are left
// out of the map. Callers must only pass keys they are allowed to hand out
// (the catalogue's paths).
func (s *Signer) SignAll(keys []string) (urls map[string]string, expiresAt time.Time) {
	now := s.now().UTC()
	at := now.Add(-skew).Truncate(time.Second)
	expires := s.ttl + now.Sub(at)
	// X-Amz-Expires is whole seconds: round up so a URL never dies early.
	if rem := expires % time.Second; rem != 0 {
		expires += time.Second - rem
	}
	expiresAt = at.Add(expires)
	urls = make(map[string]string, len(keys))
	key := s.signingKey(at.Format("20060102"))
	for _, k := range keys {
		if !ValidKey(k) {
			continue
		}
		urls[k] = presignGET(s.ep.scheme, s.ep.host, s.ep.objectPath(k), s.ep.accessKeyID, key, region, service, at, expires)
	}
	return urls, expiresAt
}
