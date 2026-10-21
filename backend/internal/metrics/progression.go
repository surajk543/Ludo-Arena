package metrics

// Progression, missions, Collection Room and social metrics (human players
// only; labels are bounded enums, never user, item or room values).
var (
	// MissionsCompleted counts missions whose target was reached, by period
	// kind: daily | weekly | event.
	MissionsCompleted = counter("missions_completed_total", "Missions that reached their target.", "period")
	// MissionRewardsClaimed counts successful reward claims by period kind.
	MissionRewardsClaimed = counter("mission_rewards_claimed_total", "Mission rewards claimed.", "period")
	// XPAwarded sums XP granted, by source: match | mission.
	XPAwarded = counter("xp_awarded_total", "XP awarded to human players.", "source")
	// LevelUps counts level increases (one per level gained).
	LevelUps = counter("level_ups_total", "Levels gained by human players.")
	// CosmeticUnlocks counts items added to collections, by source:
	// level | mission | event | purchase | first_win.
	CosmeticUnlocks = counter("cosmetic_unlocks_total", "Cosmetic items unlocked.", "source")
	// CosmeticEquips counts loadout changes by slot.
	CosmeticEquips = counter("cosmetic_equips_total", "Cosmetic loadout changes.", "slot")
	// CosmeticPurchases counts purchases by currency: coins | diamonds.
	CosmeticPurchases = counter("cosmetic_purchases_total", "Cosmetic purchases.", "currency")
	// FriendRequests counts friend-graph events: sent | sent_to_bot | accepted
	// | auto_accepted | declined | cancelled | removed | rejected.
	FriendRequests = counter("friend_requests_total", "Friend request events.", "event")
	// InvitesSent counts private-room invites: sent | not_friends | rate_limited | error.
	InvitesSent = counter("invites_sent_total", "Private-room invites to friends.", "result")
	// PlayerReports counts POST /reports outcomes. reason is one of the five
	// report reasons or "invalid"; result is created | already_reported |
	// report_limit | cannot_report_self | not_in_room | not_found |
	// room_not_found | bad_request | error.
	PlayerReports = counter("player_reports_total", "Player reports by reason and result.", "reason", "result")
	// ReturningUsers is the approximate number of humans active yesterday who
	// are also active today (HyperLogLog inclusion-exclusion).
	ReturningUsers = gauge("returning_users_estimate", "Approximate humans active in the previous window who are active again.", "window")
)

// Profile-picture Store and private asset signing (human players only).
var (
	// ProfilePicturePurchases counts pictures bought with diamonds, by
	// format: image | lottie.
	ProfilePicturePurchases = counter("profile_picture_purchases_total", "Profile pictures bought.", "format")
	// ProfilePictureEquips counts PUT /me/profile-picture changes, by action:
	// equip | remove.
	ProfilePictureEquips = counter("profile_picture_equips_total", "Profile picture changes.", "action")
	// AssetSignRequests counts POST /assets/sign outcomes: ok | unavailable.
	AssetSignRequests = counter("asset_sign_requests_total", "Asset URL signing requests by result.", "result")
	// AssetURLsSigned counts URLs handed out (catalogue paths only).
	AssetURLsSigned = counter0("asset_urls_signed_total", "Presigned asset URLs handed out.")
	// ProfilePictureCatalogReloads counts catalogue reloads: ok | error.
	ProfilePictureCatalogReloads = counter("profile_picture_catalog_reloads_total", "Profile-picture catalogue reloads by result.", "result")
)
