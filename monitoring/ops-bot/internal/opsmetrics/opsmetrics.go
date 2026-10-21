// Package opsmetrics is a tiny Prometheus text-format registry for the ops
// bot's own metrics (counters and gauges with fixed label names). It avoids
// pulling the full client library into this small service.
package opsmetrics

import (
	"fmt"
	"io"
	"math"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
)

type kind string

const (
	counterKind kind = "counter"
	gaugeKind   kind = "gauge"
)

// Vec is a counter or gauge with labels.
type Vec struct {
	name, help string
	kind       kind
	labels     []string

	mu     sync.Mutex
	values map[string]float64 // key: label values joined by \xff
}

// Registry holds metric families in registration order.
type Registry struct {
	mu   sync.Mutex
	vecs []*Vec
}

func (r *Registry) add(name, help string, k kind, labels []string) *Vec {
	v := &Vec{name: name, help: help, kind: k, labels: labels, values: map[string]float64{}}
	if len(labels) == 0 {
		v.values[""] = 0
	}
	r.mu.Lock()
	r.vecs = append(r.vecs, v)
	r.mu.Unlock()
	return v
}

// Counter registers a counter.
func (r *Registry) Counter(name, help string, labels ...string) *Vec {
	return r.add(name, help, counterKind, labels)
}

// Gauge registers a gauge.
func (r *Registry) Gauge(name, help string, labels ...string) *Vec {
	return r.add(name, help, gaugeKind, labels)
}

func (v *Vec) key(lv []string) string {
	if len(lv) != len(v.labels) {
		panic(fmt.Sprintf("opsmetrics: %s wants %d label values, got %d", v.name, len(v.labels), len(lv)))
	}
	return strings.Join(lv, "\xff")
}

// Add adds delta (counters must not decrease).
func (v *Vec) Add(delta float64, labelValues ...string) {
	if v.kind == counterKind && delta < 0 {
		return
	}
	k := v.key(labelValues)
	v.mu.Lock()
	v.values[k] += delta
	v.mu.Unlock()
}

// Inc adds one.
func (v *Vec) Inc(labelValues ...string) { v.Add(1, labelValues...) }

// Set sets a gauge.
func (v *Vec) Set(val float64, labelValues ...string) {
	k := v.key(labelValues)
	v.mu.Lock()
	v.values[k] = val
	v.mu.Unlock()
}

// Value returns the current value (tests).
func (v *Vec) Value(labelValues ...string) float64 {
	k := v.key(labelValues)
	v.mu.Lock()
	defer v.mu.Unlock()
	return v.values[k]
}

// WriteTo writes the text exposition format.
func (r *Registry) WriteTo(w io.Writer) (int64, error) {
	var b strings.Builder
	r.mu.Lock()
	vecs := append([]*Vec(nil), r.vecs...)
	r.mu.Unlock()
	for _, v := range vecs {
		fmt.Fprintf(&b, "# HELP %s %s\n# TYPE %s %s\n", v.name, escapeHelp(v.help), v.name, v.kind)
		v.mu.Lock()
		keys := make([]string, 0, len(v.values))
		for k := range v.values {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			b.WriteString(v.name)
			if len(v.labels) > 0 {
				vals := strings.Split(k, "\xff")
				b.WriteByte('{')
				for i, l := range v.labels {
					if i > 0 {
						b.WriteByte(',')
					}
					fmt.Fprintf(&b, "%s=\"%s\"", l, escapeLabel(vals[i]))
				}
				b.WriteByte('}')
			}
			b.WriteByte(' ')
			b.WriteString(formatFloat(v.values[k]))
			b.WriteByte('\n')
		}
		v.mu.Unlock()
	}
	n, err := io.WriteString(w, b.String())
	return int64(n), err
}

// ServeHTTP serves /metrics.
func (r *Registry) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	_, _ = r.WriteTo(w)
}

func formatFloat(f float64) string {
	switch {
	case math.IsNaN(f):
		return "NaN"
	case math.IsInf(f, 1):
		return "+Inf"
	case math.IsInf(f, -1):
		return "-Inf"
	}
	return strconv.FormatFloat(f, 'g', -1, 64)
}

func escapeHelp(s string) string {
	return strings.NewReplacer(`\`, `\\`, "\n", `\n`).Replace(s)
}

func escapeLabel(s string) string {
	return strings.NewReplacer(`\`, `\\`, "\n", `\n`, `"`, `\"`).Replace(s)
}
