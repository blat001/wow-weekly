local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local function RewardIlvl(activityID)
	local getLinks = C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks
	local getIlvl = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
	if not (activityID and getLinks and getIlvl) then return nil end
	local results = { pcall(getLinks, activityID) }
	if not results[1] then return nil end
	local best = 0
	for i = 2, #results do
		if type(results[i]) == "string" and results[i] ~= "" then
			local ok, ilvl = pcall(getIlvl, results[i])
			if ok and ilvl and ilvl > best then best = ilvl end
		end
	end
	return best > 0 and best or nil
end

local function TrackForIlvl(ilvl)
	if not ilvl then return nil end
	if ilvl >= 318 then return "M" end
	if ilvl >= 305 then return "H" end
	if ilvl >= 292 then return "C" end
	if ilvl >= 279 then return "V" end
	return "A"
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
	if ok and activities then
		for _, a in ipairs(activities) do
			if (a.progress or 0) > rawProgress then rawProgress = a.progress end
			if (a.level or 0) >= Constants.DELVE_MIN_TIER then
				if (a.threshold or 0) > count then count = a.threshold end
			end
			slots[#slots + 1] = {
				threshold = a.threshold or 0,
				unlocked = (a.progress or 0) >= (a.threshold or 0),
				ilvl = RewardIlvl(a.id),
				level = a.level or 0,
			}
		end
		st.rewardIlvl = Constants.MaxRewardIlvl(activities)  -- Hero-track ceiling
	end
	table.sort(slots, function(a, b) return a.threshold < b.threshold end)
	for _, slot in ipairs(slots) do
		slot.track = TrackForIlvl(slot.ilvl)
		if not slot.track then
			if slot.level >= 8 then slot.track = "H"
			elseif slot.level >= 5 then slot.track = "C"
			else slot.track = "V" end
		end
	end
	st.count = count                 -- Tier 8+ slots filled (0/2/4/8)
	st.rawProgress = rawProgress      -- total runs of any tier (for reference)
	st.slots = slots
	st.lastUpdated = time()
	charState.trackers[self.id] = st
	if rawProgress > 0 then Constants.RecordActivity(charState, "delves") end
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
	local n = Constants.IsMidnightSeason2Active() and (st.count or 0) or (st.rawProgress or 0)
	return string.format("Delves vault (%d/%d)", n, Constants.DELVE_HERO_THRESHOLD)
end

_G[ADDON_NAME .. "DelveTracker"] = DelveTracker

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(DelveTracker)
end
