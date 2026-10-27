package report

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"ludoarena/opsbot/internal/promapi"
)

// resourcesStep is the resolution of the /metrics charts.
const resourcesStep = 2 * time.Minute

// HostUsage is one host's CPU and RAM over the window.
type HostUsage struct {
	Instance           string
	CPU, RAM           []promapi.Point // %
	CPUStats, RAMStats SeriesStats
	Cores, MemBytes    Num
}

// Resources is the /metrics report: CPU and RAM per host and the backend's
// PostgreSQL connections over the last 24 hours.
type Resources struct {
	At, Start, End time.Time
	Step           time.Duration
	Hosts          []HostUsage
	// PostgreSQL pool of every backend instance (summed): open connections
	// (in use + idle + being opened), in use, and the pool limit.
	PGOpen, PGInUse, PGLimit  []promapi.Point
	PGOpenStats, PGInUseStats SeriesStats
	PGLimitNow                Num
	Errors                    []string
}

// Busiest returns the host with the highest value of f (nil without hosts).
func (r Resources) Busiest(f func(HostUsage) Num) *HostUsage {
	var best *HostUsage
	for i := range r.Hosts {
		if v := f(r.Hosts[i]); v.OK && (best == nil || v.V > f(*best).V) {
			best = &r.Hosts[i]
		}
	}
	return best
}

// Resources collects the /metrics report.
func (c *Collector) Resources(ctx context.Context) Resources {
	e := &errList{}
	at := c.now()
	q := c.Q
	r := Resources{At: at, Start: at.Add(-Window), End: at, Step: resourcesStep}
	stale := 3 * resourcesStep

	hosts := map[string]*HostUsage{}
	host := func(inst string) *HostUsage {
		if h, ok := hosts[inst]; ok {
			return h
		}
		h := &HostUsage{Instance: inst}
		hosts[inst] = h
		return h
	}
	for _, s := range c.series(ctx, e, "cpu chart", q.HostCPU(rateWindow*2), r.Start, at, resourcesStep) {
		h := host(s.Labels["instance"])
		h.CPU = clampPoints(s.Points)
	}
	for _, s := range c.series(ctx, e, "ram chart", q.HostRAM(), r.Start, at, resourcesStep) {
		h := host(s.Labels["instance"])
		h.RAM = clampPoints(s.Points)
	}
	if len(hosts) > 0 {
		if s, ok := c.vec(ctx, e, "cpu cores", q.HostCores(), at); ok {
			for inst, v := range promapi.ByLabel(s, "instance") {
				if h, known := hosts[inst]; known {
					h.Cores = N(v)
				}
			}
		}
		if s, ok := c.vec(ctx, e, "memory size", q.HostMemTotal(), at); ok {
			for inst, v := range promapi.ByLabel(s, "instance") {
				if h, known := hosts[inst]; known {
					h.MemBytes = N(v)
				}
			}
		}
	}
	for _, inst := range promapi.SortedKeys(hosts) {
		h := hosts[inst]
		h.CPUStats, h.RAMStats = StatsOf(h.CPU, at, stale), StatsOf(h.RAM, at, stale)
		r.Hosts = append(r.Hosts, *h)
	}

	pool := c.series(ctx, e, "postgres pool", q.PGPool(), r.Start, at, resourcesStep)
	r.PGOpen = sumPoints(pool)
	for _, s := range pool {
		if s.Labels["state"] == "acquired" {
			r.PGInUse = s.Points
		}
	}
	if len(pool) > 0 && r.PGInUse == nil {
		r.PGInUse = zeroLike(r.PGOpen) // nothing acquired yet: the series appears on first use
	}
	r.PGLimit = firstPoints(c.series(ctx, e, "postgres pool limit", q.PGPoolMax(), r.Start, at, resourcesStep))
	r.PGOpenStats, r.PGInUseStats = StatsOf(r.PGOpen, at, stale), StatsOf(r.PGInUse, at, stale)
	r.PGLimitNow = StatsOf(r.PGLimit, at, stale).Now
	r.Errors = e.list
	return r
}

