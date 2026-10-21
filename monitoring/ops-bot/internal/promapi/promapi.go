// Package promapi is a minimal client for the Prometheus HTTP API
// (instant queries and range queries). Absent data is not an error: an empty
// result simply means "no data" and callers render it as n/a.
package promapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Sample is one instant-vector element.
type Sample struct {
	Labels map[string]string
	Value  float64
}

// Point is one value of a range series.
type Point struct {
	T time.Time
	V float64
}

// Series is one range-vector element.
type Series struct {
	Labels map[string]string
	Points []Point
}

// Client queries one Prometheus server.
type Client struct {
	base string
	http *http.Client
	// OnError, when set, is called for every failed query (metrics).
	OnError func(err error)
}

// New returns a client for baseURL (e.g. http://prometheus:9090).
func New(baseURL string, timeout time.Duration) *Client {
	return &Client{base: strings.TrimRight(baseURL, "/"), http: &http.Client{Timeout: timeout}}
}

// Error is an error reported by the Prometheus API.
type Error struct {
	Status    int
	ErrorType string
	Message   string
}

func (e *Error) Error() string {
	return fmt.Sprintf("prometheus: %s (%d): %s", e.ErrorType, e.Status, e.Message)
}

type apiResponse struct {
	Status    string          `json:"status"`
	ErrorType string          `json:"errorType"`
	Error     string          `json:"error"`
	Data      json.RawMessage `json:"data"`
}

type queryData struct {
	ResultType string          `json:"resultType"`
	Result     json.RawMessage `json:"result"`
}

// Query evaluates expr at time at (zero → server time).
func (c *Client) Query(ctx context.Context, expr string, at time.Time) ([]Sample, error) {
	v := url.Values{"query": {expr}}
	if !at.IsZero() {
		v.Set("time", formatTime(at))
	}
	data, err := c.do(ctx, "/api/v1/query", v)
	if err != nil {
		return nil, err
	}
	switch data.ResultType {
	case "vector":
		var raw []struct {
			Metric map[string]string `json:"metric"`
			Value  [2]any            `json:"value"`
		}
		if err := json.Unmarshal(data.Result, &raw); err != nil {
			return nil, c.fail(fmt.Errorf("prometheus: decode vector: %w", err))
		}
		out := make([]Sample, 0, len(raw))
		for _, r := range raw {
			val, err := parseValue(r.Value[1])
			if err != nil {
				return nil, c.fail(err)
			}
			out = append(out, Sample{Labels: r.Metric, Value: val})
		}
		return out, nil
	case "scalar":
		var raw [2]any
		if err := json.Unmarshal(data.Result, &raw); err != nil {
			return nil, c.fail(fmt.Errorf("prometheus: decode scalar: %w", err))
		}
		val, err := parseValue(raw[1])
		if err != nil {
			return nil, c.fail(err)
		}
		return []Sample{{Labels: map[string]string{}, Value: val}}, nil
	default:
		return nil, c.fail(fmt.Errorf("prometheus: unexpected result type %q for an instant query", data.ResultType))
	}
}

// QueryRange evaluates expr over [start, end] every step.
func (c *Client) QueryRange(ctx context.Context, expr string, start, end time.Time, step time.Duration) ([]Series, error) {
	v := url.Values{
		"query": {expr},
		"start": {formatTime(start)},
		"end":   {formatTime(end)},
		"step":  {strconv.FormatFloat(step.Seconds(), 'f', -1, 64)},
	}
	data, err := c.do(ctx, "/api/v1/query_range", v)
	if err != nil {
		return nil, err
	}
	if data.ResultType != "matrix" {
		return nil, c.fail(fmt.Errorf("prometheus: unexpected result type %q for a range query", data.ResultType))
	}
	var raw []struct {
		Metric map[string]string `json:"metric"`
		Values [][2]any          `json:"values"`
	}
	if err := json.Unmarshal(data.Result, &raw); err != nil {
		return nil, c.fail(fmt.Errorf("prometheus: decode matrix: %w", err))
	}
	out := make([]Series, 0, len(raw))
	for _, r := range raw {
		s := Series{Labels: r.Metric, Points: make([]Point, 0, len(r.Values))}
		for _, pv := range r.Values {
			ts, ok := pv[0].(float64)
			if !ok {
				return nil, c.fail(errors.New("prometheus: bad timestamp in matrix"))
			}
			val, err := parseValue(pv[1])
			if err != nil {
				return nil, c.fail(err)
			}
			sec, frac := math.Modf(ts)
			s.Points = append(s.Points, Point{T: time.Unix(int64(sec), int64(frac*1e9)), V: val})
		}
		out = append(out, s)
	}
	return out, nil
}

func (c *Client) do(ctx context.Context, path string, v url.Values) (*queryData, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base+path, strings.NewReader(v.Encode()))
	if err != nil {
		return nil, c.fail(err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, c.fail(fmt.Errorf("prometheus: %w", err))
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	if err != nil {
		return nil, c.fail(fmt.Errorf("prometheus: read: %w", err))
	}
	var r apiResponse
	if err := json.Unmarshal(body, &r); err != nil {
		msg := strings.TrimSpace(string(body))
		if len(msg) > 200 {
			msg = msg[:200]
		}
		return nil, c.fail(&Error{Status: resp.StatusCode, ErrorType: "invalid_response", Message: msg})
	}
	if r.Status != "success" {
		return nil, c.fail(&Error{Status: resp.StatusCode, ErrorType: r.ErrorType, Message: r.Error})
	}
	var d queryData
	if err := json.Unmarshal(r.Data, &d); err != nil {
		return nil, c.fail(fmt.Errorf("prometheus: decode data: %w", err))
	}
	return &d, nil
}

func (c *Client) fail(err error) error {
	if c.OnError != nil {
		c.OnError(err)
	}
	return err
}

func parseValue(v any) (float64, error) {
	s, ok := v.(string)
	if !ok {
		return 0, fmt.Errorf("prometheus: bad sample value %v", v)
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, fmt.Errorf("prometheus: bad sample value %q", s)
	}
	return f, nil
}

func formatTime(t time.Time) string {
	return strconv.FormatFloat(float64(t.UnixMilli())/1000, 'f', -1, 64)
}

// Valid reports whether v is a usable number (not NaN or ±Inf).
func Valid(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }

// Sum adds the valid values of samples; ok is false when there are none.
func Sum(samples []Sample) (float64, bool) {
	var total float64
	ok := false
	for _, s := range samples {
		if Valid(s.Value) {
			total += s.Value
			ok = true
		}
	}
	return total, ok
}

// ByLabel maps label → summed value (valid values only).
func ByLabel(samples []Sample, label string) map[string]float64 {
	out := map[string]float64{}
	for _, s := range samples {
		if Valid(s.Value) {
			out[s.Labels[label]] += s.Value
		}
	}
	return out
}

// SortedKeys returns the keys of m in ascending order.
func SortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
