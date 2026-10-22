package server

import (
	"testing"

	"ludoarena/internal/config"
	"ludoarena/internal/rooms"
)

func TestCheckDice(t *testing.T) {
	tests := []struct {
		name    string
		env     string
		dice    rooms.Dice
		wantErr bool
	}{
		{"production default", config.EnvProduction, nil, false},
		{"production crypto", config.EnvProduction, rooms.CryptoDice{}, false},
		{"production seeded", config.EnvProduction, rooms.NewSeededDice(1), true},
		{"preproduction seeded", config.EnvPreproduction, rooms.NewSeededDice(1), false},
		{"development seeded", config.EnvDevelopment, rooms.NewSeededDice(1), false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := checkDice(tt.env, tt.dice); (err != nil) != tt.wantErr {
				t.Fatalf("checkDice(%q) error = %v, wantErr %v", tt.env, err, tt.wantErr)
			}
		})
	}
}
