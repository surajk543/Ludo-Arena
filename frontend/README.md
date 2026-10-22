# Ludo Arena — Flutter app

Online Ludo and Snakes & Ladders for Android and iOS. The **Go backend is
authoritative** for identity, sessions, dice, moves, winners, balances and
XP; this app renders server-confirmed state. Contracts live in
[`../docs`](../docs) (WebSocket protocol, REST API, app version policy,
cosmetics catalog) and [`../backend/docs/game-rules.md`](../backend/docs/game-rules.md).

Firebase is used **only for Analytics** (consent-gated). There is no
Firebase Auth / Firestore / Remote Config / Functions.

---

## Requirements

- Flutter **3.44.7** / Dart 3.12.2
- Android SDK (API 36 build tools) — `minSdk 24`
- Xcode + **CocoaPods** for iOS — deployment target **iOS 15.0**
  (Swift Package Manager is disabled for this project, see *iOS notes*)

## Run against the local backend

```bash
# Android emulator (API_BASE_URL defaults to http://10.0.2.2:8080)
flutter run

# iOS simulator (defaults to http://localhost:8080)
flutter run -d "iPhone 17 Pro"

# Physical device on your LAN
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080

# With Firebase Analytics enabled (see below)
flutter run --dart-define-from-file=config/firebase.json
```

Cleartext HTTP is allowed only for local hosts: Android via a **debug-only**
network security config (`10.0.2.2`, `localhost`, `127.0.0.1`); iOS via
`NSAllowsLocalNetworking` (local addresses only, never internet hosts).

### Build-time configuration (`--dart-define`)

