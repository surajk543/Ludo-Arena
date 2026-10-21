package assets

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

// ImmutableCacheControl is the Cache-Control every profile-picture object
// carries: paths are immutable (new art = new path).
const ImmutableCacheControl = "private, max-age=31536000, immutable"

// ObjectInfo is what HEAD reports about an object.
type ObjectInfo struct {
	Size         int64
	ContentType  string
	CacheControl string
}

// Bucket writes and inspects objects with header-signed requests (the
// import tool). Safe for concurrent use.
type Bucket struct {
	ep   endpoint
	hc   *http.Client
	now  func() time.Time
	sign *Signer // only for its cached signing key
}

// NewBucket returns a Bucket for cfg. hc may be nil (a client with a 60 s
// timeout is used).
func NewBucket(cfg Config, hc *http.Client) (*Bucket, error) {
	ep, err := cfg.endpoint()
	if err != nil {
		return nil, err
	}
	if hc == nil {
		hc = &http.Client{Timeout: 60 * time.Second}
	}
	return &Bucket{ep: ep, hc: hc, now: time.Now, sign: &Signer{ep: ep}}, nil
}

// do sends a header-signed request for key.
func (b *Bucket) do(ctx context.Context, method, key string, body []byte, extra map[string]string) (*http.Response, error) {
	if !ValidKey(key) {
		return nil, fmt.Errorf("invalid object key %q", key)
	}
	at := b.now().UTC()
	payload := emptySHA256
	if body != nil {
		payload = hexSHA256(body)
	}
	uri := uriEncode(b.ep.objectPath(key), true)
	headers := map[string]string{
		"host":                 b.ep.host,
		"x-amz-date":           at.Format(amzDateLayout),
		"x-amz-content-sha256": payload,
	}
	for k, v := range extra {
		headers[k] = v
	}
	var rd io.Reader
	if body != nil {
		rd = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, b.ep.scheme+"://"+b.ep.host+uri, rd)
	if err != nil {
		return nil, err
	}
	for k, v := range headers {
		if k != "host" {
			req.Header.Set(k, v)
		}
	}
	if body != nil {
		req.ContentLength = int64(len(body))
	}
	sk := b.sign.signingKey(at.Format("20060102"))
	req.Header.Set("Authorization", authorization(method, uri, "", headers, payload, b.ep.accessKeyID, sk, region, service, at))
	res, err := b.hc.Do(req)
	if err != nil {
		// Report the key, not the URL (it holds no secret, but stays short).
		var ue *url.Error
		if errors.As(err, &ue) {
			err = ue.Err
		}
		return nil, fmt.Errorf("%s %s: %w", method, key, err)
	}
	return res, nil
}

// Head reports the object at key; found is false for 404.
func (b *Bucket) Head(ctx context.Context, key string) (info ObjectInfo, found bool, err error) {
	res, err := b.do(ctx, http.MethodHead, key, nil, nil)
	if err != nil {
		return ObjectInfo{}, false, err
	}
	defer res.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(res.Body, 1<<16))
	switch {
	case res.StatusCode == http.StatusNotFound:
		return ObjectInfo{}, false, nil
	case res.StatusCode != http.StatusOK:
		return ObjectInfo{}, false, fmt.Errorf("HEAD %s: HTTP %d", key, res.StatusCode)
	}
	size, err := strconv.ParseInt(res.Header.Get("Content-Length"), 10, 64)
	if err != nil {
		size = res.ContentLength
	}
	return ObjectInfo{Size: size, ContentType: res.Header.Get("Content-Type"),
		CacheControl: res.Header.Get("Cache-Control")}, true, nil
}

// Put stores body at key with the given Content-Type and Cache-Control (both
// signed).
func (b *Bucket) Put(ctx context.Context, key string, body []byte, contentType, cacheControl string) error {
	if body == nil {
		body = []byte{}
	}
	res, err := b.do(ctx, http.MethodPut, key, body, map[string]string{
		"content-type": contentType, "cache-control": cacheControl,
	})
	if err != nil {
		return err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<16))
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("PUT %s: HTTP %d %s", key, res.StatusCode, s3Code(raw))
	}
	return nil
}

// s3Code extracts the S3 error code from an error body ("" when absent).
func s3Code(raw []byte) string {
	var e struct {
		Code string `xml:"Code"`
	}
	if xml.Unmarshal(raw, &e) == nil {
		return e.Code
	}
	return ""
}
