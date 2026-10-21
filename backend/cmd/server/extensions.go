package main

import (
	"context"

	"ludoroyale/internal/server"
)

// extensions wires optional subsystems (progression, social, analytics).
func extensions(ctx context.Context, core *server.Core) (server.Extensions, error) {
	return server.DefaultExtensions(ctx, core)
}
