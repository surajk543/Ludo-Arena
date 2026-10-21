package rooms

// Bot personas.
//
// Bots must be indistinguishable from people. A persona is a remembered bot
// identity that bot sessions wear one at a time:
//
//   - a stable internal id. A bot session's user id IS the persona id, so its
//     public uid (profile.PublicID, the same "u_" + 12 chars as a person's),
//     reports ("one report per player per 24 h") and friend requests behave
//     like a person's across matches;
//   - an avatar, a level weighted toward low-mid levels, the title such a
//     player would show, the cosmetics a player of that level could own
//     (starter, level unlocks up to its level, Store items) and its emotes;
//   - a profile-picture wardrobe: the persona keeps its picture (or none) for
//     BOT_PICTURE_KEEP_MIN..MAX matches, then changes to another active
//     catalogue picture or, occasionally, back to none, so that the long-run
//     share of bot seats wearing a picture is BOT_PICTURE_SHARE.
//
// Personas are keyed by pool and display name and leased to one live session
// at a time (the lowest free slot wins, so a bot met again usually is the same
// persona). The "known" pool (practice and private rooms, where players chose
// computer opponents) never shares personas with the "public" pool (public
// lobby fill). Nothing here touches XP or inventories.
//
// The persona id is derived from (pool, name, slot) (personaID, a UUIDv5), so
// it survives a Redis flush: the persona's look is then redrawn, but its id,
// public uid and coin wallet stay the same. That wallet is a wallet.wallets
// row with is_bot = TRUE (created when the persona is first seated; see
// wallet/bots.go and backend/docs/game-rules.md "Coins with bots").
//
// Redis (backend/docs/redis-keys.md): botpersona:{pool}:{name}:{slot},
// botlease:{pool}:{name}:{slot} and the public card botprof:{uid}.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	mrand "math/rand/v2"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/playerinfo"
)

// Persona pools.
const (
	poolPublic = "public" // public lobby fill
	poolKnown  = "known"  // practice and private rooms (chosen computer opponents)
)

// personaSlots is the number of personas per (pool, name): the most
// concurrent sessions that can share a name before falling back to an
// unremembered persona.
const personaSlots = 64

// Persona look tuning.
const (
	personaMaxLevel     = 50   // progression.MaxLevel
	personaLevelUpP     = 0.12 // per seating: the persona levelled up meanwhile
	personaEquipNewP    = 0.5  // a newly unlocked slot item gets equipped
	personaBestTitleP   = 0.6  // shows its best unlocked title (else a random owned one)
	personaPurchasedEmP = 0.1  // owns a Store emote
	pictureOffP         = 0.15 // wardrobe change: a wearer goes back to no picture
)

// seatSlots are the loadout slots a room seat shows.
var seatSlots = []string{"dice", "token", "frame", "trail", "victory"}

// persona is the stored state of one bot persona (JSON in Redis).
type persona struct {
	ID        uuid.UUID           `json:"id"`
	Avatar    int                 `json:"avatar"`
	Level     int                 `json:"level"`
	Title     string              `json:"title"`
	Cosmetics map[string]string   `json:"cosmetics"`
	Emotes    []string            `json:"emotes"`
	Wearing   bool                `json:"wearing"`
	Picture   *playerinfo.Picture `json:"picture,omitempty"`
	PicLeft   int                 `json:"picLeft"` // matches left with the current picture (or none)
	Matches   int                 `json:"matches"`
}

// wardrobeOpts configures picture changes.
type wardrobeOpts struct {
	Share            float64
	KeepMin, KeepMax int
	Pick             func() *playerinfo.Picture // a random active picture; nil when none
}

// rollLevel draws a plausible level: mostly newer players, some regulars.
func rollLevel(rng *mrand.Rand) int {
	bands := []struct {
		lo, hi int
		w      float64
	}{{1, 3, 25}, {4, 8, 30}, {9, 14, 25}, {15, 20, 13}, {21, 25, 7}}
	x := rng.Float64() * 100
	for _, b := range bands {
		if x < b.w {
			return b.lo + rng.IntN(b.hi-b.lo+1)
		}
		x -= b.w
	}
	return 1
}

// earned reports whether a player at level owns it without buying it.
func earned(it playerinfo.CatalogItem, level int) bool {
	return it.Starter || (it.Level > 0 && it.Level <= level)
}

// itemsOf returns the catalogue items of kind, in catalogue order.
func itemsOf(items []playerinfo.CatalogItem, kind string) []playerinfo.CatalogItem {
	var out []playerinfo.CatalogItem
	for _, it := range items {
		if it.Kind == kind {
			out = append(out, it)
		}
	}
	return out
}

