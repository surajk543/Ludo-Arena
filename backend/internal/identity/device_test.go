package identity

import (
	"encoding/hex"
	"errors"
	"strings"
	"testing"
)

const testSecret = "test-public-id-key-0123456789abcdef"

// Golden vectors computed independently (Python hmac/hashlib):
//
//	k = HMAC-SHA256(secret, "ludo-arena/device-id/v1")
//	subject = hex(HMAC-SHA256(k, platform + ":" + deviceId))
const (
	goldenKey     = "b14939389ec43e76ef4fefae686947163fc4c750d3848b254e21477d9657f4ab"
	goldenAndroid = "33c621c4ede4f3bb6225366aad17bfad2f29563baa5e3f617c108158f6b92f1d"
	goldenIOS     = "b4a32f02392dbf8a4a5c7cefdc41d9333bf6951dfe9d07b48b0addd39c106b94"
	goldenID      = "a1b2c3d4e5f60718"
)

func TestDeviceKeyIsDomainSeparated(t *testing.T) {
	k := DeviceKey([]byte(testSecret))
	if hex.EncodeToString(k) != goldenKey {
		t.Fatalf("DeviceKey = %x, want %s", k, goldenKey)
	}
	if string(k) == testSecret || len(k) != 32 {
		t.Fatal("device key must be derived, not the secret itself")
	}
	if hex.EncodeToString(DeviceKey([]byte(testSecret+"x"))) == goldenKey {
		t.Fatal("device key does not depend on the secret")
	}
}

func TestDeviceSubject(t *testing.T) {
	key := DeviceKey([]byte(testSecret))
	android, err := DeviceSubject(key, "android", goldenID)
	if err != nil {
		t.Fatal(err)
	}
	ios, err := DeviceSubject(key, "ios", goldenID)
	if err != nil {
		t.Fatal(err)
	}
	if android != goldenAndroid || ios != goldenIOS {
		t.Fatalf("subjects = %s / %s, want golden vectors", android, ios)
	}
	if android == ios {
		t.Fatal("the same device id on two platforms must not share a subject")
	}
	again, _ := DeviceSubject(key, "android", goldenID)
	if again != android {
		t.Fatal("subject is not stable")
	}
	if upper, _ := DeviceSubject(key, "android", strings.ToUpper(goldenID)); upper != android {
		t.Fatal("device ids must compare case-insensitively")
	}
	if other, _ := DeviceSubject(key, "android", "a1b2c3d4e5f60719"); other == android {
		t.Fatal("different device ids share a subject")
	}
	if otherKey, _ := DeviceSubject(DeviceKey([]byte(testSecret+"x")), "android", goldenID); otherKey == android {
		t.Fatal("subject does not depend on the key")
	}
	uuid := "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
	s, err := DeviceSubject(key, "ios", uuid)
	if err != nil {
		t.Fatal(err)
	}
	for _, sub := range []string{android, ios, s} {
		if len(sub) != 64 || strings.ToLower(sub) != sub {
			t.Fatalf("subject %q is not lowercase hex SHA-256", sub)
		}
		if strings.Contains(sub, goldenID) || strings.Contains(sub, strings.ToLower(uuid)) {
			t.Fatal("subject contains the raw device id")
		}
	}
}

func TestDeviceSubjectRejects(t *testing.T) {
	key := DeviceKey([]byte(testSecret))
	for _, platform := range []string{"", "web", "Android", "IOS", "android "} {
		if _, err := DeviceSubject(key, platform, goldenID); !errors.Is(err, ErrInvalidDevice) {
			t.Fatalf("platform %q: err = %v, want ErrInvalidDevice", platform, err)
		}
	}
	if _, err := DeviceSubject(key, "android", "short"); !errors.Is(err, ErrInvalidDevice) {
		t.Fatalf("bad id: err = %v", err)
	}
	if _, err := DeviceSubject(nil, "android", goldenID); err == nil || errors.Is(err, ErrInvalidDevice) {
		t.Fatalf("missing key: err = %v, want a configuration error", err)
	}
}

func TestValidDeviceID(t *testing.T) {
	cases := []struct {
		id string
		ok bool
	}{
		{"a1b2c3d4e5f60718", true},                     // ANDROID_ID (16 hex)
		{"3F2504E0-4F89-41D3-9A0C-0305E82C3301", true}, // iOS keychain UUID
		{"3f2504e0-4f89-41d3-9a0c-0305e82c3301", true},
		{strings.Repeat("ab", 32), true}, // 64 chars
		{"", false},
		{"a1b2c3d4e5f6071", false},              // 15 chars
		{strings.Repeat("ab", 32) + "c", false}, // 65 chars
		{"9774d56d682e549c", false},             // known-bad Android id
		{"9774D56D682E549C", false},
		{"0000000000000000", false},
		{"00000000-0000-0000-0000-000000000000", false},
		{"ffffffffffffffff", false},
		{"aAaAaAaAaAaAaAaA", false}, // one repeated letter, any case
		{"----------------", false},
		{"a1b2c3d4 e5f60718", false},
		{"a1b2c3d4_e5f60718", false},
		{"a1b2c3d4e5f60718!", false},
		{"a1b2c3d4e5f6071ä", false},
		{"a1b2c3d4e5f60718\n", false},
	}
	for _, c := range cases {
		if got := ValidDeviceID(c.id); got != c.ok {
			t.Errorf("ValidDeviceID(%q) = %v, want %v", c.id, got, c.ok)
		}
	}
}
