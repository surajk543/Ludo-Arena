// Package google reads the optional Google KPI sources of the daily digest:
// the Play Console bulk installs report (Cloud Storage) and Firebase
// Analytics through the GA4 Data API. It uses plain REST over net/http (no
// Google SDKs) so tests can point it at httptest fakes, and authenticates
// with Application Default Credentials. Credentials are never logged or
// included in errors.
package google

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"golang.org/x/oauth2"
	googleoauth "golang.org/x/oauth2/google"
)

// OAuth scopes used by the clients in this package (read-only).
const (
	ScopeStorageRead   = "https://www.googleapis.com/auth/devstorage.read_only"
	ScopeAnalyticsRead = "https://www.googleapis.com/auth/analytics.readonly"
)

// dateLayout is the civil date format used in reports and requests.
const dateLayout = "2006-01-02"

// NewHTTPClient returns an OAuth2 HTTP client backed by Application Default
// Credentials: the JSON key file named by GOOGLE_APPLICATION_CREDENTIALS, the
// gcloud ADC file, or the GCE / Cloud Run metadata server. ctx must outlive
// the client (it is used for token refreshes), so pass a long-lived context.
func NewHTTPClient(ctx context.Context, scopes ...string) (*http.Client, error) {
	creds, err := googleoauth.FindDefaultCredentials(ctx, scopes...)
	if err != nil {
		return nil, fmt.Errorf("google: no Application Default Credentials (set GOOGLE_APPLICATION_CREDENTIALS to the path of a service-account JSON key, run `gcloud auth application-default login`, or attach a service account on GCP): %s", shortErr(err))
	}
	return oauth2.NewClient(ctx, creds.TokenSource), nil
}

// shortErr bounds an underlying error message so a misbehaving library can
// never echo large payloads (such as key material) into logs.
func shortErr(err error) string {
	s := err.Error()
	if len(s) > 300 {
		s = s[:300] + "…"
	}
	return s
}

// civil truncates t to its calendar date, expressed at 00:00 UTC.
func civil(t time.Time) time.Time {
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

// errNotFound marks a 404 from a Google API.
var errNotFound = errors.New("not found")

// excerpt reads at most n bytes of a response body for error messages,
// collapsing whitespace.
func excerpt(r io.Reader, n int64) string {
	b, _ := io.ReadAll(io.LimitReader(r, n))
	return strings.Join(strings.Fields(string(b)), " ")
}

func httpClient(c *http.Client) *http.Client {
	if c == nil {
		return http.DefaultClient
	}
	return c
}
