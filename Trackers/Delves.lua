local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local function RewardIlvl(activity)
	local getRewards = C_WeeklyRewards and C_WeeklyRewards.GetActivityRewards
	if not (getRewards and activity.type and activity.index) then return nil end
	local ok, rewards = pcall(getRewards, activity.type, activity.index)
	if not ok or type(rewards) ~= "table" then return nil end
	local best = 0
	for _, reward in ipairs(rewards) do
		best = math.max(best, tonumber(reward.itemLevel) or 0)
	end
	return best > 0 and best or nil
end

local function TrackForIlvl(ilvl)
	if ilvl >= 318 then return "M" end
	if ilvl >= 305 then return "H" end
	if ilvl >= 292 then return "C" end
	if ilvl >= 279 then return "V" end
	return "A"
end

local function TrackForLevel(level)
	if level >= 8 then return "H" end
	if level >= 5 then return "C" end
	return "V"
end

local function TrackColor(track)
	if track == "A" then return "|cFF0070DD" end -- rare / blue
	return Constants.COLOR_PURPLE                 -- Veteran and above / epic
end

local DelveTracker = {
	id = Constants.TRACKER_DELVES,
	label = "World",
	icon = 134400,
	category = "weekly",
	group = "vault",
	order = 3,
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
	local slots = {}
	local ok, activities = pcall(C_WeeklyRewards.GetActivities,
	                             Enum.WeeklyRewardChestThresholdType.World)
	-- GetActivities can briefly return an empty table while Weekly Rewards data is
	-- still loading (notably just after login/zone changes).  An empty result is
	-- not a valid zero-progress snapshot: replacing the saved slots here makes a
	-- character with completed delves appear to have no Great Vault credit.
	if ok and type(activities) == "table" and #activities > 0 then
		for _, a in ipairs(activities) do
			if (a.progress or 0) > rawProgress then rawProgress = a.progress end
			if (a.progress or 0) >= (a.threshold or 0)
				and (a.level or 0) >= Constants.DELVE_MIN_TIER then
				if (a.threshold or 0) > count then count = a.threshold end
			end
			slots[#slots + 1] = {
				threshold = a.threshold or 0,
				unlocked = (a.progress or 0) >= (a.threshold or 0),
				ilvl = RewardIlvl(a),
				level = a.level or 0,
			}
		end
		st.rewardIlvl = Constants.MaxRewardIlvl(activities)  -- Hero-track ceiling
		table.sort(slots, function(a, b) return a.threshold < b.threshold end)
		for _, slot in ipairs(slots) do
			slot.track = slot.ilvl and TrackForIlvl(slot.ilvl) or TrackForLevel(slot.level)
		end
		st.count = count                 -- Tier 8+ slots filled (0/2/4/8)
		st.rawProgress = rawProgress      -- total runs of any tier (for reference)
		st.slots = slots
		st.lastUpdated = time()
		if rawProgress > 0 then Constants.RecordActivity(charState, "delves") end
	end
	-- Preserve the last valid snapshot when the API is unavailable/not ready.
	charState.trackers[self.id] = st
end

function DelveTracker:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	local parts = {}
	for i = 1, 3 do
		local slot = st.slots and st.slots[i]
		if slot and slot.unlocked then
			local track = slot.track or "?"
			parts[i] = TrackColor(track) .. "[" .. track .. "]" .. Constants.COLOR_RESET
		else
			parts[i] = Constants.COLOR_GRAY .. "-" .. Constants.COLOR_RESET
		end
	end
	return table.concat(parts, " ")
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
	local gilded = charState.trackers[Constants.TRACKER_GILDEDSTASH] or {}
	local Config = _G[ADDON_NAME .. "Config"]
	local maxTier = Config and Config.GetMaxDelveTier and Config:GetMaxDelveTier() or 11
	local needsGilded = gilded.max ~= nil and gilded.max > 0
		and (gilded.looted or 0) < gilded.max and maxTier >= 11
	if Constants.IsMidnightSeason2Active() and needsGilded then
		return "Complete a Tier 11 Bountiful Delve for Gilded Stash and Hero Vault progress"
	end
	local progress = Constants.IsMidnightSeason2Active() and (st.count or 0) or (st.rawProgress or 0)
	local nextThreshold
	for _, threshold in ipairs({ 2, 4, 8 }) do
		if progress < threshold then nextThreshold = threshold break end
	end
	if not nextThreshold then return "Delve Great Vault complete" end
	local remaining = nextThreshold - progress
	local noun = remaining == 1 and "Delve" or "Delves"
	local tier = Constants.IsMidnightSeason2Active() and "Tier 8 " or ""
	return string.format("Complete %d more %s%s for the next Vault slot",
		remaining, tier, noun)
end

_G[ADDON_NAME .. "DelveTracker"] = DelveTracker

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(DelveTracker)
end
