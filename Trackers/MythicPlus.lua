local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local T = {
	id = Constants.TRACKER_MYTHICPLUS,
	label = "Dungeon",
	icon = 525134,
	category = "weekly",
	group = "vault",
	order = 2,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_MAPS_UPDATE" },
	enabledByDefault = true,
	countsForRecommend = true,
}

function T:Scan(charState)
	local st = charState.trackers[self.id] or {}

	-- Great Vault M+ track: 3 slots unlock at 1 / 4 / 8 runs.
	-- For each slot, `level` is the keystone level of the run filling it.
	-- A slot only awards Myth-track gear if its run is +10 or higher.
	-- Report the highest slot threshold (1/4/8) whose filling run is +10+.
	local count = 0
	local hasRuns = false
	if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
	-- NOTE: the M+ track is the "Activities" threshold type (there is no .MythicPlus).
	local ok, activities = pcall(C_WeeklyRewards.GetActivities,
	                             Enum.WeeklyRewardChestThresholdType.Activities)
	if ok and activities then
		for _, a in ipairs(activities) do
			if (a.progress or 0) > 0 then hasRuns = true end
			if (a.level or 0) >= Constants.MPLUS_MIN_LEVEL then
				if (a.threshold or 0) > count then count = a.threshold end
			end
		end
		st.rewardIlvl = Constants.MaxRewardIlvl(activities)  -- Myth-track ceiling
	end

	st.count = count
	st.hasRuns = hasRuns
	st.lastUpdated = time()
	charState.trackers[self.id] = st
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	local n = st.count or 0

	-- Characters who don't do M+ (no runs this week) get a gray dash.
	if n == 0 and not st.hasRuns then
		return Constants.COLOR_GRAY .. "\226\128\148" .. Constants.COLOR_RESET
	end

	local color
	if not Constants.VaultWorthDoing(charState, self:StopIlvl(charState)) then
		color = Constants.COLOR_GRAY     -- character has outgeared this source
	elseif n >= Constants.MPLUS_MYTH_THRESHOLD then
		color = Constants.COLOR_GREEN   -- enough slots at +10 for the weekly goal
	elseif n > 0 then
		color = Constants.COLOR_YELLOW  -- at least one Myth piece coming
	else
		color = Constants.COLOR_RED     -- no +10 vault slots yet
	end

	return string.format("%s%d of %d%s", color, n, Constants.MPLUS_VAULT_MAX, Constants.COLOR_RESET)
end

function T:StopIlvl(charState)
	return Constants.VAULT_STOP_MPLUS  -- never auto-skip (best dungeon gear)
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	return (st.count or 0) >= Constants.MPLUS_MYTH_THRESHOLD
end

-- Only recommend M+ to characters who actually ran M+ this week.
function T:IsRelevant(charState)
	local st = charState.trackers[self.id] or {}
	return st.hasRuns == true
end

function T:GetAction(charState)
	local st = charState.trackers[self.id] or {}
	return string.format("M+ vault (%d/%d)", st.count or 0, Constants.MPLUS_MYTH_THRESHOLD)
end

_G[ADDON_NAME .. "MythicPlusTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
