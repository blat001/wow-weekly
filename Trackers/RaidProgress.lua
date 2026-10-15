local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local DIFFICULTIES = {
	{ id = Constants.TRACKER_RAID_MYTHIC, label = "Mythic",      difficultyID = 16, order = 1 },
	{ id = Constants.TRACKER_RAID_HEROIC, label = "Heroic",      difficultyID = 15, order = 2 },
	{ id = Constants.TRACKER_RAID_NORMAL, label = "Normal",      difficultyID = 14, order = 3 },
	{ id = Constants.TRACKER_RAID_LFR,    label = "Raid Finder", difficultyID = 17, order = 4 },
}

local function IsCurrentRaid(name)
	if type(name) ~= "string" then return false end
	return string.find(string.lower(name), string.lower(Constants.CURRENT_RAID_NAME), 1, true) ~= nil
end

local function ScanDifficulty(difficultyID)
	local progress = 0
	local encounters = Constants.CURRENT_RAID_BOSSES
	-- Core requests lockouts and scans again on UPDATE_INSTANCE_INFO.
	-- Requesting here would retrigger that event from inside its handler.
	for index = 1, (GetNumSavedInstances and GetNumSavedInstances() or 0) do
		local name, _, reset, difficulty, locked, _, _, isRaid, _, _, numEncounters, encounterProgress = GetSavedInstanceInfo(index)
		if isRaid and difficulty == difficultyID and (reset or 0) > 0 and locked and IsCurrentRaid(name) then
			progress = math.max(progress, encounterProgress or 0)
			encounters = math.max(encounters, numEncounters or 0)
		end
	end
	return math.min(progress, Constants.CURRENT_RAID_BOSSES), encounters
end

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
for _, difficulty in ipairs(DIFFICULTIES) do
	local definition = difficulty
	local T = {
		id = definition.id,
		label = definition.label,
		icon = 525134,
		category = "weekly",
		group = "raidprogress",
		order = definition.order,
		cadence = "weekly",
		events = { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ENCOUNTER_END", "BOSS_KILL", "UPDATE_INSTANCE_INFO" },
		enabledByDefault = true,
		countsForRecommend = false,
	}

	function T:Scan(charState)
		local st = charState.trackers[self.id] or {}
		st.progress, st.total = ScanDifficulty(definition.difficultyID)
		st.lastUpdated = time()
		charState.trackers[self.id] = st
	end

	function T:GetSummary(charState)
		local st = charState.trackers[self.id] or {}
		local progress = st.progress or 0
		if progress >= Constants.CURRENT_RAID_BOSSES then return Constants.CHECK_GREEN end
		if progress > 0 then
			return Constants.COLOR_YELLOW .. progress .. "/" .. Constants.CURRENT_RAID_BOSSES .. Constants.COLOR_RESET
		end
		return Constants.COLOR_GRAY .. "-" .. Constants.COLOR_RESET
	end

	function T:IsComplete(charState)
		local st = charState.trackers[self.id] or {}
		return (st.progress or 0) >= Constants.CURRENT_RAID_BOSSES
	end

	-- A difficulty row is useful only after this character has killed a boss
	-- on that difficulty during the current lockout.
	function T:IsVisible(charState)
		local st = charState.trackers[self.id] or {}
		return (st.progress or 0) > 0
	end

	TrackerRegistry:Register(T)
end
