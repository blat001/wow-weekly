local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

-- Storyline 6385: one permanent quest unlocked per weekly reset.
-- https://www.wowhead.com/ptr-2/storyline/the-labyrinth-of-kindojan-6385
-- Later steps are read from the client instead of guessing their quest IDs.
local QUESTS = { 98951, 98963, 98962, 98961 }
local LAUNCH = 1791903600 -- October 13, 2026 15:00 UTC, US launch reset
local WEEK = 604800
local TOTAL_STEPS = 6

local T = {
	id = Constants.TRACKER_SOULFRAGMENT,
	label = "Soul Fragment",
	icon = "Interface\\Icons\\ability_argus_soulbombdebufflarge",
	category = "weekly",
	group = "delves",
	order = 5,
	-- Preserve permanent flags; the selected quest advances at weekly reset,
	-- including for offline alts.
	cadence = "persistent",
	enabledByDefault = true,
	countsForRecommend = false,
}

local function CurrentStep()
	local getter = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
	if not getter then return nil end
	local remaining = getter()
	if type(remaining) ~= "number" then return nil end
	-- Nearest whole week aligns regional maintenance times with release weeks
	-- and tolerates daylight-saving shifts. Advance only at the game's reset.
	local week = math.floor((time() + remaining - LAUNCH) / WEEK + 0.5)
	return math.min(TOTAL_STEPS, math.max(0, week))
end

function T:Scan(charState)
	local st = charState.trackers[self.id] or {}
	st.quests = st.quests or {}
	st.completed = st.completed or {}
	for step, questID in ipairs(QUESTS) do st.quests[step] = questID end
	local getChain = C_QuestLine and C_QuestLine.GetQuestLineQuests
	if getChain then
		local ok, quests = pcall(getChain, 6385)
		-- Reject partial/filtered lists so missing entries cannot shift weeks.
		local valid = ok and type(quests) == "table" and #quests == TOTAL_STEPS
		if valid then
			for step, questID in ipairs(QUESTS) do
				if quests[step] ~= questID then valid = false end
			end
			for _, questID in ipairs(quests) do
				if type(questID) ~= "number" or questID <= 0 then valid = false end
			end
		end
		if valid then
			for step, questID in ipairs(quests) do st.quests[step] = questID end
		end
	end
	local getter = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	if getter then
		for _, questID in ipairs(st.quests) do
			local ok, completed = pcall(getter, questID)
			if ok and type(completed) == "boolean" then
				-- A transient false while loading cannot undo a permanent flag.
				st.completed[questID] = st.completed[questID] or completed
			end
		end
	end
	st.lastUpdated = time()
	charState.trackers[self.id] = st
end

function T:OnQuestTurnedIn(charState, questID)
	local st = charState.trackers[self.id]
	if not st then return end
	for _, id in ipairs(st.quests or {}) do
		if id == questID then st.completed[id] = true end
	end
end

function T:GetProgress(charState)
	local available = CurrentStep()
	if available == nil then return nil, nil end
	local st = charState.trackers[self.id] or {}
	local earned = 0
	for step = 1, available do
		local questID = (st.quests or {})[step] or QUESTS[step]
		local done = questID and st.completed and st.completed[questID]
		if done == nil then return nil, available end
		if done then earned = earned + 1 end
	end
	return earned, available
end

function T:GetStatus(charState)
	local earned, available = self:GetProgress(charState)
	if available == 0 then return "unavailable" end
	if earned == nil then return "unknown" end
	if earned == available then return available == TOTAL_STEPS and "finished" or "done" end
	return "pending"
end

function T:IsComplete(charState)
	local status = self:GetStatus(charState)
	return status == "done" or status == "finished"
end

function T:GetSummary(charState)
	local earned, available = self:GetProgress(charState)
	if available == 0 then return Constants.COLOR_GRAY .. "-" .. Constants.COLOR_RESET end
	if earned == nil then
		return Constants.COLOR_GRAY .. (available and ("?/" .. available) or "Unknown") .. Constants.COLOR_RESET
	end
	local color = earned == available and Constants.COLOR_GREEN
		or (earned > 0 and Constants.COLOR_YELLOW or Constants.COLOR_RED)
	return string.format("%s%d/%d%s", color, earned, available, Constants.COLOR_RESET)
end

_G[ADDON_NAME .. "SoulFragmentTracker"] = T
local registry = _G[ADDON_NAME .. "TrackerRegistry"]
if registry then registry:Register(T) end
