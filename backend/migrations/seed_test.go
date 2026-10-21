package migrations

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"ludoroyale/internal/assets"
)

const (
	pictureManifest = "../config/profile_pictures.tsv"
	pictureSeed     = "008_profile_pictures_seed.sql"
)

// renderPictureSeed renders 008_profile_pictures_seed.sql from the manifest.
func renderPictureSeed(rows []assets.PictureRow) string {
	q := func(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }
	var b strings.Builder
	b.WriteString(`-- Profile-picture catalogue seed: one row per line of
-- backend/config/profile_pictures.tsv (GENERATED; do not edit by hand).
-- Regenerate after changing the manifest:
--   UPDATE_PICTURE_SEED=1 go test ./migrations -run TestPictureSeedMatchesManifest
-- Idempotent: applied on every start. ON CONFLICT DO NOTHING (any unique
-- conflict, id or path) keeps an operator's later UPDATE of a row (price,
-- name, order, active) and never fails a start. See 007_profile_pictures.sql.
INSERT INTO progression.profile_pictures (id, name, format, path, price_diamonds, sort_order) VALUES
`)
	for i, r := range rows {
		sep := ","
		if i == len(rows)-1 {
			sep = ""
		}
		fmt.Fprintf(&b, "    (%s, %s, %s, %s, %d, %d)%s\n", q(r.ID), q(r.Name), q(r.Format), q(r.Path),
			r.PriceDiamonds, r.SortOrder, sep)
	}
	b.WriteString("ON CONFLICT DO NOTHING;\n")
	return b.String()
}

var seedTuple = regexp.MustCompile(`^\s*\('((?:[^']|'')*)', '((?:[^']|'')*)', '((?:[^']|'')*)', '((?:[^']|'')*)', (\d+), (-?\d+)\),?$`)

// TestPictureSeedMatchesManifest: the seed migration and the manifest agree
// row for row (same order, same id, name, format, path, price and sort order),
// and the statement is idempotent.
func TestPictureSeedMatchesManifest(t *testing.T) {
	f, err := os.Open(pictureManifest)
	if err != nil {
		t.Fatal(err)
	}
	rows, err := assets.ReadPictureManifest(f)
	f.Close()
	if err != nil {
		t.Fatal(err)
	}
	if os.Getenv("UPDATE_PICTURE_SEED") == "1" {
		if err := os.WriteFile(pictureSeed, []byte(renderPictureSeed(rows)), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	raw, err := os.ReadFile(pictureSeed)
	if err != nil {
		t.Fatal(err)
	}
	if embedded, err := FS.ReadFile(pictureSeed); err != nil || (os.Getenv("UPDATE_PICTURE_SEED") != "1" && string(embedded) != string(raw)) {
		t.Fatalf("seed is not embedded as on disk: %v", err)
	}
	sql := string(raw)
	if !strings.Contains(sql, "INSERT INTO progression.profile_pictures (id, name, format, path, price_diamonds, sort_order) VALUES") ||
		!strings.HasSuffix(strings.TrimSpace(sql), "ON CONFLICT DO NOTHING;") {
		t.Fatal("seed is not a single idempotent INSERT … ON CONFLICT DO NOTHING")
	}
	unq := func(s string) string { return strings.ReplaceAll(s, "''", "'") }
	var got []assets.PictureRow
	for _, line := range strings.Split(sql, "\n") {
		m := seedTuple.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		price, _ := strconv.Atoi(m[5])
		order, _ := strconv.Atoi(m[6])
		got = append(got, assets.PictureRow{ID: unq(m[1]), Name: unq(m[2]), Format: unq(m[3]), Path: unq(m[4]),
			PriceDiamonds: price, SortOrder: order})
	}
	if len(got) != len(rows) {
		t.Fatalf("seed has %d rows, manifest %d (regenerate: UPDATE_PICTURE_SEED=1)", len(got), len(rows))
	}
	for i, want := range rows {
		want.SourceKey = ""
		if got[i] != want {
			t.Errorf("row %d: seed %+v, manifest %+v", i+1, got[i], want)
		}
	}
	if sql != renderPictureSeed(rows) {
		t.Error("seed file differs from its rendering (regenerate: UPDATE_PICTURE_SEED=1)")
	}
}
