package migrations

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"ludoroyale/internal/assets"
)

// seedSpec is one catalogue whose seed migration is generated from a
// manifest in backend/config.
type seedSpec struct {
	manifest string // TSV under backend/config
	seed     string // generated migration
	table    string
	header   string // leading comment (without the shared idempotency lines)
	env      string // set to 1 to regenerate the seed
	read     func(io.Reader) ([]assets.PictureRow, error)
}

var (
	pictureSeedSpec = seedSpec{
		manifest: "../config/profile_pictures.tsv",
		seed:     "008_profile_pictures_seed.sql",
		table:    "progression.profile_pictures",
		header: `-- Profile-picture catalogue seed: one row per line of
-- backend/config/profile_pictures.tsv (GENERATED; do not edit by hand).
-- Regenerate after changing the manifest:
--   UPDATE_PICTURE_SEED=1 go test ./migrations -run TestPictureSeedMatchesManifest
`,
		env:  "UPDATE_PICTURE_SEED",
		read: assets.ReadPictureManifest,
	}
	emoteSeedSpec = seedSpec{
		manifest: "../config/emotes.tsv",
		seed:     "011_emotes_seed.sql",
		table:    "progression.emotes",
		header: `-- Store emote catalogue seed: one row per line of backend/config/emotes.tsv
-- (GENERATED; do not edit by hand). Prices are fixed per emote (10-40
-- diamonds, owner-approved 2026-10-21). Regenerate after changing the
-- manifest:
--   UPDATE_EMOTE_SEED=1 go test ./migrations -run TestEmoteSeedMatchesManifest
`,
		env:  "UPDATE_EMOTE_SEED",
		read: assets.ReadEmoteManifest,
	}
)

// render renders the seed migration from the manifest rows.
func (s seedSpec) render(rows []assets.PictureRow) string {
	q := func(v string) string { return "'" + strings.ReplaceAll(v, "'", "''") + "'" }
	var b strings.Builder
	b.WriteString(s.header)
	b.WriteString(`-- Idempotent: applied on every start. ON CONFLICT DO NOTHING (any unique
-- conflict, id or path) keeps an operator's later UPDATE of a row (price,
-- name, order, active) and never fails a start. See ` + s.schemaFile() + `.
INSERT INTO ` + s.table + ` (id, name, format, path, price_diamonds, sort_order) VALUES
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

// schemaFile is the migration that creates the seeded table.
func (s seedSpec) schemaFile() string {
	if s.table == "progression.emotes" {
		return "010_emotes.sql"
	}
	return "007_profile_pictures.sql"
}

var seedTuple = regexp.MustCompile(`^\s*\('((?:[^']|'')*)', '((?:[^']|'')*)', '((?:[^']|'')*)', '((?:[^']|'')*)', (\d+), (-?\d+)\),?$`)

// check: the seed migration and the manifest agree row for row (same order,
// same id, name, format, path, price and sort order), and the statement is
// idempotent.
func (s seedSpec) check(t *testing.T) {
	t.Helper()
	f, err := os.Open(s.manifest)
	if err != nil {
		t.Fatal(err)
	}
	rows, err := s.read(f)
	f.Close()
	if err != nil {
		t.Fatal(err)
	}
	regen := os.Getenv(s.env) == "1"
	if regen {
		if err := os.WriteFile(s.seed, []byte(s.render(rows)), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	raw, err := os.ReadFile(s.seed)
	if err != nil {
		t.Fatal(err)
	}
	if embedded, err := FS.ReadFile(s.seed); err != nil || (!regen && string(embedded) != string(raw)) {
		t.Fatalf("seed is not embedded as on disk: %v", err)
	}
	sql := string(raw)
	if !strings.Contains(sql, "INSERT INTO "+s.table+" (id, name, format, path, price_diamonds, sort_order) VALUES") ||
		!strings.HasSuffix(strings.TrimSpace(sql), "ON CONFLICT DO NOTHING;") {
		t.Fatal("seed is not a single idempotent INSERT … ON CONFLICT DO NOTHING")
	}
	unq := func(v string) string { return strings.ReplaceAll(v, "''", "'") }
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
		t.Fatalf("seed has %d rows, manifest %d (regenerate: %s=1)", len(got), len(rows), s.env)
	}
	for i, want := range rows {
		want.SourceKey = ""
		if got[i] != want {
			t.Errorf("row %d: seed %+v, manifest %+v", i+1, got[i], want)
		}
	}
	if sql != s.render(rows) {
		t.Errorf("seed file differs from its rendering (regenerate: %s=1)", s.env)
	}
}

// TestPictureSeedMatchesManifest: 008 == config/profile_pictures.tsv.
func TestPictureSeedMatchesManifest(t *testing.T) { pictureSeedSpec.check(t) }

// TestEmoteSeedMatchesManifest: 011 == config/emotes.tsv.
func TestEmoteSeedMatchesManifest(t *testing.T) { emoteSeedSpec.check(t) }
