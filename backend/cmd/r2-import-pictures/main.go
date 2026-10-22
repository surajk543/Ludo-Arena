// Command r2-import-pictures copies the profile pictures named by
// config/profile_pictures.tsv from King Teen Patti's public copy
// (https://assets.sungamestudio.com/<source_key>) into the private R2 bucket
// at each row's `path`, with Content-Type (application/json for lottie,
// image/png for image) and Cache-Control "private, max-age=31536000,
// immutable".
//
// It is idempotent: an object that already exists with the same size as the
// source is skipped (HEAD), so re-running it after adding rows to the
// manifest uploads only the new pictures. Every upload is verified with a
// HEAD (size, Content-Type, Cache-Control). Each source file is validated
// before upload (Lottie: a JSON object; image: a PNG).
//
// Credentials come from the environment only (never flags):
//
//	cd backend && set -a && . ./.env && set +a
//	go run ./cmd/r2-import-pictures -dry-run
//	go run ./cmd/r2-import-pictures
//
// R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY (all
// four). -dry-run works without them (it then only checks the manifest and
// the sources). Nothing secret is ever printed: lines name ids and object
// keys only. Exit status 1 when any row failed.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"ludoarena/internal/assets"
)

// maxObject bounds a downloaded source file.
const maxObject = 10 << 20

// retryDelay is the first retry backoff (tests shorten it).
var retryDelay = 500 * time.Millisecond

type options struct {
	Manifest    string
	Source      string // base URL of the public source copy
	DryRun      bool
	Concurrency int
	Only        map[string]bool // ids to process (empty: all)
	R2          assets.Config
	HTTP        *http.Client
}

// summary counts row outcomes.
type summary struct {
	Uploaded, Skipped, WouldUpload, Failed int
}

func main() {
	var o options
	var only string
	flag.StringVar(&o.Manifest, "manifest", "config/profile_pictures.tsv", "profile-picture manifest (TSV)")
	flag.StringVar(&o.Source, "source", "https://assets.sungamestudio.com", "public base URL of the source copy")
	flag.BoolVar(&o.DryRun, "dry-run", false, "check and report; upload nothing")
	flag.IntVar(&o.Concurrency, "concurrency", 4, "parallel transfers (1-16)")
	flag.StringVar(&only, "only", "", "comma-separated picture ids to process (default: all)")
	flag.Parse()
	o.Only = map[string]bool{}
	for _, id := range strings.Split(only, ",") {
		if id = strings.TrimSpace(id); id != "" {
			o.Only[id] = true
		}
	}
	o.R2 = assets.Config{
		AccountID: os.Getenv("R2_ACCOUNT_ID"), Bucket: os.Getenv("R2_BUCKET"),
		AccessKeyID: os.Getenv("R2_ACCESS_KEY_ID"), SecretAccessKey: os.Getenv("R2_SECRET_ACCESS_KEY"),
		Endpoint: os.Getenv("R2_ENDPOINT"),
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	sum, err := run(ctx, o, os.Stdout)
	if err != nil {
		fmt.Fprintln(os.Stderr, "r2-import-pictures:", err)
		os.Exit(2)
	}
	if sum.Failed > 0 {
		os.Exit(1)
	}
}

// run imports every manifest row and prints one line per row and a summary.
func run(ctx context.Context, o options, out io.Writer) (summary, error) {
	var sum summary
	if o.Concurrency < 1 || o.Concurrency > 16 {
		return sum, errors.New("-concurrency must be 1..16")
	}
	o.Source = strings.TrimRight(o.Source, "/")
	if !strings.HasPrefix(o.Source, "https://") && !strings.HasPrefix(o.Source, "http://") {
		return sum, errors.New("-source must be an http(s) URL")
	}
	f, err := os.Open(o.Manifest)
	if err != nil {
		return sum, err
	}
	rows, err := assets.ReadPictureManifest(f)
	f.Close()
	if err != nil {
		return sum, fmt.Errorf("manifest: %w", err)
	}
	if o.HTTP == nil {
		o.HTTP = &http.Client{Timeout: 60 * time.Second}
	}
	var bucket *assets.Bucket
	switch {
	case o.R2.Configured():
		if bucket, err = assets.NewBucket(o.R2, o.HTTP); err != nil {
			return sum, err // names the missing variables, never values
		}
	case !o.DryRun:
		return sum, errors.New("R2 is not configured: set R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY")
	}
	mode := "import"
	if o.DryRun {
		mode = "dry run"
	}
	fmt.Fprintf(out, "%s: %d manifest rows, source %s, bucket configured: %t\n", mode, len(rows), o.Source, bucket != nil)

	type result struct {
		row    assets.PictureRow
		action string // uploaded | skipped | would-upload
		detail string
		err    error
	}
	jobs := make(chan assets.PictureRow)
	results := make(chan result)
	var wg sync.WaitGroup
	for i := 0; i < o.Concurrency; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for row := range jobs {
				action, detail, err := importRow(ctx, o, bucket, row)
				results <- result{row, action, detail, err}
			}
		}()
	}
	go func() {
		defer close(jobs)
		for _, r := range rows {
			if len(o.Only) > 0 && !o.Only[r.ID] {
				continue
			}
			select {
			case jobs <- r:
			case <-ctx.Done():
				return
			}
		}
	}()
	go func() { wg.Wait(); close(results) }()
	for res := range results {
		switch {
		case res.err != nil:
			sum.Failed++
			fmt.Fprintf(out, "FAIL  %-28s %s: %v\n", res.row.ID, res.row.Path, res.err)
		case res.action == "skipped":
			sum.Skipped++
			fmt.Fprintf(out, "skip  %-28s %s (%s)\n", res.row.ID, res.row.Path, res.detail)
		case res.action == "would-upload":
			sum.WouldUpload++
			fmt.Fprintf(out, "plan  %-28s %s (%s)\n", res.row.ID, res.row.Path, res.detail)
		default:
			sum.Uploaded++
			fmt.Fprintf(out, "ok    %-28s %s (%s)\n", res.row.ID, res.row.Path, res.detail)
		}
	}
	if err := ctx.Err(); err != nil {
		return sum, err
	}
	fmt.Fprintf(out, "%s done: uploaded %d, skipped %d, would upload %d, failed %d\n",
		mode, sum.Uploaded, sum.Skipped, sum.WouldUpload, sum.Failed)
	return sum, nil
}

