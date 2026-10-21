package ludo

import (
	"errors"
	"slices"
	"testing"
)

type cell struct{ col, row int }

// trackCells is the main-track table from backend/docs/game-rules.md,
// indexed by absolute track index.
var trackCells = [TrackLength]cell{
	{1, 6}, {2, 6}, {3, 6}, {4, 6}, {5, 6}, // 0–4
	{6, 5}, {6, 4}, {6, 3}, {6, 2}, {6, 1}, {6, 0}, // 5–10
	{7, 0},                                         // 11
	{8, 0}, {8, 1}, {8, 2}, {8, 3}, {8, 4}, {8, 5}, // 12–17
	{9, 6}, {10, 6}, {11, 6}, {12, 6}, {13, 6}, {14, 6}, // 18–23
	{14, 7},                                             // 24
	{14, 8}, {13, 8}, {12, 8}, {11, 8}, {10, 8}, {9, 8}, // 25–30
	{8, 9}, {8, 10}, {8, 11}, {8, 12}, {8, 13}, {8, 14}, // 31–36
	{7, 14},                                             // 37
	{6, 14}, {6, 13}, {6, 12}, {6, 11}, {6, 10}, {6, 9}, // 38–43
	{5, 8}, {4, 8}, {3, 8}, {2, 8}, {1, 8}, {0, 8}, // 44–49
	{0, 7}, // 50
	{0, 6}, // 51
}

// homeColumnCells is the home-column table (progress 51 → 55) per color.
var homeColumnCells = [4][5]cell{
	Red:    {{1, 7}, {2, 7}, {3, 7}, {4, 7}, {5, 7}},
	Green:  {{7, 1}, {7, 2}, {7, 3}, {7, 4}, {7, 5}},
	Yellow: {{13, 7}, {12, 7}, {11, 7}, {10, 7}, {9, 7}},
	Blue:   {{7, 13}, {7, 12}, {7, 11}, {7, 10}, {7, 9}},
}

var allColors = []Color{Red, Green, Yellow, Blue}

