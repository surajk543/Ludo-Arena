package httpapi

import (
	"net/http"
	"net/url"
	"regexp"

	"ludoarena/internal/ratelimit"
)

var androidPkg = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$`)

// RegisterAppleCallback adds POST /api/v1/auth/apple/callback, used only by
// the Android "Sign in with Apple" web flow: Apple form-posts the
// authorization result here, and we redirect into the app with an Android
// intent URL (as required by the sign_in_with_apple plugin). Nothing is
// verified or stored here — the app then sends the identity token to
// POST /api/v1/auth/apple, which performs the full verification.
func RegisterAppleCallback(rt *Router, androidPackage string) {
	if !androidPkg.MatchString(androidPackage) {
		return
	}
	ip := ratelimit.AuthPerIP
	rt.Handle("POST /api/v1/auth/apple/callback", Route{IPRule: &ip, MaxBody: 32 << 10},
		func(w http.ResponseWriter, r *http.Request) error {
			if err := r.ParseForm(); err != nil {
				return ErrBadRequest
			}
			q := url.Values{}
			for _, k := range []string{"code", "id_token", "state", "user", "error"} {
				if v := r.PostForm.Get(k); v != "" {
					q.Set(k, v)
				}
			}
			target := "intent://callback?" + q.Encode() +
				"#Intent;package=" + androidPackage + ";scheme=signinwithapple;end"
			w.Header().Set("Cache-Control", "no-store")
			http.Redirect(w, r, target, http.StatusSeeOther)
			return nil
		})
}
