# Deployment & Local Development

Three independent projects, each with its own dependencies:

| Directory | Stack | Build | Config |
|---|---|---|---|
| `frontend/` | Flutter 3.44 / Dart 3.12 | `flutter build apk` / `flutter build ipa` | `--dart-define`s (public ids only) + gitignored `config/firebase.json` |
| `backend/` | Go 1.27 | `go build ./cmd/server` or `backend/Dockerfile` | environment variables (`backend/.env.example`), policy files in `backend/config/` |
| `bot-play/` | Go 1.27 (separate module) | `go build ./cmd/bot-play` or `bot-play/Dockerfile` | YAML in `bot-play/configs/` + env for the service key |

Backend secrets (`JWT_SIGNING_KEY`, `PUBLIC_ID_KEY`, `FACEBOOK_APP_SECRET`,
database/Redis passwords, the bot service key) are provided only through the
environment or a secret manager — never in the Flutter app or in Git.

## Local development

```bash
# 1. Dependencies (Docker) — or use any local PostgreSQL 16 + Redis 7
cd backend && docker compose up -d

# 2. Backend
cp .env.example .env   # edit the CHANGE_ME values
set -a && . ./.env && set +a
go run ./cmd/server    # applies migrations, serves :8080, metrics on 127.0.0.1:9090

# 3. Flutter (Android emulator reaches the host at 10.0.2.2)
cd ../frontend
dart run tool/merge_arb.dart && flutter gen-l10n
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 \
            --dart-define=APP_ENV=development \
            --dart-define-from-file=config/firebase.json   # optional (analytics)
```

## Tests

```bash
cd backend
go test -race ./...                       # unit tests (engines, policy, progression…)
TEST_DATABASE_URL=postgres://…/ludo_royale_test TEST_REDIS_ADDR=127.0.0.1:6379 \
  go test -race ./...                     # + end-to-end integration tests (tests/)

cd ../frontend && flutter analyze && flutter test
cd ../bot-play && go test -race ./...
```

Integration tests use a dedicated test database and Redis logical DB 13/14,
which they flush.

## Production checklist

- TLS terminates at the load balancer (WebSocket upgrade allowed, idle timeout
  > 60 s); set `TRUSTED_PROXY_HOPS` accordingly; `PUBLIC_URL` = https URL.
- PostgreSQL and Redis on a private network only (never public), with backups:
  PostgreSQL PITR covering schemas `wallet`, `identity`, `progression`
  together; Redis AOF `everysec` + RDB, `noeviction`.
- `APP_ENV=production`, `APP_POLICY_FILE=…/app-policy.production.json`,
  `APP_MAINTENANCE_FLAG_FILE` on a path operators can create quickly
  (e.g. a mounted volume). `BOT_LOADTEST_ENABLED` must be `false` (startup
  refuses otherwise).
- Expose `METRICS_ADDR` only to the monitoring network.
- Run ≥ 2 instances; any instance can serve any player (state + timers in
  Redis, events via Redis pub/sub). Rolling deploys: instances close
  WebSockets with `1001`; clients reconnect and resync.
- Graceful shutdown: SIGTERM → stop accepting, close sockets, drain HTTP (20 s).

## Release builds (app)

Before each release:

1. **Regenerate the open-source notices page** (the app has no in-app
   license page; Settings → About → "Legal notices" opens
   `GET /legal/open-source` in the browser, a legal requirement for the
   bundled open-source software and OFL fonts):

   ```bash
   cd frontend
   flutter build bundle --release          # writes build/flutter_assets/NOTICES.Z
   dart run tool/export_oss_notices.dart   # → backend/config/legal/open-source-notices.html
   ```

   Commit the regenerated HTML (it is deterministic: no diff without
   dependency changes; `--check` exits 1 when it is stale) and deploy the
   backend with it. The backend reads `LEGAL_NOTICES_FILE` (default
   `config/legal/open-source-notices.html`, copied into the image) at startup
   and on `SIGHUP`; while it is missing the route answers 404. Point
   `LEGAL_NOTICES_URL` (`--dart-define`) elsewhere only if the page is
   hosted somewhere else.
2. **Build obfuscated** and keep the symbols privately (needed to symbolicate
   crash stack traces; never ship or commit them):

   ```bash
   flutter build appbundle --release --obfuscate --split-debug-info=build/symbols \
     --dart-define=API_BASE_URL=https://… --dart-define=APP_ENV=production …
   flutter build ipa --release --obfuscate --split-debug-info=build/symbols …
   # archive build/symbols/ per version (e.g. in the release's private storage)
   ```

What users can and cannot see: no screen, string, icon, splash or error
state names the UI toolkit (branded icons and launch screens, a branded
release error fallback, notices on the web page only). The binary itself
still contains the UI engine library and its notices file, so the toolkit is
detectable by technical inspection of the APK/IPA (e.g. listing native
libraries) — obfuscation only hides Dart symbol names, not that.

## Brand assets (icons, launch screens)

All launcher icons and launch-screen artwork are rendered from the in-app
crest (`BrandCrestPainter` in `frontend/lib/shared/widgets/brand_logo.dart`):

```bash
cd frontend && flutter test tool/generate_brand_assets.dart
```

It rewrites `assets/branding/` (1024 px masters: App Store icon without
alpha, Play Store 512 px icon, adaptive foreground/background, monochrome
themed-icon silhouette, launch crest — not bundled into the app), every size
in `ios/Runner/Assets.xcassets/AppIcon.appiconset` (opaque, no alpha) and
`LaunchCrest.imageset`, and the Android `mipmap-*` (legacy, round, adaptive
layers + monochrome), `drawable-*/launch_logo.png` (pre-12 splash) and
`drawable-*/splash_icon.png` (Android 12+ splash: 288 dp canvas, crest
without drop shadow inside the 192 dp circle the system shows). The XML is
hand-written: `mipmap-anydpi-v26/ic_launcher*.xml` (adaptive + Android 13
themed icon), `drawable*/launch_background.xml` (pre-Android 12 splash),
`values-v31` + `values-night-v31` styles (Android 12+ system splash), and
`ios/Runner/Base.lproj/LaunchScreen.storyboard` with the `LaunchBackground`
color set (light/dark). The launch crest is 132 pt/dp wide (on a 184 × 232
canvas that keeps its shadow) and sits where the in-app splash draws it —
78 pt above center on iOS, 90 dp on Android before 12 — so the first app
frame continues the launch screen (Android 12+ always centers the system
splash icon). `frontend/test/tool/brand_assets_test.dart` checks sizes,
alpha and references. iOS caches launch screens: delete the app (or reset
the simulator) to see a changed one.

## Release signing (Android)

The project currently signs release builds with the debug key (Flutter
default). Before publishing: create an upload keystore (kept outside Git,
referenced from an untracked `android/key.properties`), enable Play App
Signing, and add the **Play App Signing SHA-1** and upload-key SHA-1 as
additional Android OAuth clients in Google Cloud (`docs/authentication.md`).

## App policy operations

See `docs/app-version-policy.md` (force/optional update, maintenance windows,
emergency flag file, reload with `kill -HUP`).
