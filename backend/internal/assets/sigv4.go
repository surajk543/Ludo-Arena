package assets

// AWS Signature Version 4, standard library only, in the two forms R2 (S3)
// accepts:
//
//   - presignGET: the signature in the query string, for a GET a phone can
//     open without credentials ("Authenticating Requests: Using Query
//     Parameters (AWS Signature Version 4)");
//   - authorization: the signature in the Authorization header, for the
//     import tool's PUT and HEAD ("Signature Calculations for the
//     Authorization Header: Transferring Payload in a Single Chunk").
//
// Both are checked against AWS's published worked examples (sigv4_test.go)
// and against the independent verifier in r2test.

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	// amzDateLayout is X-Amz-Date: ISO 8601 basic format, UTC.
	amzDateLayout = "20060102T150405Z"
	// algorithm is the only SigV4 algorithm.
	algorithm = "AWS4-HMAC-SHA256"
	// unsignedPayload is the payload hash of every presigned GET.
	unsignedPayload = "UNSIGNED-PAYLOAD"
	// emptySHA256 is the hex SHA-256 of an empty body (HEAD, GET).
	emptySHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
)

// signingKeyFor derives SigV4's signing key: HMAC("AWS4"+secret, date)
// chained through region, service and "aws4_request". date is YYYYMMDD.
func signingKeyFor(secret, date, region, service string) []byte {
	k := hmacSHA256([]byte("AWS4"+secret), date)
	k = hmacSHA256(k, region)
	k = hmacSHA256(k, service)
	return hmacSHA256(k, "aws4_request")
}

func hmacSHA256(key []byte, data string) []byte {
	h := hmac.New(sha256.New, key)
	h.Write([]byte(data))
	return h.Sum(nil)
}

func hexSHA256(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

// presignGET returns the query-presigned URL of a GET of path (the object's
// path-style path, "/<bucket>/<key>", NOT yet encoded) on scheme://host,
// signed at `at` and valid for `expires` (whole seconds). host is the only
// signed header and the payload is UNSIGNED-PAYLOAD. signingKey is
// signingKeyFor(secret, at's date, region, service).
func presignGET(scheme, host, path, accessKeyID string, signingKey []byte, region, service string,
	at time.Time, expires time.Duration) string {
	at = at.UTC()
	amzDate := at.Format(amzDateLayout)
	scope := amzDate[:8] + "/" + region + "/" + service + "/aws4_request"
	canonicalURI := uriEncode(path, true)
	// The five parameters are already in canonical (byte) order as written.
	query := "X-Amz-Algorithm=" + algorithm +
		"&X-Amz-Credential=" + uriEncode(accessKeyID+"/"+scope, false) +
		"&X-Amz-Date=" + amzDate +
		"&X-Amz-Expires=" + strconv.FormatInt(int64(expires/time.Second), 10) +
		"&X-Amz-SignedHeaders=host"
	canonicalRequest := "GET\n" +
		canonicalURI + "\n" +
		query + "\n" +
		"host:" + host + "\n" +
		"\n" +
		"host\n" +
		unsignedPayload
	stringToSign := algorithm + "\n" + amzDate + "\n" + scope + "\n" + hexSHA256([]byte(canonicalRequest))
	signature := hex.EncodeToString(hmacSHA256(signingKey, stringToSign))
	return scheme + "://" + host + canonicalURI + "?" + query + "&X-Amz-Signature=" + signature
}

// authorization returns the Authorization header value of a header-signed
// request. canonicalURI is the path exactly as sent (uriEncode(path, true)),
// canonicalQuery the canonical query exactly as sent (canonicalQuery);
// headers maps each signed header's lower-case name to its value and must
// contain host, x-amz-date (= at) and x-amz-content-sha256 (= payloadHash).
func authorization(method, canonicalURI, canonicalQuery string, headers map[string]string, payloadHash,
	accessKeyID string, signingKey []byte, region, service string, at time.Time) string {
	amzDate := at.UTC().Format(amzDateLayout)
	scope := amzDate[:8] + "/" + region + "/" + service + "/aws4_request"
	names := make([]string, 0, len(headers))
	for name := range headers {
		names = append(names, name)
	}
	sort.Strings(names)
	var ch strings.Builder
	for _, name := range names {
		ch.WriteString(name)
		ch.WriteByte(':')
		// Trimmed, inner runs of spaces folded to one.
		ch.WriteString(strings.Join(strings.Fields(headers[name]), " "))
		ch.WriteByte('\n')
	}
	signedHeaders := strings.Join(names, ";")
	canonicalRequest := method + "\n" +
		canonicalURI + "\n" +
		canonicalQuery + "\n" +
		ch.String() + "\n" +
		signedHeaders + "\n" +
		payloadHash
	stringToSign := algorithm + "\n" + amzDate + "\n" + scope + "\n" + hexSHA256([]byte(canonicalRequest))
	signature := hex.EncodeToString(hmacSHA256(signingKey, stringToSign))
	return algorithm + " Credential=" + accessKeyID + "/" + scope +
		",SignedHeaders=" + signedHeaders + ",Signature=" + signature
}

// canonicalQuery is SigV4's canonical query string: names and values
// URI-encoded ('/' too), sorted by name then value, joined with '&'; a
// parameter without a value is "name=". It is also what goes on the wire.
func canonicalQuery(params [][2]string) string {
	enc := make([][2]string, 0, len(params))
	for _, p := range params {
		enc = append(enc, [2]string{uriEncode(p[0], false), uriEncode(p[1], false)})
	}
	sort.Slice(enc, func(i, j int) bool {
		if enc[i][0] != enc[j][0] {
			return enc[i][0] < enc[j][0]
		}
		return enc[i][1] < enc[j][1]
	})
	parts := make([]string, len(enc))
	for i, p := range enc {
		parts[i] = p[0] + "=" + p[1]
	}
	return strings.Join(parts, "&")
}

// uriEncode is SigV4's URI encoding: every byte except the unreserved
// characters (A-Z a-z 0-9 - _ . ~) becomes %XX (upper-case hex); '/' is kept
// when keepSlash (a path) and encoded otherwise (a query value). S3 object
// keys are encoded exactly once.
func uriEncode(s string, keepSlash bool) string {
	const hexDigits = "0123456789ABCDEF"
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case 'A' <= c && c <= 'Z', 'a' <= c && c <= 'z', '0' <= c && c <= '9',
			c == '-', c == '_', c == '.', c == '~':
			b.WriteByte(c)
		case c == '/' && keepSlash:
			b.WriteByte(c)
		default:
			b.WriteByte('%')
			b.WriteByte(hexDigits[c>>4])
			b.WriteByte(hexDigits[c&15])
		}
	}
	return b.String()
}
