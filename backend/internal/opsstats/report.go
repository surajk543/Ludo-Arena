package opsstats

import (
	"cmp"
	"context"
	"crypto/rand"
	"encoding/hex"
	"math"
	"slices"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/rooms"
)

// Stamp is a time rendered as RFC 3339 in UTC with whole seconds
// ("2026-10-27T15:04:05Z").
type Stamp time.Time

// MarshalJSON implements json.Marshaler.
func (t Stamp) MarshalJSON() ([]byte, error) {
	return []byte(`"` + time.Time(t).UTC().Format(time.RFC3339) + `"`), nil
}

func stampOf(t *time.Time) *Stamp {
	if t == nil {
		return nil
	}
	s := Stamp(*t)
	return &s
}

// batch bounds the commands per pipeline or script call.
const batch = 512

func presenceKey(userID string) string { return "presence:" + userID } // written by the gateway

// pruneScript removes from the online set (KEYS[1]) each ARGV account whose
// presence key is missing. The check is atomic with the removal, and a
// connection sets presence before it adds its member, so a reconnect is
// never removed.
var pruneScript = redis.NewScript(`
local n = 0
for _, id in ipairs(ARGV) do
  if redis.call('EXISTS', 'presence:' .. id) == 0 then n = n + redis.call('ZREM', KEYS[1], id) end
end
return n`)

// ---------------------------------------------------------------- online

// Counts splits online people by activity.
type Counts struct {
	Ludo    int `json:"ludo"`
	Snakes  int `json:"snakes_ladders"`
	Waiting int `json:"waiting"`
	Lobby   int `json:"lobby"`
}

func (c *Counts) add(kind string) {
	switch kind {
	case rooms.ActivityLudo:
		c.Ludo++
	case rooms.ActivitySnakes:
		c.Snakes++
	case rooms.ActivityWaiting:
		c.Waiting++
	default:
		c.Lobby++
	}
}

// OnlineUser is one online person.
type OnlineUser struct {
	UID         string  `json:"uid"`
	UserID      string  `json:"userId"`
	Name        string  `json:"name"`
	CreatedAt   *Stamp  `json:"createdAt"` // first sign-in; null if unknown
	OnlineSince Stamp   `json:"onlineSince"`
	Activity    string  `json:"activity"` // ludo | snakes_ladders | waiting | lobby
	Game        *string `json:"game"`     // playing and waiting only
	Mode        *string `json:"mode"`
}

// OnlineReport is the GET /admin/ops/online response.
type OnlineReport struct {
	At     Stamp        `json:"at"`
	Total  int          `json:"total"`  // every online person
	Counts Counts       `json:"counts"` // every online person
	Users  []OnlineUser `json:"users"`  // the first limit, in report order
}

// onlineRow is an online person before the report is cut to its limit.
type onlineRow struct {
	id    uuid.UUID
	uid   string
	since int64 // unix ms
	act   rooms.Activity
}

var activityRank = map[string]int{rooms.ActivityLudo: 0, rooms.ActivitySnakes: 1, rooms.ActivityWaiting: 2, rooms.ActivityLobby: 3}

// sortOnline orders rows by activity (ludo, snakes_ladders, waiting, lobby),
// then online since (oldest first), then public id.
func sortOnline(rows []onlineRow) {
	slices.SortFunc(rows, func(a, b onlineRow) int {
		return cmp.Or(cmp.Compare(activityRank[a.act.Kind], activityRank[b.act.Kind]),
			cmp.Compare(a.since, b.since), cmp.Compare(a.uid, b.uid))
	})
}

// Online lists online people: every member of the online set whose presence
// key exists (stale members are removed), with what they are doing.
func (s *Service) Online(ctx context.Context, limit int) (OnlineReport, error) {
	at := s.opts.Now()
	zs, err := s.rdb.ZRangeWithScores(ctx, OnlineKey, 0, -1).Result()
	if err != nil {
		return OnlineReport{}, err
	}
	rows := make([]onlineRow, 0, len(zs))
	for _, z := range zs {
		m, _ := z.Member.(string)
		if id, err := uuid.Parse(m); err == nil {
			rows = append(rows, onlineRow{id: id, since: int64(z.Score)})
		}
	}
	if rows, err = s.dropStale(ctx, rows); err != nil {
		return OnlineReport{}, err
	}
	ids := make([]string, len(rows))
	for i := range rows {
		ids[i] = rows[i].id.String()
	}
	acts, err := rooms.Activities(ctx, s.rdb, ids)
	if err != nil {
		return OnlineReport{}, err
	}
	rep := OnlineReport{At: Stamp(at), Total: len(rows), Users: []OnlineUser{}}
	for i := range rows {
		rows[i].act = acts[i]
		rows[i].uid = s.publicID(rows[i].id)
		rep.Counts.add(acts[i].Kind)
	}
	sortOnline(rows)
	rows = rows[:min(limit, len(rows))]
	listed := make([]uuid.UUID, len(rows))
	for i, r := range rows {
		listed[i] = r.id
	}
	info := s.users(ctx, listed)
	for _, r := range rows {
		u := OnlineUser{UID: r.uid, UserID: r.id.String(), Name: info[r.id].name,
			CreatedAt: stampOf(info[r.id].created), OnlineSince: Stamp(time.UnixMilli(r.since)), Activity: r.act.Kind}
		if r.act.Kind != rooms.ActivityLobby {
			game, mode := r.act.Game, r.act.Mode
			u.Game, u.Mode = &game, &mode
		}
		rep.Users = append(rep.Users, u)
	}
	return rep, nil
}

