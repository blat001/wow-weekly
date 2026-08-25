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
	if level >= 10 then return "M" end
	if level >= 2 then return "H" end
	return "C"
end

local function TrackColor(track)
	if track == "A" then return "|cFF0070DD" end -- rare / blue
	return Constants.COLOR_PURPLE                 -- Veteran and above / epic
end

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
	local rawProgress = 0
	local hasRuns = false
	local highestLevel = 0
	local qualifiedRuns = 0
	local slots = {}
	if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
	-- NOTE: the M+ track is the "Activities" threshold type (there is no .MythicPlus).
	local ok, activities = pcall(C_WeeklyRewards.GetActivities,
	                             Enum.WeeklyRewardChestThresholdType.Activities)
	if ok and activities then
		for _, a in ipairs(activities) do
			if (a.progress or 0) > 0 then hasRuns = true end
			if (a.progress or 0) > 0 and (a.level or 0) > highestLevel then highestLevel = a.level end
			if (a.progress or 0) > rawProgress then rawProgress = a.progress end
			if (a.level or 0) >= Constants.MPLUS_MIN_LEVEL then
				if (a.threshold or 0) > count then count = a.threshold end
			end
			slots[#slots + 1] = {
				threshold = a.threshold or 0,
				unlocked = (a.progress or 0) >= (a.threshold or 0),
				ilvl = RewardIlvl(a),
				level = a.level or 0,
			}
		end
		st.rewardIlvl = Constants.MaxRewardIlvl(activities)  -- Myth-track ceiling
	end
	if Constants.IsMidnightSeason2Active() and C_MythicPlus and C_MythicPlus.GetRunHistory then
		local historyOK, history = pcall(C_MythicPlus.GetRunHistory, false, true)
		if historyOK and type(history) == "table" then
			for _, run in ipairs(history) do
				if run.thisWeek ~= false and (run.level or 0) >= Constants.MPLUS_MIN_LEVEL then
					qualifiedRuns = qualifiedRuns + 1
				end
			end
		end
	end
	table.sort(slots, function(a, b) return a.threshold < b.threshold end)
	for _, slot in ipairs(slots) do
		slot.track = slot.ilvl and TrackForIlvl(slot.ilvl) or TrackForLevel(slot.level)
	end

	st.count = count
	st.rawProgress = rawProgress
	st.hasRuns = hasRuns
	st.qualifiedRuns = qualifiedRuns
	st.slots = slots
	st.lastUpdated = time()
	charState.trackers[self.id] = st
	if hasRuns then Constants.RecordActivity(charState, "mplus", highestLevel) end
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	-- Mythic 0 fills the Dungeon vault during the pre-season week. Count all
	-- qualifying dungeon runs now; switch to the +10 Myth-quality goal when
	-- Season 2 begins.
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

function T:StopIlvl(charState)
	return Constants.VAULT_STOP_MPLUS  -- never auto-skip (best dungeon gear)
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	local n = Constants.IsMidnightSeason2Active() and (st.count or 0) or (st.rawProgress or 0)
	return n >= Constants.MPLUS_MYTH_THRESHOLD
end

-- Only recommend M+ to characters who actually ran M+ this week.
function T:IsRelevant(charState)
	local st = charState.trackers[self.id] or {}
	return st.hasRuns == true
end

function T:GetAction(charState)
	local st = charState.trackers[self.id] or {}
	local active = Constants.IsMidnightSeason2Active()
	local runs = active and (st.qualifiedRuns or 0) or (st.rawProgress or 0)
	local nextThreshold
	for _, threshold in ipairs({ 1, 4, 8 }) do
		if runs < threshold then nextThreshold = threshold break end
	end
	if not nextThreshold then return "Dungeon Great Vault complete" end
	local remaining = nextThreshold - runs
	local activity = active and "+10" or "M0"
	local noun = remaining == 1 and "run" or "runs"
	return string.format("%d more %s %s for next Vault slot",
		remaining, activity, noun)
end

_G[ADDON_NAME .. "MythicPlusTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
