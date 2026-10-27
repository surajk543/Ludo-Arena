# Deployment & Local Development

Four independent projects, each with its own dependencies:

| Directory | Stack | Build | Config |
|---|---|---|---|
| `frontend/` | Flutter 3.44 / Dart 3.12 | `tool/build_android_release.sh apk\|appbundle` (obfuscated, R8) / `flutter build ipa --obfuscate …` | `--dart-define`s (public ids only) + gitignored `config/firebase.json` |
| `backend/` | Go 1.27 | `go build ./cmd/server` or `backend/Dockerfile` | environment variables (`backend/.env.example`), policy files in `backend/config/` |
| `bot-play/` | Go 1.27 (separate module) | `go build ./cmd/bot-play` or `bot-play/Dockerfile` | YAML in `bot-play/configs/` + env for the service key |
| `monitoring/` | Prometheus 3, Alertmanager, node_exporter; ops bot in Go 1.27 (separate module) | `monitoring/docker-compose.yml`; `go build ./cmd/ops-bot` or `monitoring/ops-bot/Dockerfile` | env (`monitoring/.env.example`), targets and thresholds in `monitoring/prometheus/` |

Backend secrets (`JWT_SIGNING_KEY`, `PUBLIC_ID_KEY`, `FACEBOOK_APP_SECRET`,
`R2_SECRET_ACCESS_KEY`, database/Redis passwords, the bot service key) are
provided only through the environment or a secret manager — never in the
Flutter app or in Git. The profile-picture bucket (Cloudflare R2, private)
needs all four `R2_*` variables or none; copy new pictures into it with
`go run ./cmd/r2-import-pictures` ([cosmetics-catalog.md](cosmetics-catalog.md#profile-pictures)).

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
TEST_DATABASE_URL=postgres://…/ludo_arena_test TEST_REDIS_ADDR=127.0.0.1:6379 \
  go test -race ./...                     # + end-to-end integration tests (tests/)

cd ../frontend && flutter analyze && flutter test
cd ../bot-play && go test -race ./...
cd ../monitoring/ops-bot && go test -race ./...
cd .. && promtool test rules prometheus/tests/alerts_test.yml
```

Integration tests use a dedicated test database and Redis logical DB 13/14,
which they flush.

## Production VPS (ludo.sungamestudio.com)

Production currently runs on one Ubuntu 24.04 VPS: backend, bot-play,
PostgreSQL 16, Redis 7 and nginx (TLS, WebSocket proxy) on the same host,
with kernel, nginx and systemd limits sized for 20k+ WebSockets. The
configuration, provisioning script and release/rollback script are in
[`deploy/`](../deploy/README.md). Production app builds
(`--dart-define=APP_ENV=production`) use `https://ludo.sungamestudio.com`
unless `API_BASE_URL` overrides it.

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
- Expose `METRICS_ADDR` only to the monitoring network. Live player counts
  (`players_in_game`, `rooms_in_game`, `players_in_lobby`) are cluster-wide
  and identical on every instance — aggregate with `max`; `ws_connections_active`
  is per instance — aggregate with `sum`. Alert when
  `time() - max(game_stats_refreshed_timestamp_seconds) > 120` (recount every
  `GAME_STATS_INTERVAL`, default 15 s). See
  [architecture.md](architecture.md#observability-live-player-counts).
- Monitoring and alerting: run the `monitoring/` stack (Prometheus,
  Alertmanager, node_exporter on every host, Telegram ops bot) on the same
  private network. List every backend instance's `METRICS_ADDR`, bot-play's
  metrics address and each host's node_exporter in
  `monitoring/prometheus/targets/*.yml`; use `docker-compose.host.yml` on Linux
  so node_exporter reads the real host; keep ≥ 31 days of Prometheus retention
  for the 30-day trends. Prometheus (9095), Alertmanager (9093), the ops bot
  (9097) and all metrics ports stay private; the bot needs outbound HTTPS to
  `api.telegram.org` (and Google APIs for Play/GA4 KPIs). The Telegram token
  and the optional Google service-account key come only from the environment
  or a secret store. Setup: [monitoring/README.md](../monitoring/README.md).
- Run ≥ 2 instances; any instance can serve any player (state + timers in
  Redis, events via Redis pub/sub). Rolling deploys: instances close
  WebSockets with `1001`; clients reconnect and resync.
- Graceful shutdown: SIGTERM → stop accepting, close sockets, drain HTTP (20 s).

## Release builds (app)

Before each release:

1. **Regenerate the open-source notices and publish them to
   sungamestudio.com/ludo-arena/legal/** (the app has no in-app license
   page; Settings → About → "Legal notices" opens
   `https://sungamestudio.com/ludo-arena/legal/` in the browser, a legal
   requirement for the bundled open-source software and OFL fonts):

   ```bash
   cd frontend
   flutter build bundle --release          # writes build/flutter_assets/NOTICES.Z
   dart run tool/export_oss_notices.dart   # → backend/config/legal/open-source-notices.html
   ```

   Publish the regenerated HTML on the studio website at
   `https://sungamestudio.com/ludo-arena/legal/` before the release ships,
   and commit it (it is deterministic: no diff without dependency changes;
   `--check` exits 1 when it is stale). Optional fallback: the backend also
   serves the same file at `GET /legal/open-source` — it reads
   `LEGAL_NOTICES_FILE` (default `config/legal/open-source-notices.html`,
   copied into the image) at startup and on `SIGHUP`; while it is missing the
   route answers 404. Build with
   `--dart-define=LEGAL_NOTICES_URL=https://<api-host>/legal/open-source`
   only to point the app at that fallback (or any other host) instead of
   the website.
2. **Build obfuscated.** Android release builds are always obfuscated
   (owner's rule, 22 Oct 2026): Dart with `--obfuscate --split-debug-info`,
   Java/Kotlin with R8 (minify + resource shrinking).
   `frontend/android/app/build.gradle.kts` refuses any other release build,
   including a plain `flutter build apk --release` or
   `flutter run --release` without those flags. Bump `version:` in
   `pubspec.yaml`, then:

   ```bash
   cd frontend
   tool/build_android_release.sh appbundle \
     --dart-define=API_BASE_URL=https://… --dart-define=APP_ENV=production \
     --dart-define-from-file=config/firebase.json     # or: … apk …
   flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios …
   ```

   **Every Android release PR carries its symbols** (owner's rule, 22 Oct
   2026, for a private repository: never push them while the repository is
   public, since they would stay in its history and forks). The script gzips them into
   `frontend/release-symbols/android/<version>/` and stages them in git:
   - `mapping.txt.gz`: the R8 mapping.
   - `app.android-*.symbols.gz`: the Dart symbols per ABI.
   - `BUILD_INFO`: version, commit, Flutter version and the artifact's SHA-256.
   - `SHA256SUMS`.

   The dart-defines are not recorded. Anyone with these files can read the
   original names, so keep them out of public places. Play Console also reads
   the R8 mapping embedded in the AAB. To decode a crash:

   ```bash
   gunzip -k release-symbols/android/<version>/*.gz
   flutter symbolize -i dart_trace.txt -d release-symbols/android/<version>/app.android-arm64.symbols
   $ANDROID_HOME/cmdline-tools/latest/bin/retrace \
     release-symbols/android/<version>/mapping.txt java_trace.txt
   ```

   iOS has no R8; keep `build/symbols/ios` for each version to decode Dart
   traces.

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

The Android app ships on Google Play as **`com.sungamestudio.ludoarena`**
(the iOS bundle id stays `com.ludoarena.app`). Play App Signing holds the
app signing key; we only hold the **upload key**:

- The upload keystore lives in `frontend/android/`, next to
  `frontend/android/key.properties`. Both are gitignored and are **never
  committed** (the repository is public); keep a backup in the team's
  secret store.
- `key.properties` keys: `storeFile` (relative to `frontend/android/`),
  `storePassword`, `keyAlias`, `keyPassword`.
- `android/app/build.gradle.kts` signs release builds with that key. Without
  `key.properties` it falls back to the debug key (with a warning) so local
  `flutter run --release` keeps working, and
  `tool/build_android_release.sh appbundle` refuses to build: a Play upload
  must be signed with the upload key.
- Register the **upload-key SHA-1** and the **Play App Signing SHA-1** (Play
  Console › App integrity) on the Android release OAuth client in Google
  Cloud (`docs/authentication.md`), or Google Sign-In fails in Play builds.

## App policy operations

See `docs/app-version-policy.md` (force/optional update, maintenance windows,
emergency flag file, reload with `kill -HUP`).