// pickSlotItem chooses the equipped item of one slot for a player at level:
// starter items are most likely, level unlocks common, Store items rare.
func pickSlotItem(rng *mrand.Rand, items []playerinfo.CatalogItem, level int) string {
	type cand struct {
		id string
		w  float64
	}
	var cs []cand
	total := 0.0
	for _, it := range items {
		w := 0.0
		switch {
		case it.Starter:
			w = 3
		case it.Level > 0 && it.Level <= level:
			w = 2
		case it.Purchase:
			w = 0.4
		}
		if w > 0 {
			cs = append(cs, cand{it.ID, w})
			total += w
		}
	}
	if len(cs) == 0 {
		return ""
	}
	x := rng.Float64() * total
	for _, c := range cs {
		if x < c.w {
			return c.id
		}
		x -= c.w
	}
	return cs[len(cs)-1].id
}

// bestTitle returns the earned title with the highest unlock level.
func bestTitle(titles []playerinfo.CatalogItem, level int) string {
	best, bestLvl := "", -1
	for _, t := range titles {
		if earned(t, level) && t.Level > bestLvl {
			best, bestLvl = t.ID, t.Level
		}
	}
	return best
}

// pickTitle chooses the shown title: usually the best one earned.
func pickTitle(rng *mrand.Rand, titles []playerinfo.CatalogItem, level int) string {
	var owned []string
	for _, t := range titles {
		if earned(t, level) {
			owned = append(owned, t.ID)
		}
	}
	if len(owned) == 0 {
		return playerinfo.Starter().Title
	}
	if rng.Float64() < personaBestTitleP {
		return bestTitle(titles, level)
	}
	return owned[rng.IntN(len(owned))]
}

// earnedEmotes lists the emotes a player at level owns without buying.
func earnedEmotes(items []playerinfo.CatalogItem, level int) []string {
	var out []string
	for _, it := range itemsOf(items, "emote") {
		if earned(it, level) {
			out = append(out, it.ID)
		}
	}
	return out
}

// dress fills title, cosmetics and emotes for p.Level.
func (p *persona) dress(rng *mrand.Rand, items []playerinfo.CatalogItem) {
	starter := playerinfo.StarterLoadout()
	p.Cosmetics = make(map[string]string, len(seatSlots))
	for _, slot := range seatSlots {
		id := pickSlotItem(rng, itemsOf(items, slot), p.Level)
		if id == "" {
			id = starter[slot]
		}
		p.Cosmetics[slot] = id
	}
	p.Title = pickTitle(rng, itemsOf(items, "title"), p.Level)
	p.Emotes = earnedEmotes(items, p.Level)
	for _, it := range itemsOf(items, "emote") {
		if it.Purchase && rng.Float64() < personaPurchasedEmP {
			p.Emotes = append(p.Emotes, it.ID)
		}
	}
}

// levelUp raises the level by one and, like a player, sometimes equips what
// the new level unlocked.
func (p *persona) levelUp(rng *mrand.Rand, items []playerinfo.CatalogItem) {
	if p.Level >= personaMaxLevel {
		return
	}
	p.Level++
	for _, slot := range seatSlots {
		for _, it := range itemsOf(items, slot) {
			if it.Level == p.Level && rng.Float64() < personaEquipNewP {
				p.Cosmetics[slot] = it.ID
			}
		}
	}
	for _, t := range itemsOf(items, "title") {
		if t.Level == p.Level && rng.Float64() < personaBestTitleP {
			p.Title = t.ID
		}
	}
	for _, e := range earnedEmotes(items, p.Level) {
		if !slices.Contains(p.Emotes, e) {
			p.Emotes = append(p.Emotes, e)
		}
	}
}

// pictureRates returns the wardrobe switch probabilities (none → picture,
// picture → none) whose stationary share of wearers is share.
func pictureRates(share float64) (on, off float64) {
	switch {
	case share <= 0:
		return 0, 1
	case share >= 1:
		return 1, 0
	}
	off = pictureOffP
	on = share * off / (1 - share)
	if on > 1 {
		on, off = 1, (1-share)/share
	}
	return on, off
}

func keepFor(rng *mrand.Rand, o wardrobeOpts) int {
	lo, hi := max(o.KeepMin, 1), max(o.KeepMax, o.KeepMin, 1)
	return lo + rng.IntN(hi-lo+1)
}

