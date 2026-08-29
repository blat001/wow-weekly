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
	-- Raid difficulty IDs: 17=LFR, 14=Normal, 15=Heroic, 16=Mythic.
	if level == 15 or level == 16 then return "M" end
	if level == 14 then return "H" end
	if level == 17 then return "C" end
	if level >= 4 then return "M" end
	if level >= 2 then return "H" end
	return "C"
end

local function TrackColor(track)
	if track == "A" then return "|cFF0070DD" end
	return Constants.COLOR_PURPLE
end

local function RaidDifficultyRank(level)
	if level == 16 then return 4 end -- Mythic
	if level == 15 then return 3 end -- Heroic
	if level == 14 then return 2 end -- Normal
	if level == 17 then return 1 end -- Raid Finder
	return level or 0
end

local function RaidDifficultyName(level)
	if level == 16 or level == 4 then return "Mythic" end
	if level == 15 or level == 3 then return "Heroic" end
	if level == 14 or level == 2 then return "Normal" end
	if level == 17 or level == 1 then return "Raid Finder" end
	return nil
end

local T = {
	id = Constants.TRACKER_RAID,
	label = "Raid",
	icon = 525134,
	category = "weekly",
	group = "vault",
	order = 1,
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
	local rawProgress = 0
	local hasKills = false
	local highestLevel = 0
	local highestDifficulty
	local slots = {}
	local ok, activities = pcall(C_WeeklyRewards.GetActivities,
	                             Enum.WeeklyRewardChestThresholdType.Raid)
	if ok and activities then
		for _, a in ipairs(activities) do
			if (a.progress or 0) > 0 then hasKills = true end
			if (a.progress or 0) > rawProgress then rawProgress = a.progress end
			local difficultyRank = RaidDifficultyRank(a.level)
			if (a.progress or 0) > 0 and difficultyRank > highestLevel then
				highestLevel = difficultyRank
				highestDifficulty = RaidDifficultyName(a.level)
			end
			if (a.progress or 0) >= (a.threshold or 0) and (a.threshold or 0) > count then
				count = a.threshold
			end
			slots[#slots + 1] = {
				threshold = a.threshold or 0,
				unlocked = (a.progress or 0) >= (a.threshold or 0),
				ilvl = RewardIlvl(a),
				level = a.level or 0,
			}
		end
		st.rewardIlvl = Constants.MaxRewardIlvl(activities)
	end
	table.sort(slots, function(a, b) return a.threshold < b.threshold end)
	for _, slot in ipairs(slots) do
		slot.track = slot.ilvl and TrackForIlvl(slot.ilvl) or TrackForLevel(slot.level)
	end

	st.count = count
	st.rawProgress = rawProgress
	st.hasKills = hasKills
	st.highestDifficulty = highestDifficulty
	st.slots = slots
	st.lastUpdated = time()
	charState.trackers[self.id] = st
	if hasKills then Constants.RecordActivity(charState, "raid", highestLevel) end
end

function T:GetSummary(charState)
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
	local progress = st.rawProgress or st.count or 0
	local nextThreshold
	for _, threshold in ipairs({ 2, 4, 6 }) do
		if progress < threshold then nextThreshold = threshold break end
	end
	if not nextThreshold then return "Raid Great Vault complete" end
	local remaining = nextThreshold - progress
	local noun = remaining == 1 and "boss" or "bosses"
	local difficulty = st.highestDifficulty
	if not difficulty then
		local bestRank = 0
		for _, slot in ipairs(st.slots or {}) do
			local rank = RaidDifficultyRank(slot.level)
			if rank > bestRank then
				bestRank = rank
				difficulty = RaidDifficultyName(slot.level)
			end
		end
	end
	return string.format("Continue %s on %s and kill %d more %s",
		Constants.CURRENT_RAID_NAME, difficulty or "your current difficulty", remaining, noun)
end

_G[ADDON_NAME .. "RaidTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
