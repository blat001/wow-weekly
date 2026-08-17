local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

-- Additional weekly quests on the Coiled Isle. These use ordinary weekly
-- quest completion flags rather than the progress bar used by Vaults of
-- Atal'Utek.
local function CreateQuestTracker(id, label, questID, order)
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
		countsForRecommend = true,
	}

	function T:Scan(charState)
		charState.trackers[self.id] = {
			done = C_QuestLog.IsQuestFlaggedCompleted(questID) == true,
			lastUpdated = time(),
		}
	end

	function T:GetSummary(charState)
		local done = (charState.trackers[self.id] or {}).done == true
		if done then
			return Constants.CHECK_GREEN
		end
		return Constants.COLOR_GRAY .. "\226\128\148" .. Constants.COLOR_RESET
	end

	function T:IsComplete(charState)
		return (charState.trackers[self.id] or {}).done == true
	end

	function T:GetAction(charState)
		return label
	end

	return T
end

local trackers = {
	CreateQuestTracker(Constants.TRACKER_TURNBACKSURGE, "Turn Back the Surge",
		Constants.QUEST_TURN_BACK_SURGE, 1),
	CreateQuestTracker(Constants.TRACKER_PURGINGVAULTS, "Purging the Vaults",
		Constants.QUEST_PURGING_VAULTS, 2),
	CreateQuestTracker(Constants.TRACKER_COILEDISLE_WORLDBOSS, "World Boss",
		Constants.QUEST_COILED_ISLE_WORLD_BOSS, 3),
}

for _, tracker in ipairs(trackers) do
	TrackerRegistry:Register(tracker)
end
