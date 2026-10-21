package assets

import (
	"testing"
	"time"
)

// AWS example credentials used by every published SigV4 example.
const (
	awsKeyID  = "AKIAIOSFODNN7EXAMPLE"
	awsSecret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
)

// AWS's published presigned-URL example (Amazon S3 API Reference,
// "Authenticating Requests: Using Query Parameters (AWS Signature Version
// 4)"): GET /test.txt on examplebucket, 2013-05-24, 86400 s. Reproducing the
// published signature proves the canonical request, string to sign and key
// derivation are exactly SigV4's.
func TestPresignReproducesAWSExample(t *testing.T) {
	at := time.Date(2013, 5, 24, 0, 0, 0, 0, time.UTC)
	key := signingKeyFor(awsSecret, "20130524", "us-east-1", "s3")
	got := presignGET("https", "examplebucket.s3.amazonaws.com", "/test.txt", awsKeyID, key, "us-east-1", "s3", at, 24*time.Hour)
	want := "https://examplebucket.s3.amazonaws.com/test.txt" +
		"?X-Amz-Algorithm=AWS4-HMAC-SHA256" +
		"&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request" +
		"&X-Amz-Date=20130524T000000Z" +
		"&X-Amz-Expires=86400" +
		"&X-Amz-SignedHeaders=host" +
		"&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"
	if got != want {
		t.Fatalf("presigned URL\n got %s\nwant %s", got, want)
	}
}

// AWS's published header-signing examples (Amazon S3 API Reference,
// "Signature Calculations for the Authorization Header: Transferring Payload
// in a Single Chunk", Example requests).
func TestHeaderSigningReproducesAWSExamples(t *testing.T) {
	at := time.Date(2013, 5, 24, 0, 0, 0, 0, time.UTC)
	key := signingKeyFor(awsSecret, "20130524", "us-east-1", "s3")
	const host = "examplebucket.s3.amazonaws.com"
	const cred = "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,"
	cases := []struct {
		name, method, path string
		query              [][2]string
		headers            map[string]string
		payload            string
		want               string
	}{
		{
			name: "GET object", method: "GET", path: "/test.txt",
			headers: map[string]string{"host": host, "range": "bytes=0-9", "x-amz-date": "20130524T000000Z",
				"x-amz-content-sha256": emptySHA256},
			payload: emptySHA256,
			want: cred + "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date," +
				"Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41",
		},
		{
			name: "PUT object", method: "PUT", path: "/test$file.text",
			headers: map[string]string{"date": "Fri, 24 May 2013 00:00:00 GMT", "host": host,
				"x-amz-date": "20130524T000000Z", "x-amz-storage-class": "REDUCED_REDUNDANCY",
				"x-amz-content-sha256": "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072"},
			payload: "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072",
			want: cred + "SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class," +
				"Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd",
		},
		{
			name: "GET bucket lifecycle", method: "GET", path: "/", query: [][2]string{{"lifecycle", ""}},
			headers: map[string]string{"host": host, "x-amz-date": "20130524T000000Z", "x-amz-content-sha256": emptySHA256},
			payload: emptySHA256,
			want: cred + "SignedHeaders=host;x-amz-content-sha256;x-amz-date," +
				"Signature=fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543",
		},
		{
			name: "list objects", method: "GET", path: "/", query: [][2]string{{"prefix", "J"}, {"max-keys", "2"}},
			headers: map[string]string{"host": host, "x-amz-date": "20130524T000000Z", "x-amz-content-sha256": emptySHA256},
			payload: emptySHA256,
			want: cred + "SignedHeaders=host;x-amz-content-sha256;x-amz-date," +
				"Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := authorization(c.method, uriEncode(c.path, true), canonicalQuery(c.query), c.headers, c.payload,
				awsKeyID, key, "us-east-1", "s3", at)
			if got != c.want {
				t.Fatalf("\n got %s\nwant %s", got, c.want)
			}
		})
	}
}

// The derived signing key of the AWS SigV4 documentation example
// ("Calculate the signature": secret wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY,
// 20120215, us-east-1, iam).
func TestSigningKeyDerivationMatchesAWSDocs(t *testing.T) {
	got := signingKeyFor("wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "20120215", "us-east-1", "iam")
	const want = "f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d"
	if hexOf(got) != want {
		t.Fatalf("signing key %s, want %s", hexOf(got), want)
	}
}

func hexOf(b []byte) string {
	const digits = "0123456789abcdef"
	out := make([]byte, 0, len(b)*2)
	for _, c := range b {
		out = append(out, digits[c>>4], digits[c&15])
	}
	return string(out)
}

func TestURIEncoding(t *testing.T) {
	cases := []struct {
		in        string
		keepSlash bool
		want      string
	}{
		{"profile_pictures/lottie_animation/angry-tortoise.json", true, "profile_pictures/lottie_animation/angry-tortoise.json"},
		{"a b/c~d.e", true, "a%20b/c~d.e"},
		{"AKID/20261021/auto/s3/aws4_request", false, "AKID%2F20261021%2Fauto%2Fs3%2Faws4_request"},
		{"ünï", true, "%C3%BCn%C3%AF"},
		{"a+b=c&d", true, "a%2Bb%3Dc%26d"},
	}
	for _, c := range cases {
		if got := uriEncode(c.in, c.keepSlash); got != c.want {
			t.Errorf("uriEncode(%q, %t) = %q, want %q", c.in, c.keepSlash, got, c.want)
		}
	}
}

func TestCanonicalQuery(t *testing.T) {
	cases := []struct {
		in   [][2]string
		want string
	}{
		{nil, ""},
		{[][2]string{{"lifecycle", ""}}, "lifecycle="},
		{[][2]string{{"prefix", "a/"}, {"max-keys", "2"}}, "max-keys=2&prefix=a%2F"},
		{[][2]string{{"b", "2"}, {"a", "z"}, {"a", "y"}}, "a=y&a=z&b=2"},
	}
	for _, c := range cases {
		if got := canonicalQuery(c.in); got != c.want {
			t.Errorf("canonicalQuery(%v) = %q, want %q", c.in, got, c.want)
		}
	}
}
