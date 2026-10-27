package app

// Report commands (/status, /digest, /live, /playtime, /metrics).
//
// The command loop only accepts a command; one worker generates and sends
// the reports, so polling Telegram never waits for a report:
//
//   - the same command from the same chat within COMMAND_DEDUPE_WINDOW (30 s)
//     of an accepted one is dropped silently;
//   - at most queueCap commands wait; more are refused with a short reply;
//   - one report is generated at a time, commands and scheduled reports alike
//     (genLock). Waiting for the lock is not generation time;
//   - generation (collecting data and rendering) gets COMMAND_REPORT_TIMEOUT
//     (30 s). Then its context is cancelled — Prometheus and backend requests
//     abort at once and the PDF renderers stop at their next section — the
//     result is discarded even if it completes later, and the chat is told.
//     Go cannot kill a goroutine, so the cancelled generation keeps the lock
//     until it has returned: two generations never overlap;
//   - sending the document is not part of the generation budget.

import (
	"context"
	"errors"
	"fmt"
	"time"

	"ludoarena/opsbot/internal/config"
	"ludoarena/opsbot/internal/pdfreport"
	"ludoarena/opsbot/internal/report"
	"ludoarena/opsbot/internal/telegram"
)

const (
	queueCap      = 4                // commands waiting behind the running one
	deliverBudget = 2 * time.Minute  // sending one command's report (Telegram retries included)
	replyBudget   = 15 * time.Second // short replies (help, busy, timeout)
	actionEvery   = 4 * time.Second  // Telegram shows a chat action for ~5 s
)

// ChatActioner shows "sending a file…" in a chat (optional Sender extension).
type ChatActioner interface {
	SendChatAction(ctx context.Context, chatID, action string) error
}

// CommandSetter publishes the bot's command menu (optional Sender extension).
type CommandSetter interface {
	SetMyCommands(ctx context.Context, cmds []telegram.BotCommand) error
}

// Commands is the bot's command menu.
var Commands = []telegram.BotCommand{
	{Command: "live", Description: "Real players online now + last 24 h (PDF)"},
	{Command: "playtime", Description: "Top players by minutes per game, last 24 h (PDF)"},
	{Command: "metrics", Description: "CPU, RAM and PostgreSQL connections, last 24 h (PDF)"},
	{Command: "status", Description: "Hourly status report now"},
	{Command: "digest", Description: "Yesterday's KPI report"},
	{Command: "help", Description: "List the commands"},
}

// HelpText is the reply to /help and to unknown commands.
const HelpText = "<b>Ludo Arena ops bot</b>\n" +
	"/live — real players online now (user id, name, joined, game) + 24 h chart and peak\n" +
	"/playtime — top 100 players by minutes per game, last 24 h\n" +
	"/metrics — CPU, RAM and PostgreSQL connections, last 24 h\n" +
	"/status — current status report\n" +
	"/digest — yesterday's KPI report\n" +
	"/help — this message\n" +
	"<i>One report at a time; a repeated command within 30 s is ignored.</i>"

// rendered is a generated report: a document, or text when doc is nil.
type rendered struct {
	name, caption string
	doc           []byte
	text          string
}

// reportJob is one accepted report command.
type reportJob struct {
	cmd, chat string
	build     func(ctx context.Context) (rendered, error)
}

// builders maps every report command (and alias) to its canonical name and
// generator; nil when cmd is not a report command.
func (a *App) builder(cmd string) (string, func(ctx context.Context) (rendered, error)) {
	switch cmd {
	case "status":
		return "status", a.buildStatus
	case "digest", "daily":
		return "digest", func(ctx context.Context) (rendered, error) {
			return a.buildDigest(ctx, report.Yesterday(a.Clock.Now(), a.Cfg.Location))
		}
	case "live", "online":
		return "live", a.buildLive
	case "playtime":
		return "playtime", a.buildPlaytime
	case "metrics", "server":
		return "metrics", a.buildResources
	}
	return "", nil
}

