package report

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"ludoroyale/opsbot/internal/alertmanager"
	"ludoroyale/opsbot/internal/google"
)

// Meta is the per-deployment context of every message.
type Meta struct {
	Env string
	Loc *time.Location
}

func (m Meta) header(kind string, t time.Time) string {
	return fmt.Sprintf("<b>Ludo Royale · %s</b> — %s\n%s", Esc(m.Env), kind, Esc(Stamp(t, m.Loc)))
}

func joinNonEmpty(sep string, parts ...string) string {
	out := parts[:0:0]
	for _, p := range parts {
		if p != "" {
			out = append(out, p)
		}
	}
	return strings.Join(out, sep)
}

func kvLine(items []KV, name func(string) string) string {
	parts := make([]string, 0, len(items))
	for _, kv := range items {
		parts = append(parts, Esc(name(kv.Key))+" "+Int(kv.V))
	}
	return strings.Join(parts, " · ")
}

// StatusText renders the hourly status as Telegram HTML.
func StatusText(s Status, m Meta) string {
	var b strings.Builder
	b.WriteString(m.header("hourly status", s.At) + "\n\n")
	b.WriteString("<b>Playing now</b>\n")
	fmt.Fprintf(&b, "Real players %s · Bots %s\n", I(s.PlayingHuman), I(s.PlayingBot))
	rooms := "Rooms in game " + I(s.RoomsTotal())
	if len(s.RoomsByGame) > 0 {
		rooms += " (" + kvLine(s.RoomsByGame, GameName) + ")"
	}
	b.WriteString(rooms + "\n")
	fmt.Fprintf(&b, "Waiting in lobby: real %s · bots %s\n\n", I(s.LobbyHuman), I(s.LobbyBot))

	b.WriteString("<b>Online</b>\n")
	fmt.Fprintf(&b, "Real players %s · Bots %s\n\n", I(s.OnlineHuman), I(s.OnlineBot))

	b.WriteString("<b>Last hour</b>\n")
	fmt.Fprintf(&b, "Matches started %s (human-only %s · with bots %s)\n", I(s.StartedTotal()), I(s.StartedHumanOnly), I(s.StartedWithBots))
	fmt.Fprintf(&b, "Matches finished %s\n", I(s.Finished))
	fmt.Fprintf(&b, "New accounts %s · DAU %s\n\n", I(s.NewAccounts), I(s.DAU))

	b.WriteString("<b>Servers</b>\n")
	b.WriteString(serverLines(s.Snapshot, true))
	b.WriteString("\n<b>Alerts firing</b>\n")
	if len(s.Firing) == 0 {
		b.WriteString("none\n")
	}
	for _, a := range s.Firing {
		line := fmt.Sprintf("%s %s", Esc(a.Severity), Esc(a.Name))
		if a.Count > 1 {
			line += fmt.Sprintf(" ×%d", a.Count)
		} else if len(a.Instances) == 1 {
			line += " (" + Esc(a.Instances[0]) + ")"
		}
		b.WriteString(line + "\n")
	}
	b.WriteString(errorsFooter(s.Errors))
	return strings.TrimRight(b.String(), "\n")
}

func serverLines(s Snapshot, withProcs bool) string {
	var b strings.Builder
	if len(s.Hosts) == 0 {
		b.WriteString("Hosts: n/a (no node_exporter data)\n")
	}
	for _, h := range s.Hosts {
		fmt.Fprintf(&b, "%s: CPU %s · RAM %s · Disk %s\n", Esc(ShortInstance(h.Instance)), Pct(h.CPU), Pct(h.RAM), Pct(h.Disk))
	}
	if withProcs {
		for _, p := range s.Processes {
			fmt.Fprintf(&b, "%s %s: RSS %s · CPU %s\n", Esc(p.Job), Esc(ShortInstance(p.Instance)), Bytes(p.RSS), Pct(p.CPU))
		}
		fmt.Fprintf(&b, "Targets up: backend %s/%s · bot-play %s/%s\n", I(s.BackendUp), I(s.BackendTargets), I(s.BotPlayUp), I(s.BotPlayTargets))
	}
	return b.String()
}

func errorsFooter(errs []string) string {
	if len(errs) == 0 {
		return ""
	}
	shown := errs
	if len(shown) > 3 {
		shown = shown[:3]
	}
	out := "\n<i>Data gaps (" + Int(float64(len(errs))) + "): " + Esc(strings.Join(shown, "; ")) + "</i>\n"
	return out
}