func clampPoints(pts []promapi.Point) []promapi.Point {
	out := make([]promapi.Point, len(pts))
	for i, p := range pts {
		out[i] = promapi.Point{T: p.T, V: clampPct(p.V)}
	}
	return out
}

// sumPoints adds series point by point (by timestamp), in time order.
func sumPoints(series []promapi.Series) []promapi.Point {
	if len(series) == 0 {
		return nil
	}
	sum := map[int64]float64{}
	for _, s := range series {
		for _, p := range s.Points {
			if promapi.Valid(p.V) {
				sum[p.T.Unix()] += p.V
			}
		}
	}
	out := make([]promapi.Point, 0, len(sum))
	for t, v := range sum {
		out = append(out, promapi.Point{T: time.Unix(t, 0), V: v})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].T.Before(out[j].T) })
	return out
}

func zeroLike(pts []promapi.Point) []promapi.Point {
	out := make([]promapi.Point, len(pts))
	for i, p := range pts {
		out[i] = promapi.Point{T: p.T}
	}
	return out
}

// PctStats formats "41% now · avg 22% · peak 88% at 21:14".
func PctStats(st SeriesStats, loc *time.Location) string {
	peak := Pct(st.Peak)
	if st.Peak.OK {
		peak += " at " + st.PeakAt.In(loc).Format("15:04")
	}
	return Pct(st.Now) + " now · avg " + Pct(st.Avg) + " · peak " + peak
}

// PGSummary is "12 in use / 20 open · limit 50" or "n/a".
func (r Resources) PGSummary() string {
	if !r.PGOpenStats.Now.OK && !r.PGInUseStats.Now.OK {
		return NA
	}
	s := I(r.PGInUseStats.Now) + " in use / " + I(r.PGOpenStats.Now) + " open"
	if r.PGLimitNow.OK {
		s += " · limit " + I(r.PGLimitNow)
	}
	return s
}

// ResourcesCaption is the one-line summary sent with the /metrics PDF.
func ResourcesCaption(r Resources, m Meta) string {
	parts := []string{Esc(m.Env)}
	if h := r.Busiest(func(h HostUsage) Num { return h.CPUStats.Peak }); h != nil {
		parts = append(parts, fmt.Sprintf("CPU %s (peak %s)", Pct(h.CPUStats.Now), Pct(h.CPUStats.Peak)))
	}
	if h := r.Busiest(func(h HostUsage) Num { return h.RAMStats.Peak }); h != nil {
		parts = append(parts, fmt.Sprintf("RAM %s (peak %s)", Pct(h.RAMStats.Now), Pct(h.RAMStats.Peak)))
	}
	parts = append(parts, "PostgreSQL "+r.PGSummary())
	if len(parts) == 2 && len(r.Hosts) == 0 {
		parts = append(parts, "no host metrics")
	}
	return strings.Join(parts, " · ")
}

// ResourcesText renders /metrics as Telegram HTML (used when the PDF fails).
func ResourcesText(r Resources, m Meta) string {
	var b strings.Builder
	b.WriteString(m.header("server metrics, last 24 h", r.At) + "\n")
	if len(r.Hosts) == 0 {
		b.WriteString("\nNo host metrics (node_exporter not scraped).\n")
	}
	for _, h := range r.Hosts {
		fmt.Fprintf(&b, "\n<b>%s</b>\nCPU %s\nRAM %s\n", Esc(ShortInstance(h.Instance)), PctStats(h.CPUStats, m.Loc), PctStats(h.RAMStats, m.Loc))
	}
	fmt.Fprintf(&b, "\n<b>PostgreSQL connections</b>\n%s", Esc(r.PGSummary()))
	if r.PGInUseStats.Peak.OK {
		fmt.Fprintf(&b, " · peak in use %s at %s", I(r.PGInUseStats.Peak), r.PGInUseStats.PeakAt.In(m.Loc).Format("15:04"))
	}
	b.WriteString("\n")
	b.WriteString(errorsFooter(r.Errors))
	return b.String()
}
