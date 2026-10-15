local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

-- One tracker per primary profession slot (1 and 2). Each compact cell shows
-- the profession name followed by W (weekly), T (treatise), and Darkmoon Faire
-- while the monthly Faire is open, using a check
-- for completion and a gray dash otherwise.
local EMDASH = "\226\128\148"

-- Blizzard's recurring schedule: first Sunday through Saturday, realm time.
-- Use the server calendar clock, independent of local timezone/calendar filters.
-- https://news.blizzard.com/en-us/article/23785338/the-darkmoon-faire-returns
local function darkmoonPeriod()
	local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
		and C_DateAndTime.GetCurrentCalendarTime()
	if type(now) ~= "table" or not (now.weekday and now.monthDay and now.year and now.month) then return nil end
	local firstWeekday = (now.weekday - now.monthDay) % 7 + 1
	local firstSunday = 1 + (1 - firstWeekday) % 7
	if now.monthDay < firstSunday or now.monthDay >= firstSunday + 7 then return nil end
	return now.year * 100 + now.month
end

local function darkmoonStatus(st)
	local period = darkmoonPeriod()
	if not period or not st.hasProf or not st.darkmoonQuestIDs then return nil end
	-- An offline alt's completion only applies to the Faire when it was scanned.
	return st.darkmoonPeriod == period and st.darkmoonDone == true
end

-- Returns true if any quest in the list is flagged complete.
local function anyDone(questIDs)
	if not questIDs then return nil end  -- nil = not tracked for this profession
	for _, qid in ipairs(questIDs) do
		if C_QuestLog.IsQuestFlaggedCompleted(qid) then return true end
	end
	return false
end

local function compactStatus(label, done)
	if done then return Constants.COLOR_WHITE .. label .. Constants.COLOR_RESET .. Constants.CHECK_GREEN end
	return Constants.COLOR_GRAY .. label .. "-" .. Constants.COLOR_RESET
end

local function MakeProfessionTracker(slot, trackerId, label, order)
	local T = {
		id = trackerId,
		label = label,
		icon = 4576453,
		category = "weekly",
		group = "professions",
		order = order,
		cadence = "weekly",
		events = { "PLAYER_LOGIN", "QUEST_TURNED_IN" },
		enabledByDefault = true,
		countsForRecommend = true,
		slot = slot,
	}

	function T:Scan(charState)
		local data = { hasProf = false }
		local profIndices = { GetProfessions() }  -- prof1, prof2, archaeology, fishing, cooking
		local idx = profIndices[self.slot]
		if idx then
			local name, _, skillLevel, maxSkillLevel, _, _, skillLine = GetProfessionInfo(idx)
			data.hasProf = true
			data.name = name
			data.skillLevel = skillLevel or 0
			data.maxSkillLevel = maxSkillLevel or 0
			data.darkmoonQuestIDs = skillLine and Constants.PROFESSION_DARKMOON_QUESTS[skillLine]
			data.darkmoonPeriod = darkmoonPeriod()
			if data.darkmoonPeriod then data.darkmoonDone = anyDone(data.darkmoonQuestIDs) end
			data.weeklyDone   = anyDone(skillLine and Constants.PROFESSION_WEEKLY_QUESTS[skillLine])
			data.treatiseDone = anyDone(skillLine and Constants.PROFESSION_TREATISE_QUESTS[skillLine])
		end
		charState.trackers[self.id] = data
		if data.weeklyDone == true or data.treatiseDone == true or data.darkmoonDone == true then
			Constants.RecordActivity(charState, "professions")
		end
	end

	function T:GetSummary(charState)
		local st = charState.trackers[self.id] or {}
		if not st.hasProf then
			return Constants.COLOR_GRAY .. EMDASH .. Constants.COLOR_RESET
		end
		local name = Constants.COLOR_GOLD .. (st.name or "?") .. Constants.COLOR_RESET
		local darkmoon = darkmoonStatus(st)
		return name .. " " .. compactStatus("W", st.weeklyDone)
			.. " " .. compactStatus("T", st.treatiseDone)
			.. (darkmoon ~= nil and (" " .. compactStatus("Darkmoon Faire", darkmoon)) or "")
	end

	-- Weekly sweep: the character's professions are still known after a reset -
	-- only the quest completion goes back to "not done". Keep hasProf/name;
	-- flip the done flags, preserving nil (= this profession has no tracked
	-- quest, shown as a gray dot).
	function T:OnWeeklyReset(charState)
		local st = charState.trackers[self.id]
		if not st then return end
		if st.weeklyDone ~= nil then st.weeklyDone = false end
		if st.treatiseDone ~= nil then st.treatiseDone = false end
		-- Darkmoon completion is monthly and must survive this weekly sweep.
	end

	-- Relevant to the recommender if the character has this profession and we
	-- track at least one of its knowledge sources.
	function T:IsRelevant(charState)
		local st = charState.trackers[self.id] or {}
		local Config = _G[ADDON_NAME .. "Config"]
		local explicitGoal = Config and Config.HasCharacterGoal
			and Config:HasCharacterGoal(charState, "professions")
		return st.hasProf == true and (st.skillLevel or 0) >= 25
			and (explicitGoal or Constants.GetActivityAffinity(charState, "professions") >= 0.5)
			and (st.weeklyDone ~= nil or st.treatiseDone ~= nil or darkmoonStatus(st) ~= nil)
	end

	function T:IsComplete(charState)
		local st = charState.trackers[self.id] or {}
		if not st.hasProf then return true end
		local weeklyOK   = (st.weeklyDone == nil) or st.weeklyDone
		local treatiseOK = (st.treatiseDone == nil) or st.treatiseDone
		return weeklyOK and treatiseOK and darkmoonStatus(st) ~= false
	end

	-- For the recommender's grouped "Professions (...)" entry: the sub-tasks
	-- still undone for this profession, as short tags. The recommender dedupes
	-- these across both profession slots, so two profs both needing the weekly
	-- show "Weekly" once.
	function T:RecTags(charState)
		local st = charState.trackers[self.id] or {}
		local tags = {}
		if st.weeklyDone == false   then tags[#tags + 1] = "Weekly" end
		if st.treatiseDone == false then tags[#tags + 1] = "Treatise" end
		if darkmoonStatus(st) == false then tags[#tags + 1] = "Darkmoon Faire" end
		return tags
	end

	-- For the recommender: "Mining weekly+treatise" listing whatever is undone.
	function T:GetAction(charState)
		local st = charState.trackers[self.id] or {}
		local nm = st.name or "Profession"
		local parts = {}
		if st.weeklyDone == false then
			parts[#parts + 1] = "complete the weekly quest"
		end
		if st.treatiseDone == false then
			parts[#parts + 1] = "use a treatise"
		end
		if darkmoonStatus(st) == false then
			parts[#parts + 1] = "complete the Darkmoon Faire profession quest"
		end
		if #parts == 0 then return "Finish " .. nm .. " knowledge tasks" end
		return nm .. ": " .. table.concat(parts, " and ")
	end

	return T
end

local P1 = MakeProfessionTracker(1, Constants.TRACKER_PROFESSION1, "Primary", 1)
local P2 = MakeProfessionTracker(2, Constants.TRACKER_PROFESSION2, "Secondary", 2)

_G[ADDON_NAME .. "Profession1Tracker"] = P1
_G[ADDON_NAME .. "Profession2Tracker"] = P2

if TrackerRegistry then
	TrackerRegistry:Register(P1)
	TrackerRegistry:Register(P2)
end