// StatusCaption is the one-line summary sent with the status PDF.
func StatusCaption(s Status, m Meta) string {
	return fmt.Sprintf("%s · Playing: %s players · %s bots · CPU %s · RAM %s",
		Esc(m.Env), I(s.PlayingHuman), I(s.PlayingBot), Pct(s.MaxCPU()), Pct(s.MaxRAM()))
}

// DigestCaption is the one-line summary sent with the daily PDF.
func DigestCaption(d Digest, m Meta) string {
	return fmt.Sprintf("%s · %s: %s new accounts · DAU %s · %s matches · peak %s players",
		Esc(m.Env), d.Day.Format("2 Jan"), I(d.NewAccounts), I(d.DAU), I(d.Started), I(d.PeakHuman))
}

// DigestText renders the daily KPI digest as Telegram HTML.
func DigestText(d Digest, m Meta) string {
	var b strings.Builder
	fmt.Fprintf(&b, "<b>Ludo Royale · %s</b> — daily KPIs\n%s (%s)\n\n", Esc(m.Env), Date(d.Day), Esc(d.Day.Format("MST")))

	b.WriteString("<b>Players</b>\n")
	line := "New accounts " + I(d.NewAccounts)
	if len(d.NewAccountsByProvider) > 0 {
		line += " (" + kvLine(d.NewAccountsByProvider, func(s string) string { return s }) + ")"
	}
	b.WriteString(line + "\n")
	fmt.Fprintf(&b, "Sign-ins %s\n", I(d.Logins))
	fmt.Fprintf(&b, "DAU %s (UTC %s) · WAU %s\n", I(d.DAU), d.DAUDay.Format("2 Jan"), I(d.WAU))
	fmt.Fprintf(&b, "Peak playing: real %s · bots %s\n", I(d.PeakHuman), I(d.PeakBot))
	fmt.Fprintf(&b, "Peak online: real %s · bots %s\n\n", I(d.PeakOnlineHuman), I(d.PeakOnlineBot))

	b.WriteString("<b>Matches</b>\n")
	fmt.Fprintf(&b, "Started %s · finished %s\n", I(d.Started), I(d.Completed))
	fmt.Fprintf(&b, "Human-only %s %s· with bots %s\n", I(d.HumanOnly), parens(Share(d.HumanOnly, d.Started)), I(d.WithBots))
	for _, r := range d.ByGameMode {
		fmt.Fprintf(&b, "%s %s: %s started · %s finished\n", Esc(GameName(r.Game)), Esc(r.Mode), Int(r.Started), Int(r.Completed))
	}
	line = "Abandons " + I(d.Abandons)
	if len(d.AbandonsByReason) > 0 {
		line += " (" + kvLine(d.AbandonsByReason, func(s string) string { return s }) + ")"
	}
	b.WriteString(line + "\n")
	fmt.Fprintf(&b, "Matchmaking wait avg %s · p95 %s\n", Secs(d.WaitAvg), Secs(d.WaitP95))
	if len(d.MatchmakingResults) > 0 {
		b.WriteString("Matchmaking: " + kvLine(d.MatchmakingResults, func(s string) string { return s }) + "\n")
	}

	b.WriteString("\n<b>Reliability</b>\n")
	fmt.Fprintf(&b, "HTTP 5xx %s of %s requests\n", I(d.HTTP5xx), I(d.HTTPTotal))
	line = "Settlement failures " + I(d.Settlement)
	if len(d.SettlementByOp) > 0 {
		line += " (" + kvLine(d.SettlementByOp, func(s string) string { return s }) + ")"
	}
	b.WriteString(line + "\n")
	fmt.Fprintf(&b, "Client errors %s\n", I(d.ClientErrors))
	for _, h := range d.PeakHosts {
		fmt.Fprintf(&b, "Peak %s: CPU %s · RAM %s\n", Esc(ShortInstance(h.Instance)), Pct(h.CPU), Pct(h.RAM))
	}
	b.WriteString("Alerts fired: " + firedList(d.AlertsFired) + "\n")

	b.WriteString("\n" + PlayText(d.Play) + "\n")
	b.WriteString("\n" + GA4Text(d.GA4) + "\n")
	b.WriteString(errorsFooter(d.Errors))
	return strings.TrimRight(b.String(), "\n")
}

