package report

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
)

// NA is shown for missing values.
const NA = "n/a"

// Esc escapes text for Telegram's HTML parse mode.
func Esc(s string) string {
	return htmlEscaper.Replace(s)
}

var htmlEscaper = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;")

// Int formats a number rounded to an integer with thousands separators.
func Int(v float64) string {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return NA
	}
	n := int64(math.Round(v))
	neg := n < 0
	if neg {
		n = -n
	}
	s := strconv.FormatInt(n, 10)
	var b strings.Builder
	if neg {
		b.WriteByte('-')
	}
	for i := 0; i < len(s); i++ {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// I formats a Num as an integer or n/a.
func I(n Num) string {
	if !n.OK {
		return NA
	}
	return Int(n.V)
}

// Pct formats a percentage without decimals ("41%").
func Pct(n Num) string {
	if !n.OK {
		return NA
	}
	return fmt.Sprintf("%.0f%%", n.V)
}

// Secs formats seconds ("4.2 s").
func Secs(n Num) string {
	if !n.OK || math.IsNaN(n.V) || math.IsInf(n.V, 0) {
		return NA
	}
	if n.V >= 100 {
		return Int(n.V) + " s"
	}
	return strconv.FormatFloat(n.V, 'f', 1, 64) + " s"
}

// Bytes formats a byte count with binary units ("312 MiB").
func Bytes(n Num) string {
	if !n.OK {
		return NA
	}
	v := n.V
	units := []string{"B", "KiB", "MiB", "GiB", "TiB"}
	i := 0
	for v >= 1024 && i < len(units)-1 {
		v /= 1024
		i++
	}
	if v >= 100 || i == 0 {
		return fmt.Sprintf("%.0f %s", v, units[i])
	}
	return fmt.Sprintf("%.1f %s", v, units[i])
}

// Share formats part/total as a percentage, or "" when undefined.
func Share(part, total Num) string {
	if !part.OK || !total.OK || total.V <= 0 {
		return ""
	}
	return fmt.Sprintf("%.0f%%", 100*part.V/total.V)
}

// Stamp formats a time in loc for headers ("Tue 21 Oct 2026, 17:00 IST").
func Stamp(t time.Time, loc *time.Location) string {
	return t.In(loc).Format("Mon 2 Jan 2006, 15:04 MST")
}

// Clock formats a time of day in loc ("17:04 IST").
func Clock(t time.Time, loc *time.Location) string {
	return t.In(loc).Format("15:04 MST")
}

// Date formats a civil date ("Mon 20 Oct 2026").
func Date(t time.Time) string { return t.Format("Mon 2 Jan 2006") }

// Ago formats a duration compactly ("12m", "3h 5m", "2d 4h").
func Ago(d time.Duration) string {
	if d < time.Minute {
		return "<1m"
	}
	d = d.Round(time.Minute)
	days := int(d / (24 * time.Hour))
	h := int(d % (24 * time.Hour) / time.Hour)
	m := int(d % time.Hour / time.Minute)
	switch {
	case days > 0:
		return fmt.Sprintf("%dd %dh", days, h)
	case h > 0:
		return fmt.Sprintf("%dh %dm", h, m)
	default:
		return fmt.Sprintf("%dm", m)
	}
}

// GameName is the display name of a game label value.
func GameName(g string) string {
	switch g {
	case "ludo":
		return "Ludo"
	case "ludo_quick":
		return "Ludo Quick"
	case "snakes_ladders":
		return "Snakes & Ladders"
	case "":
		return "(none)"
	}
	return Title(g)
}

// Title turns a label value into words ("human_only" → "Human only").
func Title(s string) string {
	s = strings.ReplaceAll(s, "_", " ")
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

// ShortInstance shortens host:port for compact tables.
func ShortInstance(s string) string {
	if len(s) > 32 {
		return s[:31] + "…"
	}
	return s
}