// dropStale returns the rows whose presence key exists and removes the
// others from the online set.
func (s *Service) dropStale(ctx context.Context, rows []onlineRow) ([]onlineRow, error) {
	live := rows[:0:0]
	var stale []any
	for start := 0; start < len(rows); start += batch {
		part := rows[start:min(start+batch, len(rows))]
		pipe := s.rdb.Pipeline()
		cmds := make([]*redis.IntCmd, len(part))
		for i, r := range part {
			cmds[i] = pipe.Exists(ctx, presenceKey(r.id.String()))
		}
		if _, err := pipe.Exec(ctx); err != nil {
			return nil, err
		}
		for i, c := range cmds {
			if c.Val() > 0 {
				live = append(live, part[i])
			} else {
				stale = append(stale, part[i].id.String())
			}
		}
	}
	for start := 0; start < len(stale); start += batch {
		if err := pruneScript.Run(ctx, s.rdb, []string{OnlineKey}, stale[start:min(start+batch, len(stale))]...).Err(); err != nil {
			return nil, err
		}
	}
	return live, nil
}

// -------------------------------------------------------------- playtime

// HourPlaytime is one UTC hour's total play of a game.
type HourPlaytime struct {
	Hour    Stamp `json:"hour"`
	Seconds int64 `json:"seconds"`
}

// PlayerPlaytime is one person's play of a game in the window.
type PlayerPlaytime struct {
	UID       string `json:"uid"`
	UserID    string `json:"userId"`
	Name      string `json:"name"`
	CreatedAt *Stamp `json:"createdAt"`
	Seconds   int64  `json:"seconds"`
}

// GamePlaytime is one game's play in the window.
type GamePlaytime struct {
	Game    string           `json:"game"`
	Seconds int64            `json:"seconds"` // everyone's play in the window
	Players int64            `json:"players"` // people with play in the window
	Hourly  []HourPlaytime   `json:"hourly"`  // raw totals of every hour overlapping the window, oldest first
	Top     []PlayerPlaytime `json:"top"`     // seconds desc, then uid; at most limit
}

// PlaytimeReport is the GET /admin/ops/playtime response.
type PlaytimeReport struct {
	From  Stamp          `json:"from"`
	To    Stamp          `json:"to"`
	Hours int            `json:"hours"`
	Games []GamePlaytime `json:"games"` // ludo, snakes_ladders (always both)
}

// bucket is a UTC hour overlapping the window and the share of it inside.
type bucket struct {
	hour   time.Time
	weight float64
}

// window returns [to − hours, to] and the hour buckets overlapping it,
// oldest first. Only the oldest can be partly outside (to − hours inside
// it); it is weighted by the fraction inside. The newest bucket is the
// current hour, whose play so far is all inside.
func window(to time.Time, hours int) (time.Time, []bucket) {
	from := to.Add(-time.Duration(hours) * time.Hour)
	var out []bucket
	for h := from.Truncate(time.Hour); h.Before(to); h = h.Add(time.Hour) {
		w := 1.0
		if from.After(h) {
			w = float64(h.Add(time.Hour).Sub(from)) / float64(time.Hour)
		}
		out = append(out, bucket{hour: h, weight: w})
	}
	return from, out
}

func seconds(ms float64) int64 { return int64(math.Round(ms / 1000)) }

// tmpTTL bounds the life of a window's temporary union (deleted at once).
const tmpTTL = time.Minute

func tmpKey() string {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	return "ptg:tmp:" + hex.EncodeToString(b)
}

// ranked is a candidate of a game's top list.
type ranked struct {
	id      uuid.UUID
	uid     string
	seconds int64
}

// sortTop orders by seconds (most first), then public id.
func sortTop(rs []ranked) {
	slices.SortFunc(rs, func(a, b ranked) int {
		return cmp.Or(cmp.Compare(b.seconds, a.seconds), cmp.Compare(a.uid, b.uid))
	})
}

