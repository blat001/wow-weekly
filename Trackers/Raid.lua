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
	if track == "A" then return "|cFF0070DD" end
	return Constants.COLOR_PURPLE
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
	local hasKills = false
	local slots = {}
	local ok, activities = pcall(C_WeeklyRewards.GetActivities,
	                             Enum.WeeklyRewardChestThresholdType.Raid)
	if ok and activities then
		for _, a in ipairs(activities) do
			if (a.progress or 0) > 0 then hasKills = true end
			if (a.progress or 0) >= (a.threshold or 0) and (a.threshold or 0) > count then
				count = a.threshold
			end
			slots[#slots + 1] = {
				threshold = a.threshold or 0,
				unlocked = (a.progress or 0) >= (a.threshold or 0),
				ilvl = RewardIlvl(a.id),
				level = a.level or 0,
			}
		end
		st.rewardIlvl = Constants.MaxRewardIlvl(activities)
	end
	table.sort(slots, function(a, b) return a.threshold < b.threshold end)
	for _, slot in ipairs(slots) do
		slot.track = TrackForIlvl(slot.ilvl)
		if not slot.track then
			-- Raid difficulty IDs: 17=LFR, 14=Normal, 15=Heroic, 16=Mythic.
			if slot.level == 15 or slot.level == 16 then
				slot.track = "M"
			elseif slot.level == 14 then
				slot.track = "H"
			elseif slot.level == 17 then
				slot.track = "C"
			elseif slot.level >= 4 then
				slot.track = "M"
			elseif slot.level >= 2 then
				slot.track = "H"
			else
				slot.track = "C"
			end
		end
	end

	st.count = count
	st.hasKills = hasKills
	st.slots = slots
	st.lastUpdated = time()
	charState.trackers[self.id] = st
	if hasKills then Constants.RecordActivity(charState, "raid") end
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
	return string.format("Raid vault (%d/%d)", st.count or 0, Constants.RAID_VAULT_MAX)
end

_G[ADDON_NAME .. "RaidTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
