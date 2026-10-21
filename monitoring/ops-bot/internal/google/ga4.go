package google

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"
)

// DefaultGA4URL is the Google Analytics Data API base URL.
const DefaultGA4URL = "https://analyticsdata.googleapis.com"

// GA4 event names reported by Firebase Analytics.
const (
	EventFirstOpen = "first_open" // first launch after install (both platforms)
	EventAppRemove = "app_remove" // uninstall (Android only)
)

// GA4Client queries a GA4 property through the Data API v1beta. HTTP must
// carry credentials with ScopeAnalyticsRead; BaseURL defaults to
// DefaultGA4URL. PropertyID is the numeric id ("properties/123" is accepted).
type GA4Client struct {
	PropertyID, BaseURL string
	HTTP                *http.Client
}

// GA4Platform holds one platform's numbers for a day.
type GA4Platform struct {
	Platform                                      string
	ActiveUsers, NewUsers, FirstOpens, AppRemoves float64
}

// GA4Day holds the property-wide numbers of one day.
type GA4Day struct {
	Date                                          time.Time
	ActiveUsers, NewUsers, FirstOpens, AppRemoves float64
}

// GA4Summary is the digest's Firebase Analytics section.
type GA4Summary struct {
	Date      time.Time
	Platforms []GA4Platform // sorted by platform name
	// Totals has Platform "All". Users come from the day's property-wide
	// row (de-duplicated across platforms) when present, otherwise the sum
	// of platforms; event counts are summed.
	Totals GA4Platform
	Daily  []GA4Day // ascending; trendDays days ending at Date, zero-filled
}

// Summary returns `day`'s users and install/uninstall events by platform and
// a daily trend of trendDays days ending at `day`. Dates are interpreted in
// the GA4 property's time zone.
func (g *GA4Client) Summary(ctx context.Context, day time.Time, trendDays int) (GA4Summary, error) {
	if trendDays < 1 {
		trendDays = 1
	}
	day = civil(day)
	start := day.AddDate(0, 0, -(trendDays - 1))
	one := []dateRange{{StartDate: day.Format(dateLayout), EndDate: day.Format(dateLayout)}}
	trend := []dateRange{{StartDate: start.Format(dateLayout), EndDate: day.Format(dateLayout)}}
	events := &filterExpr{Filter: &filter{FieldName: "eventName", InListFilter: &inList{Values: []string{EventFirstOpen, EventAppRemove}}}}

	sum := GA4Summary{Date: day}
	platforms := map[string]*GA4Platform{}
	plat := func(name string) *GA4Platform {
		p := platforms[name]
		if p == nil {
			p = &GA4Platform{Platform: name}
			platforms[name] = p
		}
		return p
	}

	// 1. Users by platform.
	rep, err := g.run(ctx, ga4Request{DateRanges: one, Dimensions: names("platform"), Metrics: names("activeUsers", "newUsers")})
	if err != nil {
		return GA4Summary{}, err
	}
	for _, row := range rep.rows() {
		p := plat(row.dim("platform"))
		p.ActiveUsers += row.metric("activeUsers")
		p.NewUsers += row.metric("newUsers")
	}

	// 2. Install / uninstall events by platform.
	rep, err = g.run(ctx, ga4Request{DateRanges: one, Dimensions: names("platform", "eventName"), Metrics: names("eventCount"), DimensionFilter: events})
	if err != nil {
		return GA4Summary{}, err
	}
	for _, row := range rep.rows() {
		p := plat(row.dim("platform"))
		switch row.dim("eventName") {
		case EventFirstOpen:
			p.FirstOpens += row.metric("eventCount")
		case EventAppRemove:
			p.AppRemoves += row.metric("eventCount")
		}
	}

	// 3. Daily trend: users, then events.
	daily := make([]GA4Day, trendDays)
	index := map[time.Time]int{}
	for i := range daily {
		daily[i].Date = start.AddDate(0, 0, i)
		index[daily[i].Date] = i
	}
	dayUsers := false
	rep, err = g.run(ctx, ga4Request{DateRanges: trend, Dimensions: names("date"), Metrics: names("activeUsers", "newUsers")})
	if err != nil {
		return GA4Summary{}, err
	}
	for _, row := range rep.rows() {
		d, ok := parseGA4Date(row.dim("date"))
		if !ok {
			continue
		}
		if i, ok := index[d]; ok {
			daily[i].ActiveUsers += row.metric("activeUsers")
			daily[i].NewUsers += row.metric("newUsers")
			if d.Equal(day) {
				dayUsers = true
			}
		}
	}
	rep, err = g.run(ctx, ga4Request{DateRanges: trend, Dimensions: names("date", "eventName"), Metrics: names("eventCount"), DimensionFilter: events})
	if err != nil {
		return GA4Summary{}, err
	}
	for _, row := range rep.rows() {
		d, ok := parseGA4Date(row.dim("date"))
		if !ok {
			continue
		}
		i, ok := index[d]
		if !ok {
			continue
		}
		switch row.dim("eventName") {
		case EventFirstOpen:
			daily[i].FirstOpens += row.metric("eventCount")
		case EventAppRemove:
			daily[i].AppRemoves += row.metric("eventCount")
		}
	}
	sum.Daily = daily

	sum.Totals = GA4Platform{Platform: "All"}
	for _, p := range platforms {
		sum.Platforms = append(sum.Platforms, *p)
		sum.Totals.ActiveUsers += p.ActiveUsers
		sum.Totals.NewUsers += p.NewUsers
		sum.Totals.FirstOpens += p.FirstOpens
		sum.Totals.AppRemoves += p.AppRemoves
	}
	slices.SortFunc(sum.Platforms, func(a, b GA4Platform) int {
		return strings.Compare(strings.ToLower(a.Platform), strings.ToLower(b.Platform))
	})
	if dayUsers {
		last := daily[len(daily)-1]
		sum.Totals.ActiveUsers, sum.Totals.NewUsers = last.ActiveUsers, last.NewUsers
	}
	return sum, nil
}

