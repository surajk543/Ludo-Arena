// Package alertmanager receives Alertmanager webhook notifications
// (payload version 4), de-duplicates them and hands them to a delivery
// function. Delivery is asynchronous so Alertmanager is answered quickly;
// a full queue answers 503 so Alertmanager retries.
package alertmanager

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

// Alert is one alert of a webhook notification.
type Alert struct {
	Status       string            `json:"status"` // firing | resolved
	Labels       map[string]string `json:"labels"`
	Annotations  map[string]string `json:"annotations"`
	StartsAt     time.Time         `json:"startsAt"`
	EndsAt       time.Time         `json:"endsAt"`
	GeneratorURL string            `json:"generatorURL"`
	Fingerprint  string            `json:"fingerprint"`
}

// Payload is the webhook body.
type Payload struct {
	Version           string            `json:"version"`
	GroupKey          string            `json:"groupKey"`
	TruncatedAlerts   int               `json:"truncatedAlerts"`
	Status            string            `json:"status"`
	Receiver          string            `json:"receiver"`
	GroupLabels       map[string]string `json:"groupLabels"`
	CommonLabels      map[string]string `json:"commonLabels"`
	CommonAnnotations map[string]string `json:"commonAnnotations"`
	ExternalURL       string            `json:"externalURL"`
	Alerts            []Alert           `json:"alerts"`
}

// Name is the alert rule name.
func (a Alert) Name() string { return a.Labels["alertname"] }

// Severity is the severity label (default "warning").
func (a Alert) Severity() string {
	if s := a.Labels["severity"]; s != "" {
		return strings.ToLower(s)
	}
	return "warning"
}

// Firing reports whether the alert is firing.
func (a Alert) Firing() bool { return a.Status != "resolved" }

// Instance is the instance label (or job when absent).
func (a Alert) Instance() string {
	if s := a.Labels["instance"]; s != "" {
		return s
	}
	return a.Labels["job"]
}

// Summary is the summary annotation, falling back to the rule name.
func (a Alert) Summary() string {
	if s := a.Annotations["summary"]; s != "" {
		return s
	}
	return a.Name()
}

// Description is the description annotation.
func (a Alert) Description() string { return a.Annotations["description"] }

// Key identifies an alert across notifications.
func (a Alert) Key() string {
	if a.Fingerprint != "" {
		return a.Fingerprint
	}
	keys := make([]string, 0, len(a.Labels))
	for k := range a.Labels {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		b.WriteString(k + "=" + a.Labels[k] + ",")
	}
	return b.String()
}

// MaxBody limits webhook bodies.
const MaxBody = 1 << 20

// Decode parses and validates a webhook body.
func Decode(r io.Reader) (Payload, error) {
	var p Payload
	dec := json.NewDecoder(io.LimitReader(r, MaxBody))
	if err := dec.Decode(&p); err != nil {
		return Payload{}, fmt.Errorf("decode alertmanager payload: %w", err)
	}
	if len(p.Alerts) == 0 {
		return Payload{}, errors.New("alertmanager payload has no alerts")
	}
	for i := range p.Alerts {
		if p.Alerts[i].Labels == nil {
			p.Alerts[i].Labels = map[string]string{}
		}
		if p.Alerts[i].Annotations == nil {
			p.Alerts[i].Annotations = map[string]string{}
		}
		if p.Alerts[i].Status == "" {
			p.Alerts[i].Status = p.Status
		}
	}
	return p, nil
}

// Deduper drops an alert notification when the same alert was already
// delivered with the same status within the window. A status change
// (firing → resolved → firing) is always delivered. Keep the window below
// Alertmanager's repeat_interval so hourly reminders still arrive.
type Deduper struct {
	Window time.Duration
	Now    func() time.Time

	mu   sync.Mutex
	last map[string]seen
}

type seen struct {
	status string
	at     time.Time
}

// Filter returns the alerts that should be delivered and records them.
func (d *Deduper) Filter(alerts []Alert) []Alert {
	now := time.Now()
	if d.Now != nil {
		now = d.Now()
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.last == nil {
		d.last = map[string]seen{}
	}
	for k, v := range d.last { // bounded memory
		if now.Sub(v.at) > 24*time.Hour+d.Window {
			delete(d.last, k)
		}
	}
	out := alerts[:0:0]
	for _, a := range alerts {
		k := a.Key()
		if prev, ok := d.last[k]; ok && prev.status == a.Status && d.Window > 0 && now.Sub(prev.at) < d.Window {
			continue
		}
		d.last[k] = seen{status: a.Status, at: now}
		out = append(out, a)
	}
	return out
}

// Handler serves POST /alertmanager.
type Handler struct {
	// BearerToken, when set, must match "Authorization: Bearer <token>".
	BearerToken string
	// Enqueue hands a payload to the delivery worker; false means the
	// queue is full (the handler answers 503 and Alertmanager retries).
	Enqueue func(Payload) bool
	// OnReceive is called for every accepted payload (metrics).
	OnReceive func(Payload)
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if h.BearerToken != "" {
		got, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || subtle.ConstantTimeCompare([]byte(got), []byte(h.BearerToken)) != 1 {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
	}
	p, err := Decode(r.Body)
	if err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	if h.OnReceive != nil {
		h.OnReceive(p)
	}
	if !h.Enqueue(p) {
		http.Error(w, "queue full", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, "ok\n")
}
