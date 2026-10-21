package google

import (
	"bytes"
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
	"unicode/utf8"
)

// Play Console bulk installs report columns (canonical header names).
const (
	ColDailyDeviceInstalls   = "Daily Device Installs"
	ColDailyDeviceUninstalls = "Daily Device Uninstalls"
	ColDailyDeviceUpgrades   = "Daily Device Upgrades"
	ColTotalUserInstalls     = "Total User Installs"
	ColDailyUserInstalls     = "Daily User Installs"
	ColDailyUserUninstalls   = "Daily User Uninstalls"
	ColActiveDeviceInstalls  = "Active Device Installs"
	ColInstallEvents         = "Install events"
	ColUpdateEvents          = "Update events"
	ColUninstallEvents       = "Uninstall events"
)

var canonicalColumns = []string{
	ColDailyDeviceInstalls, ColDailyDeviceUninstalls, ColDailyDeviceUpgrades,
	ColTotalUserInstalls, ColDailyUserInstalls, ColDailyUserUninstalls,
	ColActiveDeviceInstalls, ColInstallEvents, ColUpdateEvents, ColUninstallEvents,
}

// DefaultStorageURL is the Cloud Storage JSON API base URL.
const DefaultStorageURL = "https://storage.googleapis.com"

// maxReportBytes bounds a downloaded monthly report.
const maxReportBytes = 32 << 20

// PlayDay is one day of the installs report. Values holds only the columns
// present with a parseable number, keyed by canonical header name (unknown
// columns keep their header text).
type PlayDay struct {
	Date   time.Time
	Values map[string]float64
}

// PlayReport is the merged installs report for a window of days.
type PlayReport struct {
	Days    []PlayDay // ascending by date
	Columns []string  // value columns present in the source files
}

// Latest returns the most recent day of the report.
func (r PlayReport) Latest() (PlayDay, bool) {
	if len(r.Days) == 0 {
		return PlayDay{}, false
	}
	return r.Days[len(r.Days)-1], true
}

// ParseInstallsCSV decodes a Play Console bulk installs report. Play exports
// are UTF-16LE with a BOM; UTF-16BE, UTF-8 (with or without BOM) and
// BOM-less UTF-16LE are accepted too. Columns are matched by header name
// (case-insensitive, trimmed); missing columns are simply absent and empty
// cells skipped. Rows sharing a date (dimension reports) are summed. It
// returns the days in ascending order and the value columns in header order.
func ParseInstallsCSV(data []byte) ([]PlayDay, []string, error) {
	text := decodeText(data)
	r := csv.NewReader(strings.NewReader(text))
	r.FieldsPerRecord = -1
	r.LazyQuotes = true
	r.TrimLeadingSpace = true

	header, err := r.Read()
	if err == io.EOF {
		return nil, nil, errors.New("play report: empty file")
	}
	if err != nil {
		return nil, nil, fmt.Errorf("play report: header: %w", err)
	}

	dateIdx := -1
	valueCols := map[int]string{}
	var columns []string
	for i, h := range header {
		name := strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))
		switch {
		case name == "":
			continue
		case strings.EqualFold(name, "Date"):
			if dateIdx < 0 {
				dateIdx = i
			}
			continue
		case strings.EqualFold(name, "Package Name"), strings.EqualFold(name, "Package name"):
			continue
		}
		for _, c := range canonicalColumns {
			if strings.EqualFold(name, c) {
				name = c
				break
			}
		}
		if slices.Contains(columns, name) {
			continue
		}
		valueCols[i] = name
		columns = append(columns, name)
	}
	if dateIdx < 0 {
		return nil, nil, errors.New("play report: no Date column in header")
	}

	byDate := map[time.Time]map[string]float64{}
	numeric := map[string]bool{}
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, nil, fmt.Errorf("play report: %w", err)
		}
		if dateIdx >= len(rec) {
			continue
		}
		day, ok := parseReportDate(rec[dateIdx])
		if !ok {
			continue // blank or summary line
		}
		vals := byDate[day]
		if vals == nil {
			vals = map[string]float64{}
			byDate[day] = vals
		}
		for i, name := range valueCols {
			if i >= len(rec) {
				continue
			}
			if v, ok := parseNumber(rec[i]); ok {
				vals[name] += v
				numeric[name] = true
			}
		}
	}

	// Unknown columns are values only if they hold numbers (e.g. not "Country").
	columns = slices.DeleteFunc(columns, func(c string) bool {
		return !numeric[c] && !slices.Contains(canonicalColumns, c)
	})

	days := make([]PlayDay, 0, len(byDate))
	for d, v := range byDate {
		days = append(days, PlayDay{Date: d, Values: v})
	}
	slices.SortFunc(days, func(a, b PlayDay) int { return a.Date.Compare(b.Date) })
	return days, columns, nil
}

// decodeText converts a report to a Go string, detecting its encoding.
func decodeText(b []byte) string {
	switch {
	case len(b) >= 2 && b[0] == 0xFF && b[1] == 0xFE:
		return decodeUTF16(b[2:], false)
	case len(b) >= 2 && b[0] == 0xFE && b[1] == 0xFF:
		return decodeUTF16(b[2:], true)
	case len(b) >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF:
		return string(b[3:])
	}
	// BOM-less UTF-16: ASCII text has a NUL in every other byte.
	if len(b) >= 4 {
		n := min(len(b), 128) &^ 1
		var oddNUL, evenNUL int
		for i := 0; i < n; i += 2 {
			if b[i] == 0 {
				evenNUL++
			}
			if b[i+1] == 0 {
				oddNUL++
			}
		}
		half := n / 4
		switch {
		case oddNUL > half && evenNUL == 0:
			return strings.TrimPrefix(decodeUTF16(b, false), "\ufeff")
		case evenNUL > half && oddNUL == 0:
			return strings.TrimPrefix(decodeUTF16(b, true), "\ufeff")
		}
	}
	if !utf8.Valid(b) {
		return strings.ToValidUTF8(string(b), "\uFFFD")
	}
	return string(b)
}

