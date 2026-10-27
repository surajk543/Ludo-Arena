package pdfreport

// Richer building blocks of the on-demand reports (/live, /playtime,
// /metrics): ranked tables with medal badges, coloured cells and inline
// bars, a proportion bar, and printable player names.

import (
	"fmt"
	"math"
	"slices"
	"strings"
	"unicode"

	"golang.org/x/text/encoding/charmap"

	"ludoarena/opsbot/internal/report"
)

var (
	colPurple = rgb{0x93, 0x33, 0xEA}
	colCyan   = rgb{0x08, 0x91, 0xB2}
	colAmber  = rgb{0xCA, 0x8A, 0x04}
	colSlate  = rgb{0x94, 0xA3, 0xB8}
	colGold   = rgb{0xD9, 0x9A, 0x06}
	colSilver = rgb{0x8C, 0x96, 0xA3}
	colBronze = rgb{0xB4, 0x6A, 0x3C}
	colStripe = rgb{0xFA, 0xFA, 0xFB}
	colWhite  = rgb{0xFF, 0xFF, 0xFF}
)

// gameColor matches the chart palette (charts.fixed).
func gameColor(game string) rgb {
	if game == "snakes_ladders" {
		return colCyan
	}
	return colPurple
}

// cell is one value of a rich table.
type cell struct {
	Text  string
	Color *rgb // text colour (default ink)
	Bold  bool
	Badge *rgb // white text on a filled circle (rank medals)
	// HasBar draws a proportional bar (Bar 0..1) with Text right-aligned after it.
	HasBar bool
	Bar    float64
}

func plain(s string) cell { return cell{Text: s} }

func barCell(frac float64, text string) cell { return cell{Text: text, HasBar: true, Bar: frac} }

// rankCell is the rank column: medals for the first three.
func rankCell(rank int) cell {
	c := cell{Text: fmt.Sprint(rank), Bold: rank <= 3}
	switch rank {
	case 1:
		c.Badge = &colGold
	case 2:
		c.Badge = &colSilver
	case 3:
		c.Badge = &colBronze
	}
	return c
}

// richTable draws a striped table of cells; the header repeats on every
// page. barColor fills the inline bars.
func (d *doc) richTable(cols []column, rows [][]cell, barColor rgb) {
	p := d.pdf
	const rh = 6.2
	d.ensure(rh * float64(min(len(rows), 4)+1))
	header := func() {
		d.fill(colLight)
		d.font("B", 8, colMuted)
		p.SetX(margin)
		for _, c := range cols {
			p.CellFormat(c.W*contentW, rh, d.tr(c.Title), "", 0, align(c.Align), true, 0, "")
		}
		p.Ln(rh)
	}
	header()
	for i, r := range rows {
		if p.GetY()+rh > pageH-margin-6 {
			p.AddPage()
			header()
		}
		y := p.GetY()
		if i%2 == 1 {
			d.fill(colStripe)
		} else {
			d.fill(colWhite)
		}
		p.Rect(margin, y, contentW, rh, "F")
		x := margin
		for j, col := range cols {
			w := col.W * contentW
			if j < len(r) {
				d.cell(r[j], x, y, w, rh, align(col.Align), barColor)
			}
			x += w
		}
		p.SetXY(margin, y+rh)
	}
	d.draw(colBorder)
	p.SetLineWidth(0.2)
	p.Line(margin, p.GetY(), pageW-margin, p.GetY())
	p.Ln(gap)
}

func (d *doc) cell(c cell, x, y, w, h float64, al string, barColor rgb) {
	p := d.pdf
	style := ""
	if c.Bold {
		style = "B"
	}
	ink := colInk
	if c.Color != nil {
		ink = *c.Color
	}
	switch {
	case c.Badge != nil:
		d.fill(*c.Badge)
		cx := x + w/2
		if al == "L" {
			cx = x + 3.2
		}
		p.Circle(cx, y+h/2, 2.3, "F")
		d.font("B", 7.5, colWhite)
		p.SetXY(cx-3, y)
		p.CellFormat(6, h, d.tr(c.Text), "", 0, "C", false, 0, "")
	case c.HasBar:
		const textW = 13.0
		bw := math.Max(w-textW-2, 4)
		d.fill(colLight)
		p.RoundedRect(x+1, y+h/2-1.3, bw, 2.6, 1.3, "1234", "F")
		if frac := math.Min(math.Max(c.Bar, 0), 1); frac > 0 {
			d.fill(barColor)
			p.RoundedRect(x+1, y+h/2-1.3, math.Max(bw*frac, 2.6), 2.6, 1.3, "1234", "F")
		}
		d.font(style, 8, ink)
		p.SetXY(x+w-textW, y)
		p.CellFormat(textW, h, d.tr(c.Text), "", 0, "R", false, 0, "")
	default:
		d.font(style, 8.5, ink)
		p.SetXY(x, y)
		p.CellFormat(w, h, d.tr(fit(p, d.tr, c.Text, w-2)), "", 0, al, false, 0, "")
	}
}