// changePicture applies one wardrobe change and restarts the keep counter.
func (p *persona) changePicture(rng *mrand.Rand, o wardrobeOpts) {
	on, off := pictureRates(o.Share)
	if p.Wearing {
		p.Wearing = rng.Float64() >= off
	} else {
		p.Wearing = rng.Float64() < on
	}
	prev := p.Picture
	p.Picture = nil
	if p.Wearing && o.Pick != nil {
		for i := 0; i < 4; i++ { // another picture than before, when there is one
			if pic := o.Pick(); pic != nil {
				p.Picture = pic
				if prev == nil || pic.ID != prev.ID {
					break
				}
			}
		}
	}
	if p.Picture == nil {
		p.Wearing = false
	}
	p.PicLeft = keepFor(rng, o)
}

// newPersona creates a persona with a fresh id and look.
func newPersona(rng *mrand.Rand, items []playerinfo.CatalogItem, o wardrobeOpts) persona {
	p := persona{ID: uuid.New(), Avatar: rng.IntN(12), Level: rollLevel(rng)}
	p.dress(rng, items)
	p.Wearing = rng.Float64() < o.Share
	if p.Wearing && o.Pick != nil {
		p.Picture = o.Pick()
	}
	if p.Picture == nil {
		p.Wearing = false
	}
	p.PicLeft = keepFor(rng, o)
	return p
}

// nextMatch advances the persona to its next seating: it may have levelled
// up, and its wardrobe changes once the current picture's matches are used.
func (p *persona) nextMatch(rng *mrand.Rand, items []playerinfo.CatalogItem, o wardrobeOpts) {
	if p.Matches > 0 && rng.Float64() < personaLevelUpP {
		p.levelUp(rng, items)
	}
	if p.PicLeft <= 0 {
		p.changePicture(rng, o)
	}
	p.PicLeft--
	p.Matches++
}

// card is the persona's public profile under uid and name.
func (p *persona) card(uid, name string) playerinfo.BotCard {
	return playerinfo.BotCard{UID: uid, Name: name, Avatar: p.Avatar, Picture: p.Picture, Level: p.Level, Title: p.Title}
}

// ---- storage ----

// poolFor maps an assignment kind to its persona pool.
func poolFor(kind string) string {
	if kind == "public_fill" {
		return poolPublic
	}
	return poolKnown
}

// nameKey is the persona key part of a display name (case-insensitive).
func nameKey(name string) string {
	h := fnv.New64a()
	h.Write([]byte(strings.ToLower(strings.TrimSpace(name))))
	return strconv.FormatUint(h.Sum64(), 16)
}

// personaNamespace is the UUIDv5 namespace of persona ids (a constant: changing
// it would give every persona a new id and a new wallet).
var personaNamespace = uuid.MustParse("6f1d7c2e-3b9a-4f57-9a64-2c8e5d0b7a31")

// personaID is the stable id of the persona in slot of (pool, name): a UUIDv5
// of "{pool}:{nameKey}:{slot}". It is the bot session's user id and its
// wallet's user_id, and does not depend on anything stored in Redis.
func personaID(pool, name string, slot int) uuid.UUID {
	return uuid.NewSHA1(personaNamespace, []byte(pool+":"+nameKey(name)+":"+strconv.Itoa(slot)))
}

func personaKey(pool, name string, slot int) string {
	return "botpersona:" + pool + ":" + nameKey(name) + ":" + strconv.Itoa(slot)
}

func personaLeaseKey(pool, name string, slot int) string {
	return "botlease:" + pool + ":" + nameKey(name) + ":" + strconv.Itoa(slot)
}

// personaLeaseScript takes the first free lease key (SET NX PX) and returns its
// index, or -1 when every slot is in use.
var personaLeaseScript = redis.NewScript(`
for i, k in ipairs(KEYS) do
  if redis.call('SET', k, ARGV[1], 'NX', 'PX', ARGV[2]) then return i - 1 end
end
return -1`)

// personaReleaseScript deletes a lease only while it still holds token.
var personaReleaseScript = redis.NewScript(`
if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) end
return 0`)

// personaLease is a persona taken for one bot session.
type personaLease struct {
	p     persona
	key   string // botpersona key ("" for an unremembered persona)
	lease string // botlease key ("" when none)
	token string
}

// wardrobe returns the picture options of new and advanced personas.
func (s *Service) wardrobe() wardrobeOpts {
	o := wardrobeOpts{Share: s.Bots.PictureShare, KeepMin: s.Bots.PictureKeepMin, KeepMax: s.Bots.PictureKeepMax}
	if s.Pictures != nil {
		o.Pick = s.Pictures.RandomPicture
	}
	return o
}

func (s *Service) catalogItems() []playerinfo.CatalogItem {
	if s.Catalog == nil {
		return nil
	}
	return s.Catalog.CatalogItems()
}

func newRNG() *mrand.Rand { return mrand.New(mrand.NewPCG(mrand.Uint64(), mrand.Uint64())) }

