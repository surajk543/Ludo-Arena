package tests

import (
	"context"
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"ludoroyale/internal/postgres"
)

// Guard for the PostgreSQL boundaries in CLAUDE.md: live game state lives in
// Redis only, and tables are not added without asking. A failure here means a
// migration added a table or a gameplay-state column; get the change approved
// and update the allowlists below together with CLAUDE.md and the docs.

const schemaRule = "see CLAUDE.md \"PostgreSQL boundaries\": live game state lives in Redis only; do not add tables without asking"

// allowedTables is every approved table in non-system schemas. The migration
// runner keeps no tracking table (idempotent SQL under an advisory lock).
var allowedTables = []string{
	"wallet.wallets",
	"identity.auth_identities",
	"progression.player_progress",
	"progression.mission_progress",
	"progression.mission_claims",
	"progression.match_receipts",
	"progression.inventory",
	"progression.loadout",
	"progression.friendships",
	"progression.player_reports",
	// Profile-picture catalogue (owner-approved 2026-10-21; no player data).
	"progression.profile_pictures",
}

// gameplayWords are column-name words (split on "_") that indicate stored
// game state or room contents.
var gameplayWords = []string{
	"board", "token", "tokens", "position", "positions", "pos", "dice", "die", "roll", "rolls",
	"turn", "turns", "move", "moves", "seat", "seats", "snapshot", "snapshots", "state", "states",
	"legal", "phase", "room", "rooms", "game", "games", "chat", "score", "scores", "rank",
	"winner", "placements", "pot",
}

// allowedColumns are approved exceptions: plain references on a report and
// the display name (approved separately).
var allowedColumns = []string{
	"progression.player_reports.room_id",
	"progression.player_reports.game",
	"progression.player_progress.display_name",
}

func TestSchemaHoldsNoGameplayState(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	pg, err := postgres.Open(ctx, dbURL, 2)
	if err != nil {
		t.Fatal(err)
	}
	defer pg.Close()
	if err := postgres.Migrate(ctx, pg); err != nil {
		t.Fatal(err)
	}
	const userSchemas = `table_schema NOT IN ('pg_catalog', 'information_schema')
		AND table_schema NOT LIKE 'pg\_toast%' AND table_schema NOT LIKE 'pg\_temp%'`

	rows, err := pg.Query(ctx, `SELECT table_schema || '.' || table_name FROM information_schema.tables
		WHERE `+userSchemas+` ORDER BY 1`)
	if err != nil {
		t.Fatal(err)
	}
	var tables []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatal(err)
		}
		tables = append(tables, name)
	}
	rows.Close()
	for _, tb := range tables {
		if !slices.Contains(allowedTables, tb) {
			t.Errorf("table %s is not in the approved allowlist (%s)", tb, schemaRule)
		}
	}
	if !slices.Contains(tables, "progression.player_reports") || !slices.Contains(tables, "wallet.wallets") {
		t.Fatalf("schema query found no migrated tables: %v", tables)
	}

	rows, err = pg.Query(ctx, `SELECT table_schema || '.' || table_name || '.' || column_name FROM information_schema.columns
		WHERE `+userSchemas+` ORDER BY 1`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	checked := 0
	for rows.Next() {
		var col string
		if err := rows.Scan(&col); err != nil {
			t.Fatal(err)
		}
		checked++
		if slices.Contains(allowedColumns, col) {
			continue
		}
		name := col[strings.LastIndexByte(col, '.')+1:]
		for _, w := range strings.Split(strings.ToLower(name), "_") {
			if slices.Contains(gameplayWords, w) {
				t.Errorf("column %s looks like gameplay state or room contents (%q) (%s)", col, w, schemaRule)
			}
		}
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	if checked == 0 {
		t.Fatal("no columns checked")
	}
}