// submit queues a report command unless it repeats one accepted within the
// dedupe window or the queue is full.
func (a *App) submit(ctx context.Context, cmd, chat string, build func(context.Context) (rendered, error)) {
	a.init()
	key := chat + "\x00" + cmd
	window := a.Cfg.CommandDedupe
	now := a.Clock.Now()
	a.mu.Lock()
	for k, t := range a.recent {
		if now.Sub(t) >= window {
			delete(a.recent, k)
		}
	}
	if _, dup := a.recent[key]; dup {
		a.mu.Unlock()
		a.Metrics.Commands.Inc(cmd, "duplicate")
		a.Log.Info("dropping repeated command", "command", cmd, "window", window)
		return
	}
	select {
	case a.jobs <- reportJob{cmd: cmd, chat: chat, build: build}:
		if window > 0 {
			a.recent[key] = now
		}
		a.mu.Unlock()
		a.Metrics.Commands.Inc(cmd, "accepted")
	default:
		a.mu.Unlock()
		a.Metrics.Commands.Inc(cmd, "busy")
		a.reply(ctx, chat, fmt.Sprintf("⏳ /%s not started: %d reports are already waiting. Try again in a minute.", cmd, queueCap))
	}
}

// RunReports generates and sends queued report commands one at a time until
// ctx ends (started by Run).
func (a *App) RunReports(ctx context.Context) {
	a.init()
	for {
		select {
		case <-ctx.Done():
			return
		case j := <-a.jobs:
			a.runJob(ctx, j)
		}
	}
}

type outcome struct {
	r   rendered
	err error
}

func (a *App) runJob(ctx context.Context, j reportJob) {
	if err := a.lockGen(ctx); err != nil {
		return // shutting down
	}
	timeout := a.Cfg.CommandTimeout
	gctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	go a.keepChatAction(gctx, j.chat)
	started := time.Now()
	done := make(chan outcome, 1)
	go func() {
		defer a.unlockGen() // only when generation has really returned
		r, err := j.build(gctx)
		done <- outcome{r, err}
	}()
	var res outcome
	select {
	case res = <-done:
	case <-gctx.Done():
	}
	late := gctx.Err() != nil // read before cancel(), which sets it too
	took := time.Since(started)
	cancel()
	switch {
	case ctx.Err() != nil:
		return // shutting down
	case late || errors.Is(res.err, context.DeadlineExceeded):
		// Out of time: whatever the generation produces now is discarded.
		a.Metrics.Commands.Inc(j.cmd, "timeout")
		a.Log.Warn("command report cancelled: generation took too long", "command", j.cmd, "timeout", timeout)
		a.reply(ctx, j.chat, fmt.Sprintf("⏱ /%s was cancelled: the report was not ready within %s. Try again in a moment.", j.cmd, timeout))
		return
	case res.err != nil:
		a.Metrics.Commands.Inc(j.cmd, "failed")
		a.Log.Error("command report failed", "command", j.cmd, "err", res.err)
		a.reply(ctx, j.chat, "⚠️ /"+j.cmd+" failed: "+report.Esc(res.err.Error()))
		return
	}
	a.Metrics.Generation.Set(took.Seconds(), j.cmd)
	dctx, dcancel := context.WithTimeout(ctx, deliverBudget)
	defer dcancel()
	if err := a.send(dctx, "command", []string{j.chat}, res.r); err != nil {
		a.Metrics.Commands.Inc(j.cmd, "failed")
		a.Log.Error("command report delivery failed", "command", j.cmd, "err", err)
		return
	}
	a.Metrics.Commands.Inc(j.cmd, "sent")
}

