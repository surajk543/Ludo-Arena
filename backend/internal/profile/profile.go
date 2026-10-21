// Package profile derives public player ids and caches display data.
//
// Display names and avatars are non-authoritative presentation data kept in
// Redis (profile:{userId}); they are refreshed on every login and fall back to
// generated values if Redis loses them. No profile table exists in PostgreSQL.
package profile

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base32"
	"fmt"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

// Profile is what other players may see.
type Profile struct {
	UID    string `json:"uid"`
	Name   string `json:"name"`
	Avatar int    `json:"avatar"`
}

// Service manages public ids and display profiles.
type Service struct {
	rdb *redis.Client
	key []byte
}

// New returns a Service. key is the HMAC secret for public ids.
func New(rdb *redis.Client, key []byte) *Service { return &Service{rdb: rdb, key: key} }

var b32 = base32.NewEncoding("abcdefghijkmnpqrstuvwxyz23456789").WithPadding(base32.NoPadding)

// PublicID returns the stable pseudonymous id shown to other players
// ("u_" + 12 chars). It does not reveal the account id.
func (s *Service) PublicID(userID uuid.UUID) string {
	m := hmac.New(sha256.New, s.key)
	m.Write(userID[:])
	return "u_" + b32.EncodeToString(m.Sum(nil))[:12]
}

// Avatar returns the default avatar index (0..11) for an account.
func (s *Service) Avatar(userID uuid.UUID) int { return int(userID[15]) % 12 }

// GuestName is the generated name for accounts without a provider name.
func (s *Service) GuestName(userID uuid.UUID) string {
	return "Player " + strings.ToUpper(s.PublicID(userID)[2:6])
}

// SanitizeName trims, removes control characters and limits length. Empty
// results return "".
func SanitizeName(name string) string {
	name = strings.TrimSpace(name)
	var b strings.Builder
	for _, r := range name {
		if unicode.IsControl(r) || r == utf8.RuneError {
			continue
		}
		b.WriteRune(r)
	}
	out := strings.Join(strings.Fields(b.String()), " ")
	if r := []rune(out); len(r) > 20 {
		out = strings.TrimSpace(string(r[:20]))
	}
	return out
}

// Save stores the display profile and the public-id → account mapping.
// If name is empty, an existing name is kept or a generated one is used.
func (s *Service) Save(ctx context.Context, userID uuid.UUID, name string) (Profile, error) {
	p := Profile{UID: s.PublicID(userID), Avatar: s.Avatar(userID)}
	key := "profile:" + userID.String()
	name = SanitizeName(name)
	if name == "" {
		existing, err := s.rdb.HGet(ctx, key, "name").Result()
		if err == nil && existing != "" {
			name = existing
		} else {
			name = s.GuestName(userID)
		}
	}
	p.Name = name
	pipe := s.rdb.TxPipeline()
	pipe.HSet(ctx, key, "name", p.Name, "avatar", p.Avatar)
	pipe.Set(ctx, "pubid:"+p.UID, userID.String(), 0)
	_, err := pipe.Exec(ctx)
	return p, err
}

// Get returns the cached profile, regenerating defaults when missing.
func (s *Service) Get(ctx context.Context, userID uuid.UUID) Profile {
	p := Profile{UID: s.PublicID(userID), Avatar: s.Avatar(userID), Name: s.GuestName(userID)}
	vals, err := s.rdb.HMGet(ctx, "profile:"+userID.String(), "name", "avatar").Result()
	if err == nil {
		if n, ok := vals[0].(string); ok && n != "" {
			p.Name = n
		}
		if a, ok := vals[1].(string); ok {
			if v, err := strconv.Atoi(a); err == nil && v >= 0 && v < 12 {
				p.Avatar = v
			}
		}
	}
	return p
}

// GetMany returns profiles for several accounts in one round trip.
func (s *Service) GetMany(ctx context.Context, ids []uuid.UUID) map[uuid.UUID]Profile {
	out := make(map[uuid.UUID]Profile, len(ids))
	pipe := s.rdb.Pipeline()
	cmds := make([]*redis.SliceCmd, len(ids))
	for i, id := range ids {
		cmds[i] = pipe.HMGet(ctx, "profile:"+id.String(), "name", "avatar")
	}
	_, _ = pipe.Exec(ctx)
	for i, id := range ids {
		p := Profile{UID: s.PublicID(id), Avatar: s.Avatar(id), Name: s.GuestName(id)}
		if vals, err := cmds[i].Result(); err == nil {
			if n, ok := vals[0].(string); ok && n != "" {
				p.Name = n
			}
		}
		out[id] = p
	}
	return out
}

// Resolve maps a public id back to an account id (cache; durable callers
// should fall back to the progression store).
func (s *Service) Resolve(ctx context.Context, uid string) (uuid.UUID, error) {
	raw, err := s.rdb.Get(ctx, "pubid:"+uid).Result()
	if err != nil {
		return uuid.Nil, fmt.Errorf("unknown public id: %w", err)
	}
	return uuid.Parse(raw)
}
