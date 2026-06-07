local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

-- Prey (Midnight weekly hunt). One tracker per difficulty (Normal / Hard /
-- Nightmare). Each difficulty is its own weekly goal of 4 distinct kills; we
-- count how many quests from that difficulty's rotating pool are flagged
-- complete this week and show "n/4". Quest pools live in Constants
-- (PREY_*_QUESTS), sourced from SavedInstances.
local GOAL = Constants.PREY_WEEKLY_GOAL or 4

-- How many quests in the list are flagged complete (capped at the weekly goal).
local function CountDone(questIDs)
	if not questIDs then return 0 end
	local n = 0
	for _, qid in ipairs(questIDs) do
		if C_QuestLog.IsQuestFlaggedCompleted(qid) then
			n = n + 1
			if n >= GOAL then break end
		end
	end
	return n
end

local function MakePreyTracker(trackerId, label, order, questIDs)
	local T = {
		id = trackerId,
		label = label,
		icon = 4576453,
		category = "weekly",
		group = "prey",
		order = order,
		cadence = "weekly",
		events = { "PLAYER_LOGIN", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" },
		enabledByDefault = true,
		-- Display-only for now: left out of the Recommender so it does not
		-- suggest the wrong difficulty (a geared character only does the
		-- highest tier). Flip to true if you want Prey to feed the recommender.
		countsForRecommend = false,
		questIDs = questIDs,
	}

	function T:Scan(charState)
		charState.trackers[self.id] = {
			done = CountDone(self.questIDs),
			lastUpdated = time(),
		}
	end

	function T:GetSummary(charState)
		local st = charState.trackers[self.id] or {}
		local done = st.done or 0
		local color
		if done >= GOAL then
			color = Constants.COLOR_GREEN
		elseif done > 0 then
			color = Constants.COLOR_YELLOW
		else
			color = Constants.COLOR_RED
		end
		return string.format("%s%d/%d%s", color, done, GOAL, Constants.COLOR_RESET)
	end

	function T:IsComplete(charState)
		local st = charState.trackers[self.id] or {}
		return (st.done or 0) >= GOAL
	end

	function T:GetAction(charState)
		local st = charState.trackers[self.id] or {}
		return string.format("Prey %s (%d/%d)", label, st.done or 0, GOAL)
	end

	return T
end

local Normal    = MakePreyTracker(Constants.TRACKER_PREY_NORMAL,    "Normal",    1, Constants.PREY_NORMAL_QUESTS)
local Hard      = MakePreyTracker(Constants.TRACKER_PREY_HARD,      "Hard",      2, Constants.PREY_HARD_QUESTS)
local Nightmare = MakePreyTracker(Constants.TRACKER_PREY_NIGHTMARE, "Nightmare", 3, Constants.PREY_NIGHTMARE_QUESTS)

_G[ADDON_NAME .. "PreyNormalTracker"]    = Normal
_G[ADDON_NAME .. "PreyHardTracker"]      = Hard
_G[ADDON_NAME .. "PreyNightmareTracker"] = Nightmare

if TrackerRegistry then
	TrackerRegistry:Register(Normal)
	TrackerRegistry:Register(Hard)
	TrackerRegistry:Register(Nightmare)
end
