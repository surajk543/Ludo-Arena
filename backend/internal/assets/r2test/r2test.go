// Package r2test is a fake Cloudflare R2 bucket for tests: an httptest
// server answering path-style PUT, HEAD and GET on one bucket, keeping
// objects in memory.
//
// It VERIFIES every request's AWS Signature Version 4 with its own
// implementation, written from the AWS documentation and independent of
// package assets:
//
//   - header-signed requests (Authorization: AWS4-HMAC-SHA256 …), the import
//     tool's PUT and HEAD;
//   - query-presigned GETs (X-Amz-Signature in the query), the URLs handed
//     to phones, including their validity window (X-Amz-Date +
//     X-Amz-Expires).
//
// A request whose signature, scope, date or payload hash does not hold is
// refused 403 with R2's error code, so a test that reads or writes through
// it proves that what went on the wire is what was signed.
package r2test

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// Server is one fake bucket.
type Server struct {
	*httptest.Server
	Bucket      string
	AccessKeyID string
	Secret      string

	mu      sync.Mutex
	now     func() time.Time
	objects map[string]Object
	counts  map[string]int // method -> requests with a good signature
	denied  int
}

// Object is what the fake holds at a key.
type Object struct {
	Body         []byte
	ContentType  string
	CacheControl string
}

// New starts a fake R2 holding bucket for the key pair accessKeyID/secret
// and closes it when the test ends.
func New(t testing.TB, bucket, accessKeyID, secret string) *Server {
	t.Helper()
	s := &Server{Bucket: bucket, AccessKeyID: accessKeyID, Secret: secret, now: time.Now,
		objects: map[string]Object{}, counts: map[string]int{}}
	s.Server = httptest.NewServer(http.HandlerFunc(s.serve))
	t.Cleanup(s.Close)
	return s
}

// SetNow replaces the fake's clock (expiry tests).
func (s *Server) SetNow(now func() time.Time) { s.mu.Lock(); s.now = now; s.mu.Unlock() }

// Seed stores an object without a request.
func (s *Server) Seed(key string, body []byte, contentType, cacheControl string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.objects[key] = Object{Body: append([]byte(nil), body...), ContentType: contentType, CacheControl: cacheControl}
}

// Object returns the object at key.
func (s *Server) Object(key string) (Object, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	o, ok := s.objects[key]
	return o, ok
}

// Keys returns every stored key, sorted.
func (s *Server) Keys() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]string, 0, len(s.objects))
	for k := range s.objects {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// Count returns how many requests of method passed signature checks.
func (s *Server) Count(method string) int { s.mu.Lock(); defer s.mu.Unlock(); return s.counts[method] }

// Denied returns how many requests were refused for their signature.
func (s *Server) Denied() int { s.mu.Lock(); defer s.mu.Unlock(); return s.denied }

func (s *Server) serve(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeError(w, http.StatusBadRequest, "IncompleteBody")
		return
	}
	var code string
	if r.URL.Query().Has("X-Amz-Signature") {
		code = s.verifyPresigned(r)
	} else {
		code = s.verifyHeader(r, body)
	}
	if code != "" {
		s.mu.Lock()
		s.denied++
		s.mu.Unlock()
		writeError(w, http.StatusForbidden, code)
		return
	}
	s.mu.Lock()
	s.counts[r.Method]++
	s.mu.Unlock()

	path, err := url.PathUnescape(r.URL.EscapedPath())
	if err != nil {
		writeError(w, http.StatusBadRequest, "InvalidURI")
		return
	}
	prefix := "/" + s.Bucket + "/"
	if !strings.HasPrefix(path, prefix) || len(path) == len(prefix) {
		writeError(w, http.StatusNotFound, "NoSuchBucket")
		return
	}
	key := path[len(prefix):]
	switch r.Method {
	case http.MethodPut:
		s.mu.Lock()
		s.objects[key] = Object{Body: body, ContentType: r.Header.Get("Content-Type"), CacheControl: r.Header.Get("Cache-Control")}
		s.mu.Unlock()
		w.Header().Set("ETag", `"`+hexSHA(body)[:32]+`"`)
		w.WriteHeader(http.StatusOK)
	case http.MethodGet, http.MethodHead:
		o, ok := s.Object(key)
		if !ok {
			writeError(w, http.StatusNotFound, "NoSuchKey")
			return
		}
		if o.ContentType != "" {
			w.Header().Set("Content-Type", o.ContentType)
		}
		if o.CacheControl != "" {
			w.Header().Set("Cache-Control", o.CacheControl)
		}
		w.Header().Set("Content-Length", strconv.Itoa(len(o.Body)))
		w.WriteHeader(http.StatusOK)
		if r.Method == http.MethodGet {
			_, _ = w.Write(o.Body)
		}
	default:
		writeError(w, http.StatusMethodNotAllowed, "MethodNotAllowed")
	}
}

