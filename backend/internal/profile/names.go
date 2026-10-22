package profile

import (
	_ "embed"
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

// Rules for display names that players choose themselves (PATCH /api/v1/me).
// Provider and generated names are not subject to them (see SanitizeName).

// Length limits of a chosen name, in Unicode code points after NormalizeName.
const (
	NameMinRunes = 3
	NameMaxRunes = 16
)

// Rejection reasons, returned to clients as error details.reason of the
// invalid_name error (docs/rest-api.md).
const (
	ReasonTooShort          = "too_short"
	ReasonTooLong           = "too_long"
	ReasonInvalidCharacters = "invalid_characters"
	ReasonReserved          = "reserved"
	ReasonInappropriate     = "inappropriate"
)

// NameError is a rejected display name.
type NameError struct{ Reason string }

func (e *NameError) Error() string { return "invalid display name: " + e.Reason }

// maxMarks bounds consecutive combining marks on one letter: enough for
// Indic and Arabic (nukta + virama + vowel sign + candrabindu), not enough
// for "Zalgo" text that draws over neighbouring names.
const maxMarks = 4

// reservedWords may not appear anywhere in a chosen name (compared as
// skeletons, see skeleton). "Ludo Arena" (the product name) is covered by
// "ludoarena" because separators are removed; "ludoroyale" (the former
// name) stays reserved. Names may also not start with "bot": bots are
// shown as "Bot …" and the app strips that prefix.
var reservedWords = []string{"admin", "moderator", "support", "official", "system", "ludoarena", "ludoroyale"}

var botPrefix = skeleton("bot")

//go:embed blocklist.txt
var blocklistFile string

// blocklist holds the skeletons of the embedded blocklist entries.
var blocklist = parseBlocklist(blocklistFile)

var reservedSkeletons = func() []string {
	out := make([]string, len(reservedWords))
	for i, w := range reservedWords {
		out[i] = skeleton(w)
	}
	return out
}()

func parseBlocklist(file string) []string {
	var out []string
	for _, line := range strings.Split(file, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if sk := skeleton(line); sk != "" {
			out = append(out, sk)
		}
	}
	return out
}

// NormalizeName is the canonical form of a chosen name: Unicode NFC, leading
// and trailing whitespace removed and every internal whitespace run collapsed
// to one ASCII space. Case is preserved.
func NormalizeName(raw string) string {
	return strings.Join(strings.Fields(norm.NFC.String(raw)), " ")
}

// ValidateName normalizes raw and checks it against the chosen-name rules,
// in this order: length (too_short / too_long), characters
// (invalid_characters), reserved words (reserved), blocklist
// (inappropriate). It returns the normalized name or a *NameError.
//
// Allowed characters: Unicode letters (L*), non-spacing and spacing
// combining marks (Mn, Mc; needed for Devanagari, Urdu, Arabic) directly
// after a letter (at most maxMarks in a row), decimal digits (Nd), space,
// '_', '.', '-'. At least one letter is required. Everything else is
// rejected: emoji and other symbols, punctuation, control and format
// characters (zero-width joiner/space, bidi controls), enclosing marks
// (keycaps), variation selectors and invisible fillers (e.g. U+3164).
func ValidateName(raw string) (string, error) {
	name := NormalizeName(raw)
	switch n := utf8.RuneCountInString(name); {
	case n < NameMinRunes:
		return "", &NameError{ReasonTooShort}
	case n > NameMaxRunes:
		return "", &NameError{ReasonTooLong}
	}
	if !validChars(name) {
		return "", &NameError{ReasonInvalidCharacters}
	}
	sk := skeleton(name)
	if strings.HasPrefix(sk, botPrefix) {
		return "", &NameError{ReasonReserved}
	}
	for _, w := range reservedSkeletons {
		if strings.Contains(sk, w) {
			return "", &NameError{ReasonReserved}
		}
	}
	for _, w := range blocklist {
		if strings.Contains(sk, w) {
			return "", &NameError{ReasonInappropriate}
		}
	}
	return name, nil
}

func validChars(name string) bool {
	letters, marks, afterLetter := 0, 0, false
	for _, r := range name {
		switch {
		case r == utf8.RuneError, unicode.In(r, unicode.Variation_Selector, unicode.Other_Default_Ignorable_Code_Point):
			// Invisible characters that are (or behave like) letters or
			// marks: Hangul fillers, Khmer inherent vowels, U+034F, VS1–256.
			return false
		case unicode.IsLetter(r):
			letters++
			marks, afterLetter = 0, true
		case unicode.In(r, unicode.Mn, unicode.Mc):
			if !afterLetter || marks >= maxMarks {
				return false
			}
			marks++
		case unicode.Is(unicode.Nd, r), r == ' ', r == '_', r == '.', r == '-':
			marks, afterLetter = 0, false
		default:
			return false
		}
	}
	return letters > 0
}

// skeleton reduces a name to the form compared against reserved words and
// the blocklist: compatibility decomposition (fullwidth and "fancy" letters
// become plain), combining marks dropped (accents, matras), lower case,
// common look-alikes folded (Cyrillic/Greek homoglyphs, digits used as
// letters, l → i) and everything except letters and digits removed (so
// spaces, '_', '.', '-' cannot split a word). Both sides of every comparison
// go through skeleton, so the folding is symmetric.
func skeleton(s string) string {
	var b strings.Builder
	for _, r := range norm.NFKD.String(s) {
		if unicode.Is(unicode.M, r) {
			continue
		}
		r = unicode.ToLower(r)
		if f, ok := confusables[r]; ok {
			b.WriteString(f)
			continue
		}
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// confusables maps lower-case look-alikes to the Latin letters they imitate.
// Deliberately small; values are final (not folded again).
var confusables = map[rune]string{
	// Digits and letters used as letters ("adm1n", "b0t", "4dmin").
	'0': "o", '1': "i", '3': "e", '4': "a", '5': "s", '7': "t", '8': "b", 'l': "i",
	// Latin letters without a canonical decomposition.
	'ı': "i", 'ł': "i", 'ø': "o", 'đ': "d", 'ð': "d", 'ß': "ss", 'æ': "ae", 'œ': "oe",
	// Cyrillic.
	'а': "a", 'в': "b", 'е': "e", 'ё': "e", 'к': "k", 'м': "m", 'н': "h", 'о': "o", 'р': "p",
	'с': "c", 'т': "t", 'у': "y", 'х': "x", 'ѕ': "s", 'і': "i", 'ї': "i", 'ј': "j", 'ԁ': "d",
	'ӏ': "i", 'ү': "y",
	// Greek.
	'α': "a", 'β': "b", 'ε': "e", 'η': "n", 'ι': "i", 'κ': "k", 'ν': "v", 'ο': "o", 'ρ': "p",
	'τ': "t", 'υ': "u", 'χ': "x",
}
