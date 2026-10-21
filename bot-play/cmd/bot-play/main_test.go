package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestCLIExitCodes(t *testing.T) {
	prof := "../../configs/profiles.yaml"
	cases := []struct {
		name string
		args []string
		env  string
		code int
		want string
	}{
		{"version", []string{"--version"}, "", exitOK, "bot-play"},
		{"validate", []string{"--config", "../../configs/environments/production.yaml", "--profiles", prof, "--validate"}, "", exitOK, "configuration OK"},
		{"bad config path", []string{"--config", "nope.yaml", "--profiles", prof}, "", exitConfig, "invalid configuration"},
		{"loadtest without ack", []string{"--config", "../../configs/loadtest.example.yaml", "--profiles", prof}, "", exitRefused, "not_acknowledged"},
		{"missing key", []string{"--config", "../../configs/environments/development.yaml", "--profiles", prof}, "", exitConfig, "BOT_SERVICE_KEY"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("BOT_SERVICE_KEY", c.env)
			var stderr bytes.Buffer
			if got := run(c.args, &stderr); got != c.code || !strings.Contains(stderr.String(), c.want) {
				t.Fatalf("exit %d (want %d), stderr: %s", got, c.code, stderr.String())
			}
		})
	}
}
