// Package promtest is a fake Prometheus HTTP API for tests: queries are
// answered from rules matched by substring, anything else returns an empty
// result (the "no data" case).
package promtest

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"

	"ludoarena/opsbot/internal/promapi"
)

// Rule answers queries containing Match. Vector answers instant queries,
// Matrix answers range queries; Err returns a bad_data error.
type Rule struct {
	Match  string
	Vector []promapi.Sample
	Matrix []promapi.Series
	Err    string
}

// Server is a running fake.
type Server struct {
	*httptest.Server
	mu      sync.Mutex
	rules   []Rule
	Queries []string // every query received, in order
}

// S builds a sample with label pairs ("actor", "human", …).
func S(v float64, labels ...string) promapi.Sample {
	l := map[string]string{}
	for i := 0; i+1 < len(labels); i += 2 {
		l[labels[i]] = labels[i+1]
	}
	return promapi.Sample{Labels: l, Value: v}
}

// New starts a fake with rules (first match wins).
func New(rules ...Rule) *Server {
	s := &Server{rules: rules}
	s.Server = httptest.NewServer(http.HandlerFunc(s.serve))
	return s
}

// Received returns a copy of the queries seen so far.
func (s *Server) Received() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.Queries...)
}

func (s *Server) serve(w http.ResponseWriter, r *http.Request) {
	_ = r.ParseForm()
	q := r.Form.Get("query")
	s.mu.Lock()
	s.Queries = append(s.Queries, q)
	var rule *Rule
	for i := range s.rules {
		if strings.Contains(q, s.rules[i].Match) {
			rule = &s.rules[i]
			break
		}
	}
	s.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	if rule != nil && rule.Err != "" {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]any{"status": "error", "errorType": "bad_data", "error": rule.Err})
		return
	}
	switch r.URL.Path {
	case "/api/v1/query":
		result := []any{}
		if rule != nil {
			for _, smp := range rule.Vector {
				result = append(result, map[string]any{"metric": smp.Labels, "value": []any{1.7e9, fmtV(smp.Value)}})
			}
		}
		write(w, "vector", result)
	case "/api/v1/query_range":
		result := []any{}
		if rule != nil {
			for _, ser := range rule.Matrix {
				vals := make([]any, 0, len(ser.Points))
				for _, p := range ser.Points {
					vals = append(vals, []any{float64(p.T.UnixMilli()) / 1000, fmtV(p.V)})
				}
				result = append(result, map[string]any{"metric": ser.Labels, "values": vals})
			}
		}
		write(w, "matrix", result)
	default:
		http.NotFound(w, r)
	}
}

func fmtV(v float64) string { return strconv.FormatFloat(v, 'f', -1, 64) }

func write(w http.ResponseWriter, typ string, result []any) {
	_ = json.NewEncoder(w).Encode(map[string]any{"status": "success", "data": map[string]any{"resultType": typ, "result": result}})
}
