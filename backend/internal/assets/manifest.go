package assets

import (
	"bufio"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Catalogue formats (profile pictures and Store emotes).
const (
	FormatImage  = "image"
	FormatLottie = "lottie"
)

// ManifestHeader is the first line of config/profile_pictures.tsv and
// config/emotes.tsv.
const ManifestHeader = "id\tname\tformat\tsource_key\tpath\tprice_diamonds\tsort_order"

// PictureRow is one row of a catalogue manifest: the catalogue row (seeded
// by migrations/008_profile_pictures_seed.sql or 011_emotes_seed.sql) plus
// source_key, the object's key in the copy it was imported from (the import
// tool's source).
type PictureRow struct {
	ID            string
	Name          string
	Format        string
	SourceKey     string
	Path          string
	PriceDiamonds int
	SortOrder     int
}

// EmoteRow is one row of config/emotes.tsv (the same columns).
type EmoteRow = PictureRow

var (
	pictureIDPattern = regexp.MustCompile(`^pp_[a-z0-9_]{1,61}$`)
	emoteIDPattern   = regexp.MustCompile(`^em_[a-z0-9_]{1,61}$`)
)

// manifestRules are one catalogue's id shape and its object paths by format
// (the bucket layout of docs/cosmetics-catalog.md).
type manifestRules struct {
	id                    *regexp.Regexp
	lottiePath, imagePath *regexp.Regexp
}

var (
	pictureRules = manifestRules{
		id:         pictureIDPattern,
		lottiePath: regexp.MustCompile(`^profile_pictures/lottie_animation/[a-z0-9_-]+(?:\.[a-z0-9_-]+)*\.json$`),
		imagePath:  regexp.MustCompile(`^profile_pictures/image/[a-z0-9_-]+(?:\.[a-z0-9_-]+)*\.png$`),
	}
	emoteRules = manifestRules{
		id:         emoteIDPattern,
		lottiePath: regexp.MustCompile(`^emotes/[a-z0-9_-]+(?:\.[a-z0-9_-]+)*\.json$`),
		imagePath:  regexp.MustCompile(`^emotes/[a-z0-9_-]+(?:\.[a-z0-9_-]+)*\.png$`),
	}
)

// ValidPictureID reports whether id has the profile-picture id shape.
func ValidPictureID(id string) bool { return pictureIDPattern.MatchString(id) }

// ValidEmoteID reports whether id has the Store emote id shape.
func ValidEmoteID(id string) bool { return emoteIDPattern.MatchString(id) }

// ContentType is the Content-Type of a format's objects.
func ContentType(format string) string {
	if format == FormatLottie {
		return "application/json"
	}
	return "image/png"
}

// ReadPictureManifest parses and validates config/profile_pictures.tsv: the
// exact header, seven tab-separated fields per row, catalogue-valid values
// and unique ids and paths. Blank lines are not allowed (a TSV row count is
// the catalogue).
func ReadPictureManifest(r io.Reader) ([]PictureRow, error) { return readManifest(r, pictureRules) }

// ReadEmoteManifest parses and validates config/emotes.tsv like
// ReadPictureManifest (em_ ids, objects under emotes/).
func ReadEmoteManifest(r io.Reader) ([]EmoteRow, error) { return readManifest(r, emoteRules) }

func readManifest(r io.Reader, rules manifestRules) ([]PictureRow, error) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 64<<10), 1<<20)
	if !sc.Scan() {
		if err := sc.Err(); err != nil {
			return nil, err
		}
		return nil, fmt.Errorf("manifest is empty")
	}
	if got := strings.TrimSuffix(sc.Text(), "\r"); got != ManifestHeader {
		return nil, fmt.Errorf("manifest header is %q, want %q", got, ManifestHeader)
	}
	var rows []PictureRow
	ids, paths := map[string]bool{}, map[string]bool{}
	line := 1
	for sc.Scan() {
		line++
		f := strings.Split(strings.TrimSuffix(sc.Text(), "\r"), "\t")
		if len(f) != 7 {
			return nil, fmt.Errorf("line %d: %d fields, want 7", line, len(f))
		}
		price, err1 := strconv.Atoi(f[5])
		order, err2 := strconv.Atoi(f[6])
		row := PictureRow{ID: f[0], Name: f[1], Format: f[2], SourceKey: f[3], Path: f[4], PriceDiamonds: price, SortOrder: order}
		switch {
		case !rules.id.MatchString(row.ID):
			return nil, fmt.Errorf("line %d: id %q must match %s", line, row.ID, rules.id)
		case row.Name == "" || utf8.RuneCountInString(row.Name) > 64 || strings.TrimSpace(row.Name) != row.Name || !utf8.ValidString(row.Name):
			return nil, fmt.Errorf("line %d: name must be 1-64 characters without surrounding spaces", line)
		case row.Format != FormatImage && row.Format != FormatLottie:
			return nil, fmt.Errorf("line %d: format %q must be image or lottie", line, row.Format)
		case row.Format == FormatLottie && !rules.lottiePath.MatchString(row.Path),
			row.Format == FormatImage && !rules.imagePath.MatchString(row.Path),
			!ValidKey(row.Path):
			return nil, fmt.Errorf("line %d: path %q does not fit format %s", line, row.Path, row.Format)
		case !ValidKey(row.SourceKey):
			return nil, fmt.Errorf("line %d: source_key %q is not a valid key", line, row.SourceKey)
		case err1 != nil || price < 1 || price > 1_000_000:
			return nil, fmt.Errorf("line %d: price_diamonds must be 1..1000000", line)
		case err2 != nil:
			return nil, fmt.Errorf("line %d: sort_order must be an integer", line)
		case ids[row.ID]:
			return nil, fmt.Errorf("line %d: duplicate id %s", line, row.ID)
		case paths[row.Path]:
			return nil, fmt.Errorf("line %d: duplicate path %s", line, row.Path)
		}
		ids[row.ID], paths[row.Path] = true, true
		rows = append(rows, row)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("manifest has no rows")
	}
	return rows, nil
}
