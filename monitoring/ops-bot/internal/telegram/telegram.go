// Package telegram is a small Telegram Bot API client for the ops bot:
// sendMessage (HTML), sendDocument (multipart upload) and getUpdates
// (long polling for commands).
//
// The bot token is a secret. It only ever appears in request URLs and is
// redacted from every error and log line this package produces (Go's
// url.Error embeds the full URL, so transport errors are rewritten).
//
// Sends honour Telegram's rate limits: a per-chat minimum gap is reserved
// once per logical send (before the first attempt; retries are paced by
// retry_after or the backoff instead), 429 answers are retried after
// parameters.retry_after, and 5xx / transport failures are retried with
// exponential backoff. Other 4xx answers are returned as *APIError at once.
package telegram

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	defaultBaseURL  = "https://api.telegram.org"
	defaultMinGap   = 3 * time.Second
	defaultRetries  = 3
	maxRetryAfter   = 120 * time.Second
	maxBackoff      = 30 * time.Second
	maxMessageRunes = 4096
	maxCaptionRunes = 1024
	maxResponseBody = 1 << 20
	pollSlack       = 15 * time.Second
	redacted        = "<redacted>"
)

// Config configures a Client. Only Token is required.
type Config struct {
	BaseURL    string        // default "https://api.telegram.org"
	Token      string        // secret; never logged; redacted from every error
	MinGap     time.Duration // minimum gap between sends to one chat (0 → 3 s, negative → none)
	MaxRetries int           // retries after the first attempt (0 → 3, negative → none)
	HTTPClient *http.Client  // default: 70 s timeout
	Logger     *slog.Logger  // default slog.Default()
	Sleep      func(ctx context.Context, d time.Duration) error
}

// Client talks to the Bot API. It is safe for concurrent use.
type Client struct {
	base       string
	token      string
	minGap     time.Duration
	maxRetries int
	http       *http.Client
	log        *slog.Logger
	sleep      func(ctx context.Context, d time.Duration) error
	now        func() time.Time

	mu   sync.Mutex
	next map[string]time.Time // per-chat earliest next send
}

// New returns a Client with defaults applied.
func New(cfg Config) *Client {
	c := &Client{
		base:       strings.TrimRight(cfg.BaseURL, "/"),
		token:      cfg.Token,
		minGap:     cfg.MinGap,
		maxRetries: cfg.MaxRetries,
		http:       cfg.HTTPClient,
		log:        cfg.Logger,
		sleep:      cfg.Sleep,
		now:        time.Now,
		next:       map[string]time.Time{},
	}
	if c.base == "" {
		c.base = defaultBaseURL
	}
	if c.minGap == 0 {
		c.minGap = defaultMinGap
	}
	switch {
	case c.maxRetries == 0:
		c.maxRetries = defaultRetries
	case c.maxRetries < 0:
		c.maxRetries = 0
	}
	if c.http == nil {
		c.http = &http.Client{Timeout: 70 * time.Second}
	}
	if c.log == nil {
		c.log = slog.Default()
	}
	if c.sleep == nil {
		c.sleep = sleepCtx
	}
	return c
}

// APIError is an unsuccessful Bot API answer. It never contains the token.
type APIError struct {
	Method      string
	StatusCode  int
	Description string
	RetryAfter  int // seconds, from parameters.retry_after (429 only)
}

func (e *APIError) Error() string {
	return fmt.Sprintf("telegram %s: %d %s", e.Method, e.StatusCode, e.Description)
}

// transportError is a network-level failure with the token removed.
type transportError struct {
	method string
	msg    string
}

func (e *transportError) Error() string { return "telegram " + e.method + ": " + e.msg }

// Update is one getUpdates entry (only messages are requested).
type Update struct {
	UpdateID int64    `json:"update_id"`
	Message  *Message `json:"message"`
}

// Message is the subset of a Telegram message the ops bot needs.
type Message struct {
	MessageID int64  `json:"message_id"`
	Chat      Chat   `json:"chat"`
	Text      string `json:"text"`
}

