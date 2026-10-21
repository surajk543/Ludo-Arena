package metrics

import (
	"encoding/json"
	"math"
	"math/rand/v2"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

const reservoirSize = 50000

// LoadStats aggregates load-test statistics for the JSON report.
type LoadStats struct {
	mu    sync.Mutex
	start time.Time
	rng   *rand.Rand

	peak, current      int
	sessionsOK         int64
	sessionsFailed     int64
	gamesStarted       map[string]int64
	gamesFinished      map[string]int64
	actions            map[string]int64
	latencies          map[string]*reservoir
	errors             map[string]int64
	resyncs            map[string]int64
	hashMismatches     int64
	reconnectOK        int64
	reconnectFailed    int64
	bytesReceived      int64
	compression        map[string]int64
	connectionFailures map[string]int64
	malformedByKind    map[string]int64
	resyncVerify       map[string]int64
}

type reservoir struct {
	n       int64
	max     time.Duration
	samples []time.Duration
}

// NewLoadStats creates an empty aggregator.
func NewLoadStats(start time.Time) *LoadStats {
	return &LoadStats{
		start: start, rng: rand.New(rand.NewPCG(uint64(start.UnixNano()), 7)),
		gamesStarted: map[string]int64{}, gamesFinished: map[string]int64{},
		actions: map[string]int64{}, latencies: map[string]*reservoir{},
		errors: map[string]int64{}, resyncs: map[string]int64{},
		compression: map[string]int64{}, connectionFailures: map[string]int64{},
		malformedByKind: map[string]int64{}, resyncVerify: map[string]int64{},
	}
}

func (s *LoadStats) action(t string) { s.mu.Lock(); s.actions[t]++; s.mu.Unlock() }
func (s *LoadStats) errorCode(c string) {
	s.mu.Lock()
	s.errors[c]++
	s.mu.Unlock()
}
func (s *LoadStats) connFailure(r string) {
	s.mu.Lock()
	s.connectionFailures[r]++
	s.mu.Unlock()
}
func (s *LoadStats) resync(r string) { s.mu.Lock(); s.resyncs[r]++; s.mu.Unlock() }
func (s *LoadStats) hashMismatch()   { s.mu.Lock(); s.hashMismatches++; s.mu.Unlock() }
func (s *LoadStats) bytes(n int)     { s.mu.Lock(); s.bytesReceived += int64(n); s.mu.Unlock() }
func (s *LoadStats) compressionResult(r string) {
	s.mu.Lock()
	s.compression[r]++
	s.mu.Unlock()
}
func (s *LoadStats) malformed(k string) { s.mu.Lock(); s.malformedByKind[k]++; s.mu.Unlock() }
func (s *LoadStats) resyncVerification(r string) {
	s.mu.Lock()
	s.resyncVerify[r]++
	s.mu.Unlock()
}
func (s *LoadStats) gameStarted(g string)  { s.mu.Lock(); s.gamesStarted[g]++; s.mu.Unlock() }
func (s *LoadStats) gameFinished(g string) { s.mu.Lock(); s.gamesFinished[g]++; s.mu.Unlock() }

func (s *LoadStats) session(ok bool) {
	s.mu.Lock()
	if ok {
		s.sessionsOK++
	} else {
		s.sessionsFailed++
	}
	s.mu.Unlock()
}

func (s *LoadStats) reconnect(ok bool) {
	s.mu.Lock()
	if ok {
		s.reconnectOK++
	} else {
		s.reconnectFailed++
	}
	s.mu.Unlock()
}

func (s *LoadStats) population(n int) {
	s.mu.Lock()
	s.current = n
	if n > s.peak {
		s.peak = n
	}
	s.mu.Unlock()
}

func (s *LoadStats) latency(action string, d time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r := s.latencies[action]
	if r == nil {
		r = &reservoir{}
		s.latencies[action] = r
	}
	r.n++
	if d > r.max {
		r.max = d
	}
	if len(r.samples) < reservoirSize {
		r.samples = append(r.samples, d)
		return
	}
	if j := s.rng.Int64N(r.n); j < reservoirSize { // Algorithm R
		r.samples[j] = d
	}
}

// LatencySummary is one action's latency distribution in milliseconds.
type LatencySummary struct {
	Count int64   `json:"count"`
	P50   float64 `json:"p50"`
	P95   float64 `json:"p95"`
	P99   float64 `json:"p99"`
	Max   float64 `json:"max"`
}

// Report is the load-test JSON report.
type Report struct {
	StartedAt          time.Time                 `json:"startedAt"`
	FinishedAt         time.Time                 `json:"finishedAt"`
	DurationSeconds    float64                   `json:"durationSeconds"`
	Environment        string                    `json:"environment"`
	BackendHost        string                    `json:"backendHost"`
	TargetConnections  int                       `json:"targetConnections"`
	FinalTarget        int                       `json:"finalTargetConnections"`
	PeakConnections    int                       `json:"peakConnections"`
	SuccessfulSessions int64                     `json:"successfulSessions"`
	FailedSessions     int64                     `json:"failedSessions"`
	GamesStarted       map[string]int64          `json:"gamesStarted"`
	GamesFinished      map[string]int64          `json:"gamesFinished"`
	ActionsTotal       int64                     `json:"actionsTotal"`
	ActionsPerSecond   float64                   `json:"actionsPerSecond"`
	ActionsByType      map[string]int64          `json:"actionsByType"`
	LatencyMS          map[string]LatencySummary `json:"latencyMs"`
	ErrorsByCode       map[string]int64          `json:"errorsByCode"`
	Resyncs            int64                     `json:"resyncs"`
	ResyncsByReason    map[string]int64          `json:"resyncsByReason"`
	HashMismatches     int64                     `json:"hashMismatches"`
	ReconnectAttempts  int64                     `json:"reconnectAttempts"`
	ReconnectSuccesses int64                     `json:"reconnectSuccesses"`
	ReconnectRate      float64                   `json:"reconnectSuccessRate"`
	BytesReceived      int64                     `json:"bytesReceived"`
	Compression        map[string]int64          `json:"compression"`
	ConnectionFailures map[string]int64          `json:"connectionFailures"`
	MalformedSent      map[string]int64          `json:"malformedSent"`
	ResyncVerification map[string]int64          `json:"reconnectResyncVerification"`
}

// Build produces the report as of now.
func (s *LoadStats) Build(env, host string, target, finalTarget int, now time.Time) Report {
	s.mu.Lock()
	defer s.mu.Unlock()
	dur := now.Sub(s.start).Seconds()
	r := Report{
		StartedAt: s.start.UTC(), FinishedAt: now.UTC(), DurationSeconds: round(dur, 3),
		Environment: env, BackendHost: host, TargetConnections: target, FinalTarget: finalTarget, PeakConnections: s.peak,
		SuccessfulSessions: s.sessionsOK, FailedSessions: s.sessionsFailed,
		GamesStarted: clone(s.gamesStarted), GamesFinished: clone(s.gamesFinished),
		ActionsByType: clone(s.actions), LatencyMS: map[string]LatencySummary{},
		ErrorsByCode: clone(s.errors), ResyncsByReason: clone(s.resyncs),
		HashMismatches: s.hashMismatches, BytesReceived: s.bytesReceived,
		Compression: clone(s.compression), ConnectionFailures: clone(s.connectionFailures),
		MalformedSent: clone(s.malformedByKind), ResyncVerification: clone(s.resyncVerify),
		ReconnectAttempts: s.reconnectOK + s.reconnectFailed, ReconnectSuccesses: s.reconnectOK,
	}
	for _, n := range s.actions {
		r.ActionsTotal += n
	}
	for reason, n := range s.resyncs {
		if reason != "connect" && reason != "reconnect" { // initial syncs are not recoveries
			r.Resyncs += n
		}
	}
	if dur > 0 {
		r.ActionsPerSecond = round(float64(r.ActionsTotal)/dur, 2)
	}
	if r.ReconnectAttempts > 0 {
		r.ReconnectRate = round(float64(s.reconnectOK)/float64(r.ReconnectAttempts), 4)
	}
	for a, res := range s.latencies {
		r.LatencyMS[a] = summarize(res)
	}
	return r
}

// WriteFile writes the report as indented JSON (atomically via rename).
func (r Report) WriteFile(path string) error {
	b, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return err
	}
	if dir := filepath.Dir(path); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(b, '\n'), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func summarize(r *reservoir) LatencySummary {
	if r == nil || len(r.samples) == 0 {
		return LatencySummary{}
	}
	s := make([]time.Duration, len(r.samples))
	copy(s, r.samples)
	sort.Slice(s, func(i, j int) bool { return s[i] < s[j] })
	return LatencySummary{
		Count: r.n, P50: msf(pct(s, 0.50)), P95: msf(pct(s, 0.95)), P99: msf(pct(s, 0.99)), Max: msf(r.max),
	}
}

// pct is the nearest-rank percentile of sorted samples.
func pct(sorted []time.Duration, p float64) time.Duration {
	if len(sorted) == 0 {
		return 0
	}
	idx := int(math.Ceil(p*float64(len(sorted)))) - 1
	idx = max(0, min(idx, len(sorted)-1))
	return sorted[idx]
}

func msf(d time.Duration) float64 { return round(float64(d)/float64(time.Millisecond), 3) }

func round(v float64, places int) float64 {
	p := math.Pow(10, float64(places))
	return math.Round(v*p) / p
}

func clone(m map[string]int64) map[string]int64 {
	out := make(map[string]int64, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}
