package charts

import (
	"bytes"
	"errors"
	"image/png"
	"math"
	"testing"
	"time"

	"gonum.org/v1/plot"
)

func decode(t *testing.T, b []byte) (w, h int) {
	t.Helper()
	img, err := png.Decode(bytes.NewReader(b))
	if err != nil {
		t.Fatalf("not a PNG: %v", err)
	}
	// The image must not be blank: look for a non-white pixel.
	bounds := img.Bounds()
	for y := bounds.Min.Y; y < bounds.Max.Y; y += 3 {
		for x := bounds.Min.X; x < bounds.Max.X; x += 3 {
			if r, g, b, _ := img.At(x, y).RGBA(); r < 0xF000 || g < 0xF000 || b < 0xF000 {
				return bounds.Dx(), bounds.Dy()
			}
		}
	}
	t.Fatal("PNG is blank")
	return 0, 0
}

func TestTimeChart(t *testing.T) {
	start := time.Date(2026, 10, 20, 17, 0, 0, 0, time.UTC)
	var a, b []Point
	for i := 0; i < 289; i++ {
		ts := start.Add(time.Duration(i) * 5 * time.Minute)
		a = append(a, Point{T: ts, V: 1000 + 400*math.Sin(float64(i)/40)})
		if i < 100 || i > 120 { // a gap breaks the line
			b = append(b, Point{T: ts, V: 300})
		}
	}
	img, err := TimeChart(TimeSpec{Title: "Players", YLabel: "players", Lines: []Line{{Name: "Real players", Points: a}, {Name: "Bots", Points: b}},
		Step: 5 * time.Minute})
	if err != nil {
		t.Fatal(err)
	}
	w, h := decode(t, img)
	if wantW := int(math.Round(DefaultWidthMM / 25.4 * DPI)); w < wantW-2 || w > wantW+2 || h < 300 {
		t.Errorf("size = %dx%d", w, h)
	}
	if _, err := TimeChart(TimeSpec{Lines: []Line{{Name: "x"}}}); !errors.Is(err, ErrNoData) {
		t.Errorf("empty series err = %v, want ErrNoData", err)
	}
	// Area fill and peak marks (left, middle and right of the range).
	marked, err := TimeChart(TimeSpec{Title: "Online", Lines: []Line{{Name: "Online", Points: a}}, Step: 5 * time.Minute, Area: true,
		Marks: []Mark{{T: a[0].T, V: a[0].V, Label: "start"}, {T: a[150].T, V: a[150].V, Label: "peak 1,400 · 05:30"},
			{T: a[288].T, V: a[288].V, Label: "now"}, {T: start, V: math.NaN()}}})
	if err != nil {
		t.Fatal(err)
	}
	if decode(t, marked); bytes.Equal(marked, img) {
		t.Error("marks and area did not change the image")
	}
	if img, err := TimeChart(TimeSpec{Percent: true, Lines: []Line{{Name: "cpu", Points: []Point{{T: start, V: 40}}}}}); err != nil {
		t.Errorf("single point: %v", err)
	} else {
		decode(t, img)
	}
}

func TestBarChart(t *testing.T) {
	cats := []string{"1 Oct", "2 Oct", "3 Oct"}
	for _, stacked := range []bool{false, true} {
		img, err := BarChart(BarSpec{Title: "Matches", Categories: cats, Stacked: stacked,
			Series: []Bars{{Name: "Ludo", Values: []float64{10, 20, 30}}, {Name: "Snakes & Ladders", Values: []float64{5, math.NaN()}}}})
		if err != nil {
			t.Fatal(err)
		}
		decode(t, img)
	}
	if _, err := BarChart(BarSpec{Categories: cats, Series: []Bars{{Name: "x", Values: []float64{0, 0, 0}}}}); !errors.Is(err, ErrNoData) {
		t.Errorf("all-zero err = %v, want ErrNoData", err)
	}
}

func TestTicks(t *testing.T) {
	ticks := numTicker{max: 12345}.Ticks(0, 15000)
	if ticks[len(ticks)-1].Label != "10,000" || ticks[1].Label != "2,500" {
		t.Errorf("ticks = %+v", ticks)
	}
	if pct := (numTicker{percent: true, max: 100}).Ticks(0, 122); pct[len(pct)-1].Label != "100%" {
		t.Errorf("percent ticks = %+v", pct)
	}
	ist, _ := time.LoadLocation("Asia/Kolkata")
	start := time.Date(2026, 10, 20, 17, 3, 0, 0, ist)
	tt := timeTicker{loc: ist, span: 24 * time.Hour}.Ticks(float64(start.Unix()), float64(start.Add(24*time.Hour).Unix()))
	if len(tt) == 0 || tt[0].Label != "18:00" {
		t.Errorf("time ticks = %+v", tt)
	}
	days := timeTicker{loc: ist, span: 30 * 24 * time.Hour}.Ticks(float64(start.Unix()), float64(start.Add(30*24*time.Hour).Unix()))
	if len(days) > 9 {
		t.Errorf("30-day axis has %d labels", len(days))
	}
	labels := sparseLabels{labels: make([]string, 30), max: 12}.Ticks(0, 29)
	var _ []plot.Tick = labels
	if len(labels) != 30 {
		t.Errorf("sparse labels = %d", len(labels))
	}
}
