package pdfreport

import (
	"bytes"
	"compress/zlib"
	"io"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"ludoarena/opsbot/internal/alertmanager"
	"ludoarena/opsbot/internal/google"
	"ludoarena/opsbot/internal/promapi"
	"ludoarena/opsbot/internal/report"
)

var (
	ist  = mustLoc("Asia/Kolkata")
	meta = report.Meta{Env: "production", Loc: ist}
	now  = time.Date(2026, 10, 21, 17, 0, 0, 0, ist)
)

func mustLoc(name string) *time.Location {
	l, err := time.LoadLocation(name)
	if err != nil {
		panic(err)
	}
	return l
}

func wave(start time.Time, n int, step time.Duration, base, amp float64, phase float64) []promapi.Point {
	pts := make([]promapi.Point, n)
	for i := range pts {
		pts[i] = promapi.Point{T: start.Add(time.Duration(i) * step), V: base + amp*math.Sin(float64(i)/float64(n)*2*math.Pi+phase)}
	}
	return pts
}

func series(label, value string, pts []promapi.Point) promapi.Series {
	return promapi.Series{Labels: map[string]string{label: value}, Points: pts}
}

// SampleStatus is a realistic status with 24 h of chart data.
func SampleStatus() report.Status {
	start := now.Add(-24 * time.Hour)
	hourEnd := now
	var mh, ms []promapi.Point
	for i := 0; i < 24; i++ {
		t := hourEnd.Add(time.Duration(i-23) * time.Hour)
		mh = append(mh, promapi.Point{T: t, V: 300 + 200*math.Sin(float64(i)/4)})
		ms = append(ms, promapi.Point{T: t, V: 120 + 60*math.Cos(float64(i)/5)})
	}
	return report.Status{
		Snapshot: report.Snapshot{
			At: now, PlayingHuman: report.N(1234), PlayingBot: report.N(456),
			OnlineHuman: report.N(1502), OnlineBot: report.N(470),
			Hosts: []report.Host{
				{Instance: "app-1:9100", CPU: report.N(41.2), RAM: report.N(63.4), Disk: report.N(38)},
				{Instance: "app-2:9100", CPU: report.N(35.8), RAM: report.N(58.1), Disk: report.N(41)},
			},
			Processes: []report.Process{
				{Job: "backend", Instance: "app-1:9090", RSS: report.N(312 << 20), CPU: report.N(38)},
				{Job: "backend", Instance: "app-2:9090", RSS: report.N(298 << 20), CPU: report.N(31)},
				{Job: "bot-play", Instance: "app-1:9091", RSS: report.N(84 << 20), CPU: report.N(6)},
			},
			BackendUp: report.N(2), BackendTargets: report.N(2), BotPlayUp: report.N(1), BotPlayTargets: report.N(1),
		},
		RoomsByGame:      []report.KV{{Key: "ludo", V: 301}, {Key: "snakes_ladders", V: 118}},
		RoomsOK:          true,
		LobbyHuman:       report.N(12),
		LobbyBot:         report.N(0),
		StartedHumanOnly: report.N(380),
		StartedWithBots:  report.N(40),
		Finished:         report.N(410),
		NewAccounts:      report.N(35),
		DAU:              report.N(2300),
		Firing:           []report.FiringAlert{{Name: "HostCPUHigh", Severity: "warning", Count: 1, Instances: []string{"app-1:9100"}}},
		Charts: report.Charts{
			Start: start, End: now,
			Players: []promapi.Series{
				series("actor", "human", wave(start, 289, 5*time.Minute, 900, 400, 0)),
				series("actor", "bot", wave(start, 289, 5*time.Minute, 300, 150, 1)),
			},
			CPU: []promapi.Series{
				series("instance", "app-1:9100", wave(start, 289, 5*time.Minute, 45, 25, 0)),
				series("instance", "app-2:9100", wave(start, 289, 5*time.Minute, 35, 20, 0.5)),
			},
			RAM: []promapi.Series{
				series("instance", "app-1:9100", wave(start, 289, 5*time.Minute, 62, 5, 0)),
				series("instance", "app-2:9100", wave(start, 289, 5*time.Minute, 57, 4, 1)),
			},
			MatchesByGame: []promapi.Series{series("game", "ludo", mh), series("game", "snakes_ladders", ms)},
		},
	}
}

