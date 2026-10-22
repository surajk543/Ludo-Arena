package google

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
	"unicode/utf16"
)

const pkg = "com.ludoarena.app"

const fullHeader = "Date,Package Name,Daily Device Installs,Daily Device Uninstalls,Daily Device Upgrades,Total User Installs,Daily User Installs,Daily User Uninstalls,Active Device Installs,Install events,Update events,Uninstall events"

var allColumns = []string{
	ColDailyDeviceInstalls, ColDailyDeviceUninstalls, ColDailyDeviceUpgrades,
	ColTotalUserInstalls, ColDailyUserInstalls, ColDailyUserUninstalls,
	ColActiveDeviceInstalls, ColInstallEvents, ColUpdateEvents, ColUninstallEvents,
}

func encUTF16(s string, bigEndian, bom bool) []byte {
	u := utf16.Encode([]rune(s))
	var out []byte
	if bom {
		if bigEndian {
			out = append(out, 0xFE, 0xFF)
		} else {
			out = append(out, 0xFF, 0xFE)
		}
	}
	for _, c := range u {
		if bigEndian {
			out = append(out, byte(c>>8), byte(c))
		} else {
			out = append(out, byte(c), byte(c>>8))
		}
	}
	return out
}

func utf8BOM(s string) []byte { return append([]byte{0xEF, 0xBB, 0xBF}, s...) }

func date(s string) time.Time {
	t, err := time.ParseInLocation(dateLayout, s, time.UTC)
	if err != nil {
		panic(err)
	}
	return t
}

// fullRows is a realistic two-day overview with CRLF line endings.
var fullRows = fullHeader + "\r\n" +
	"2026-10-18,com.ludoarena.app,152,31,890,10450,140,29,8120,171,955,36\r\n" +
	"2026-10-19,com.ludoarena.app,175,40,612,10585,161,37,8243,198,640,44\r\n"

var fullWant = []PlayDay{
	{Date: date("2026-10-18"), Values: map[string]float64{
		ColDailyDeviceInstalls: 152, ColDailyDeviceUninstalls: 31, ColDailyDeviceUpgrades: 890,
		ColTotalUserInstalls: 10450, ColDailyUserInstalls: 140, ColDailyUserUninstalls: 29,
		ColActiveDeviceInstalls: 8120, ColInstallEvents: 171, ColUpdateEvents: 955, ColUninstallEvents: 36,
	}},
	{Date: date("2026-10-19"), Values: map[string]float64{
		ColDailyDeviceInstalls: 175, ColDailyDeviceUninstalls: 40, ColDailyDeviceUpgrades: 612,
		ColTotalUserInstalls: 10585, ColDailyUserInstalls: 161, ColDailyUserUninstalls: 37,
		ColActiveDeviceInstalls: 8243, ColInstallEvents: 198, ColUpdateEvents: 640, ColUninstallEvents: 44,
	}},
}