// Chat identifies where a message came from.
type Chat struct {
	ID   int64  `json:"id"`
	Type string `json:"type"`
}

// Redact replaces every occurrence of token (raw or URL-escaped, with or
// without the "bot" path prefix) with "<redacted>".
func Redact(s, token string) string {
	if token == "" {
		return s
	}
	for _, t := range []string{token, url.QueryEscape(token), url.PathEscape(token)} {
		s = strings.ReplaceAll(s, "bot"+t, "bot"+redacted)
		s = strings.ReplaceAll(s, t, redacted)
	}
	return s
}

// ParseCommand splits a bot command: "/status@MyBot  x" → ("status", "x").
// Text that is not a command returns ("", "").
func ParseCommand(text string) (cmd string, args string) {
	text = strings.TrimSpace(text)
	if !strings.HasPrefix(text, "/") {
		return "", ""
	}
	head, rest, _ := strings.Cut(text, " ")
	if i := strings.IndexAny(head, "\n\t"); i >= 0 {
		rest = head[i:] + " " + rest
		head = head[:i]
	}
	head = strings.TrimPrefix(head, "/")
	head, _, _ = strings.Cut(head, "@")
	if head == "" {
		return "", ""
	}
	return strings.ToLower(head), strings.TrimSpace(rest)
}

// SendMessage sends an HTML message, split at line boundaries when it is
// longer than Telegram's 4096-character limit. If Telegram rejects the
// markup ("can't parse entities"), the part is resent once as plain text.
func (c *Client) SendMessage(ctx context.Context, chatID, htmlText string) error {
	for _, part := range splitText(htmlText, maxMessageRunes) {
		if err := c.waitSlot(ctx, chatID); err != nil {
			return err
		}
		err := c.sendMessage(ctx, chatID, part, true)
		if isEntityError(err) {
			c.log.Warn("telegram: HTML rejected, resending as plain text", "method", "sendMessage", "error", err.Error())
			err = c.sendMessage(ctx, chatID, plainText(part), false)
		}
		if err != nil {
			return err
		}
	}
	return nil
}

type linkPreview struct {
	IsDisabled bool `json:"is_disabled"`
}

type sendMessageReq struct {
	ChatID             any          `json:"chat_id"`
	Text               string       `json:"text"`
	ParseMode          string       `json:"parse_mode,omitempty"`
	LinkPreviewOptions *linkPreview `json:"link_preview_options,omitempty"`
}

func (c *Client) sendMessage(ctx context.Context, chatID, text string, htmlMode bool) error {
	req := sendMessageReq{ChatID: chatIDValue(chatID), Text: text, LinkPreviewOptions: &linkPreview{IsDisabled: true}}
	if htmlMode {
		req.ParseMode = "HTML"
	}
	body, err := json.Marshal(req)
	if err != nil {
		return err
	}
	_, err = c.do(ctx, "sendMessage", func() (io.Reader, string) {
		return bytes.NewReader(body), "application/json"
	})
	return err
}

// SendDocument uploads data as a file with an optional HTML caption. A
// caption longer than 1024 characters is converted to plain text and cut.
func (c *Client) SendDocument(ctx context.Context, chatID, filename string, data []byte, captionHTML string) error {
	if err := c.waitSlot(ctx, chatID); err != nil {
		return err
	}
	caption, mode := captionHTML, "HTML"
	switch {
	case caption == "":
		mode = ""
	case utf8.RuneCountInString(caption) > maxCaptionRunes:
		caption, mode = truncateRunes(plainText(caption), maxCaptionRunes), ""
	}
	err := c.sendDocument(ctx, chatID, filename, data, caption, mode)
	if mode != "" && isEntityError(err) {
		c.log.Warn("telegram: HTML caption rejected, resending as plain text", "method", "sendDocument", "error", err.Error())
		err = c.sendDocument(ctx, chatID, filename, data, truncateRunes(plainText(caption), maxCaptionRunes), "")
	}
	return err
}