// share is one segment of a proportion bar.
type share struct {
	Label string
	V     float64
	Color rgb
}

// splitBar draws a labelled 100 % bar of parts with a legend below it
// ("Ludo 40 · 31%"). Nothing is drawn when the parts add up to zero.
func (d *doc) splitBar(title string, parts []share, format func(float64) string) {
	var total float64
	for _, s := range parts {
		total += math.Max(s.V, 0)
	}
	if total <= 0 {
		return
	}
	p := d.pdf
	const barH = 5.5
	d.ensure(barH + 18)
	d.font("B", 8.5, colMuted)
	p.SetX(margin)
	p.CellFormat(contentW, 5, d.tr(title), "", 1, "L", false, 0, "")
	y := p.GetY() + 0.5
	d.fill(colLight)
	p.RoundedRect(margin, y, contentW, barH, 1.8, "1234", "F")
	x := margin
	for i, s := range parts {
		if s.V <= 0 {
			continue
		}
		w := contentW * s.V / total
		d.fill(s.Color)
		corners := ""
		if x == margin {
			corners += "14"
		}
		if i == len(parts)-1 || x+w >= margin+contentW-0.01 {
			corners += "23"
		}
		p.RoundedRect(x, y, w, barH, 1.8, corners, "F")
		x += w
	}
	ly := y + barH + 2.2
	lx := margin
	for _, s := range parts {
		label := fmt.Sprintf("%s %s · %.0f%%", s.Label, format(s.V), 100*math.Max(s.V, 0)/total)
		d.font("", 8, colInk)
		lw := p.GetStringWidth(d.tr(label)) + 8
		if lx+lw > margin+contentW {
			lx = margin
			ly += 5
		}
		d.fill(s.Color)
		p.RoundedRect(lx, ly+1, 3, 3, 0.8, "1234", "F")
		p.SetXY(lx+4.2, ly)
		p.CellFormat(lw-4.2, 5, d.tr(label), "", 0, "L", false, 0, "")
		lx += lw
	}
	p.SetY(ly + 5 + gap)
}

// scripts names the writing systems the PDF font (Helvetica, cp1252) cannot
// draw, so a name in them is labelled instead of printed as dots.
var scripts = []struct {
	name  string
	table *unicode.RangeTable
}{
	{"Devanagari", unicode.Devanagari}, {"Arabic", unicode.Arabic}, {"Bengali", unicode.Bengali},
	{"Gurmukhi", unicode.Gurmukhi}, {"Gujarati", unicode.Gujarati}, {"Tamil", unicode.Tamil},
	{"Telugu", unicode.Telugu}, {"Kannada", unicode.Kannada}, {"Malayalam", unicode.Malayalam},
	{"Sinhala", unicode.Sinhala}, {"Thai", unicode.Thai}, {"Cyrillic", unicode.Cyrillic},
	{"Greek", unicode.Greek}, {"Hebrew", unicode.Hebrew}, {"Chinese", unicode.Han},
	{"Japanese", unicode.Hiragana}, {"Japanese", unicode.Katakana}, {"Korean", unicode.Hangul},
}

func scriptOf(r rune) string {
	for _, s := range scripts {
		if unicode.Is(s.table, r) {
			return s.name
		}
	}
	return "symbols"
}

// printable reports whether the PDF font can draw r.
func printable(r rune) bool {
	if r < 0x80 {
		return unicode.IsPrint(r)
	}
	_, ok := charmap.Windows1252.EncodeRune(r)
	return ok
}

// PDFName makes a player name printable: characters the PDF font cannot
// draw are left out and their script is named ("Raj [+Devanagari]",
// "[Arabic script]"). The user id next to it stays exact. Combining marks
// of an unprintable script (vowel signs) do not add a script of their own.
func PDFName(name string) string {
	var kept strings.Builder
	var found []string
	for _, r := range name {
		if printable(r) {
			kept.WriteRune(r)
			continue
		}
		if unicode.Is(unicode.Mn, r) || unicode.Is(unicode.Mc, r) || r == '‍' || r == '‌' || r == '️' {
			if len(found) > 0 {
				continue
			}
		}
		if s := scriptOf(r); !slices.Contains(found, s) {
			found = append(found, s)
		}
	}
	if len(found) == 0 {
		return name
	}
	k := strings.Join(strings.Fields(kept.String()), " ")
	label := strings.Join(found, "/")
	if strings.IndexFunc(k, unicode.IsLetter) >= 0 {
		return k + " [+" + label + "]"
	}
	if label == "symbols" {
		return "[symbols]"
	}
	return "[" + label + " script]"
}

// ctxDone is the error of a cancelled report (checked between sections).
func ctxDone(err error) error {
	if err == nil {
		return nil
	}
	return fmt.Errorf("pdf cancelled: %w", err)
}

// minutesOf formats seconds as minutes for legends and tables.
func minutesOf(v float64) string { return report.Minutes(int64(v)) }