func decodeUTF16(b []byte, bigEndian bool) string {
	u := make([]uint16, len(b)/2)
	for i := range u {
		if bigEndian {
			u[i] = uint16(b[2*i])<<8 | uint16(b[2*i+1])
		} else {
			u[i] = uint16(b[2*i]) | uint16(b[2*i+1])<<8
		}
	}
	return string(utf16.Decode(u))
}

var reportDateLayouts = []string{dateLayout, "2006/01/02", "20060102", "01/02/2006", "Jan 2, 2006"}

func parseReportDate(s string) (time.Time, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return time.Time{}, false
	}
	for _, l := range reportDateLayouts {
		if t, err := time.ParseInLocation(l, s, time.UTC); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

func parseNumber(s string) (float64, bool) {
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, ",", "")
	s = strings.ReplaceAll(s, "\u00a0", "")
	if s == "" {
		return 0, false
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}

// NormalizeBucket extracts the bucket name from a bucket name or a gs:// URI
// as shown by Play Console ("Download reports → Copy Cloud Storage URI").
func NormalizeBucket(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "gs://")
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}

// ObjectName is the Cloud Storage object of the monthly installs overview.
func ObjectName(pkg string, month time.Time) string {
	return "stats/installs/installs_" + pkg + "_" + month.Format("200601") + "_overview.csv"
}

// PlayClient downloads Play Console bulk installs reports from Cloud
// Storage. HTTP must carry credentials with ScopeStorageRead (see
// NewHTTPClient); BaseURL defaults to DefaultStorageURL.
type PlayClient struct {
	Bucket, Package, BaseURL string
	HTTP                     *http.Client
}

// Installs returns the report days in the window of `days` days ending at
// `until` (inclusive). It downloads every monthly overview covering the
// window plus the month before `until` (reports lag 1–2 days, so at the
// start of a month the newest data is in the previous file). A missing
// monthly file (404) is not an error. Callers that want the latest day
// despite the reporting lag should ask for a window of several days.
func (p *PlayClient) Installs(ctx context.Context, until time.Time, days int) (PlayReport, error) {
	bucket := NormalizeBucket(p.Bucket)
	if bucket == "" {
		return PlayReport{}, errors.New("play: reports bucket not configured")
	}
	if p.Package == "" {
		return PlayReport{}, errors.New("play: package name not configured")
	}
	if days < 1 {
		days = 1
	}
	until = civil(until)
	from := until.AddDate(0, 0, -(days - 1))

	first := monthOf(from)
	if prev := monthOf(until).AddDate(0, -1, 0); prev.Before(first) {
		first = prev
	}
	merged := map[time.Time]map[string]float64{}
	var columns []string
	for m := first; !m.After(monthOf(until)); m = m.AddDate(0, 1, 0) {
		data, err := p.fetch(ctx, bucket, ObjectName(p.Package, m))
		if errors.Is(err, errNotFound) {
			continue
		}
		if err != nil {
			return PlayReport{}, err
		}
		ds, cols, err := ParseInstallsCSV(data)
		if err != nil {
			return PlayReport{}, fmt.Errorf("%s: %w", ObjectName(p.Package, m), err)
		}
		for _, c := range cols {
			if !slices.Contains(columns, c) {
				columns = append(columns, c)
			}
		}
		for _, d := range ds {
			if d.Date.Before(from) || d.Date.After(until) {
				continue
			}
			vals := merged[d.Date]
			if vals == nil {
				vals = map[string]float64{}
				merged[d.Date] = vals
			}
			for k, v := range d.Values {
				vals[k] += v
			}
		}
	}
	rep := PlayReport{Columns: columns}
	for d, v := range merged {
		rep.Days = append(rep.Days, PlayDay{Date: d, Values: v})
	}
	slices.SortFunc(rep.Days, func(a, b PlayDay) int { return a.Date.Compare(b.Date) })
	return rep, nil
}

func monthOf(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, time.UTC)
}

func (p *PlayClient) fetch(ctx context.Context, bucket, object string) ([]byte, error) {
	base := strings.TrimRight(p.BaseURL, "/")
	if base == "" {
		base = DefaultStorageURL
	}
	u := base + "/storage/v1/b/" + url.PathEscape(bucket) + "/o/" + url.PathEscape(object) + "?alt=media"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, fmt.Errorf("play: %w", err)
	}
	resp, err := httpClient(p.HTTP).Do(req)
	if err != nil {
		return nil, fmt.Errorf("play: download %s: %w", object, err)
	}
	defer resp.Body.Close()
	switch {
	case resp.StatusCode == http.StatusNotFound:
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		return nil, errNotFound
	case resp.StatusCode/100 != 2:
		return nil, fmt.Errorf("play: download %s: HTTP %d: %s", object, resp.StatusCode, excerpt(resp.Body, 300))
	}
	var buf bytes.Buffer
	if _, err := io.Copy(&buf, io.LimitReader(resp.Body, maxReportBytes+1)); err != nil {
		return nil, fmt.Errorf("play: download %s: %w", object, err)
	}
	if buf.Len() > maxReportBytes {
		return nil, fmt.Errorf("play: %s exceeds %d bytes", object, maxReportBytes)
	}
	return buf.Bytes(), nil
}
