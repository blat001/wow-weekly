local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local T = {
	id = Constants.TRACKER_RAID,
	label = "Raid",
	icon = 525134,
	category = "weekly",
	group = "vault",
	order = 3,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "ENCOUNTER_END", "BOSS_KILL", "UPDATE_INSTANCE_INFO" },
	enabledByDefault = true,
	countsForRecommend = true,
}

function T:Scan(charState)
	local st = charState.trackers[self.id] or {}

	-- Great Vault raid track: 3 slots unlock at 2 / 4 / 6 boss kills.
	-- `progress` = bosses killed this week, `threshold` = bosses needed for that slot.
	-- Report the highest slot threshold (2/4/6) whose run requirement is met.
	local count = 0
	local hasKills = false
	local ok, activities = pcall(C_WeeklyRewards.GetActivities,
	                             Enum.WeeklyRewardChestThresholdType.Raid)
	if ok and activities then
		for _, a in ipairs(activities) do
			if (a.progress or 0) > 0 then hasKills = true end
			if (a.progress or 0) >= (a.threshold or 0) and (a.threshold or 0) > count then
				count = a.threshold
			end
		end
		st.rewardIlvl = Constants.MaxRewardIlvl(activities)
	end

	st.count = count
	st.hasKills = hasKills
	st.lastUpdated = time()
	charState.trackers[self.id] = st
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	local n = st.count or 0

	-- Characters who don't raid (no kills this week) get a gray dash.
	if n == 0 and not st.hasKills then
		return Constants.COLOR_GRAY .. "\226\128\148" .. Constants.COLOR_RESET
	end

	local color
	if not Constants.VaultWorthDoing(charState, self:StopIlvl(charState)) then
		color = Constants.COLOR_GRAY     -- character has outgeared this source
	elseif n >= Constants.RAID_FULL_THRESHOLD then
		color = Constants.COLOR_GREEN   -- all 3 raid vault slots unlocked
	elseif n > 0 then
		color = Constants.COLOR_YELLOW  -- at least one slot unlocked
	else
		color = Constants.COLOR_RED     -- kills started but no slot filled yet
	end

	return string.format("%s%d of %d%s", color, n, Constants.RAID_VAULT_MAX, Constants.COLOR_RESET)
end

function T:StopIlvl(charState)
	return Constants.VAULT_STOP_RAID  -- never auto-skip (best gear in the game)
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	return (st.count or 0) >= Constants.RAID_FULL_THRESHOLD
end

-- Only recommend raid to characters who actually raided this week.
function T:IsRelevant(charState)
	local st = charState.trackers[self.id] or {}
	return st.hasKills == true
end

function T:GetAction(charState)
	local st = charState.trackers[self.id] or {}
	return string.format("Raid vault (%d/%d)", st.count or 0, Constants.RAID_VAULT_MAX)
end

_G[ADDON_NAME .. "RaidTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