func TestParseInstallsCSV(t *testing.T) {
	tests := []struct {
		name     string
		data     []byte
		wantDays []PlayDay
		wantCols []string
		wantErr  string
	}{
		{name: "utf16le with BOM", data: encUTF16(fullRows, false, true), wantDays: fullWant, wantCols: allColumns},
		{name: "utf16le without BOM", data: encUTF16(fullRows, false, false), wantDays: fullWant, wantCols: allColumns},
		{name: "utf16be with BOM", data: encUTF16(fullRows, true, true), wantDays: fullWant, wantCols: allColumns},
		{name: "utf8 with BOM", data: utf8BOM(fullRows), wantDays: fullWant, wantCols: allColumns},
		{name: "utf8 plain LF", data: []byte(strings.ReplaceAll(fullRows, "\r\n", "\n")), wantDays: fullWant, wantCols: allColumns},
		{
			name: "missing columns",
			data: encUTF16("Date,Package Name,Daily Device Installs,Daily User Uninstalls\r\n2026-10-19,com.ludoarena.app,175,37\r\n", false, true),
			wantDays: []PlayDay{{Date: date("2026-10-19"), Values: map[string]float64{
				ColDailyDeviceInstalls: 175, ColDailyUserUninstalls: 37,
			}}},
			wantCols: []string{ColDailyDeviceInstalls, ColDailyUserUninstalls},
		},
		{
			name: "unknown numeric column kept, text column dropped",
			data: []byte("Date,Package Name,Country,Daily Device Installs,Daily Crashes\n2026-10-19,com.ludoarena.app,IN,175,3\n"),
			wantDays: []PlayDay{{Date: date("2026-10-19"), Values: map[string]float64{
				ColDailyDeviceInstalls: 175, "Daily Crashes": 3,
			}}},
			wantCols: []string{ColDailyDeviceInstalls, "Daily Crashes"},
		},
		{
			name: "thousands separators",
			data: []byte("Date,Package Name,Total User Installs,Active Device Installs\n2026-10-19,com.ludoarena.app,\"1,234,567\",\"98,765\"\n"),
			wantDays: []PlayDay{{Date: date("2026-10-19"), Values: map[string]float64{
				ColTotalUserInstalls: 1234567, ColActiveDeviceInstalls: 98765,
			}}},
			wantCols: []string{ColTotalUserInstalls, ColActiveDeviceInstalls},
		},
		{
			name: "duplicate dates summed (dimension report)",
			data: encUTF16("Date,Package Name,Country,Daily Device Installs,Daily Device Uninstalls\r\n"+
				"2026-10-19,com.ludoarena.app,IN,150,30\r\n"+
				"2026-10-19,com.ludoarena.app,ID,20,8\r\n"+
				"2026-10-18,com.ludoarena.app,IN,100,10\r\n", false, true),
			wantDays: []PlayDay{
				{Date: date("2026-10-18"), Values: map[string]float64{ColDailyDeviceInstalls: 100, ColDailyDeviceUninstalls: 10}},
				{Date: date("2026-10-19"), Values: map[string]float64{ColDailyDeviceInstalls: 170, ColDailyDeviceUninstalls: 38}},
			},
			wantCols: []string{ColDailyDeviceInstalls, ColDailyDeviceUninstalls},
		},
		{
			name: "empty cells skipped and blank lines ignored",
			data: []byte("Date,Package Name,Daily Device Installs,Daily Device Uninstalls\n2026-10-19,com.ludoarena.app,,40\n\n,,,\n"),
			wantDays: []PlayDay{{Date: date("2026-10-19"), Values: map[string]float64{
				ColDailyDeviceUninstalls: 40,
			}}},
			wantCols: []string{ColDailyDeviceInstalls, ColDailyDeviceUninstalls},
		},
		{
			name: "quoted, differently cased headers",
			data: []byte("\"date\",\"package name\",\" daily device installs \",\"UNINSTALL EVENTS\"\n\"2026/10/19\",\"com.ludoarena.app\",\"175\",\"44\"\n"),
			wantDays: []PlayDay{{Date: date("2026-10-19"), Values: map[string]float64{
				ColDailyDeviceInstalls: 175, ColUninstallEvents: 44,
			}}},
			wantCols: []string{ColDailyDeviceInstalls, ColUninstallEvents},
		},
		{name: "no Date column", data: []byte("Day,Package Name,Daily Device Installs\n2026-10-19,com.ludoarena.app,1\n"), wantErr: "no Date column"},
		{name: "empty file", data: nil, wantErr: "empty"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			days, cols, err := ParseInstallsCSV(tc.data)
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("err = %v, want containing %q", err, tc.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !reflect.DeepEqual(days, tc.wantDays) {
				t.Errorf("days = %+v\nwant %+v", days, tc.wantDays)
			}
			if !reflect.DeepEqual(cols, tc.wantCols) {
				t.Errorf("columns = %q, want %q", cols, tc.wantCols)
			}
		})
	}
}