// lockGen takes the generation lock (one report generation at a time).
func (a *App) lockGen(ctx context.Context) error {
	select {
	case a.genLock <- struct{}{}:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (a *App) unlockGen() { <-a.genLock }

// generate runs build under the generation lock (scheduled reports).
func (a *App) generate(ctx context.Context, build func(context.Context) (rendered, error)) (rendered, error) {
	if err := a.lockGen(ctx); err != nil {
		return rendered{}, err
	}
	defer a.unlockGen()
	return build(ctx)
}

// keepChatAction shows "sending a file…" in the chat while ctx lasts.
func (a *App) keepChatAction(ctx context.Context, chat string) {
	ca, ok := a.Sender.(ChatActioner)
	if !ok {
		return
	}
	for {
		actx, cancel := context.WithTimeout(ctx, 3*time.Second)
		_ = ca.SendChatAction(actx, chat, telegram.ActionUploadDocument) // best effort
		cancel()
		select {
		case <-ctx.Done():
			return
		case <-time.After(actionEvery):
		}
	}
}

// reply sends a short message to one chat.
func (a *App) reply(ctx context.Context, chat, html string) {
	rctx, cancel := context.WithTimeout(ctx, replyBudget)
	defer cancel()
	_ = a.deliver(rctx, "command", []string{chat}, func(c string) error { return a.Sender.SendMessage(rctx, c, html) })
}

// send delivers a rendered report to chats.
func (a *App) send(ctx context.Context, kind string, chats []string, r rendered) error {
	if r.doc == nil {
		return a.deliver(ctx, kind, chats, func(chat string) error { return a.Sender.SendMessage(ctx, chat, r.text) })
	}
	return a.deliver(ctx, kind, chats, func(chat string) error { return a.Sender.SendDocument(ctx, chat, r.name, r.doc, r.caption) })
}

// pdfOr returns the document, or the text fallback when rendering failed for
// another reason than ctx ending.
func (a *App) pdfOr(ctx context.Context, what string, doc []byte, err error, name, caption string, text func() string) (rendered, error) {
	if err == nil {
		return rendered{name: name, caption: caption, doc: doc}, nil
	}
	if cerr := ctx.Err(); cerr != nil {
		return rendered{}, cerr
	}
	a.Log.Error(what+" pdf failed; sending text", "err", err)
	return rendered{text: text()}, nil
}

func (a *App) buildStatus(ctx context.Context) (rendered, error) {
	pdf := a.Cfg.ReportFormat == config.FormatPDF
	st := a.Collector.Status(ctx, pdf)
	m := a.meta()
	text := func() string { return report.StatusText(st, m) }
	if !pdf {
		return rendered{text: text()}, nil
	}
	doc, err := pdfreport.StatusPDF(st, m, pdfreport.Options{})
	return a.pdfOr(ctx, "status", doc, err, pdfreport.StatusFileName(st.At, m.Loc), report.StatusCaption(st, m), text)
}

func (a *App) buildDigest(ctx context.Context, day time.Time) (rendered, error) {
	pdf := a.Cfg.ReportFormat == config.FormatPDF
	dg := a.Collector.Digest(ctx, day, pdf)
	m := a.meta()
	text := func() string { return report.DigestText(dg, m) }
	if !pdf {
		return rendered{text: text()}, nil
	}
	doc, err := pdfreport.DigestPDF(dg, m, a.Clock.Now(), pdfreport.Options{})
	return a.pdfOr(ctx, "digest", doc, err, pdfreport.DigestFileName(dg.Day), report.DigestCaption(dg, m), text)
}

// The on-demand reports are always PDFs (text only if rendering fails).

func (a *App) buildLive(ctx context.Context) (rendered, error) {
	l := a.Collector.Live(ctx)
	m := a.meta()
	doc, err := pdfreport.LivePDF(ctx, l, m, pdfreport.Options{})
	return a.pdfOr(ctx, "live", doc, err, pdfreport.LiveFileName(l.At, m.Loc), report.LiveCaption(l, m),
		func() string { return report.LiveText(l, m) })
}

func (a *App) buildPlaytime(ctx context.Context) (rendered, error) {
	p := a.Collector.Playtime(ctx)
	m := a.meta()
	doc, err := pdfreport.PlaytimePDF(ctx, p, m, pdfreport.Options{})
	return a.pdfOr(ctx, "playtime", doc, err, pdfreport.PlaytimeFileName(p.At, m.Loc), report.PlaytimeCaption(p, m),
		func() string { return report.PlaytimeText(p, m) })
}

func (a *App) buildResources(ctx context.Context) (rendered, error) {
	r := a.Collector.Resources(ctx)
	m := a.meta()
	doc, err := pdfreport.ResourcesPDF(ctx, r, m, pdfreport.Options{})
	return a.pdfOr(ctx, "metrics", doc, err, pdfreport.ResourcesFileName(r.At, m.Loc), report.ResourcesCaption(r, m),
		func() string { return report.ResourcesText(r, m) })
}

// publishCommands sets the command menu once at start (best effort).
func (a *App) publishCommands(ctx context.Context) {
	cs, ok := a.Sender.(CommandSetter)
	if !ok {
		return
	}
	cctx, cancel := context.WithTimeout(ctx, replyBudget)
	defer cancel()
	if err := cs.SetMyCommands(cctx, Commands); err != nil {
		a.Log.Warn("telegram setMyCommands failed; commands still work", "err", err)
	}
}