| Define | Default | Meaning |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:8080` (Android) / `http://localhost:8080` (iOS) | Backend origin, without `/api/v1`. `https` → `wss` for the socket. |
| `APP_ENV` | `development` | `development` \| `preproduction` \| `production`; sent to `GET /app/config`. |
| `GOOGLE_SERVER_CLIENT_ID` | project `ludo-royale-63887` web client | Google ID-token audience validated by the backend (required on Android). |
| `GOOGLE_IOS_CLIENT_ID` | project `ludo-royale-63887` iOS client | iOS OAuth client. Must match `ios/Flutter/AppConfig.xcconfig`. |
| `APPLE_SERVICE_ID` | empty | Apple Services ID for the **Android** web flow. |
| `APPLE_REDIRECT_URI` | empty | Redirect URI of that Services ID (the backend's `/api/v1/auth/apple/callback`). Both Apple values are needed to show Apple on Android; iOS always uses the native flow. |
| `FACEBOOK_ENABLED` | `false` | Shows "Continue with Facebook". Also requires the native app id (below). |
| `FIREBASE_*` | see *Firebase Analytics* | Read from `config/firebase.json` via `--dart-define-from-file`. |
| `LEGAL_NOTICES_URL` | `https://sungamestudio.com/ludo-arena/legal/` | Page opened in the browser by Settings → About → Legal notices (the backend's `${API_BASE_URL}/legal/open-source` is an optional fallback). |

Provider client ids are public identifiers; **no secret is ever compiled
into the app**.

### Sign-in providers — where the ids live

- **Google**: Dart defaults in `lib/core/config/app_config.dart`
  (`defaultGoogleServerClientId`, `defaultGoogleIosClientId`) and, for iOS,
  **`ios/Flutter/AppConfig.xcconfig`** (`GOOGLE_IOS_CLIENT_ID`,
  `GOOGLE_REVERSED_CLIENT_ID` URL scheme, `GOOGLE_SERVER_CLIENT_ID`). Android
  needs no id in code: its OAuth client is registered for
  `com.ludoarena.app` + the signing SHA-1 in Google Cloud.
- **Facebook** (not configured yet): Android reads `FACEBOOK_APP_ID` /
  `FACEBOOK_CLIENT_TOKEN` from a Gradle property (`-P…` or
  `~/.gradle/gradle.properties`) or the environment; iOS from
  `ios/Flutter/AppConfig.xcconfig` (also set
  `FACEBOOK_URL_SCHEME = fb$(FACEBOOK_APP_ID)`). Then build with
  `--dart-define=FACEBOOK_ENABLED=true`.
- **Apple**: iOS uses the `Sign in with Apple` capability
  (`ios/Runner/Runner.entitlements`). Android uses the web flow when
  `APPLE_SERVICE_ID` + `APPLE_REDIRECT_URI` are defined; the callback
  activity (`signinwithapple://callback`) is in the Android manifest.

## Firebase Analytics (analytics only)

1. Copy `config/firebase.example.json` → `config/firebase.json`
   (**gitignored**) and fill in the API keys. Keys read by the app:
   `FIREBASE_API_KEY`, `FIREBASE_IOS_API_KEY` (optional, falls back to the
   Android key), `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`,
   `FIREBASE_ANDROID_APP_ID`, `FIREBASE_IOS_APP_ID`, `FIREBASE_STORAGE_BUCKET`
   (optional). Non-secret ids also have code defaults; without an API key
   the app runs with a **no-op** analytics service.
2. Run with `--dart-define-from-file=config/firebase.json`.
3. Collection is **off by default** natively
   (`firebase_analytics_collection_enabled=false` in the Android manifest,
   `FIREBASE_ANALYTICS_COLLECTION_ENABLED=false` in `Info.plist`) and is
   switched on only after the user opts in (first-run sheet after sign-in,
   or Settings → Privacy). Withdrawal disables collection immediately and
   persists.
4. Events are sent only when Firebase is configured **and** consent is
   granted **and** the server says `user.actorType == "human"`. Only the
   whitelisted catalogue in `lib/core/analytics/analytics_catalog.dart` is
   sent — never names, ids, room codes, tokens or emails.

**DebugView**

```bash
# Android
adb shell setprop debug.firebase.analytics.app com.ludoarena.app
adb shell setprop debug.firebase.analytics.app .none.   # turn off
# iOS: add -FIRDebugEnabled to the Run scheme's launch arguments in Xcode
```

## Architecture

```
lib/
  main.dart                 → app/bootstrap.dart (pre-first-frame setup)
  app/
    app.dart                LudoArenaApp: MaterialApp.router, theme, locale
    bootstrap.dart          prefs, AppInfo, date symbols, release error fallback, analytics init
    gate/app_gate_controller.dart   startup/access state machine
    router.dart             GoRouter + gateRedirect (pure, tested)
    routes.dart             ALL route path constants + builders
    feature_routes.dart     the one list feature engineers extend
    realtime_binder.dart    starts/stops the WebSocket with the gate/session
    shell/app_shell_host.dart  optional-update dialog, consent sheet, 4409 dialog, level-up toasts
  core/
    config/                 AppConfig (--dart-define), AppInfo (version/build/platform)
    storage/                SecureSessionStore (tokens, guest secret, device id, session flags ONLY), PreferencesStore
    device/                 DeviceIdentity (ANDROID_ID / iOS keychain UUID) for restore after reinstall
    network/                ApiClient (Dio), TokenManager (single-flight refresh), ApiException, DTOs
    app_policy/             AppPolicy model, repository, cache, PolicySignalBus
    protocol/               ludo-arena.v1 envelope, models, events, state hash, RoomStateReducer
    realtime/               RealtimeConnection, backoff, ActiveRoomController, status
    errors/                 localizedErrorMessage(l10n, code) for every REST/WS/client code
    analytics/              AnalyticsService + gated Firebase implementation + consent
    audio_haptics/          AudioService (Sfx), HapticsService, ReducedMotion
    localization/           LanguageController, SupportedLocales, number/date formatting
    settings/               AppSettings (sound, volumes, haptics, reduced motion, quick-chat mute)
    theme/                  tokens, AppColors (light/dark), typography, seat colors, ThemeModeController
    telemetry/, time/, lifecycle/, state/ (inMatchProvider)
  shared/widgets/           premium component library (import widgets.dart)
  features/
    app_update/             splash, force update, maintenance, unreachable, optional update dialog
    authentication/         identity adapters, SessionController, login, Save Progress, onboarding
    home/ wallet/ profile/ settings/
```

### Startup gate

`AppGateController` (`lib/app/gate`) implements
`initializing → checkingPolicy → maintenance | forceUpdate | unreachable |
(optionalUpdatePrompt →) restoringSession → loadingWallet → ready` (or
`→ signedOut → login`). The router redirects on every phase change; nothing
behind the gate (home, games, deep links) is reachable before `ready`, and a
branded splash covers every transient phase. The policy is re-fetched on
resume (throttled to 30 s, always on blocking screens and after visiting the
store), on REST 426/503, on WebSocket close 4426/4503, and every 30 s on the
maintenance screen. The last policy is cached for display only.

### Session restore and the device id

`SessionController.restore()` tries, in order: the stored refresh token;
nothing more if the user signed out or was signed out by a sign-in on
another device (`session.signed_out` / `session.replaced`, cleared by the
next explicit sign-in); the stored guest secret; then
`POST /auth/device/resume` with the device id, so an update or reinstall
lands back in the same guest with its coins and progress (404 → login
screen). "Play as guest" resumes the stored guest secret, else sends the
device id to `POST /auth/guest` (the device's guest, or a new guest bound to
it). A guest sign-out keeps the guest secret and the binding, so "Play as
guest" always brings the same guest back (docs/authentication.md "Guest
persistence"). Guests restored without a binding bind the device once
(`PUT /account/device`, a 409 is final); linked accounts are never bound.
Save Progress turns the guest into a linked account: the server drops its
guest secret and binding and the app forgets them, so the next "Play as
guest" on the device is a new guest.

The device id (`lib/core/device/device_identity.dart`) is
`Settings.Secure.ANDROID_ID` on Android 8+ (scoped to the signing key,
survives reinstalls; read through the `ludo_arena/device_id` channel in
`MainActivity.kt`) and a random UUID kept in the iOS keychain
(`session.device_id`, this device only). Android 7 has no device id and
keeps the guest-secret behaviour. The id is sent only in those request
bodies: never logged, never in URLs, never sent to analytics.

### Key providers

| Provider | Type | Purpose |
|---|---|---|
| `appGateControllerProvider` | `NotifierProvider<AppGateController, GateState>` | Gate phase, current policy, `retry()`, `markVisitingStore()` |
| `sessionControllerProvider` | `NotifierProvider<SessionController, SessionState>` | user, sign-in/guest/link/logout/switch-back |
| `walletControllerProvider` | `NotifierProvider<WalletController, WalletState>` | server-confirmed coins/diamonds |
| `progressionSummaryProvider` | `Provider<ProgressionSummary?>` | level / XP / title |
| `realtimeConnectionProvider` | `Provider<RealtimeConnection>` | the WebSocket (`send`, `events`) |
| `activeRoomControllerProvider` | `NotifierProvider<ActiveRoomController, ActiveRoomState>` | current room + commands + ordered `events` |
| `realtimeStatusProvider` | `NotifierProvider<…, RealtimeStatus>` | connection indicator |
| `apiClientProvider` | `Provider<ApiClient>` | REST (`get/post/put/delete`) |
| `analyticsServiceProvider` | `Provider<AnalyticsService>` | typed analytics events |
| `themeModeControllerProvider`, `languageControllerProvider`, `settingsControllerProvider` | Notifier | persisted UI preferences |
| `inMatchProvider` | `NotifierProvider<InMatchController, bool>` | set by game screens; defers prompts |
| `audioServiceProvider`, `hapticsServiceProvider` | Provider | feedback honoring Settings |

### Adding screens

Add `GoRoute`s to `lib/app/feature_routes.dart` using the constants in
`lib/app/routes.dart` (`AppRoutes.matchmakingFor(...)`,
`AppRoutes.game(roomId)`, …). Every feature route is automatically behind
the gate.

## Localization

Languages: English, हिन्दी, اردو, العربية, Bahasa Indonesia
(`SupportedLocales.all`). Default = device language if supported, else
English; the choice is persisted and applied instantly (no sign-out, no
effect on the session, wallet or a running match).

Workflow:

1. Add keys to the fragments `lib/l10n/parts/<area>/{en,hi,ur,id,ar}.arb`
   (never edit `lib/l10n/app_*.arb`). Prefix keys with the area
   (`homePlayOnline`), give every English key an `@key` description, use
   ICU placeholders/plurals instead of concatenation.
2. `dart run tool/merge_arb.dart && flutter gen-l10n`
3. Use `AppLocalizations.of(context).yourKey`.

Adding a language: add it to `SupportedLocales.all`, to `locales` in
`tool/merge_arb.dart`, create `<code>.arb` in every area (including
`core/languageNameNative`), merge and generate.

Server error codes → text: `localizedErrorMessage(l10n, code)`
(`lib/core/errors/error_messages.dart`). Coins: `formatCoins`,
`formatCoinsCompact`, `formatNumberFull` (`lib/core/localization/number_format.dart`).
Settings → Number format picks the `NumberSystem`: Indian (`1,00,000`,
`10 Lakh`) or international (`100,000`, `1M`); until the user chooses, en/hi/ur
use Indian and id/ar international. The locale still decides digits,
separators and unit words. The choice reaches every caller through
`NumberSystemDelegate` in `MaterialApp.localizationsDelegates`
(`appLocalizationsDelegates`), so callers only pass
`Localizations.localeOf(context)` and never branch on the system.

### RTL

Arabic and Urdu switch the whole UI to RTL automatically. Use
`EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`;
mirror only directional icons. Keep identifiers readable: room codes,
friend codes and version numbers are rendered inside
`Directionality(textDirection: TextDirection.ltr)` (or wrapped in
`⁦ … ⁩` isolates inside sentences). Game boards are never mirrored.

Fonts: Fredoka (display) and Nunito (body) with Baloo 2 (Devanagari) and
Baloo Bhaijaan 2 (Arabic script) as fallbacks on every text style. All
bundled fonts are OFL; their license texts ship next to the fonts and are
listed (`lib/core/legal/bundled_licenses.dart`) on the open-source notices
page.

## Branding, legal notices and release builds

- **App icons and launch screens** are generated from the in-app crest
  (`BrandCrestPainter`): `flutter test tool/generate_brand_assets.dart`
  rewrites `assets/branding/` (masters) plus every iOS/Android icon size
  (adaptive + monochrome themed icon) and the launch-screen crest. The XML
  (adaptive icon, Android 12+ splash styles, `LaunchScreen.storyboard`) is
  hand-written; see `docs/deployment.md` → "Brand assets".
- **Open-source notices** are not shown inside the app. Settings → About →
  "Legal notices" opens `LEGAL_NOTICES_URL` (default
  `https://sungamestudio.com/ludo-arena/legal/`, the studio website) in the
  browser. Regenerate the page before each release (`flutter build bundle
  --release && dart run tool/export_oss_notices.dart`) and publish it to
  sungamestudio.com/ludo-arena/legal/; the backend also serves it at
  `${API_BASE_URL}/legal/open-source` as an optional fallback.
- **Release error fallback**: in release/profile builds a widget whose build
  fails renders a small branded "Something went wrong" (`lib/app/error_fallback.dart`).

## Sounds and music

- **Effects** (`assets/audio/sfx/*.wav`, 16-bit PCM mono — iOS cannot play
  Ogg) come from Kenney's CC0 packs. `tool/import_kenney_audio.sh
  <kenney-dir>` re-creates them from the unzipped packs (source file → name,
  trim, loudness and fades are in the script). The `Sfx` enum
  (`lib/core/audio_haptics/sfx.dart`) maps names to files, per-sound gain,
  cooldown and voice limit.
- **Lobby music** (`assets/audio/music/lobby_loop.m4a`, CC0, Freesound) loops
  on lobby / meta screens only (`lib/app/lobby_music.dart`): it fades out
  when a match screen opens, pauses in the background and never takes audio
  focus.
- `AudioService` (`lib/core/audio_haptics/audio_service.dart`) is the only
  audio entry point: Settings → Sound (master switch) plus effects / music
  volumes; one UI sound per tap (gesture coalescing); missing assets are
  logged once and skipped.
- Sources, licenses and processing of every shipped file:
  `assets/audio/ASSET_LICENSES.md` (not bundled in the app).

## Testing

```bash
dart run tool/merge_arb.dart && flutter gen-l10n
flutter analyze
flutter test
```

Tests drive the real controllers against fakes at the HTTP/SDK boundary
(`test/helpers/fake_backend.dart` is a Dio adapter; `test/helpers/harness.dart`
wires every provider override). `test/l10n/screens_overflow_matrix_test.dart`
renders every core screen in all languages, light/dark, at 320×640 (plus
1.3× text) and fails on any overflow.

## iOS notes

- Swift Package Manager is **disabled** (`flutter: config:
  enable-swift-package-manager: false` in `pubspec.yaml`): with SPM, Xcode
  resolves every package-level dependency of firebase-ios-sdk 13
  (`gtm-session-fetcher >= 4`) against GoogleSignIn 9
  (`gtm-session-fetcher 3.3.x`) and fails; CocoaPods resolves only the pods
  in use.
- Deployment target is iOS 15.0 (Firebase Analytics requirement).
- Simulator builds are **arm64-only** (`EXCLUDED_ARCHS[sdk=iphonesimulator*]
  = x86_64` in `ios/Flutter/AppConfig.xcconfig` and the Podfile): Xcode 27's
  `lipo -verify_arch` rejects multiple architectures, which breaks Flutter
  3.44's "Any iOS Simulator" builds. Apple-silicon simulators are unaffected.
- First iOS build runs `pod install` (several minutes); afterwards
  `flutter run -d "iPhone 17 Pro"` works as usual.
- `Runner.entitlements` enables Sign in with Apple; enable the capability
  for `com.ludoarena.app` in the Apple Developer portal before shipping.
