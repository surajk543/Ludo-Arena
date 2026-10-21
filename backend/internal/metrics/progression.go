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
	// FriendRequests counts friend-graph events: sent | accepted | auto_accepted
	// | declined | cancelled | removed | rejected.
	FriendRequests = counter("friend_requests_total", "Friend request events.", "event")
	// InvitesSent counts private-room invites: sent | not_friends | rate_limited | error.
	InvitesSent = counter("invites_sent_total", "Private-room invites to friends.", "result")
	// ReturningUsers is the approximate number of humans active yesterday who
	// are also active today (HyperLogLog inclusion-exclusion).
	ReturningUsers = gauge("returning_users_estimate", "Approximate humans active in the previous window who are active again.", "window")
)