func TestNormalizeBucket(t *testing.T) {
	tests := []struct{ in, want string }{
		{"pubsite_prod_rev_01234567890987654321", "pubsite_prod_rev_01234567890987654321"},
		{"gs://pubsite_prod_rev_01234567890987654321", "pubsite_prod_rev_01234567890987654321"},
		{"gs://pubsite_prod_rev_01234567890987654321/stats/installs/", "pubsite_prod_rev_01234567890987654321"},
		{"  gs://pubsite_prod_rev_1/ ", "pubsite_prod_rev_1"},
		{"", ""},
	}
	for _, tc := range tests {
		if got := NormalizeBucket(tc.in); got != tc.want {
			t.Errorf("NormalizeBucket(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestObjectName(t *testing.T) {
	got := ObjectName(pkg, date("2026-10-21"))
	if want := "stats/installs/installs_com.ludoarena.app_202610_overview.csv"; got != want {
		t.Fatalf("ObjectName = %q, want %q", got, want)
	}
}

// monthCSV renders an overview for the given inclusive day range.
func monthCSV(from, to string) []byte {
	var b strings.Builder
	b.WriteString(fullHeader + "\r\n")
	for d := date(from); !d.After(date(to)); d = d.AddDate(0, 0, 1) {
		n := d.Day()
		fmt.Fprintf(&b, "%s,%s,%d,%d,0,%d,%d,%d,%d,%d,0,%d\r\n", d.Format(dateLayout), pkg, 100+n, 10+n, 10000+n, 90+n, 9+n, 8000+n, 110+n, 12+n)
	}
	return encUTF16(b.String(), false, true)
}

type fakeGCS struct {
	srv     *httptest.Server
	mu      sync.Mutex
	objects map[string][]byte // object name -> content
	status  int               // forced status when non-zero
	paths   []string
}

func newFakeGCS(t *testing.T, bucket string) *fakeGCS {
	f := &fakeGCS{objects: map[string][]byte{}}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		f.paths = append(f.paths, r.URL.EscapedPath())
		if f.status != 0 {
			http.Error(w, `{"error":{"code":500,"message":"backend error"}}`, f.status)
			return
		}
		if r.Method != http.MethodGet || r.URL.Query().Get("alt") != "media" {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		prefix := "/storage/v1/b/" + bucket + "/o/"
		p := r.URL.EscapedPath()
		if !strings.HasPrefix(p, prefix) || strings.Contains(strings.TrimPrefix(p, prefix), "/") {
			http.Error(w, "object name must be one escaped path segment", http.StatusBadRequest)
			return
		}
		name := strings.ReplaceAll(strings.TrimPrefix(p, prefix), "%2F", "/")
		data, ok := f.objects[name]
		if !ok {
			http.Error(w, `{"error":{"code":404,"message":"No such object"}}`, http.StatusNotFound)
			return
		}
		_, _ = w.Write(data)
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func dayList(r PlayReport) []string {
	var out []string
	for _, d := range r.Days {
		out = append(out, d.Date.Format(dateLayout))
	}
	return out
}

func TestPlayInstalls(t *testing.T) {
	const bucket = "pubsite_prod_rev_01234567890987654321"
	sep := ObjectName(pkg, date("2026-09-01"))
	oct := ObjectName(pkg, date("2026-10-01"))

	t.Run("lag at month start falls back to previous month", func(t *testing.T) {
		f := newFakeGCS(t, bucket)
		f.objects[sep] = monthCSV("2026-09-01", "2026-09-30")
		p := &PlayClient{Bucket: "gs://" + bucket + "/stats/installs/", Package: pkg, BaseURL: f.srv.URL, HTTP: f.srv.Client()}
		rep, err := p.Installs(context.Background(), date("2026-10-01"), 30)
		if err != nil {
			t.Fatal(err)
		}
		days := dayList(rep)
		if len(days) != 29 || days[0] != "2026-09-02" || days[len(days)-1] != "2026-09-30" {
			t.Fatalf("days = %v", days)
		}
		last, ok := rep.Latest()
		if !ok || !last.Date.Equal(date("2026-09-30")) || last.Values[ColDailyDeviceInstalls] != 130 {
			t.Fatalf("latest = %+v, %v", last, ok)
		}
		if !reflect.DeepEqual(rep.Columns, allColumns) {
			t.Errorf("columns = %q", rep.Columns)
		}
		wantPaths := []string{
			"/storage/v1/b/" + bucket + "/o/stats%2Finstalls%2Finstalls_com.ludoarena.app_202609_overview.csv",
			"/storage/v1/b/" + bucket + "/o/stats%2Finstalls%2Finstalls_com.ludoarena.app_202610_overview.csv",
		}
		if !reflect.DeepEqual(f.paths, wantPaths) {
			t.Errorf("paths = %q\nwant %q", f.paths, wantPaths)
		}
	})

	t.Run("window trimming across months", func(t *testing.T) {
		f := newFakeGCS(t, bucket)
		f.objects[sep] = monthCSV("2026-09-01", "2026-09-30")
		f.objects[oct] = monthCSV("2026-10-01", "2026-10-21")
		p := &PlayClient{Bucket: bucket, Package: pkg, BaseURL: f.srv.URL + "/", HTTP: f.srv.Client()}
		rep, err := p.Installs(context.Background(), time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC), 7)
		if err != nil {
			t.Fatal(err)
		}
		want := []string{"2026-10-14", "2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18", "2026-10-19", "2026-10-20"}
		if got := dayList(rep); !reflect.DeepEqual(got, want) {
			t.Fatalf("days = %v, want %v", got, want)
		}
		rep, err = p.Installs(context.Background(), date("2026-10-05"), 10)
		if err != nil {
			t.Fatal(err)
		}
		if got := dayList(rep); len(got) != 10 || got[0] != "2026-09-26" || got[9] != "2026-10-05" {
			t.Fatalf("cross-month days = %v", got)
		}
	})

	t.Run("no reports yet", func(t *testing.T) {
		f := newFakeGCS(t, bucket)
		p := &PlayClient{Bucket: bucket, Package: pkg, BaseURL: f.srv.URL, HTTP: f.srv.Client()}
		rep, err := p.Installs(context.Background(), date("2026-10-20"), 30)
		if err != nil {
			t.Fatal(err)
		}
		if _, ok := rep.Latest(); ok || len(rep.Days) != 0 {
			t.Fatalf("expected empty report, got %v", dayList(rep))
		}
	})

	t.Run("server error", func(t *testing.T) {
		f := newFakeGCS(t, bucket)
		f.status = http.StatusInternalServerError
		p := &PlayClient{Bucket: bucket, Package: pkg, BaseURL: f.srv.URL, HTTP: f.srv.Client()}
		_, err := p.Installs(context.Background(), date("2026-10-20"), 30)
		if err == nil || !strings.Contains(err.Error(), "HTTP 500") || !strings.Contains(err.Error(), "backend error") {
			t.Fatalf("err = %v", err)
		}
	})

	t.Run("not configured", func(t *testing.T) {
		for _, p := range []*PlayClient{{Package: pkg}, {Bucket: "gs://", Package: pkg}, {Bucket: bucket}} {
			if _, err := p.Installs(context.Background(), date("2026-10-20"), 30); err == nil || !strings.Contains(err.Error(), "not configured") {
				t.Errorf("%+v: err = %v", p, err)
			}
		}
	})
}

// fakeGA4 answers runReport by the request's dimension signature.
type fakeGA4 struct {
	srv      *httptest.Server
	mu       sync.Mutex
	problems []string
	requests []ga4Request
	status   int
	body     string
}

func (f *fakeGA4) problem(format string, args ...any) {
	f.problems = append(f.problems, fmt.Sprintf(format, args...))
}

func row(dims []string, metrics ...string) map[string]any {
	dv := make([]map[string]string, len(dims))
	for i, d := range dims {
		dv[i] = map[string]string{"value": d}
	}
	mv := make([]map[string]string, len(metrics))
	for i, m := range metrics {
		mv[i] = map[string]string{"value": m}
	}
	return map[string]any{"dimensionValues": dv, "metricValues": mv}
}

func headers(n ...string) []map[string]string {
	out := make([]map[string]string, len(n))
	for i, s := range n {
		out[i] = map[string]string{"name": s}
	}
	return out
}

func newFakeGA4(t *testing.T, day, trendStart string) *fakeGA4 {
	f := &fakeGA4{}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		if f.status != 0 {
			w.WriteHeader(f.status)
			_, _ = io.WriteString(w, f.body)
			return
		}
		if r.Method != http.MethodPost || r.URL.Path != "/v1beta/properties/123456789:runReport" {
			f.problem("unexpected %s %s", r.Method, r.URL.Path)
		}
		if ct := r.Header.Get("Content-Type"); ct != "application/json" {
			f.problem("content type %q", ct)
		}
		var req ga4Request
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			f.problem("decode: %v", err)
		}
		f.requests = append(f.requests, req)
		var dims []string
		for _, d := range req.Dimensions {
			dims = append(dims, d.Name)
		}
		var mets []string
		for _, m := range req.Metrics {
			mets = append(mets, m.Name)
		}
		wantRange := dateRange{StartDate: day, EndDate: day}
		if slices.Contains(dims, "date") {
			wantRange = dateRange{StartDate: trendStart, EndDate: day}
		}
		if len(req.DateRanges) != 1 || req.DateRanges[0] != wantRange {
			f.problem("%v: dateRanges %+v, want %+v", dims, req.DateRanges, wantRange)
		}
		if slices.Contains(dims, "eventName") {
			fl := req.DimensionFilter
			if fl == nil || fl.Filter == nil || fl.Filter.FieldName != "eventName" || fl.Filter.InListFilter == nil ||
				!reflect.DeepEqual(fl.Filter.InListFilter.Values, []string{"first_open", "app_remove"}) {
				f.problem("%v: missing eventName filter: %+v", dims, fl)
			}
		} else if req.DimensionFilter != nil {
			f.problem("%v: unexpected filter", dims)
		}
		resp := map[string]any{"dimensionHeaders": headers(dims...), "metricHeaders": headers(mets...)}
		switch strings.Join(dims, ",") {
		case "platform":
			resp["rows"] = []any{row([]string{"iOS"}, "30", "10"), row([]string{"Android"}, "120", "40")}
		case "platform,eventName":
			resp["rows"] = []any{
				row([]string{"Android", "first_open"}, "45"),
				row([]string{"Android", "app_remove"}, "12"),
				row([]string{"iOS", "first_open"}, "11"),
			}
		case "date":
			resp["rows"] = []any{row([]string{"20261020"}, "140", "48"), row([]string{"20261018"}, "100", "30"), row([]string{"20260101"}, "999", "999")}
		case "date,eventName":
			resp["rows"] = []any{
				row([]string{"20261020", "first_open"}, "56"),
				row([]string{"20261020", "app_remove"}, "12"),
				row([]string{"20261019", "first_open"}, "40"),
			}
		default:
			f.problem("unexpected dimensions %v", dims)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(resp)
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func TestGA4Summary(t *testing.T) {
	f := newFakeGA4(t, "2026-10-20", "2026-10-14")
	g := &GA4Client{PropertyID: "properties/123456789", BaseURL: f.srv.URL, HTTP: f.srv.Client()}
	sum, err := g.Summary(context.Background(), time.Date(2026, 10, 20, 23, 0, 0, 0, time.UTC), 7)
	if err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	for _, p := range f.problems {
		t.Error(p)
	}
	if len(f.requests) != 4 {
		t.Errorf("requests = %d, want 4", len(f.requests))
	}
	f.mu.Unlock()

	if !sum.Date.Equal(date("2026-10-20")) {
		t.Errorf("date = %v", sum.Date)
	}
	wantPlatforms := []GA4Platform{
		{Platform: "Android", ActiveUsers: 120, NewUsers: 40, FirstOpens: 45, AppRemoves: 12},
		{Platform: "iOS", ActiveUsers: 30, NewUsers: 10, FirstOpens: 11},
	}
	if !reflect.DeepEqual(sum.Platforms, wantPlatforms) {
		t.Errorf("platforms = %+v", sum.Platforms)
	}
	// Users from the de-duplicated property-wide row (140, not 120+30).
	wantTotals := GA4Platform{Platform: "All", ActiveUsers: 140, NewUsers: 48, FirstOpens: 56, AppRemoves: 12}
	if sum.Totals != wantTotals {
		t.Errorf("totals = %+v, want %+v", sum.Totals, wantTotals)
	}
	if len(sum.Daily) != 7 {
		t.Fatalf("daily = %d days", len(sum.Daily))
	}
	wantDaily := map[string]GA4Day{
		"2026-10-14": {},
		"2026-10-18": {ActiveUsers: 100, NewUsers: 30},
		"2026-10-19": {FirstOpens: 40},
		"2026-10-20": {ActiveUsers: 140, NewUsers: 48, FirstOpens: 56, AppRemoves: 12},
	}
	for i, d := range sum.Daily {
		if want := date("2026-10-14").AddDate(0, 0, i); !d.Date.Equal(want) {
			t.Errorf("daily[%d].Date = %v, want %v", i, d.Date, want)
		}
		if w, ok := wantDaily[d.Date.Format(dateLayout)]; ok {
			w.Date = d.Date
			if d != w {
				t.Errorf("daily %s = %+v, want %+v", d.Date.Format(dateLayout), d, w)
			}
		}
	}
}

func TestGA4TotalsFallBackToPlatformSum(t *testing.T) {
	// The trend has no row for the day itself: totals sum the platforms.
	f := newFakeGA4(t, "2026-10-21", "2026-10-21")
	g := &GA4Client{PropertyID: "123456789", BaseURL: f.srv.URL, HTTP: f.srv.Client()}
	sum, err := g.Summary(context.Background(), date("2026-10-21"), 1)
	if err != nil {
		t.Fatal(err)
	}
	if sum.Totals.ActiveUsers != 150 || sum.Totals.NewUsers != 50 || len(sum.Daily) != 1 || sum.Daily[0].ActiveUsers != 0 {
		t.Fatalf("summary = %+v", sum)
	}
}

func TestGA4Errors(t *testing.T) {
	tests := []struct {
		name, property string
		status         int
		body, want     string
	}{
		{
			name: "permission denied", property: "123456789", status: http.StatusForbidden,
			body: `{"error":{"code":403,"message":"User does not have sufficient permissions for this property.","status":"PERMISSION_DENIED"}}`,
			want: "HTTP 403 PERMISSION_DENIED: User does not have sufficient permissions for this property.",
		},
		{name: "non-JSON error", property: "123456789", status: http.StatusBadGateway, body: "<html>bad gateway</html>", want: "HTTP 502"},
		{name: "not configured", property: "", want: "not configured"},
		{name: "non-numeric property", property: "G-ABC123", want: "not numeric"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f := newFakeGA4(t, "2026-10-20", "2026-10-20")
			f.status, f.body = tc.status, tc.body
			g := &GA4Client{PropertyID: tc.property, BaseURL: f.srv.URL, HTTP: f.srv.Client()}
			_, err := g.Summary(context.Background(), date("2026-10-20"), 1)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v, want containing %q", err, tc.want)
			}
		})
	}
}

func TestNewHTTPClientMissingCredentials(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "no-such-key.json")
	t.Setenv("GOOGLE_APPLICATION_CREDENTIALS", missing)
	_, err := NewHTTPClient(context.Background(), ScopeStorageRead)
	if err == nil || !strings.Contains(err.Error(), "GOOGLE_APPLICATION_CREDENTIALS") {
		t.Fatalf("err = %v", err)
	}
}
