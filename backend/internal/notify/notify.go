// Package notify delivers server messages to a user's live WebSocket
// connection on whichever backend instance holds it, via Redis pub/sub
// (channel ev:user:{userId}). Delivery is best effort.
package notify

import (
	"context"
	"log/slog"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/protocol"
)

// UserChannel is the pub/sub channel for a user.
func UserChannel(userID string) string { return "ev:user:" + userID }

// Publisher implements gameevents.Notifier.
type Publisher struct {
	rdb *redis.Client
	log *slog.Logger
}

// New returns a Publisher.
func New(rdb *redis.Client, log *slog.Logger) *Publisher { return &Publisher{rdb: rdb, log: log} }

// NotifyUser publishes one message to the user.
func (p *Publisher) NotifyUser(ctx context.Context, userID uuid.UUID, msgType string, payload any) {
	p.Send(ctx, userID.String(), protocol.Encode(msgType, "", payload))
}

// Send publishes a pre-encoded envelope to a user id string (humans or bots).
func (p *Publisher) Send(ctx context.Context, userID string, msg []byte) {
	if err := p.rdb.Publish(ctx, UserChannel(userID), msg).Err(); err != nil {
		p.log.Warn("notify publish failed", "error", err.Error())
	}
}
