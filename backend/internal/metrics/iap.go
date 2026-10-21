package metrics

// In-app purchase (coin pack) metrics. Labels are bounded enums: store is
// google_play | app_store | unknown, never a product, order or account id.
var (
	// IAPPurchases counts POST /store/purchases outcomes by store and result:
	// granted | replayed | invalid | pending | unavailable | unreachable |
	// bad_request | error.
	IAPPurchases = counter("iap_purchases_total", "Coin pack purchase submissions by result.", "store", "result")
	// IAPCurrencyGranted sums coins and diamonds granted by purchases, by
	// store and currency (coins | diamonds).
	IAPCurrencyGranted = counter("iap_currency_granted_total", "Coins and diamonds granted by purchases.", "store", "currency")
	// IAPRefunds counts refund handling by store and result: refunded |
	// already_refunded | unknown | error.
	IAPRefunds = counter("iap_refunds_total", "Purchase refunds handled by result.", "store", "result")
	// IAPRefundShortfalls counts refunds that could not take back everything
	// (the balance was lower than the grant; clamped at zero).
	IAPRefundShortfalls = counter("iap_refund_shortfalls_total", "Refunds clamped at a zero balance.", "store")
	// IAPConsumes counts server-side Google Play consumes: ok | error.
	IAPConsumes = counter("iap_google_consumes_total", "Google Play consume calls after a grant.", "result")
	// IAPVoidedPolls counts Google Play voided-purchase polls: ok | error.
	IAPVoidedPolls = counter("iap_google_voided_polls_total", "Google Play voided purchase polls.", "result")
	// IAPAppleLookups counts App Store Server API lookups before a grant: ok
	// | fallback (Apple unreachable; the verified signed copy was used).
	IAPAppleLookups = counter("iap_apple_lookups_total", "App Store Server API transaction lookups.", "result")
	// IAPAppleNotifications counts App Store Server Notifications by result:
	// refunded | already_refunded | unknown | ignored | invalid | error.
	IAPAppleNotifications = counter("iap_apple_notifications_total", "App Store Server Notifications by result.", "result")
)
