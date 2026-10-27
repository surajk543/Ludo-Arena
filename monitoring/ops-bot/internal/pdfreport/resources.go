package pdfreport

import (
	"context"
	"fmt"
	"time"

	"ludoarena/opsbot/internal/charts"
	"ludoarena/opsbot/internal/report"
)

// resChartH is the height of the /metrics charts (mm).
const resChartH = 64.0

// ResourcesFileName is the document name of a /metrics report.
func ResourcesFileName(at time.Time, loc *time.Location) string {
	return "ludo-arena-metrics-" + at.In(loc).Format("2006-01-02-1504-MST") + ".pdf"
}

// ResourcesPDF renders the /metrics report: CPU and RAM per host and the
// backend's PostgreSQL connections over the last 24 hours.
func ResourcesPDF(ctx context.Context, r report.Resources, m report.Meta, opt Options) ([]byte, error) {
	loc := m.Loc
	stamp := report.Stamp(r.At, loc)
	d := newDoc("Ludo Arena — Server metrics, last 24 hours", m.Env+" · "+stamp,
		"Server metrics · "+m.Env+" · "+stamp, colCyan, r.At, opt)

	blue, orange, green, cyan := colAccent, colOrange, colGreen, colCyan
	cpu := r.Busiest(func(h report.HostUsage) report.Num { return h.CPUStats.Peak })
	ram := r.Busiest(func(h report.HostUsage) report.Num { return h.RAMStats.Peak })
	hostSub := func(h *report.HostUsage, extra string) string {
		if h == nil {
			return "no node_exporter data"
		}
		if len(r.Hosts) == 1 {
			return extra
		}
		return report.ShortInstance(h.Instance)
	}
	var cpuS, ramS report.SeriesStats
	var cores, mem report.Num
	if cpu != nil {
		cpuS, cores = cpu.CPUStats, cpu.Cores
	}
	if ram != nil {
		ramS, mem = ram.RAMStats, ram.MemBytes
	}
	d.section("Summary")
	d.tiles([]tile{
		{Label: "CPU now", Value: report.Pct(cpuS.Now), Sub: hostSub(cpu, countOf(cores, "core")), Accent: &blue},
		{Label: "CPU average (24 h)", Value: report.Pct(cpuS.Avg), Accent: &blue},
		{Label: "CPU peak (24 h)", Value: report.Pct(cpuS.Peak), Sub: peakSub(cpuS, loc), Accent: &blue},
		{Label: "PostgreSQL in use", Value: report.I(r.PGInUseStats.Now), Sub: pgSub(r), Accent: &green},
		{Label: "RAM now", Value: report.Pct(ramS.Now), Sub: hostSub(ram, "of "+report.Bytes(mem)), Accent: &orange},
		{Label: "RAM average (24 h)", Value: report.Pct(ramS.Avg), Accent: &orange},
		{Label: "RAM peak (24 h)", Value: report.Pct(ramS.Peak), Sub: peakSub(ramS, loc), Accent: &orange},
		{Label: "PostgreSQL peak in use", Value: report.I(r.PGInUseStats.Peak), Sub: peakSub(r.PGInUseStats, loc), Accent: &cyan},
	})
	if err := ctx.Err(); err != nil {
		return nil, ctxDone(err)
	}

	d.ensure(resChartH + 16)
	d.section("CPU usage")
	png, err := charts.TimeChart(charts.TimeSpec{
		Title: "CPU usage per host", YLabel: "CPU %", Percent: true, Area: len(r.Hosts) == 1,
		Lines: hostLines(r, func(h report.HostUsage) []charts.Point { return toChart(h.CPU) }),
		Marks: peakMark(cpuS, loc, report.Pct(cpuS.Peak)), Loc: loc, Start: r.Start, End: r.End, Step: r.Step, HeightMM: resChartH,
	})
	d.chart(png, err, resChartH, "CPU per host: no node_exporter data in the last 24 hours.")
	if err := ctx.Err(); err != nil {
		return nil, ctxDone(err)
	}

	d.ensure(resChartH + 16)
	d.section("RAM usage")
	png, err = charts.TimeChart(charts.TimeSpec{
		Title: "RAM in use per host", YLabel: "RAM %", Percent: true, Area: len(r.Hosts) == 1,
		Lines: hostLines(r, func(h report.HostUsage) []charts.Point { return toChart(h.RAM) }),
		Marks: peakMark(ramS, loc, report.Pct(ramS.Peak)), Loc: loc, Start: r.Start, End: r.End, Step: r.Step, HeightMM: resChartH,
	})
	d.chart(png, err, resChartH, "RAM per host: no node_exporter data in the last 24 hours.")
	if err := ctx.Err(); err != nil {
		return nil, ctxDone(err)
	}

	d.ensure(resChartH + 16)
	d.section("PostgreSQL connections")
	png, err = charts.TimeChart(charts.TimeSpec{
		Title: "Backend PostgreSQL pool connections (all instances)", YLabel: "connections", Area: true,
		Lines: []charts.Line{
			{Name: "Open", Points: toChart(r.PGOpen)},
			{Name: "In use", Points: toChart(r.PGInUse)},
			{Name: "Pool limit", Points: toChart(r.PGLimit)},
		},
		Marks: peakMark(r.PGInUseStats, loc, report.I(r.PGInUseStats.Peak)+" in use"),
		Loc:   loc, Start: r.Start, End: r.End, Step: r.Step, HeightMM: resChartH,
	})
	d.chart(png, err, resChartH, "PostgreSQL connections: no data in the last 24 hours (postgres_pool_connections is not exported by this backend).")
	if err := ctx.Err(); err != nil {
		return nil, ctxDone(err)
	}

	d.section("Hosts")
	if len(r.Hosts) == 0 {
		d.notice("No host metrics (node_exporter not scraped).")
	} else {
		rows := make([][]cell, 0, len(r.Hosts))
		for _, h := range r.Hosts {
			rows = append(rows, []cell{plain(report.ShortInstance(h.Instance)), plain(report.I(h.Cores)), plain(report.Bytes(h.MemBytes)),
				pctCell(h.CPUStats.Now), plain(report.Pct(h.CPUStats.Avg)), plain(peakText(h.CPUStats, loc)),
				pctCell(h.RAMStats.Now), plain(report.Pct(h.RAMStats.Avg)), plain(peakText(h.RAMStats, loc))})
		}
		d.richTable([]column{{"Host", 0.22, "L"}, {"Cores", 0.07, "R"}, {"Memory", 0.1, "R"},
			{"CPU now", 0.08, "R"}, {"CPU avg", 0.08, "R"}, {"CPU peak", 0.13, "R"},
			{"RAM now", 0.08, "R"}, {"RAM avg", 0.08, "R"}, {"RAM peak", 0.16, "R"}}, rows, colCyan)
	}
	footerNotes(d, r.Errors, fmt.Sprintf("CPU = 100%% minus idle time over %s windows; RAM = memory in use (MemAvailable). "+
		"PostgreSQL = the backend's connection pool summed over instances: open = in use + idle + being opened; the pool limit is DB_MAX_CONNS per instance. "+
		"Samples every %s.", "4-minute", report.Ago(r.Step)))
	return d.bytes()
}