// SampleDigest is a realistic daily report with trends and Google data.
func SampleDigest(withGoogle bool) report.Digest {
	day := time.Date(2026, 10, 20, 0, 0, 0, 0, ist)
	civil := time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)
	from := civil.AddDate(0, 0, -29)
	var dau []report.DayValue
	var ludo, snakes, humans, bots, cpu, ram []report.DayValue
	for i := 0; i < 30; i++ {
		d := from.AddDate(0, 0, i)
		f := float64(i)
		if i >= 8 { // Prometheus retention covers 22 days
			dau = append(dau, report.DayValue{Day: d, V: 1800 + 25*f + 120*math.Sin(f/3)})
			ludo = append(ludo, report.DayValue{Day: d, V: 2800 + 40*f + 200*math.Sin(f/2)})
			snakes = append(snakes, report.DayValue{Day: d, V: 1200 + 20*f})
			humans = append(humans, report.DayValue{Day: d, V: 1100 + 15*f})
			bots = append(bots, report.DayValue{Day: d, V: 400 + 5*f})
			cpu = append(cpu, report.DayValue{Day: d, V: 55 + 15*math.Sin(f/4)})
			ram = append(ram, report.DayValue{Day: d, V: 66 + 3*math.Cos(f/5)})
		}
	}
	dg := report.Digest{
		Day: day, End: day.AddDate(0, 0, 1), DAUDay: civil,
		NewAccounts:           report.N(512),
		NewAccountsByProvider: []report.KV{{Key: "google", V: 301}, {Key: "guest", V: 211}},
		Logins:                report.N(4120),
		DAU:                   report.N(2510), WAU: report.N(9800),
		ByGameMode: []report.GameModeRow{
			{Game: "ludo", Mode: "public", Started: 3010, Completed: 2950},
			{Game: "ludo", Mode: "private", Started: 220, Completed: 210},
			{Game: "snakes_ladders", Mode: "public", Started: 1180, Completed: 1160},
			{Game: "snakes_ladders", Mode: "practice", Started: 90, Completed: 88},
		},
		Started: report.N(4500), Completed: report.N(4408),
		HumanOnly: report.N(4100), WithBots: report.N(400),
		Abandons: report.N(130), AbandonsByReason: []report.KV{{Key: "left", V: 90}, {Key: "timeout", V: 40}},
		PeakHuman: report.N(1534), PeakBot: report.N(512), PeakOnlineHuman: report.N(1820), PeakOnlineBot: report.N(530),
		WaitAvg: report.N(6.2), WaitP95: report.N(18.4),
		MatchmakingResults: []report.KV{{Key: "cancelled", V: 120}, {Key: "matched", V: 4010}, {Key: "timeout", V: 22}},
		HTTP5xx:            report.N(12), HTTPTotal: report.N(251000),
		Settlement: report.N(0), ClientErrors: report.N(31),
		PeakHosts:   []report.Host{{Instance: "app-1:9100", CPU: report.N(78), RAM: report.N(71)}},
		AlertsFired: []report.FiringAlert{{Name: "HostCPUHigh", Severity: "warning"}},
		Trends: report.Trends{
			Days: 30, From: from, To: civil, DAU: dau,
			MatchesByGame: []report.DaySeries{{Name: "ludo", Values: ludo}, {Name: "snakes_ladders", Values: snakes}},
			PeakPlayers:   []report.DaySeries{{Name: "bot", Values: bots}, {Name: "human", Values: humans}},
			CPUMax:        []report.DaySeries{{Name: "app-1:9100", Values: cpu}},
			RAMMax:        []report.DaySeries{{Name: "app-1:9100", Values: ram}},
		},
	}
	if withGoogle {
		var days []google.PlayDay
		for i := 0; i < 29; i++ {
			d := from.AddDate(0, 0, i)
			days = append(days, google.PlayDay{Date: d, Values: map[string]float64{
				google.ColDailyUserInstalls:     float64(140 + 3*i),
				google.ColDailyUserUninstalls:   float64(30 + i%7),
				google.ColDailyDeviceInstalls:   float64(150 + 3*i),
				google.ColDailyDeviceUninstalls: float64(35 + i%5),
				google.ColActiveDeviceInstalls:  float64(8000 + 110*i),
				google.ColTotalUserInstalls:     float64(12000 + 140*i),
			}})
		}
		dg.Play = report.PlaySection{Configured: true, Report: google.PlayReport{Days: days, Columns: []string{google.ColDailyUserInstalls, google.ColDailyUserUninstalls}}}
		var daily []google.GA4Day
		for i := 0; i < 30; i++ {
			daily = append(daily, google.GA4Day{Date: from.AddDate(0, 0, i), FirstOpens: float64(150 + 2*i), AppRemoves: float64(25 + i%6)})
		}
		dg.GA4 = report.GA4Section{Configured: true, Summary: google.GA4Summary{
			Date: civil,
			Platforms: []google.GA4Platform{
				{Platform: "Android", ActiveUsers: 2100, NewUsers: 160, FirstOpens: 170, AppRemoves: 31},
				{Platform: "iOS", ActiveUsers: 380, NewUsers: 28, FirstOpens: 29},
			},
			Totals: google.GA4Platform{Platform: "All", ActiveUsers: 2480, NewUsers: 188, FirstOpens: 199, AppRemoves: 31},
			Daily:  daily,
		}}
	}
	return dg
}

