local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local DelveTracker = {
	id = Constants.TRACKER_DELVES,
	label = "World",
	icon = 134400,
	category = "weekly",
	group = "vault",
	order = 1,
	cadence = "weekly",
	events = { "PLAYER_LOGIN" },
	enabledByDefault = true,
	countsForRecommend = true,
}

function DelveTracker:Scan(charState)
	local st = charState.trackers[self.id] or {}
	-- The World/Delve vault track has 3 slots that unlock at 2 / 4 / 8 runs.
	-- For each slot, `level` is the TIER of the run currently filling it (0 = unfilled).
	-- A slot only awards Hero-quality gear if its filling run is Tier 8+.
	-- We report the highest slot threshold (2/4/8) whose filling run is Tier 8+,
	-- i.e. how many vault slots are currently Hero-eligible.
	local count = 0
	local rawProgress = 0
	local ok, activities = pcall(C_WeeklyRewards.GetActivities,
	                             Enum.WeeklyRewardChestThresholdType.World)
	if ok and activities then
		for _, a in ipairs(activities) do
			if (a.progress or 0) > rawProgress then rawProgress = a.progress end
			if (a.level or 0) >= Constants.DELVE_MIN_TIER then
				if (a.threshold or 0) > count then count = a.threshold end
			end
		end
		st.rewardIlvl = Constants.MaxRewardIlvl(activities)  -- Hero-track ceiling
	end
	st.count = count                 -- Tier 8+ slots filled (0/2/4/8)
	st.rawProgress = rawProgress      -- total runs of any tier (for reference)
	st.lastUpdated = time()
	charState.trackers[self.id] = st
end

function DelveTracker:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	-- During the pre-season week ordinary Delves still fill the Great Vault;
	-- there simply are no Bountiful rewards. Track all qualifying runs until
	-- Season 2 starts, then resume the Tier 8+ quality goal.
	local n = Constants.IsMidnightSeason2Active() and (st.count or 0) or (st.rawProgress or 0)
	local color
	if not Constants.VaultWorthDoing(charState, self:StopIlvl(charState)) then
		color = Constants.COLOR_GRAY     -- in Mythic gear: delves no longer upgrade
	elseif n >= Constants.DELVE_HERO_THRESHOLD then
		color = Constants.COLOR_GREEN   -- 4+ slots: enough Hero gear, weekly goal met
	elseif n > 0 then
		color = Constants.COLOR_YELLOW  -- 2 slots: at least one Hero piece coming
	else
		color = Constants.COLOR_RED     -- 0 slots: no Hero gear yet
	end
	return string.format("%s%d of %d%s", color, n, Constants.DELVE_VAULT_MAX, Constants.COLOR_RESET)
end

function DelveTracker:StopIlvl(charState)
	return Constants.VAULT_STOP_DELVE  -- skip delves once in Myth gear (avg >= 318)
end

function DelveTracker:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	local n = Constants.IsMidnightSeason2Active() and (st.count or 0) or (st.rawProgress or 0)
	return n >= Constants.DELVE_HERO_THRESHOLD
end

function DelveTracker:GetAction(charState)
	local st = charState.trackers[self.id] or {}
	local n = Constants.IsMidnightSeason2Active() and (st.count or 0) or (st.rawProgress or 0)
	return string.format("Delves vault (%d/%d)", n, Constants.DELVE_HERO_THRESHOLD)
end

_G[ADDON_NAME .. "DelveTracker"] = DelveTracker

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(DelveTracker)
end
