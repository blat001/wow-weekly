local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

-- One tracker per primary profession slot (1 and 2). Each cell stacks the
-- character's profession name with a dotted "Weekly" line and "Treatise" line,
-- each dot green (done) / red (not done) / gray (this profession has no such
-- quest). Because professions differ per character the row label is generic
-- ("Primary"/"Secondary") and the detail lives in the cell.
local EMDASH = "\226\128\148"

-- Returns true if any quest in the list is flagged complete.
local function anyDone(questIDs)
	if not questIDs then return nil end  -- nil = not tracked for this profession
	for _, qid in ipairs(questIDs) do
		if C_QuestLog.IsQuestFlaggedCompleted(qid) then return true end
	end
	return false
end

-- One dotted status line, e.g. "<greendot> Weekly". done == nil -> gray (untracked).
local function statusLine(label, done)
	local dot
	if done == nil then
		dot = Constants.DOT_GRAY
	elseif done then
		dot = Constants.DOT_GREEN
	else
		dot = Constants.DOT_RED
	end
	return dot .. " " .. Constants.COLOR_WHITE .. label .. Constants.COLOR_RESET
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
			local name, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
			data.hasProf = true
			data.name = name
			data.weeklyDone   = anyDone(skillLine and Constants.PROFESSION_WEEKLY_QUESTS[skillLine])
			data.treatiseDone = anyDone(skillLine and Constants.PROFESSION_TREATISE_QUESTS[skillLine])
		end
		charState.trackers[self.id] = data
	end

	function T:GetSummary(charState)
		local st = charState.trackers[self.id] or {}
		if not st.hasProf then
			return Constants.COLOR_GRAY .. EMDASH .. Constants.COLOR_RESET
		end
		-- Profession name as a gold sub-heading so it reads distinctly from the
		-- white dotted status lines below it.
		local name = Constants.COLOR_GOLD .. (st.name or "?") .. Constants.COLOR_RESET
		return name .. "\n"
			.. statusLine("Weekly", st.weeklyDone) .. "\n"
			.. statusLine("Treatise", st.treatiseDone)
	end

	-- Relevant to the recommender if the character has this profession and we
	-- track at least one of its knowledge sources.
	function T:IsRelevant(charState)
		local st = charState.trackers[self.id] or {}
		return st.hasProf == true and (st.weeklyDone ~= nil or st.treatiseDone ~= nil)
	end

	function T:IsComplete(charState)
		local st = charState.trackers[self.id] or {}
		if not st.hasProf then return true end
		local weeklyOK   = (st.weeklyDone == nil) or st.weeklyDone
		local treatiseOK = (st.treatiseDone == nil) or st.treatiseDone
		return weeklyOK and treatiseOK
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
		return tags
	end

	-- For the recommender: "Mining weekly+treatise" listing whatever is undone.
	function T:GetAction(charState)
		local st = charState.trackers[self.id] or {}
		local nm = st.name or "Profession"
		local parts = {}
		if st.weeklyDone == false   then parts[#parts + 1] = "weekly" end
		if st.treatiseDone == false then parts[#parts + 1] = "treatise" end
		if #parts == 0 then return nm end
		return nm .. " " .. table.concat(parts, "+")
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