// Playtime reports each game's play in the last hours (1–24) and its top
// limit players. Per game, the window's hours are summed with their weights
// into a temporary zset (ZUNIONSTORE … WEIGHTS), counted and ranked, then
// deleted.
func (s *Service) Playtime(ctx context.Context, hours, limit int) (PlaytimeReport, error) {
	to := s.opts.Now().UTC().Truncate(time.Second)
	from, buckets := window(to, hours)
	rep := PlaytimeReport{From: Stamp(from), To: Stamp(to), Hours: hours}

	type gameCmds struct {
		tmp   string
		count *redis.IntCmd
		edge  *redis.ZSliceCmd // the limit-th member
		cands *redis.ZSliceCmd
	}
	pipe := s.rdb.Pipeline()
	totals := make([]*redis.MapStringStringCmd, len(buckets))
	for i, b := range buckets {
		totals[i] = pipe.HGetAll(ctx, TotalKey(b.hour))
	}
	cmds := make([]gameCmds, len(Games))
	for i, g := range Games {
		keys, weights := make([]string, len(buckets)), make([]float64, len(buckets))
		for j, b := range buckets {
			keys[j], weights[j] = PlayKey(g, b.hour), b.weight
		}
		c := gameCmds{tmp: tmpKey()}
		pipe.ZUnionStore(ctx, c.tmp, &redis.ZStore{Keys: keys, Weights: weights})
		pipe.PExpire(ctx, c.tmp, tmpTTL)
		c.count = pipe.ZCount(ctx, c.tmp, "(0", "+inf")
		c.edge = pipe.ZRevRangeWithScores(ctx, c.tmp, int64(limit-1), int64(limit-1))
		cmds[i] = c
	}
	if _, err := pipe.Exec(ctx); err != nil {
		return PlaytimeReport{}, err
	}
	// Every member that rounds to at least the limit-th member's seconds, so
	// ties at the cut are ordered by uid like the rest.
	pipe = s.rdb.Pipeline()
	for i := range cmds {
		lo := "(0"
		if e := cmds[i].edge.Val(); len(e) == 1 {
			if sec := seconds(e[0].Score); sec >= 1 {
				lo = strconv.FormatFloat((float64(sec)-0.5)*1000, 'f', -1, 64)
			}
		}
		cmds[i].cands = pipe.ZRevRangeByScoreWithScores(ctx, cmds[i].tmp, &redis.ZRangeBy{Max: "+inf", Min: lo})
		pipe.Del(ctx, cmds[i].tmp)
	}
	if _, err := pipe.Exec(ctx); err != nil {
		return PlaytimeReport{}, err
	}

	tops := make([][]ranked, len(Games))
	var listed []uuid.UUID
	for i := range cmds {
		for _, z := range cmds[i].cands.Val() {
			m, _ := z.Member.(string)
			if id, err := uuid.Parse(m); err == nil {
				tops[i] = append(tops[i], ranked{id: id, uid: s.publicID(id), seconds: seconds(z.Score)})
			}
		}
		sortTop(tops[i])
		tops[i] = tops[i][:min(limit, len(tops[i]))]
		for _, r := range tops[i] {
			listed = append(listed, r.id)
		}
	}
	info := s.users(ctx, listed)
	for i, g := range Games {
		gp := GamePlaytime{Game: g, Players: cmds[i].count.Val(), Hourly: make([]HourPlaytime, len(buckets)),
			Top: make([]PlayerPlaytime, 0, len(tops[i]))}
		var total float64
		for j, b := range buckets {
			ms, _ := strconv.ParseFloat(totals[j].Val()[g], 64)
			total += ms * b.weight
			gp.Hourly[j] = HourPlaytime{Hour: Stamp(b.hour), Seconds: seconds(ms)}
		}
		gp.Seconds = seconds(total)
		for _, r := range tops[i] {
			gp.Top = append(gp.Top, PlayerPlaytime{UID: r.uid, UserID: r.id.String(), Name: info[r.id].name,
				CreatedAt: stampOf(info[r.id].created), Seconds: r.seconds})
		}
		rep.Games = append(rep.Games, gp)
	}
	return rep, nil
}

// ----------------------------------------------------------------- people

type userInfo struct {
	name    string
	created *time.Time
}

func (s *Service) publicID(id uuid.UUID) string {
	if s.profiles == nil {
		return ""
	}
	return s.profiles.PublicID(id)
}

// users returns the display names and creation times of accounts. There is
// no accounts table: an account was created with its first identity
// (min(created_at) of identity.auth_identities). A failed lookup is logged
// and leaves the fields empty, so the report is still served.
func (s *Service) users(ctx context.Context, ids []uuid.UUID) map[uuid.UUID]userInfo {
	out := make(map[uuid.UUID]userInfo, len(ids))
	if len(ids) == 0 {
		return out
	}
	if s.profiles != nil {
		for id, p := range s.profiles.GetMany(ctx, ids) {
			out[id] = userInfo{name: p.Name}
		}
	}
	if s.pg == nil {
		return out
	}
	rows, err := s.pg.Query(ctx, `
		SELECT user_id, min(created_at) FROM identity.auth_identities
		 WHERE user_id = ANY($1) GROUP BY user_id`, ids)
	if err != nil {
		s.warn("ops report: account creation times unavailable", err)
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id uuid.UUID
		var at time.Time
		if err := rows.Scan(&id, &at); err != nil {
			s.warn("ops report: account creation times unavailable", err)
			return out
		}
		u := out[id]
		u.created = &at
		out[id] = u
	}
	if err := rows.Err(); err != nil {
		s.warn("ops report: account creation times unavailable", err)
	}
	return out
}

func (s *Service) warn(msg string, err error) {
	if s.log != nil {
		s.log.Warn(msg, "error", err.Error())
	}
}