func parseGA4Date(s string) (time.Time, bool) {
	t, err := time.ParseInLocation("20060102", strings.TrimSpace(s), time.UTC)
	return t, err == nil
}

// --- Data API wire types -----------------------------------------------------

type dateRange struct {
	StartDate string `json:"startDate"`
	EndDate   string `json:"endDate"`
}

type named struct {
	Name string `json:"name"`
}

func names(n ...string) []named {
	out := make([]named, len(n))
	for i, s := range n {
		out[i] = named{Name: s}
	}
	return out
}

type inList struct {
	Values []string `json:"values"`
}

type filter struct {
	FieldName    string  `json:"fieldName"`
	InListFilter *inList `json:"inListFilter,omitempty"`
}

type filterExpr struct {
	Filter *filter `json:"filter,omitempty"`
}

type ga4Request struct {
	DateRanges      []dateRange `json:"dateRanges"`
	Dimensions      []named     `json:"dimensions,omitempty"`
	Metrics         []named     `json:"metrics"`
	DimensionFilter *filterExpr `json:"dimensionFilter,omitempty"`
	Limit           int64       `json:"limit,omitempty"`
}

type ga4Value struct {
	Value string `json:"value"`
}

type ga4Response struct {
	DimensionHeaders []named `json:"dimensionHeaders"`
	MetricHeaders    []named `json:"metricHeaders"`
	Rows             []struct {
		DimensionValues []ga4Value `json:"dimensionValues"`
		MetricValues    []ga4Value `json:"metricValues"`
	} `json:"rows"`
	RowCount int64 `json:"rowCount"`
}

type ga4Row struct {
	resp *ga4Response
	i    int
}

func (r *ga4Response) rows() []ga4Row {
	out := make([]ga4Row, len(r.Rows))
	for i := range r.Rows {
		out[i] = ga4Row{resp: r, i: i}
	}
	return out
}

func (r ga4Row) dim(name string) string {
	for j, h := range r.resp.DimensionHeaders {
		if h.Name == name && j < len(r.resp.Rows[r.i].DimensionValues) {
			return r.resp.Rows[r.i].DimensionValues[j].Value
		}
	}
	return ""
}

func (r ga4Row) metric(name string) float64 {
	for j, h := range r.resp.MetricHeaders {
		if h.Name == name && j < len(r.resp.Rows[r.i].MetricValues) {
			v, err := strconv.ParseFloat(strings.TrimSpace(r.resp.Rows[r.i].MetricValues[j].Value), 64)
			if err != nil {
				return 0
			}
			return v
		}
	}
	return 0
}

type ga4Error struct {
	Error struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
		Status  string `json:"status"`
	} `json:"error"`
}

const maxGA4Bytes = 8 << 20

func (g *GA4Client) run(ctx context.Context, body ga4Request) (*ga4Response, error) {
	prop := strings.TrimPrefix(strings.TrimSpace(g.PropertyID), "properties/")
	if prop == "" {
		return nil, errors.New("ga4: property id not configured")
	}
	if _, err := strconv.ParseUint(prop, 10, 64); err != nil {
		return nil, fmt.Errorf("ga4: property id %q is not numeric", prop)
	}
	base := strings.TrimRight(g.BaseURL, "/")
	if base == "" {
		base = DefaultGA4URL
	}
	body.Limit = 10000
	payload, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("ga4: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+"/v1beta/properties/"+prop+":runReport", bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("ga4: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := httpClient(g.HTTP).Do(req)
	if err != nil {
		return nil, fmt.Errorf("ga4 runReport: %w", err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxGA4Bytes))
	if err != nil {
		return nil, fmt.Errorf("ga4 runReport: %w", err)
	}
	if resp.StatusCode/100 != 2 {
		var e ga4Error
		if json.Unmarshal(data, &e) == nil && e.Error.Message != "" {
			return nil, fmt.Errorf("ga4 runReport: HTTP %d %s: %s", resp.StatusCode, e.Error.Status, e.Error.Message)
		}
		return nil, fmt.Errorf("ga4 runReport: HTTP %d: %s", resp.StatusCode, excerpt(bytes.NewReader(data), 300))
	}
	var out ga4Response
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("ga4 runReport: decode response: %w", err)
	}
	return &out, nil
}
