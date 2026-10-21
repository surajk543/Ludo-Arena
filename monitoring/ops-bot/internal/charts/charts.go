// Package charts renders the report charts as PNG images with gonum/plot
// (pure Go, no cgo). Charts share one palette, white background, light
// horizontal grid lines, thousands separators and local-time axes.
package charts

import (
	"bytes"
	"errors"
	"fmt"
	"image/color"
	"math"
	"strconv"
	"strings"
	"time"

	xfont "golang.org/x/image/font"
	"gonum.org/v1/plot"
	pfont "gonum.org/v1/plot/font"
	"gonum.org/v1/plot/plotter"
	"gonum.org/v1/plot/vg"
	"gonum.org/v1/plot/vg/draw"
	"gonum.org/v1/plot/vg/vgimg"
)

// ErrNoData is returned when there is nothing to draw.
var ErrNoData = errors.New("charts: no data")

// Default image geometry: a full-width A4 chart at 150 dpi.
const (
	DefaultWidthMM  = 180
	DefaultHeightMM = 57
	DPI             = 150
)

// Point is one sample of a time series.
type Point struct {
	T time.Time
	V float64
}

// Line is a named time series.
type Line struct {
	Name   string
	Points []Point
}

// TimeSpec describes a time-series line chart.
type TimeSpec struct {
	Title, YLabel     string
	Lines             []Line
	Loc               *time.Location
	Start, End        time.Time     // x range (zero: from the data)
	Step              time.Duration // sample spacing; gaps > 2.5 steps break the line
	Percent           bool          // y axis 0–100 %
	WidthMM, HeightMM float64
}

// Bars is one named series of a bar chart.
type Bars struct {
	Name   string
	Values []float64
}

// BarSpec describes a bar chart over categories (hours or days).
type BarSpec struct {
	Title, YLabel     string
	Categories        []string
	Series            []Bars
	Stacked           bool
	WidthMM, HeightMM float64
}

// Palette is the categorical palette (colour-blind friendly order).
var Palette = []color.RGBA{
	{0x25, 0x63, 0xEB, 0xFF}, // blue
	{0xF9, 0x73, 0x16, 0xFF}, // orange
	{0x16, 0xA3, 0x4A, 0xFF}, // green
	{0xDC, 0x26, 0x26, 0xFF}, // red
	{0x93, 0x33, 0xEA, 0xFF}, // purple
	{0x08, 0x91, 0xB2, 0xFF}, // cyan
	{0xCA, 0x8A, 0x04, 0xFF}, // amber
	{0xDB, 0x27, 0x77, 0xFF}, // pink
}

// fixed colours keep meanings stable across charts.
var fixed = map[string]color.RGBA{
	"real players": Palette[0], "human": Palette[0], "humans": Palette[0],
	"bots": Palette[1], "bot": Palette[1],
	"installs": Palette[2], "first_open": Palette[2], "first opens": Palette[2],
	"uninstalls": Palette[3], "app_remove": Palette[3], "app removes": Palette[3],
	"ludo": Palette[4], "snakes & ladders": Palette[5],
}

// ColorFor returns the colour of series i named name.
func ColorFor(name string, i int) color.RGBA {
	if c, ok := fixed[strings.ToLower(name)]; ok {
		return c
	}
	return Palette[i%len(Palette)]
}

var (
	ink     = color.RGBA{0x1F, 0x29, 0x37, 0xFF}
	subtle  = color.RGBA{0x6B, 0x72, 0x80, 0xFF}
	gridCol = color.RGBA{0xE5, 0xE7, 0xEB, 0xFF}
)

func init() {
	// Sans-serif text everywhere (gonum's default is Liberation Serif).
	plot.DefaultFont = pfont.Font{Typeface: "Liberation", Variant: "Sans"}
}

func newPlot(title, ylabel string) *plot.Plot {
	p := plot.New()
	p.Title.Text = title
	p.Title.TextStyle.Font.Size = vg.Points(11)
	p.Title.TextStyle.Font.Weight = xfont.WeightBold
	p.Title.TextStyle.Color = ink
	p.Title.Padding = vg.Points(6)
	p.Y.Label.Text = ylabel
	p.Y.Label.TextStyle.Font.Size = vg.Points(8.5)
	p.Y.Label.TextStyle.Color = subtle
	for _, a := range []*plot.Axis{&p.X, &p.Y} {
		a.Tick.Label.Font.Size = vg.Points(8)
		a.Tick.Label.Color = subtle
		a.Tick.LineStyle.Color = gridCol
		a.LineStyle.Color = gridCol
		a.Padding = vg.Points(2)
	}
	p.Legend.Top = true
	p.Legend.Left = true
	p.Legend.TextStyle.Font.Size = vg.Points(8)
	p.Legend.TextStyle.Color = ink
	p.Legend.XOffs = vg.Points(6)
	p.Legend.YOffs = vg.Points(-2)
	p.Legend.ThumbnailWidth = vg.Points(14)
	g := plotter.NewGrid()
	g.Vertical.Width = 0
	g.Horizontal.Color = gridCol
	g.Horizontal.Width = vg.Points(0.5)
	p.Add(g)
	return p
}

