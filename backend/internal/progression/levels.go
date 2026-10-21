package progression

// MaxLevel is the highest level. XP keeps accumulating after it (weekly
// leaderboards), but the level no longer changes.
const MaxLevel = 50

// XP awarded per eligible match (see docs/progression.md → Anti-farming).
const (
	XPMatchCompleted = 20
	XPWinBonus       = 15
	XPFriendBonus    = 5
)

// XPToNext is the XP needed to go from level to level+1:
// 100 + 50 × (level − 1). This is the `nextLevelXp` API field.
func XPToNext(level int) int64 {
	if level < 1 {
		level = 1
	}
	return 100 + 50*int64(level-1)
}

// LevelStartXP is the total XP at which level is reached (the `levelXp` API
// field): Σ_{k=1}^{level−1} XPToNext(k) = 100(L−1) + 25(L−1)(L−2).
func LevelStartXP(level int) int64 {
	if level <= 1 {
		return 0
	}
	if level > MaxLevel {
		level = MaxLevel
	}
	l := int64(level - 1)
	return 100*l + 25*l*(l-1)
}

// LevelForXP returns the level reached with a total of xp.
func LevelForXP(xp int64) int {
	for l := MaxLevel; l > 1; l-- {
		if xp >= LevelStartXP(l) {
			return l
		}
	}
	return 1
}
