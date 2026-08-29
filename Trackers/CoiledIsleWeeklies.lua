local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

-- Additional weekly quests on the Coiled Isle. These use ordinary weekly
-- quest completion flags rather than the progress bar used by Vaults of
-- Atal'Utek.
local function QuestProgress(questID)
	local objectives = C_QuestLog.GetQuestObjectives
		and C_QuestLog.GetQuestObjectives(questID)
	if objectives then
		for _, objective in ipairs(objectives) do
			if (objective.numRequired or 0) > 0 then
				return objective.numFulfilled or 0, objective.numRequired
			end
		end
	end
	return nil
end

local function CreateQuestTracker(id, label, questID, order, progressMax, percentage, recommend)
	local T = {
		id = id,
		label = label,
		icon = 4576453,
		category = "weekly",
		group = "rituals", -- retained group ID; displayed as "Coiled Isle"
		order = order,
		cadence = "weekly",
		events = { "PLAYER_LOGIN", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" },
		enabledByDefault = true,
		countsForRecommend = recommend ~= false,
	}

	function T:Scan(charState)
		local done = C_QuestLog.IsQuestFlaggedCompleted(questID) == true
		local cur, max
		if progressMax then
			cur, max = QuestProgress(questID)
			max = max or progressMax
			cur = done and max or (cur or 0)
		elseif percentage then
			local getPercent = C_QuestLog.GetQuestProgressBarPercent
			cur = done and 100 or (getPercent and getPercent(questID))
			max = 100
		end
		charState.trackers[self.id] = {
			done = done,
			cur = cur,
			max = max,
			lastUpdated = time(),
		}
	end

	function T:GetSummary(charState)
		local st = charState.trackers[self.id] or {}
		local done = st.done == true
		if progressMax then
			local cur, max = st.cur or 0, st.max or progressMax
			local color = done and Constants.COLOR_GREEN
				or (cur > 0 and Constants.COLOR_YELLOW or Constants.COLOR_RED)
			return string.format("%s%d/%d%s", color, cur, max, Constants.COLOR_RESET)
		elseif percentage and st.cur ~= nil then
			local color = done and Constants.COLOR_GREEN
				or (st.cur > 0 and Constants.COLOR_YELLOW or Constants.COLOR_RED)
			return string.format("%s%d%%%s", color, math.floor(st.cur), Constants.COLOR_RESET)
		end
		if done then
			return Constants.CHECK_GREEN
		end
		return Constants.COLOR_GRAY .. "\226\128\148" .. Constants.COLOR_RESET
	end

	function T:IsComplete(charState)
		return (charState.trackers[self.id] or {}).done == true
	end

	function T:GetAction(charState)
		if progressMax then
			local st = charState.trackers[self.id] or {}
			local remaining = math.max(0, (st.max or progressMax) - (st.cur or 0))
			return string.format("Complete %d more objectives for %s", remaining, label)
		elseif percentage then
			local st = charState.trackers[self.id] or {}
			if st.cur ~= nil then
				return string.format("Finish %s (%d%% remaining)", label,
					math.max(0, 100 - math.floor(st.cur)))
			end
		end
		if id == Constants.TRACKER_COILEDISLE_WORLDBOSS then
			return "Defeat the Coiled Isle World Boss"
		end
		return "Complete " .. label
	end

	return T
end

local trackers = {
	CreateQuestTracker(Constants.TRACKER_TURNBACKSURGE, "Turn Back the Surge",
		Constants.QUEST_TURN_BACK_SURGE, 1, 3),
	CreateQuestTracker(Constants.TRACKER_PURGINGVAULTS, "Purging the Vaults",
		Constants.QUEST_PURGING_VAULTS, 2, nil, true, false),
	CreateQuestTracker(Constants.TRACKER_COILEDISLE_WORLDBOSS, "World Boss",
		Constants.QUEST_COILED_ISLE_WORLD_BOSS, 3),
}

for _, tracker in ipairs(trackers) do
	TrackerRegistry:Register(tracker)
end