func sampleAlerts() []alertmanager.Alert {
	return []alertmanager.Alert{
		{Status: "firing", Labels: map[string]string{"alertname": "HostCPUHigh", "severity": "warning", "instance": "app-1:9100"},
			Annotations: map[string]string{"summary": "CPU usage on app-1:9100 is 92%", "description": "Above 85% for 5 minutes."},
			StartsAt:    now.Add(-12 * time.Minute)},
		{Status: "resolved", Labels: map[string]string{"alertname": "BackendInstanceDown", "severity": "critical", "instance": "app-2:9090"},
			Annotations: map[string]string{"summary": "Backend app-2:9090 is down"},
			StartsAt:    now.Add(-40 * time.Minute), EndsAt: now.Add(-5 * time.Minute)},
	}
}

// pdfText extracts the text drawn with Tj operators from every (inflated)
// content stream: enough to check what a reader would see.
func pdfText(t *testing.T, pdf []byte) string {
	t.Helper()
	var all bytes.Buffer
	streams := regexp.MustCompile(`(?s)stream\r?\n(.*?)\r?\nendstream`).FindAllSubmatch(pdf, -1)
	for _, s := range streams {
		r, err := zlib.NewReader(bytes.NewReader(s[1]))
		if err != nil {
			all.Write(s[1])
			continue
		}
		b, err := io.ReadAll(r)
		if err != nil {
			continue
		}
		all.Write(b)
	}
	var out strings.Builder
	for _, m := range regexp.MustCompile(`\(((?:\\.|[^\\)])*)\)\s*Tj`).FindAllSubmatch(all.Bytes(), -1) {
		s := strings.NewReplacer(`\(`, "(", `\)`, ")", `\\`, `\`).Replace(string(m[1]))
		out.WriteString(cp1252(s) + "\n")
	}
	return out.String()
}

// cp1252 decodes the few non-ASCII cp1252 characters the reports use.
func cp1252(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		switch c := s[i]; c {
		case 0x85:
			b.WriteString("…")
		case 0x96:
			b.WriteString("–")
		case 0x97:
			b.WriteString("—")
		case 0xB7:
			b.WriteString("·")
		default:
			b.WriteByte(c)
		}
	}
	return b.String()
}

func pageCount(pdf []byte) int {
	return len(regexp.MustCompile(`/Type /Page\b[^s]`).FindAll(pdf, -1))
}

func checkPDF(t *testing.T, pdf []byte, minPages, maxPages int, want ...string) string {
	t.Helper()
	if !bytes.HasPrefix(pdf, []byte("%PDF-")) {
		t.Fatalf("not a PDF: %q", pdf[:min(len(pdf), 16)])
	}
	if !bytes.Contains(pdf[len(pdf)-64:], []byte("%%EOF")) {
		t.Fatal("PDF has no EOF trailer")
	}
	if n := pageCount(pdf); n < minPages || n > maxPages {
		t.Fatalf("pages = %d, want %d–%d", n, minPages, maxPages)
	}
	text := pdfText(t, pdf)
	for _, w := range want {
		if !strings.Contains(text, w) {
			t.Errorf("PDF text lacks %q\n--- text ---\n%s", w, text)
		}
	}
	return text
}

func countImages(pdf []byte) int {
	return len(regexp.MustCompile(`/Subtype /Image`).FindAll(pdf, -1))
}

func TestStatusPDF(t *testing.T) {
	pdf, err := StatusPDF(SampleStatus(), meta, Options{})
	if err != nil {
		t.Fatal(err)
	}
	checkPDF(t, pdf, 1, 2, "Ludo Arena", "Hourly status", "production", "Real players playing", "1,234", "456",
		"Rooms in game", "419", "HostCPUHigh", "app-1:9100", "312 MiB", "Page 1/2")
	if n := countImages(pdf); n != 4 {
		t.Errorf("embedded charts = %d, want 4", n)
	}
}

func TestStatusPDFWithoutData(t *testing.T) {
	st := report.Status{Snapshot: report.Snapshot{At: now}}
	pdf, err := StatusPDF(st, meta, Options{})
	if err != nil {
		t.Fatal(err)
	}
	checkPDF(t, pdf, 1, 2, "n/a", "No alerts are firing.", "players_in_game is not exported", "no node_exporter data")
	if n := countImages(pdf); n != 0 {
		t.Errorf("charts without data = %d, want 0", n)
	}
}

func TestDigestPDF(t *testing.T) {
	pdf, err := DigestPDF(SampleDigest(true), meta, now, Options{})
	if err != nil {
		t.Fatal(err)
	}
	checkPDF(t, pdf, 2, 3, "Daily KPI report", "Tue 20 Oct 2026", "New accounts", "512", "google 301", "4,500",
		"Snakes & Ladders", "Google Play installs", "Latest available day", "Firebase Analytics (GA4)", "Android",
		"Trends: last 30 days", "DAU data for 22 of the 30 days")
	if n := countImages(pdf); n != 6 {
		t.Errorf("embedded charts = %d, want 6", n)
	}
}

func TestDigestPDFNotConfigured(t *testing.T) {
	dg := SampleDigest(false)
	dg.GA4 = report.GA4Section{Configured: true, Err: "google: PERMISSION_DENIED"}
	pdf, err := DigestPDF(dg, meta, now, Options{})
	if err != nil {
		t.Fatal(err)
	}
	text := checkPDF(t, pdf, 2, 3, "Not configured. Set PLAY_REPORTS_BUCKET", "Unavailable: google: PERMISSION_DENIED")
	if strings.Contains(text, "Latest available day") {
		t.Error("unconfigured Play section rendered data")
	}
}

// alertCharts is the last hour of the sample status (RAM left empty).
func alertCharts() report.Charts {
	st := SampleStatus()
	ch := report.Charts{Start: now.Add(-time.Hour), End: now}
	last := func(in []promapi.Series) (out []promapi.Series) {
		for _, s := range in {
			out = append(out, promapi.Series{Labels: s.Labels, Points: s.Points[len(s.Points)-13:]})
		}
		return out
	}
	ch.Players, ch.CPU = last(st.Charts.Players), last(st.Charts.CPU)
	return ch
}

func TestAlertPDF(t *testing.T) {
	pdf, err := AlertPDF(sampleAlerts(), SampleStatus().Snapshot, alertCharts(), meta, now, Options{})
	if err != nil {
		t.Fatal(err)
	}
	checkPDF(t, pdf, 1, 1, "Alert FIRING: HostCPUHigh (+1)", "resolved", "BackendInstanceDown", "lasted 35m",
		"Busiest host CPU", "41%", "Last hour", "RAM per host: no node_exporter data.")
	if n := countImages(pdf); n != 2 {
		t.Errorf("embedded charts = %d, want 2", n)
	}
	if got := AlertFileName(sampleAlerts(), now, ist); got != "ludo-arena-alert-HostCPUHigh-2026-10-21-1700-IST.pdf" {
		t.Errorf("AlertFileName = %q", got)
	}
}

func TestFileNames(t *testing.T) {
	if got := StatusFileName(now, ist); got != "ludo-arena-status-2026-10-21-1700-IST.pdf" {
		t.Errorf("StatusFileName = %q", got)
	}
	if got := DigestFileName(time.Date(2026, 10, 20, 0, 0, 0, 0, ist)); got != "ludo-arena-daily-2026-10-20.pdf" {
		t.Errorf("DigestFileName = %q", got)
	}
}

// TestWriteSamples writes the sample reports for manual review when
// OPSBOT_SAMPLE_DIR is set (go test ./internal/pdfreport -run Samples).
func TestWriteSamples(t *testing.T) {
	dir := os.Getenv("OPSBOT_SAMPLE_DIR")
	if dir == "" {
		t.Skip("OPSBOT_SAMPLE_DIR not set")
	}
	st, _ := StatusPDF(SampleStatus(), meta, Options{})
	dg, _ := DigestPDF(SampleDigest(true), meta, now, Options{})
	al, _ := AlertPDF(sampleAlerts(), SampleStatus().Snapshot, alertCharts(), meta, now, Options{})
	for name, b := range map[string][]byte{"fixture-status.pdf": st, "fixture-daily.pdf": dg, "fixture-alert.pdf": al} {
		if err := os.WriteFile(filepath.Join(dir, name), b, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}