// leasePersona takes the lowest free persona slot of (pool, name) for one
// session (token: a unique id of the claim) and advances it to this match.
// When every slot is busy or Redis fails, it returns a new persona that is
// not remembered (a random id; it gets a wallet like any other persona).
func (s *Service) leasePersona(ctx context.Context, pool, name, token string) personaLease {
	rng, items, o := newRNG(), s.catalogItems(), s.wardrobe()
	keys := make([]string, personaSlots)
	for i := range keys {
		keys[i] = personaLeaseKey(pool, name, i)
	}
	ttl := s.Bots.SessionTTL + 5*time.Minute
	slot, err := personaLeaseScript.Run(ctx, s.RDB, keys, token, ttl.Milliseconds()).Int()
	if err != nil || slot < 0 {
		if err != nil {
			s.Log.Warn("bot persona lease failed", "error", err.Error())
		}
		p := newPersona(rng, items, o)
		p.nextMatch(rng, items, o)
		return personaLease{p: p}
	}
	l := personaLease{key: personaKey(pool, name, slot), lease: keys[slot], token: token}
	var p persona
	raw, err := s.RDB.Get(ctx, l.key).Bytes()
	if err != nil || json.Unmarshal(raw, &p) != nil || p.Level < 1 {
		if err != nil && !errors.Is(err, redis.Nil) {
			s.Log.Warn("bot persona read failed", "error", err.Error())
		}
		p = newPersona(rng, items, o)
	}
	// The slot's id, whatever was stored (personas saved before ids were
	// derived carried a random one).
	p.ID = personaID(pool, name, slot)
	// No other session holds this persona: any room pointer of its id is
	// left over from an earlier session.
	_ = s.RDB.Del(ctx, userRoomKey(p.ID.String())).Err()
	p.nextMatch(rng, items, o)
	l.p = p
	return l
}

// keepPersona stores the persona after a successful seating and publishes
// its public card.
func (s *Service) keepPersona(ctx context.Context, l personaLease, uid, name string) {
	pipe := s.RDB.Pipeline()
	if l.key != "" {
		if raw, err := json.Marshal(l.p); err == nil {
			pipe.Set(ctx, l.key, raw, s.Bots.PersonaTTL)
		}
	}
	if raw, err := json.Marshal(l.p.card(uid, name)); err == nil {
		pipe.Set(ctx, playerinfo.BotCardKey(uid), raw, playerinfo.BotCardTTL)
	}
	if _, err := pipe.Exec(ctx); err != nil {
		s.Log.Warn("bot persona save failed", "error", err.Error())
	}
}

// releasePersona frees a persona lease (no-op without one).
func (s *Service) releasePersona(ctx context.Context, leaseKey, token string) {
	if leaseKey == "" || token == "" {
		return
	}
	if err := personaReleaseScript.Run(ctx, s.RDB, []string{leaseKey}, token).Err(); err != nil && !errors.Is(err, redis.Nil) {
		s.Log.Warn("bot persona release failed", "error", err.Error())
	}
}

// botSeat builds the seat of a bot session wearing persona p.
func (s *Service) botSeat(p persona, uid, name string) Player {
	cos := make(map[string]string, len(p.Cosmetics))
	for k, v := range p.Cosmetics {
		cos[k] = v
	}
	emotes := append([]string(nil), p.Emotes...)
	sort.Strings(emotes)
	return Player{UserID: p.ID.String(), UID: uid, Name: name, Avatar: p.Avatar, Level: p.Level, Title: p.Title,
		Cosmetics: cos, Picture: p.Picture, Bot: true, BotEmotes: emotes, JoinedAt: s.nowMs()}
}

// botSessionRecord is the botsess:{uid} value:
// "{sessionId}|{botId}|{roomId}|{leaseKey}|{leaseToken}" (the last two empty
// without a lease; records of older servers have only the first three).
func botSessionRecord(sid, botID, roomID, leaseKey, token string) string {
	return fmt.Sprintf("%s|%s|%s|%s|%s", sid, botID, roomID, leaseKey, token)
}

type botSessionInfo struct {
	SessionID, BotID, RoomID, LeaseKey, LeaseToken string
}

func parseBotSession(raw string) (botSessionInfo, bool) {
	parts := strings.SplitN(raw, "|", 5)
	if len(parts) < 3 {
		return botSessionInfo{}, false
	}
	for len(parts) < 5 {
		parts = append(parts, "")
	}
	return botSessionInfo{SessionID: parts[0], BotID: parts[1], RoomID: parts[2], LeaseKey: parts[3], LeaseToken: parts[4]}, true
}