func hostLines(r report.Resources, pts func(report.HostUsage) []charts.Point) []charts.Line {
	out := make([]charts.Line, 0, len(r.Hosts))
	for _, h := range r.Hosts {
		out = append(out, charts.Line{Name: report.ShortInstance(h.Instance), Points: pts(h)})
	}
	return out
}

func countOf(n report.Num, unit string) string {
	if !n.OK {
		return ""
	}
	if n.V == 1 {
		return "1 " + unit
	}
	return report.I(n) + " " + unit + "s"
}

func pgSub(r report.Resources) string {
	if !r.PGOpenStats.Now.OK {
		return "no pool metrics"
	}
	s := report.I(r.PGOpenStats.Now) + " open"
	if r.PGLimitNow.OK {
		s += " · limit " + report.I(r.PGLimitNow)
	}
	return s
}

// pctCell colours a utilisation: orange from 70 %, red from 85 %.
func pctCell(n report.Num) cell {
	c := plain(report.Pct(n))
	switch {
	case n.OK && n.V >= 85:
		c.Color, c.Bold = &colRed, true
	case n.OK && n.V >= 70:
		c.Color = &colOrange
	}
	return c
}

func peakText(st report.SeriesStats, loc *time.Location) string {
	if !st.Peak.OK {
		return report.NA
	}
	return report.Pct(st.Peak) + " · " + st.PeakAt.In(loc).Format("15:04")
}
