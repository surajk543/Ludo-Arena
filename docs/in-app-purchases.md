# In-app purchases — coin packs

Players buy **coin packs** (virtual coins plus bonus diamonds) for real money
through **Google Play** (Android) and the **App Store** (iOS). The Shop shows
them as its first category, **Coins**, and every Shop visit opens there.
Coins and diamonds have **no cash value** and can never be withdrawn,
exchanged or transferred.

The Go backend is authoritative: it verifies every purchase with the store
and credits the pack from its own configuration. The app only opens the
store's payment sheet and hands the store's proof of purchase to the server.

REST contract: [`rest-api.md` → Coin packs](rest-api.md#coin-packs-in-app-purchases).

## Products

All four are **consumable** products with the **same product id on Google
Play and the App Store** (`backend/config/coin_packs.json` can map a
different id per platform if a store ever needs one).

| Product id | Label (badge) | Coins | Diamonds | Price (India) |
|---|---|---|---|---|
| `coins_starter` | Starter | 5,000,000 (50 lakh) | 5 | ₹199 |
| `coins_popular` | Popular (badge) | 8,000,000 (80 lakh) | 8 | ₹299 |
| `coins_great_value` | Great Value | 15,000,000 (1.5 crore) | 100 | ₹499 |
| `coins_best_value` | Best Value (badge) | 35,000,000 (3.5 crore) | 250 | ₹999 |

The prices charged are the ones set in Play Console / App Store Connect; the
app shows the store's localized price. `fallbackPrice` in the configuration
is shown only while the store has not reported the product yet. Coins and
diamonds granted always come from `coin_packs.json` on the server. That file
is validated when it is loaded (positive amounts and prices, unique pack and
product ids, known badges) and is reloaded within `APP_POLICY_POLL_SECONDS`
(or on SIGHUP) when it changes; an invalid edit is rejected and the previous
list stays active.

## How a purchase flows

1. The app loads `GET /store/coin-packs` (packs, `purchasesAvailable`, and the
   account's `accountToken`) and the store's product details.
2. **Buy** → `InAppPurchase.buyConsumable` with `applicationUserName =
   accountToken` (Google `obfuscatedAccountId`, Apple `appAccountToken`) and,
   on Android, `autoConsume: false`.
3. The store reports the purchase as purchased → the app sends
   `POST /store/purchases` (Android: purchase token; iOS: StoreKit 2 signed
   transaction + transaction id), retrying network errors and 5xx.
4. The server verifies the purchase with the store (below), then **one
   PostgreSQL transaction** inserts the `progression.purchases` row and
   credits the wallet. `UNIQUE (store, transaction_id)` makes the grant
   exactly-once: retries, a second device or concurrent submissions get the
   original grant back (`"replayed": true`), never a second credit.
5. After the 200 the app consumes (Android) / finishes (iOS) the purchase,
   updates the wallet and celebrates. The server also pushes
   `wallet.updated` (`reason: "purchase"`). On Google Play the server
   consumes the purchase itself right after the grant too (so it is never
   auto-refunded for lack of acknowledgement); the app's consume is then a
   harmless no-op.
6. Anything else (refused, pending, server or store unreachable) leaves the
   purchase **unconsumed / unfinished**: the store keeps offering it and the
   app delivers it again — StoreKit 2 re-delivers unfinished transactions at
   launch by itself; on Android the app asks Google Play for unconsumed
   purchases after each sign-in. A purchase that arrives while the app is
   signed out waits for the sign-in.

### Account binding

`accountToken` is `HMAC-SHA256(PUBLIC_ID_KEY, account id)` shaped as a UUID:
stable per account, one-way, and different from every other id the app sees.
The store records it with the purchase and returns it in the verified
purchase; the server refuses (`purchase_invalid`) a purchase whose token is
missing or is not the caller's. A purchase token or signed transaction
therefore cannot be redeemed by another account — not by a second account on
the same phone, nor after the buyer deleted their account and signed up
again. (`PUBLIC_ID_KEY` must never change, or undelivered purchases could no
longer be matched; it also defines every public player id.)

### Verification

**Google Play** — Android Publisher API v3
[`purchases.products.get`](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products/get)
for the configured package and product, authenticated as the service account
(OAuth 2.0 JWT bearer grant signed with its key; access tokens cached for
their lifetime). The purchase must be `purchaseState` 0 (purchased; 2 =
pending → 409 `purchase_pending`, 1 = cancelled → 422), for that product,
with `obfuscatedExternalAccountId` equal to the caller's token, quantity
1–10 (multi-quantity is off, so always 1). A token of another app or product
is answered 400/404 by Google → 422. The purchase token itself is **never
stored**: `transaction_id` is its SHA-256 (hex); `order_id` keeps Google's
order number (`GPA.…`) for support. License-tester purchases
(`purchaseType` 0) are accepted, so testers can try the packs on any
backend.

**App Store** — the StoreKit 2 signed transaction (JWS) is verified locally,
exactly like Apple's App Store Server Library: ES256 header with an `x5c`
chain whose leaf and intermediate carry Apple's marker OIDs
(`1.2.840.113635.100.6.11.1`, `1.2.840.113635.100.6.2.1`), chain valid to
**Apple Root CA - G3** at the transaction's `signedDate`, signature valid
with the leaf key. The root certificate is embedded in the binary
(`backend/internal/iap/AppleRootCA-G3.cer`, downloaded from
<https://www.apple.com/certificateauthority/AppleRootCA-G3.cer>, SHA-256
`63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79`,
valid until 2039-04-30). Then: `bundleId` = `APPLE_BUNDLE_ID`, `productId` =
the pack's product, `type` = `Consumable`, no `revocationDate`,
`environment` Production (or Sandbox while `APPLE_IAP_ALLOW_SANDBOX=true`),
`appAccountToken` = the caller's token. With the optional **App Store Server
API** key, the server also re-reads the transaction from Apple ("Get
Transaction Info") and uses Apple's answer (it shows a refund that the app's
copy predates; an id alone is then enough). If Apple's API is down, the
verified signed copy is used (`iap_apple_lookups_total{result="fallback"}`).

### Refunds

A refund **takes back what the purchase granted**, each currency clamped at
the current balance (never below zero), marks the row `refunded` and pushes
`wallet.updated` (`reason: "refund"`, negative deltas). It is idempotent: a
refund seen again changes nothing.

- **Google Play**: every `GOOGLE_PLAY_VOIDED_POLL_INTERVAL` (default 1 h;
  0 disables) one backend instance (Redis lock `iap:google:voided:lock`)
  reads the [Voided Purchases
  API](https://developers.google.com/android-publisher/voided-purchases) for
  the last `GOOGLE_PLAY_VOIDED_LOOKBACK` (default 7 days, max 30) and refunds
  every voided in-app purchase it granted (refunds, chargebacks, cancelled
  orders). Real-time developer notifications are not needed.
- **App Store**: App Store Server Notifications **V2** at
  `POST https://<api-host>/api/v1/iap/apple/notifications`. The signed payload
  is verified like a transaction; `REFUND` and `REVOKE` refund it, other
  types are acknowledged and ignored. `REFUND_REVERSED` is **not**
  re-granted automatically (rare; support can credit it by hand).

A refund for a purchase whose account was deleted finds nothing to take back
(`result: unknown`).

## Configuration (backend)

All in the environment (`backend/.env.example`); key **files** stay outside
the repository and are never committed or logged. Without a store's
settings its purchases answer **503 `iap_unavailable`** and the Shop still
lists the packs (the app says "This pack isn't available yet").

| Variable | Default | Meaning |
|---|---|---|
| `COIN_PACKS_FILE` | `config/coin_packs.json` | Pack list (reloaded on change) |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_FILE` | – (off) | Service account JSON key; enables Google Play |
| `GOOGLE_PLAY_PACKAGE_NAME` | `com.sungamestudio.ludoarena` | Android (Play) package verified |
| `GOOGLE_PLAY_VOIDED_POLL_INTERVAL` | `1h` | Voided purchases poll (0 = off, ≥ 1m in production) |
| `GOOGLE_PLAY_VOIDED_LOOKBACK` | `168h` | How far back each poll looks (1h–720h) |
| `APPLE_IAP_ENABLED` | `false` | Enables App Store verification (signed transactions) |
| `APPLE_BUNDLE_ID` | `com.ludoarena.app` | iOS bundle id verified |
| `APPLE_IAP_ALLOW_SANDBOX` | `true` | Accept sandbox purchases (App Review, TestFlight, sandbox testers) |
| `APPLE_IAP_KEY_ID`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_FILE` | – | Optional App Store Server API key (all three or none; also enables Apple) |

A configured store whose key file cannot be read or parsed **stops the
startup** (fix the file or unset the variable). Test hooks
(`GOOGLE_PLAY_API_URL`, `APPLE_ROOT_CA_FILE`, `APPLE_IAP_API_URL`) are
refused in production.

## Google Play Console setup

1. **Payments profile**: Play Console → Settings → Payments profile (merchant
   account) must be set up to sell in-app products.
2. **Products**: the app must have the Play Billing library — upload a build
   with this version (the `in_app_purchase` plugin adds the `BILLING`
   permission) to any track first. Then Monetize with Play → Products →
   **In-app products** (one-time products) → Create, for each of the four:
   - Product ID: `coins_starter`, `coins_popular`, `coins_great_value`,
     `coins_best_value` (ids cannot be reused or changed later);
   - name and description (e.g. "Starter — 50 lakh coins + 5 diamonds");
   - default price ₹199 / ₹299 / ₹499 / ₹999 (Play converts other countries;
     adjust if wanted);
   - leave **multi-quantity off**; **Activate**.
   Play has no "consumable" flag: a product is consumable because it is
   consumed after each grant (the server and the app do).
3. **Service account** (verification, consume, voided purchases):
   - Google Cloud project `ludo-royale-63887` → APIs & Services → enable the
     **Google Play Android Developer API**;
   - IAM → Service accounts → create one (e.g. `play-iap-verifier`), no
     project roles needed → Keys → add a **JSON** key. Store the file outside
     the repository on the server and set `GOOGLE_PLAY_SERVICE_ACCOUNT_FILE`
     to its path (`GOOGLE_PLAY_PACKAGE_NAME=com.sungamestudio.ludoarena`);
   - Play Console → **Users and permissions** → Invite new users → the service
     account's e-mail → App permissions for Ludo Arena: **View financial
     data, orders, and cancellation survey responses** and **Manage orders
     and subscriptions**. New permissions can take up to 24–36 h to work
     (until then the server logs `store verification credentials refused`
     and purchases answer 503).
4. **Testing**: Play Console → Settings → **License testing** → add the
   testers' Google accounts (Gmail). Install the app from an internal or
   closed testing track with such an account: purchases show "Test card,
   always approves" (free) and "Test card, always declines"; the "slow test
   card" approves after a few minutes (exercises `purchase_pending`). Refund
   a test order in Play Console → Order management to see the voided-purchase
   refund (within one poll interval).

## App Store Connect setup

1. **Agreements, Tax, and Banking**: the Paid Applications agreement must be
   active.
2. **Xcode**: Runner target → Signing & Capabilities → add **In-App
   Purchase**.
3. **Products**: the app → Monetization → **In-App Purchases** → create four
   of type **Consumable**: Reference Name (e.g. "Coins Starter"), Product ID
   `coins_starter`, `coins_popular`, `coins_great_value`, `coins_best_value`;
   price ₹199 / ₹299 / ₹499 / ₹999 (choose the India price point, let Apple
   equalize the others); a display name and description per language; the
   review screenshot (the Shop's Coins category). Submit the first products
   **with an app version** for review.
4. **Server notifications**: the app → App Information → **App Store Server
   Notifications** → Production Server URL
   `https://<production-api-host>/api/v1/iap/apple/notifications`, Sandbox
   Server URL the same path on the backend that serves TestFlight builds;
   **Version 2**. "Request a Test Notification" (or the App Store Server
   API) sends a `TEST` notification, answered `{"result":"ignored"}`.
5. **Backend**: `APPLE_IAP_ENABLED=true`, `APPLE_BUNDLE_ID=com.ludoarena.app`.
   Optional App Store Server API key: Users and Access → Integrations →
   **In-App Purchase** → generate a key → download the `.p8` (only once),
   note the Key ID and the Issuer ID → `APPLE_IAP_KEY_FILE` (path outside the
   repository), `APPLE_IAP_KEY_ID`, `APPLE_IAP_ISSUER_ID`.
6. **Testing**: Users and Access → Sandbox → **Test Accounts**; sign in on the
   device under Settings → App Store → Sandbox Account. TestFlight and App
   Review purchases are sandbox purchases, so keep
   `APPLE_IAP_ALLOW_SANDBOX=true` in production (App Review buys against the
   production backend). Refund a sandbox purchase from the device (Settings →
   Apple ID → Media & Purchases → Manage / "Request a refund" in the sandbox)
   to receive a `REFUND` notification.

## Stored data and privacy

`progression.purchases` (migration `013_purchases.sql`, owner-approved
2026-10-22) holds, per granted purchase: account id, store, product id,
transaction reference (App Store transaction id, or the SHA-256 of the Google
purchase token), Google order number, coins and diamonds granted, status
(`granted` / `refunded`) and times. Stores never send card or payment
details, so none exist here. Rows are deleted with the account (account
deletion and `ON DELETE CASCADE`). The analytics event `coin_pack_purchased`
(app, after the server's first grant) carries only the pack label slug and
the price value and currency — no ids, tokens or order numbers. Store
listings: "Contains in-app purchases"; Data safety / App Privacy: purchase
history (see the README).

## Operations

- Metrics (Prometheus, bounded labels): `iap_purchases_total{store,result}`
  (`granted`, `replayed`, `invalid`, `pending`, `unavailable`,
  `unreachable`, `bad_request`, `error`),
  `iap_currency_granted_total{store,currency}`,
  `iap_refunds_total{store,result}`, `iap_refund_shortfalls_total{store}`,
  `iap_google_consumes_total{result}`, `iap_google_voided_polls_total{result}`,
  `iap_apple_lookups_total{result}`, `iap_apple_notifications_total{result}`.
- Logs: `purchase refused` (Info) names the reason (e.g. `purchase belongs to
  another account`, `purchase state 1`, `bundle id`); `store verification
  credentials refused` (Error) means the service account permissions or the
  App Store Connect key are wrong; never a token, key or account id.
- Support lookups: `SELECT store, product_id, order_id, status, created_at
  FROM progression.purchases WHERE order_id = 'GPA.…'` (Google) or `WHERE
  store = 'app_store' AND transaction_id = '…'` (Apple).
- Changing a pack: edit `coin_packs.json` (amounts apply to purchases granted
  afterwards); a removed pack still answers replays of its old purchases.