// TimeChart renders a line chart of time series.
func TimeChart(s TimeSpec) ([]byte, error) {
	loc := s.Loc
	if loc == nil {
		loc = time.UTC
	}
	p := newPlot(s.Title, s.YLabel)
	var ymax float64
	var tmin, tmax time.Time
	drawn := 0
	for i, l := range s.Lines {
		segs := segments(l.Points, s.Step)
		if len(segs) == 0 {
			continue
		}
		c := ColorFor(l.Name, i)
		for j, seg := range segs {
			xys := make(plotter.XYs, len(seg))
			for k, pt := range seg {
				xys[k].X = float64(pt.T.Unix())
				xys[k].Y = pt.V
				ymax = math.Max(ymax, pt.V)
				if tmin.IsZero() || pt.T.Before(tmin) {
					tmin = pt.T
				}
				if pt.T.After(tmax) {
					tmax = pt.T
				}
			}
			ln, err := plotter.NewLine(xys)
			if err != nil {
				return nil, fmt.Errorf("charts: %w", err)
			}
			ln.Color = c
			ln.Width = vg.Points(1.4)
			p.Add(ln)
			if len(seg) == 1 { // a lone sample is invisible as a line
				sc, _ := plotter.NewScatter(xys)
				sc.Color = c
				sc.Radius = vg.Points(1.5)
				p.Add(sc)
			}
			if j == 0 && l.Name != "" {
				p.Legend.Add(l.Name, ln)
			}
		}
		drawn++
	}
	if drawn == 0 {
		return nil, ErrNoData
	}
	if !s.Start.IsZero() {
		tmin = s.Start
	}
	if !s.End.IsZero() {
		tmax = s.End
	}
	if !tmax.After(tmin) {
		tmax = tmin.Add(time.Minute)
	}
	p.X.Min, p.X.Max = float64(tmin.Unix()), float64(tmax.Unix())
	p.X.Tick.Marker = timeTicker{loc: loc, span: tmax.Sub(tmin)}
	p.Y.Min = 0
	if s.Percent {
		p.Y.Max = 100 * 1.22
		p.Y.Tick.Marker = numTicker{percent: true, max: 100}
	} else {
		p.Y.Max = headroom(ymax)
		p.Y.Tick.Marker = numTicker{max: p.Y.Max / 1.22}
	}
	return render(p, s.WidthMM, s.HeightMM)
}

// BarChart renders grouped or stacked bars over categories.
func BarChart(s BarSpec) ([]byte, error) {
	if len(s.Categories) == 0 || len(s.Series) == 0 {
		return nil, ErrNoData
	}
	hasData := false
	for _, b := range s.Series {
		for _, v := range b.Values {
			if v > 0 {
				hasData = true
			}
		}
	}
	if !hasData {
		return nil, ErrNoData
	}
	p := newPlot(s.Title, s.YLabel)
	w := widthMM(s.WidthMM, DefaultWidthMM)
	slot := vg.Length(w*0.80/float64(len(s.Categories))) * vg.Millimeter
	barW := slot * 0.7
	if !s.Stacked && len(s.Series) > 1 {
		barW = slot * 0.8 / vg.Length(len(s.Series))
	}
	var prev *plotter.BarChart
	totals := make([]float64, len(s.Categories))
	for i, ser := range s.Series {
		vals := make(plotter.Values, len(s.Categories))
		for k := range vals {
			if k < len(ser.Values) && ser.Values[k] > 0 && !math.IsNaN(ser.Values[k]) {
				vals[k] = ser.Values[k]
			}
			totals[k] += vals[k]
		}
		bc, err := plotter.NewBarChart(vals, barW)
		if err != nil {
			return nil, fmt.Errorf("charts: %w", err)
		}
		bc.Color = ColorFor(ser.Name, i)
		bc.LineStyle.Width = 0
		if s.Stacked {
			if prev != nil {
				bc.StackOn(prev)
			}
			prev = bc
		} else if len(s.Series) > 1 {
			bc.Offset = barW * (vg.Length(i) - vg.Length(len(s.Series)-1)/2)
		}
		p.Add(bc)
		p.Legend.Add(ser.Name, bc)
	}
	var ymax float64
	for k, t := range totals {
		if s.Stacked {
			ymax = math.Max(ymax, t)
		} else {
			for _, ser := range s.Series {
				if k < len(ser.Values) {
					ymax = math.Max(ymax, ser.Values[k])
				}
			}
		}
	}
	p.NominalX(s.Categories...)
	p.X.Tick.Marker = sparseLabels{labels: s.Categories, max: 12}
	p.X.Padding = 0
	p.Y.Min = 0
	p.Y.Max = headroom(ymax)
	p.Y.Tick.Marker = numTicker{max: p.Y.Max / 1.22}
	return render(p, s.WidthMM, s.HeightMM)
}

