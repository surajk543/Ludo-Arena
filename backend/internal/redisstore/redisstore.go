// Package redisstore opens the Redis client used for live game state, rooms,
// matchmaking, sessions, presence and rate limits. See docs/redis-keys.md for
// the key layout and expiry rules.
package redisstore

import (
	"context"
	"crypto/tls"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// Open connects to Redis and verifies connectivity.
func Open(ctx context.Context, addr, password string, db int, useTLS bool) (*redis.Client, error) {
	opts := &redis.Options{
		Addr:         addr,
		Password:     password,
		DB:           db,
		DialTimeout:  3 * time.Second,
		ReadTimeout:  2 * time.Second,
		WriteTimeout: 2 * time.Second,
		PoolSize:     64,
		MinIdleConns: 4,
	}
	if useTLS {
		opts.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}
	rdb := redis.NewClient(opts)
	pingCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	if err := rdb.Ping(pingCtx).Err(); err != nil {
		_ = rdb.Close()
		return nil, fmt.Errorf("ping redis: %w", err)
	}
	return rdb, nil
}