func absInt(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func manhattan(a, b cell) int { return absInt(a.col-b.col) + absInt(a.row-b.row) }

func chebyshev(a, b cell) int { return max(absInt(a.col-b.col), absInt(a.row-b.row)) }

func inRect(c cell, c0, c1, r0, r1 int) bool {
	return c.col >= c0 && c.col <= c1 && c.row >= r0 && c.row <= r1
}

func inBaseOrHome(c cell) bool {
	return inRect(c, 0, 5, 0, 5) || inRect(c, 9, 14, 0, 5) || inRect(c, 9, 14, 9, 14) ||
		inRect(c, 0, 5, 9, 14) || inRect(c, 6, 8, 6, 8)
}

func TestTrackGeometry(t *testing.T) {
	seen := map[cell]int{}
	for i, c := range trackCells {
		if prev, dup := seen[c]; dup {
			t.Fatalf("track squares %d and %d share cell %v", prev, i, c)
		}
		seen[c] = i
		if c.col < 0 || c.col > 14 || c.row < 0 || c.row > 14 {
			t.Errorf("track square %d %v is off the 15×15 grid", i, c)
		}
		if inBaseOrHome(c) {
			t.Errorf("track square %d %v lies in a base or the home area", i, c)
		}
		next := trackCells[(i+1)%TrackLength]
		if chebyshev(c, next) != 1 {
			t.Errorf("track squares %d %v and %d %v are not neighbours", i, c, (i+1)%TrackLength, next)
		}
	}
	for _, col := range allColors {
		for _, hc := range homeColumnCells[col] {
			if _, onTrack := seen[hc]; onTrack {
				t.Errorf("%s home column cell %v is also a track square", col, hc)
			}
		}
	}
}

func TestStartSquares(t *testing.T) {
	cases := []struct {
		color Color
		abs   int
		cell  cell
	}{
		{Red, 0, cell{1, 6}},
		{Green, 13, cell{8, 1}},
		{Yellow, 26, cell{13, 8}},
		{Blue, 39, cell{6, 13}},
	}
	for _, tc := range cases {
		t.Run(tc.color.String(), func(t *testing.T) {
			if got := StartIndex(tc.color); got != tc.abs {
				t.Fatalf("StartIndex = %d, want %d", got, tc.abs)
			}
			if got := TrackIndex(tc.color, 0); got != tc.abs {
				t.Fatalf("TrackIndex(progress 0) = %d, want %d", got, tc.abs)
			}
			if trackCells[tc.abs] != tc.cell {
				t.Fatalf("start cell = %v, want %v", trackCells[tc.abs], tc.cell)
			}
			if !IsSafe(tc.abs) {
				t.Fatalf("start square %d must be safe", tc.abs)
			}
		})
	}
}

func TestSafeSquares(t *testing.T) {
	wantSafe := []int{0, 8, 13, 21, 26, 34, 39, 47}
	for abs := -2; abs < TrackLength+2; abs++ {
		if got, want := IsSafe(abs), slices.Contains(wantSafe, abs); got != want {
			t.Errorf("IsSafe(%d) = %v, want %v", abs, got, want)
		}
	}
	stars := map[int]cell{8: {6, 2}, 21: {12, 6}, 34: {8, 12}, 47: {2, 8}}
	for abs, c := range stars {
		if trackCells[abs] != c {
			t.Errorf("star square %d at %v, want %v", abs, trackCells[abs], c)
		}
	}
}

func TestTrackIndex(t *testing.T) {
	for _, col := range allColors {
		t.Run(col.String(), func(t *testing.T) {
			visited := map[int]bool{}
			for p := 0; p <= LastTrack; p++ {
				got := TrackIndex(col, p)
				if want := (13*int(col) + p) % TrackLength; got != want {
					t.Fatalf("TrackIndex(%d) = %d, want %d", p, got, want)
				}
				visited[got] = true
			}
			if len(visited) != 51 {
				t.Fatalf("visits %d distinct squares, want 51", len(visited))
			}
			skipped := (StartIndex(col) + TrackLength - 1) % TrackLength
			if visited[skipped] {
				t.Fatalf("must turn into the home column before square %d", skipped)
			}
			for _, p := range []int{Base, HomeColumnFirst, 52, 53, 54, 55, Home, -5, 57} {
				if got := TrackIndex(col, p); got != -1 {
					t.Errorf("TrackIndex(%d) = %d, want -1", p, got)
				}
			}

			// Progress 50 is the square right before the home column, and the
			// home column leads into the center.
			last := trackCells[TrackIndex(col, LastTrack)]
			column := homeColumnCells[col]
			if manhattan(last, column[0]) != 1 {
				t.Fatalf("progress 50 cell %v is not adjacent to home column start %v", last, column[0])
			}
			for i := 1; i < len(column); i++ {
				if manhattan(column[i-1], column[i]) != 1 {
					t.Fatalf("home column cells %v and %v are not adjacent", column[i-1], column[i])
				}
			}
			end := column[len(column)-1]
			if inRect(end, 6, 8, 6, 8) || !(inRect(cell{end.col + 1, end.row}, 6, 8, 6, 8) ||
				inRect(cell{end.col - 1, end.row}, 6, 8, 6, 8) || inRect(cell{end.col, end.row + 1}, 6, 8, 6, 8) ||
				inRect(cell{end.col, end.row - 1}, 6, 8, 6, 8)) {
				t.Fatalf("home column end %v does not border the home area", end)
			}
		})
	}
}

func TestColorsFor(t *testing.T) {
	cases := []struct {
		n    int
		want []Color
		err  error
	}{
		{2, []Color{Red, Yellow}, nil},
		{3, []Color{Red, Green, Yellow}, nil},
		{4, []Color{Red, Green, Yellow, Blue}, nil},
		{0, nil, ErrBadPlayerCount},
		{1, nil, ErrBadPlayerCount},
		{5, nil, ErrBadPlayerCount},
		{-1, nil, ErrBadPlayerCount},
	}
	for _, tc := range cases {
		got, err := ColorsFor(tc.n)
		if !errors.Is(err, tc.err) {
			t.Errorf("ColorsFor(%d) err = %v, want %v", tc.n, err, tc.err)
		}
		if !slices.Equal(got, tc.want) {
			t.Errorf("ColorsFor(%d) = %v, want %v", tc.n, got, tc.want)
		}
	}
}

func TestColorString(t *testing.T) {
	want := map[Color]string{Red: "red", Green: "green", Yellow: "yellow", Blue: "blue", Color(7): "Color(7)", Color(-1): "Color(-1)"}
	for c, s := range want {
		if c.String() != s {
			t.Errorf("Color(%d).String() = %q, want %q", int(c), c.String(), s)
		}
	}
}

func TestVariant(t *testing.T) {
	cases := []struct {
		v      Variant
		valid  bool
		tokens int
		enter  []int
	}{
		{Classic, true, 4, []int{6}},
		{Quick, true, 2, []int{1, 6}},
		{"", false, 4, []int{6}},
		{"turbo", false, 4, []int{6}},
	}
	for _, tc := range cases {
		if tc.v.Valid() != tc.valid {
			t.Errorf("%q.Valid() = %v", tc.v, !tc.valid)
		}
		if tc.v.TokensPerPlayer() != tc.tokens {
			t.Errorf("%q.TokensPerPlayer() = %d, want %d", tc.v, tc.v.TokensPerPlayer(), tc.tokens)
		}
		for d := 1; d <= 6; d++ {
			if got, want := tc.v.CanEnter(d), slices.Contains(tc.enter, d); got != want {
				t.Errorf("%q.CanEnter(%d) = %v, want %v", tc.v, d, got, want)
			}
		}
	}
}