func widthMM(v, def float64) float64 {
	if v <= 0 {
		return def
	}
	return v
}

func render(p *plot.Plot, wmm, hmm float64) ([]byte, error) {
	w := vg.Length(widthMM(wmm, DefaultWidthMM)) * vg.Millimeter
	h := vg.Length(widthMM(hmm, DefaultHeightMM)) * vg.Millimeter
	c := vgimg.NewWith(vgimg.UseWH(w, h), vgimg.UseDPI(DPI))
	p.Draw(draw.New(c))
	var buf bytes.Buffer
	if _, err := (vgimg.PngCanvas{Canvas: c}).WriteTo(&buf); err != nil {
		return nil, fmt.Errorf("charts: encode png: %w", err)
	}
	return buf.Bytes(), nil
}

// headroom leaves space above the data for the legend.
func headroom(max float64) float64 {
	if max <= 0 {
		return 1.22
	}
	return niceCeil(max) * 1.22
}

func niceCeil(v float64) float64 {
	if v <= 0 {
		return 1
	}
	exp := math.Pow(10, math.Floor(math.Log10(v)))
	for _, m := range []float64{1, 2, 2.5, 5, 10} {
		if m*exp >= v {
			return m * exp
		}
	}
	return 10 * exp
}

// segments splits a series where samples are missing for > 2.5 steps.
func segments(pts []Point, step time.Duration) [][]Point {
	var out [][]Point
	var cur []Point
	for i, p := range pts {
		if math.IsNaN(p.V) || math.IsInf(p.V, 0) {
			continue
		}
		if i > 0 && step > 0 && len(cur) > 0 && p.T.Sub(cur[len(cur)-1].T) > step*5/2 {
			out = append(out, cur)
			cur = nil
		}
		cur = append(cur, p)
	}
	if len(cur) > 0 {
		out = append(out, cur)
	}
	return out
}

// numTicker labels the y axis with about five round values.
type numTicker struct {
	percent bool
	max     float64
}

func (t numTicker) Ticks(min, max float64) []plot.Tick {
	top := t.max
	if top <= 0 {
		top = max
	}
	step := niceCeil(top / 5)
	var out []plot.Tick
	for v := 0.0; v <= top*1.0001; v += step {
		out = append(out, plot.Tick{Value: v, Label: label(v, t.percent)})
	}
	return out
}

func label(v float64, percent bool) string {
	if percent {
		return strconv.FormatFloat(v, 'f', -1, 64) + "%"
	}
	if v != math.Trunc(v) {
		return strconv.FormatFloat(v, 'f', 1, 64)
	}
	return thousands(int64(v))
}

func thousands(n int64) string {
	s := strconv.FormatInt(n, 10)
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// timeTicker places labelled ticks on round local times.
type timeTicker struct {
	loc  *time.Location
	span time.Duration
}

func (t timeTicker) Ticks(min, max float64) []plot.Tick {
	steps := []time.Duration{5 * time.Minute, 10 * time.Minute, 15 * time.Minute, 30 * time.Minute,
		time.Hour, 2 * time.Hour, 3 * time.Hour, 4 * time.Hour, 6 * time.Hour, 12 * time.Hour, 24 * time.Hour,
		48 * time.Hour, 72 * time.Hour, 7 * 24 * time.Hour, 14 * 24 * time.Hour}
	step := steps[len(steps)-1]
	for _, s := range steps {
		if t.span/s <= 8 {
			step = s
			break
		}
	}
	format := "15:04"
	if step >= 24*time.Hour {
		format = "2 Jan"
	}
	start := time.Unix(int64(min), 0).In(t.loc)
	day := time.Date(start.Year(), start.Month(), start.Day(), 0, 0, 0, 0, t.loc)
	var out []plot.Tick
	for tick := day; !tick.After(time.Unix(int64(max), 0)); tick = tick.Add(step) {
		if tick.Before(start) {
			continue
		}
		out = append(out, plot.Tick{Value: float64(tick.Unix()), Label: tick.In(t.loc).Format(format)})
	}
	return out
}

// sparseLabels labels at most max categories (evenly spaced, last included).
type sparseLabels struct {
	labels []string
	max    int
}

func (s sparseLabels) Ticks(min, max float64) []plot.Tick {
	n := len(s.labels)
	every := 1
	for n/every > s.max {
		every++
	}
	out := make([]plot.Tick, 0, n)
	for i, l := range s.labels {
		if (n-1-i)%every != 0 {
			l = ""
		}
		out = append(out, plot.Tick{Value: float64(i), Label: l})
	}
	return out
}