// importRow handles one manifest row.
func importRow(ctx context.Context, o options, bucket *assets.Bucket, row assets.PictureRow) (action, detail string, err error) {
	src := o.Source + "/" + row.SourceKey
	var existing *assets.ObjectInfo
	if bucket != nil {
		info, found, err := retry(ctx, func() (assets.ObjectInfo, bool, error) { return bucket.Head(ctx, row.Path) })
		if err != nil {
			return "", "", err
		}
		if found {
			existing = &info
		}
	}
	if existing != nil {
		// Same size as the source: already imported (paths are immutable).
		if size, err := sourceSize(ctx, o.HTTP, src); err == nil && size == existing.Size {
			return "skipped", fmt.Sprintf("exists, %d B", size), nil
		}
	}
	body, err := download(ctx, o.HTTP, src)
	if err != nil {
		return "", "", err
	}
	if existing != nil && existing.Size == int64(len(body)) {
		return "skipped", fmt.Sprintf("exists, %d B", len(body)), nil
	}
	if err := validate(row.Format, body); err != nil {
		return "", "", err
	}
	verb := "new"
	if existing != nil {
		verb = fmt.Sprintf("replaces %d B", existing.Size)
	}
	if o.DryRun {
		return "would-upload", fmt.Sprintf("%d B, %s", len(body), verb), nil
	}
	ct := assets.ContentType(row.Format)
	if _, _, err := retry(ctx, func() (struct{}, bool, error) {
		return struct{}{}, true, bucket.Put(ctx, row.Path, body, ct, assets.ImmutableCacheControl)
	}); err != nil {
		return "", "", err
	}
	info, found, err := retry(ctx, func() (assets.ObjectInfo, bool, error) { return bucket.Head(ctx, row.Path) })
	switch {
	case err != nil:
		return "", "", fmt.Errorf("verify: %w", err)
	case !found:
		return "", "", errors.New("verify: object missing after upload")
	case info.Size != int64(len(body)):
		return "", "", fmt.Errorf("verify: size %d, uploaded %d", info.Size, len(body))
	case !strings.HasPrefix(info.ContentType, ct):
		return "", "", fmt.Errorf("verify: Content-Type %q, want %q", info.ContentType, ct)
	case info.CacheControl != assets.ImmutableCacheControl:
		return "", "", fmt.Errorf("verify: Cache-Control %q", info.CacheControl)
	}
	return "uploaded", fmt.Sprintf("%d B, %s, verified", len(body), verb), nil
}

// retry runs fn up to 3 times with a short backoff.
func retry[T any](ctx context.Context, fn func() (T, bool, error)) (T, bool, error) {
	var (
		v   T
		ok  bool
		err error
	)
	for attempt := 0; attempt < 3; attempt++ {
		if v, ok, err = fn(); err == nil {
			return v, ok, nil
		}
		select {
		case <-ctx.Done():
			return v, ok, ctx.Err()
		case <-time.After(time.Duration(attempt+1) * retryDelay):
		}
	}
	return v, ok, err
}

// sourceSize HEADs a public source file; an unknown length is an error.
func sourceSize(ctx context.Context, hc *http.Client, url string) (int64, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, url, nil)
	if err != nil {
		return 0, err
	}
	res, err := hc.Do(req)
	if err != nil {
		return 0, err
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("source HEAD: HTTP %d", res.StatusCode)
	}
	n, err := strconv.ParseInt(res.Header.Get("Content-Length"), 10, 64)
	if err != nil {
		return 0, errors.New("source HEAD: no Content-Length")
	}
	return n, nil
}

// download GETs a public source file (bounded, retried).
func download(ctx context.Context, hc *http.Client, url string) ([]byte, error) {
	b, _, err := retry(ctx, func() ([]byte, bool, error) {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return nil, false, err
		}
		res, err := hc.Do(req)
		if err != nil {
			return nil, false, err
		}
		defer res.Body.Close()
		if res.StatusCode != http.StatusOK {
			return nil, false, fmt.Errorf("source GET %s: HTTP %d", url, res.StatusCode)
		}
		b, err := io.ReadAll(io.LimitReader(res.Body, maxObject+1))
		if err != nil {
			return nil, false, err
		}
		if len(b) > maxObject {
			return nil, false, fmt.Errorf("source %s is larger than %d bytes", url, maxObject)
		}
		return b, true, nil
	})
	return b, err
}

var pngMagic = []byte("\x89PNG\r\n\x1a\n")

// validate checks that body is what the format promises.
func validate(format string, body []byte) error {
	switch format {
	case assets.FormatLottie:
		var v map[string]json.RawMessage
		if err := json.Unmarshal(body, &v); err != nil {
			return fmt.Errorf("source is not a JSON object (Lottie): %w", err)
		}
		if _, ok := v["layers"]; !ok {
			return errors.New("source JSON has no \"layers\" (not a Lottie animation)")
		}
	case assets.FormatImage:
		if !bytes.HasPrefix(body, pngMagic) {
			return errors.New("source is not a PNG")
		}
	default:
		return fmt.Errorf("unknown format %q", format)
	}
	return nil
}