// verifyHeader checks an Authorization-header signature; "" means valid.
func (s *Server) verifyHeader(r *http.Request, body []byte) string {
	const prefix = "AWS4-HMAC-SHA256 "
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, prefix) {
		return "AccessDenied"
	}
	fields := map[string]string{}
	for _, part := range strings.Split(strings.TrimPrefix(auth, prefix), ",") {
		k, v, ok := strings.Cut(strings.TrimSpace(part), "=")
		if !ok {
			return "AuthorizationHeaderMalformed"
		}
		fields[k] = v
	}
	cred := strings.Split(fields["Credential"], "/")
	if code := s.checkScope(cred); code != "" {
		return code
	}
	amzDate := r.Header.Get("X-Amz-Date")
	at, err := time.Parse("20060102T150405Z", amzDate)
	if err != nil || cred[1] != amzDate[:8] {
		return "AuthorizationHeaderMalformed"
	}
	if d := s.clock().Sub(at); d > 15*time.Minute || d < -15*time.Minute {
		return "RequestTimeTooSkewed"
	}
	payload := r.Header.Get("X-Amz-Content-Sha256")
	if payload != "UNSIGNED-PAYLOAD" && payload != hexSHA(body) {
		return "XAmzContentSHA256Mismatch"
	}
	signed := strings.Split(fields["SignedHeaders"], ";")
	if !contains(signed, "host") || !contains(signed, "x-amz-date") || !contains(signed, "x-amz-content-sha256") {
		return "AccessDenied"
	}
	if r.Method == http.MethodPut && (!contains(signed, "content-type") || !contains(signed, "cache-control")) {
		return "AccessDenied" // this fake insists the stored metadata is signed
	}
	canon := strings.Join([]string{r.Method, r.URL.EscapedPath(), canonicalQueryOf(r.URL.Query(), ""),
		canonicalHeaders(r, signed), fields["SignedHeaders"], payload}, "\n")
	if !s.signatureOK(cred, amzDate, canon, fields["Signature"]) {
		return "SignatureDoesNotMatch"
	}
	return ""
}

// verifyPresigned checks a query-string signature; "" means valid.
func (s *Server) verifyPresigned(r *http.Request) string {
	q := r.URL.Query()
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		return "AccessDenied"
	}
	if q.Get("X-Amz-Algorithm") != "AWS4-HMAC-SHA256" {
		return "AuthorizationQueryParametersError"
	}
	cred := strings.Split(q.Get("X-Amz-Credential"), "/")
	if code := s.checkScope(cred); code != "" {
		return code
	}
	amzDate := q.Get("X-Amz-Date")
	at, err := time.Parse("20060102T150405Z", amzDate)
	if err != nil || cred[1] != amzDate[:8] {
		return "AuthorizationQueryParametersError"
	}
	expires, err := strconv.Atoi(q.Get("X-Amz-Expires"))
	if err != nil || expires < 1 || expires > 604800 {
		return "AuthorizationQueryParametersError"
	}
	now := s.clock()
	if now.Before(at.Add(-15*time.Minute)) || now.After(at.Add(time.Duration(expires)*time.Second)) {
		return "AccessDenied" // "Request has expired" / not yet valid
	}
	signed := strings.Split(q.Get("X-Amz-SignedHeaders"), ";")
	if !contains(signed, "host") {
		return "AuthorizationQueryParametersError"
	}
	canon := strings.Join([]string{r.Method, r.URL.EscapedPath(), canonicalQueryOf(q, "X-Amz-Signature"),
		canonicalHeaders(r, signed), q.Get("X-Amz-SignedHeaders"), "UNSIGNED-PAYLOAD"}, "\n")
	if !s.signatureOK(cred, amzDate, canon, q.Get("X-Amz-Signature")) {
		return "SignatureDoesNotMatch"
	}
	return ""
}

func (s *Server) clock() time.Time {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.now().UTC()
}

// checkScope validates <key id>/<date>/auto/s3/aws4_request.
func (s *Server) checkScope(cred []string) string {
	if len(cred) != 5 || cred[2] != "auto" || cred[3] != "s3" || cred[4] != "aws4_request" || len(cred[1]) != 8 {
		return "AuthorizationHeaderMalformed"
	}
	if cred[0] != s.AccessKeyID {
		return "InvalidAccessKeyId"
	}
	return ""
}

func (s *Server) signatureOK(cred []string, amzDate, canonicalRequest, got string) bool {
	scope := strings.Join(cred[1:], "/")
	sts := "AWS4-HMAC-SHA256\n" + amzDate + "\n" + scope + "\n" + hexSHA([]byte(canonicalRequest))
	k := mac([]byte("AWS4"+s.Secret), cred[1])
	for _, part := range cred[2:] {
		k = mac(k, part)
	}
	want := hex.EncodeToString(mac(k, sts))
	return hmac.Equal([]byte(want), []byte(got))
}

func canonicalHeaders(r *http.Request, signed []string) string {
	var b strings.Builder
	for _, name := range signed {
		v := r.Header.Get(name)
		if name == "host" {
			v = r.Host
		}
		b.WriteString(name + ":" + strings.Join(strings.Fields(v), " ") + "\n")
	}
	return b.String()
}

// canonicalQueryOf re-encodes the received query (minus skip) RFC 3986-style
// and sorts it.
func canonicalQueryOf(values url.Values, skip string) string {
	var pairs []string
	for name, vs := range values {
		if name == skip {
			continue
		}
		for _, v := range vs {
			pairs = append(pairs, encode(name)+"="+encode(v))
		}
	}
	sort.Strings(pairs)
	return strings.Join(pairs, "&")
}

func encode(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if ('A' <= c && c <= 'Z') || ('a' <= c && c <= 'z') || ('0' <= c && c <= '9') || strings.IndexByte("-_.~", c) >= 0 {
			b.WriteByte(c)
		} else {
			fmt.Fprintf(&b, "%%%02X", c)
		}
	}
	return b.String()
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func mac(key []byte, data string) []byte {
	h := hmac.New(sha256.New, key)
	h.Write([]byte(data))
	return h.Sum(nil)
}

func hexSHA(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func writeError(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Content-Type", "application/xml")
	w.WriteHeader(status)
	fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?><Error><Code>%s</Code><Message>%s</Message></Error>`, code, code)
}