var quoteEscaper = strings.NewReplacer(`\`, `\\`, `"`, `\"`)

func (c *Client) sendDocument(ctx context.Context, chatID, filename string, data []byte, caption, mode string) error {
	ctype := "application/octet-stream"
	if strings.HasSuffix(strings.ToLower(filename), ".pdf") {
		ctype = "application/pdf"
	}
	_, err := c.do(ctx, "sendDocument", func() (io.Reader, string) {
		var buf bytes.Buffer
		w := multipart.NewWriter(&buf)
		_ = w.WriteField("chat_id", chatID)
		if caption != "" {
			_ = w.WriteField("caption", caption)
		}
		if mode != "" {
			_ = w.WriteField("parse_mode", mode)
		}
		h := make(textproto.MIMEHeader)
		h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="document"; filename="%s"`, quoteEscaper.Replace(filename)))
		h.Set("Content-Type", ctype)
		if part, err := w.CreatePart(h); err == nil {
			_, _ = part.Write(data)
		}
		_ = w.Close()
		return &buf, w.FormDataContentType()
	})
	return err
}

type getUpdatesReq struct {
	Offset         int64    `json:"offset,omitempty"`
	Timeout        int      `json:"timeout"`
	AllowedUpdates []string `json:"allowed_updates"`
}

// GetUpdates long-polls for new messages. It does not retry; callers loop.
func (c *Client) GetUpdates(ctx context.Context, offset int64, timeout time.Duration) ([]Update, error) {
	secs := int(timeout / time.Second)
	if secs < 0 {
		secs = 0
	}
	body, err := json.Marshal(getUpdatesReq{Offset: offset, Timeout: secs, AllowedUpdates: []string{"message"}})
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, time.Duration(secs)*time.Second+pollSlack)
	defer cancel()
	raw, err := c.once(ctx, "getUpdates", func() (io.Reader, string) {
		return bytes.NewReader(body), "application/json"
	})
	if err != nil {
		return nil, err
	}
	var ups []Update
	if err := json.Unmarshal(raw, &ups); err != nil {
		return nil, fmt.Errorf("telegram getUpdates: decode result: %w", err)
	}
	return ups, nil
}

type apiResponse struct {
	OK          bool            `json:"ok"`
	Result      json.RawMessage `json:"result"`
	ErrorCode   int             `json:"error_code"`
	Description string          `json:"description"`
	Parameters  *struct {
		RetryAfter int `json:"retry_after"`
	} `json:"parameters"`
}

// do performs a method call with the retry policy described in the package
// documentation. build is called once per attempt.
func (c *Client) do(ctx context.Context, method string, build func() (io.Reader, string)) (json.RawMessage, error) {
	for attempt := 0; ; attempt++ {
		res, err := c.once(ctx, method, build)
		if err == nil {
			return res, nil
		}
		if attempt >= c.maxRetries || ctx.Err() != nil {
			return nil, err
		}
		wait, ok := retryDelay(err, attempt)
		if !ok {
			return nil, err
		}
		c.log.Warn("telegram: retrying", "method", method, "attempt", attempt+1, "wait", wait, "error", err.Error())
		if serr := c.sleep(ctx, wait); serr != nil {
			return nil, fmt.Errorf("%w (gave up: %v)", err, serr)
		}
	}
}

// once performs a single HTTP call and decodes the Bot API envelope.
func (c *Client) once(ctx context.Context, method string, build func() (io.Reader, string)) (json.RawMessage, error) {
	body, ctype := build()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base+"/bot"+c.token+"/"+method, body)
	if err != nil {
		return nil, &transportError{method: method, msg: Redact(err.Error(), c.token)}
	}
	req.Header.Set("Content-Type", ctype)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, &transportError{method: method, msg: Redact(err.Error(), c.token)}
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBody))
	if err != nil {
		return nil, &transportError{method: method, msg: Redact(err.Error(), c.token)}
	}
	var ar apiResponse
	if err := json.Unmarshal(raw, &ar); err != nil {
		return nil, &APIError{Method: method, StatusCode: resp.StatusCode, Description: "unexpected response: " + http.StatusText(resp.StatusCode)}
	}
	if !ar.OK || resp.StatusCode >= 300 {
		e := &APIError{Method: method, StatusCode: ar.ErrorCode, Description: Redact(ar.Description, c.token)}
		if e.StatusCode == 0 {
			e.StatusCode = resp.StatusCode
		}
		if ar.Parameters != nil {
			e.RetryAfter = ar.Parameters.RetryAfter
		}
		return nil, e
	}
	return ar.Result, nil
}

// retryDelay reports whether err is retryable and how long to wait.
func retryDelay(err error, attempt int) (time.Duration, bool) {
	var ae *APIError
	if errors.As(err, &ae) {
		switch {
		case ae.StatusCode == http.StatusTooManyRequests:
			if ae.RetryAfter > 0 {
				return min(time.Duration(ae.RetryAfter)*time.Second, maxRetryAfter), true
			}
			return backoff(attempt), true
		case ae.StatusCode >= 500:
			return backoff(attempt), true
		}
		return 0, false
	}
	var te *transportError
	if errors.As(err, &te) {
		return backoff(attempt), true
	}
	return 0, false
}

func backoff(attempt int) time.Duration {
	if attempt > 5 {
		return maxBackoff
	}
	return min(time.Second<<attempt, maxBackoff)
}

// waitSlot reserves the chat's next send slot and sleeps until it.
func (c *Client) waitSlot(ctx context.Context, chatID string) error {
	if c.minGap <= 0 {
		return ctx.Err()
	}
	c.mu.Lock()
	now := c.now()
	slot := now
	if n, ok := c.next[chatID]; ok && n.After(now) {
		slot = n
	}
	c.next[chatID] = slot.Add(c.minGap)
	c.mu.Unlock()
	if d := slot.Sub(now); d > 0 {
		return c.sleep(ctx, d)
	}
	return ctx.Err()
}

func sleepCtx(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return ctx.Err()
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

func isEntityError(err error) bool {
	var ae *APIError
	return errors.As(err, &ae) && ae.StatusCode == http.StatusBadRequest &&
		strings.Contains(strings.ToLower(ae.Description), "can't parse entities")
}

// chatIDValue sends numeric chat ids as JSON numbers and @names as strings.
func chatIDValue(chatID string) any {
	if n, err := strconv.ParseInt(strings.TrimSpace(chatID), 10, 64); err == nil {
		return n
	}
	return chatID
}

var tagRE = regexp.MustCompile(`<[^>]*>`)

// plainText strips HTML tags and unescapes entities.
func plainText(s string) string {
	return html.UnescapeString(tagRE.ReplaceAllString(s, ""))
}

// truncateRunes cuts s to at most n runes, ending with "…" when cut.
func truncateRunes(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return string(r[:n-1]) + "…"
}

// splitText splits s into chunks of at most limit runes at line boundaries.
// A single line longer than limit is cut on rune boundaries.
func splitText(s string, limit int) []string {
	if utf8.RuneCountInString(s) <= limit {
		return []string{s}
	}
	var (
		out []string
		cur strings.Builder
		n   int
	)
	flush := func() {
		if t := strings.TrimRight(cur.String(), "\n"); t != "" {
			out = append(out, t)
		}
		cur.Reset()
		n = 0
	}
	for _, line := range strings.SplitAfter(s, "\n") {
		ln := utf8.RuneCountInString(line)
		if n+ln > limit {
			flush()
		}
		for ln > limit {
			r := []rune(line)
			out = append(out, string(r[:limit]))
			line = string(r[limit:])
			ln -= limit
		}
		cur.WriteString(line)
		n += ln
	}
	flush()
	return out
}
