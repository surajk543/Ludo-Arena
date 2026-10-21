// Package migrations embeds the idempotent SQL migrations applied at startup.
package migrations

import "embed"

// FS holds the *.sql files, applied in lexical order.
//
//go:embed *.sql
var FS embed.FS
