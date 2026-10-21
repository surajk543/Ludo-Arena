package profile

import (
	"errors"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestNormalizeName(t *testing.T) {
	cases := []struct{ in, want string }{
		{"  Asha  ", "Asha"},
		{"Asha \t\n  Verma", "Asha Verma"},
		{"Asha\U000000a0\U00002003Verma", "Asha Verma"},  // NBSP, em space
		{"Jose\U00000301", "José"},                       // NFD → NFC
		{"\U00000915\U0000093c", "\U00000915\U0000093c"}, // क़ stays decomposed (composition exclusion)
		{"\U00000958", "\U00000915\U0000093c"},           // precomposed क़ is decomposed by NFC
		{"Ra\U0000200dhul", "Ra\U0000200dhul"},           // zero-width chars are not whitespace (rejected later)
		{"", ""},
	}
	for _, c := range cases {
		if got := NormalizeName(c.in); got != c.want {
			t.Errorf("NormalizeName(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestValidateNameAccepts(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Asha", "Asha"},
		{"  rahul   kumar ", "rahul kumar"},
		{"Ali", "Ali"},
		{"राहुल", "राहुल"}, // Devanagari with vowel signs (Mc, Mn)
		{"प्रिया शर्मा", "प्रिया शर्मा"}, // virama conjunct
		{"علی رضا", "علی رضا"},           // Urdu
		{"محمد", "محمد"},                 // Arabic
		{"مُحَمَّد", "مُحَمَّد"},         // Arabic with harakat (shadda + fatha)
		{"عائشہ", "عائشہ"},               // Urdu
		{"Putri Ayu", "Putri Ayu"},       // Indonesian
		{"Budi_Santoso", "Budi_Santoso"},
		{"Dewi.Lestari-99", "Dewi.Lestari-99"},
		{"José", "José"},
		{"Jose\U00000301", "José"},               // normalized to NFC
		{"Siddharth2024", "Siddharth2024"},       // 13 runes
		{"abcdefghijklmnop", "abcdefghijklmnop"}, // exactly 16
		{"李小龙", "李小龙"},
		{"Ömer", "Ömer"},
		{"Шамиль", "Шамиль"},
	}
	for _, c := range cases {
		got, err := ValidateName(c.in)
		if err != nil || got != c.want {
			t.Errorf("ValidateName(%q) = %q, %v; want %q", c.in, got, err, c.want)
		}
	}
}

func TestValidateNameRejects(t *testing.T) {
	cases := []struct{ in, reason string }{
		// Length (after normalization).
		{"", ReasonTooShort},
		{"   ", ReasonTooShort},
		{"ab", ReasonTooShort},
		{" a\t ", ReasonTooShort},
		{"abcdefghijklmnopq", ReasonTooLong},
		{strings.Repeat("र", 17), ReasonTooLong},
		// Characters.
		{"😀😀😀", ReasonInvalidCharacters},
		{"Asha😀", ReasonInvalidCharacters},
		{"Ra\U0000200dhul", ReasonInvalidCharacters},                // zero-width joiner
		{"Ra\U0000200bhul", ReasonInvalidCharacters},                // zero-width space
		{"Ra\U0000feffhul", ReasonInvalidCharacters},                // BOM / ZWNBSP
		{"\U0000202eAsha", ReasonInvalidCharacters},                 // bidi override
		{"Asha\u0000", ReasonInvalidCharacters},                     // control
		{"Asha\U0000fe0f", ReasonInvalidCharacters},                 // variation selector
		{"\U00003164\U00003164\U00003164", ReasonInvalidCharacters}, // Hangul filler (invisible "letter")
		{"Asha\U00003164", ReasonInvalidCharacters},
		{"1\U000020e3 Asha", ReasonInvalidCharacters},                                    // keycap (enclosing mark)
		{"\U00000301Asha", ReasonInvalidCharacters},                                      // mark without a base letter
		{"Asha \U00000301x", ReasonInvalidCharacters},                                    // mark after a space
		{"x\U00000301\U00000302\U00000303\U00000304\U00000305", ReasonInvalidCharacters}, // Zalgo stack (5 marks)
		{"Asha!", ReasonInvalidCharacters},
		{"Asha@home", ReasonInvalidCharacters},
		{"<b>Asha", ReasonInvalidCharacters},
		{"Asha's", ReasonInvalidCharacters},
		{"12345", ReasonInvalidCharacters}, // no letter
		{"___", ReasonInvalidCharacters},
		{"Asha\U00002800", ReasonInvalidCharacters}, // braille blank
		// Reserved.
		{"Bot", ReasonReserved},
		{"bot_asha", ReasonReserved},
		{"B o t Max", ReasonReserved},
		{"B.o.t-Max", ReasonReserved},
		{"B0t Max", ReasonReserved},
		{"Вот Max", ReasonReserved}, // Cyrillic В, о, т
		{"ADMIN", ReasonReserved},
		{"SuperAdmin7", ReasonReserved},
		{"4dm1n", ReasonReserved},
		{"ａｄｍｉｎ", ReasonReserved}, // fullwidth letters
		{"Ādmīn", ReasonReserved},
		{"Game Moderator", ReasonReserved},
		{"Support Team", ReasonReserved},
		{"Official Asha", ReasonReserved},
		{"System", ReasonReserved},
		{"Ludo Royale", ReasonReserved},
		{"ludo_royale_x", ReasonReserved},
		{"LudoRoyale", ReasonReserved},
		// Blocklist.
		{"fuck", ReasonInappropriate},
		{"F.u.c k you", ReasonInappropriate},
		{"FUCK", ReasonInappropriate},
		{"fuсk", ReasonInappropriate}, // Cyrillic с
		{"Madarchod", ReasonInappropriate},
		{"bhen chod", ReasonInappropriate},
		{"Chutiya123", ReasonInappropriate},
		{"lavda_lasun", ReasonInappropriate},
		{"kontol", ReasonInappropriate},
		{"Bullsh1t", ReasonInappropriate},
	}
	for _, c := range cases {
		_, err := ValidateName(c.in)
		var ne *NameError
		if !errors.As(err, &ne) || ne.Reason != c.reason {
			t.Errorf("ValidateName(%q) = %v, want reason %s", c.in, err, c.reason)
		}
	}
}

func TestValidateNameEdge(t *testing.T) {
	// Length counts code points after normalization: "a b" is 3.
	if got, err := ValidateName("  a   b  "); err != nil || got != "a b" {
		t.Fatalf(`"  a   b  " = %q, %v`, got, err)
	}
	// 16 Devanagari code points are fine, 17 are too long; the stored form
	// is at most 64 bytes (migration 005 CHECK).
	ok := strings.Repeat("रा", 8)
	if got, err := ValidateName(ok); err != nil || utf8.RuneCountInString(got) != 16 || len(got) > 64 {
		t.Fatalf("16 runes: %q %v", got, err)
	}
	// Four marks on one letter are allowed (Indic stacks), five are not.
	four := "\U0000091c\U0000093c\U0000094d\U0000093e\U00000901" // ज + nukta, virama, aa, candrabindu
	if _, err := ValidateName(four + " ab"); err != nil {
		t.Fatalf("4 marks rejected: %v", err)
	}
	if _, err := ValidateName(four + "\U00000902 ab"); err == nil {
		t.Fatal("5 marks accepted")
	}
	// Names that merely contain "bot" later are fine; only the start is reserved.
	if _, err := ValidateName("Abbot Kinney"); err != nil {
		t.Fatalf("Abbot: %v", err)
	}
}

// Common names must never hit the reserved list or the blocklist (substring
// matching makes short entries dangerous; see blocklist.txt).
func TestCommonNamesPass(t *testing.T) {
	names := []string{
		"Hassan", "Shital", "Shitij", "Harshit", "Dikshit", "Ankit", "Mohit", "Rohit", "Sumit",
		"Nazia", "Babita", "Gandhi", "Bhosle", "Kuttappan", "Fukuda", "Dickson", "Hancock",
		"Peacock", "Sexton", "Pornchai", "Randi", "Lundgren", "Salah", "Jihad", "Lauda",
		"Chitra", "Suchitra", "Cassandra", "Classic", "Grape", "Therese", "Analisa",
		"Priya Sharma", "Muhammad Ali", "Fatima Zahra", "Ayesha Khan", "Siti Nurhaliza",
		"Agus Salim", "Bambang", "Wahyu", "Rizky", "Abdullah", "Mustafa", "Yusuf",
		"Zainab", "Amit Kumar", "Sunita", "Lakshmi", "Venkatesh", "Gurpreet", "Harpreet",
		"राहुल", "علی رضا", "محمد", "Nguyen", "Matsushita",
	}
	for _, n := range names {
		if _, err := ValidateName(n); err != nil {
			t.Errorf("common name %q rejected: %v", n, err)
		}
	}
}

func TestBlocklistFile(t *testing.T) {
	if len(blocklist) < 20 {
		t.Fatalf("blocklist has %d entries", len(blocklist))
	}
	seen := map[string]bool{}
	for _, line := range strings.Split(blocklistFile, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		sk := skeleton(line)
		// Short entries match inside ordinary names.
		if utf8.RuneCountInString(sk) < 4 {
			t.Errorf("blocklist entry %q is too short (skeleton %q)", line, sk)
		}
		if seen[sk] {
			t.Errorf("duplicate blocklist entry %q", line)
		}
		seen[sk] = true
		// Every entry blocks itself, also when spaced out or upper-cased.
		for _, v := range []string{line, strings.ToUpper(line), strings.Join(strings.Split(line, ""), " ")} {
			if len([]rune(NormalizeName(v))) > NameMaxRunes {
				continue
			}
			if _, err := ValidateName(v); err == nil {
				t.Errorf("blocklist variant %q accepted", v)
			}
		}
	}
}

func TestSkeleton(t *testing.T) {
	cases := []struct{ in, want string }{
		{"B o t", "bot"},
		{"B_0.T-", "bot"},
		{"ADMIN", "admin"},
		{"Ádmín", "admin"},
		{"ａｄｍｉｎ", "admin"},
		{"𝐚𝐝𝐦𝐢𝐧", "admin"},
		{"аdmіn", "admin"}, // Cyrillic а, і
		{"Ludo Royale", "iudoroyaie"},
		{"1337", "ieet"},
	}
	for _, c := range cases {
		if got := skeleton(c.in); got != c.want {
			t.Errorf("skeleton(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