func parens(s string) string {
	if s == "" {
		return ""
	}
	return "(" + s + ") "
}

func firedList(a []FiringAlert) string {
	if len(a) == 0 {
		return "none"
	}
	names := make([]string, 0, len(a))
	for _, x := range a {
		names = append(names, Esc(x.Name))
	}
	return strings.Join(names, ", ")
}

// PlayText renders the Google Play section.
func PlayText(p PlaySection) string {
	const title = "<b>Google Play installs</b>"
	switch {
	case !p.Configured:
		return title + "\nnot configured (set PLAY_REPORTS_BUCKET)"
	case p.Err != "":
		return title + "\nunavailable: " + Esc(p.Err)
	}
	day, ok := p.Report.Latest()
	if !ok {
		return title + "\nno report rows yet (Play reports lag 1–2 days)"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s (latest day %s)\n", title, day.Date.Format("2006-01-02"))
	for _, row := range playRows {
		if v, ok := day.Values[row.col]; ok {
			fmt.Fprintf(&b, "%s %s\n", row.label, Int(v))
		}
	}
	return strings.TrimRight(b.String(), "\n")
}

var playRows = []struct{ col, label string }{
	{google.ColDailyUserInstalls, "User installs"},
	{google.ColDailyUserUninstalls, "User uninstalls"},
	{google.ColDailyDeviceInstalls, "Device installs"},
	{google.ColDailyDeviceUninstalls, "Device uninstalls"},
	{google.ColDailyDeviceUpgrades, "Device upgrades"},
	{google.ColActiveDeviceInstalls, "Active device installs"},
	{google.ColTotalUserInstalls, "Total user installs"},
	{google.ColInstallEvents, "Install events"},
	{google.ColUninstallEvents, "Uninstall events"},
	{google.ColUpdateEvents, "Update events"},
}

// PlayRows lists the Play columns in display order (column, label).
func PlayRows() [][2]string {
	out := make([][2]string, 0, len(playRows))
	for _, r := range playRows {
		out = append(out, [2]string{r.col, r.label})
	}
	return out
}

// GA4Text renders the Firebase Analytics section.
func GA4Text(g GA4Section) string {
	const title = "<b>Firebase Analytics</b>"
	switch {
	case !g.Configured:
		return title + "\nnot configured (set GA4_PROPERTY_ID)"
	case g.Err != "":
		return title + "\nunavailable: " + Esc(g.Err)
	}
	s := g.Summary
	var b strings.Builder
	fmt.Fprintf(&b, "%s (%s)\n", title, s.Date.Format("2006-01-02"))
	fmt.Fprintf(&b, "Installs (first_open) %s%s\n", Int(s.Totals.FirstOpens), platformSplit(s.Platforms, func(p google.GA4Platform) float64 { return p.FirstOpens }))
	fmt.Fprintf(&b, "Uninstalls (app_remove, Android) %s\n", Int(s.Totals.AppRemoves))
	fmt.Fprintf(&b, "Active users %s%s\n", Int(s.Totals.ActiveUsers), platformSplit(s.Platforms, func(p google.GA4Platform) float64 { return p.ActiveUsers }))
	fmt.Fprintf(&b, "New users %s", Int(s.Totals.NewUsers))
	return b.String()
}

func platformSplit(ps []google.GA4Platform, f func(google.GA4Platform) float64) string {
	if len(ps) < 2 {
		return ""
	}
	parts := make([]string, 0, len(ps))
	for _, p := range ps {
		parts = append(parts, Esc(p.Platform)+" "+Int(f(p)))
	}
	return " (" + strings.Join(parts, " · ") + ")"
}

// MaxAlertsPerMessage bounds one alert message.
const MaxAlertsPerMessage = 10

// AlertText renders an Alertmanager notification enriched with the current
// resource usage and player counts.
func AlertText(alerts []alertmanager.Alert, snap Snapshot, m Meta, now time.Time) string {
	sorted := append([]alertmanager.Alert(nil), alerts...)
	sort.SliceStable(sorted, func(i, j int) bool {
		if sorted[i].Firing() != sorted[j].Firing() {
			return sorted[i].Firing()
		}
		return severityRank(sorted[i].Severity()) > severityRank(sorted[j].Severity())
	})
	var b strings.Builder
	for i, a := range sorted {
		if i == MaxAlertsPerMessage {
			fmt.Fprintf(&b, "… and %d more\n\n", len(sorted)-i)
			break
		}
		b.WriteString(AlertBlock(a, m, now) + "\n\n")
	}
	b.WriteString(SnapshotLine(snap))
	fmt.Fprintf(&b, "\n<i>%s · %s</i>", Esc(m.Env), Esc(Clock(now, m.Loc)))
	return b.String()
}

// AlertBlock renders one alert (2–4 lines).
func AlertBlock(a alertmanager.Alert, m Meta, now time.Time) string {
	var b strings.Builder
	if a.Firing() {
		fmt.Fprintf(&b, "%s <b>FIRING</b> · %s · %s\n", severityIcon(a.Severity()), Esc(a.Severity()), Esc(a.Name()))
	} else {
		fmt.Fprintf(&b, "✅ <b>RESOLVED</b> · %s\n", Esc(a.Name()))
	}
	fmt.Fprintf(&b, "<b>%s</b>\n", Esc(a.Summary()))
	where := joinNonEmpty(" · ", Esc(a.Instance()))
	if !a.StartsAt.IsZero() {
		if a.Firing() {
			where = joinNonEmpty(" · ", where, fmt.Sprintf("since %s (%s)", Esc(Clock(a.StartsAt, m.Loc)), Ago(now.Sub(a.StartsAt))))
		} else if !a.EndsAt.IsZero() && a.EndsAt.After(a.StartsAt) {
			where = joinNonEmpty(" · ", where, "lasted "+Ago(a.EndsAt.Sub(a.StartsAt)))
		}
	}
	if where != "" {
		b.WriteString(where + "\n")
	}
	if d := a.Description(); d != "" && a.Firing() {
		if r := []rune(d); len(r) > 300 {
			d = string(r[:300]) + "…"
		}
		b.WriteString(Esc(d) + "\n")
	}
	return strings.TrimRight(b.String(), "\n")
}

func severityIcon(s string) string {
	switch s {
	case "critical":
		return "🔴"
	case "warning":
		return "🟠"
	}
	return "🔵"
}

// SnapshotLine is the "now" context appended to alerts.
func SnapshotLine(s Snapshot) string {
	var b strings.Builder
	b.WriteString("<b>Now</b> ")
	switch len(s.Hosts) {
	case 0:
		b.WriteString("CPU n/a · RAM n/a")
	case 1:
		fmt.Fprintf(&b, "CPU %s · RAM %s", Pct(s.Hosts[0].CPU), Pct(s.Hosts[0].RAM))
	default:
		parts := make([]string, 0, len(s.Hosts))
		for i, h := range s.Hosts {
			if i == 4 {
				parts = append(parts, fmt.Sprintf("+%d hosts", len(s.Hosts)-i))
				break
			}
			parts = append(parts, fmt.Sprintf("%s CPU %s RAM %s", Esc(ShortInstance(h.Instance)), Pct(h.CPU), Pct(h.RAM)))
		}
		b.WriteString(strings.Join(parts, " · "))
	}
	fmt.Fprintf(&b, "\nPlaying: real %s · bots %s · online real %s · bots %s",
		I(s.PlayingHuman), I(s.PlayingBot), I(s.OnlineHuman), I(s.OnlineBot))
	return b.String()
}

// AlertCaption is the short caption of a PDF alert.
func AlertCaption(alerts []alertmanager.Alert, m Meta, now time.Time) string {
	var firing, resolved []string
	for _, a := range alerts {
		if a.Firing() {
			firing = append(firing, a.Name())
		} else {
			resolved = append(resolved, a.Name())
		}
	}
	var parts []string
	if len(firing) > 0 {
		parts = append(parts, "FIRING: "+strings.Join(uniq(firing), ", "))
	}
	if len(resolved) > 0 {
		parts = append(parts, "RESOLVED: "+strings.Join(uniq(resolved), ", "))
	}
	return fmt.Sprintf("%s · %s · %s", Esc(m.Env), Esc(strings.Join(parts, " · ")), Esc(Clock(now, m.Loc)))
}

func uniq(s []string) []string {
	seen := map[string]bool{}
	out := s[:0:0]
	for _, x := range s {
		if !seen[x] {
			seen[x] = true
			out = append(out, x)
		}
	}
	return out
}
