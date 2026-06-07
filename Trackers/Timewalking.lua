local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

-- Timewalking weekend event weekly ("A <X> Path Through Time"). Only one
-- expansion's timewalking is active per week, and only during a Timewalking
-- weekend, so this is AVAILABLE only some weeks. We detect whichever pool quest
-- is in the log (or completed), show its progress, and stay out of the way
-- (gray dash, not relevant) on weeks with no Timewalking event.
local EMDASH = "\226\128\148"

-- Reliable "is this quest in my log?" check (GetLogIndexForQuestID can return
-- nil for some quest types even while you are on the quest).
local function IsOnLog(qid)
	if C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(qid) end
	local gi = C_QuestLog.GetLogIndexForQuestID
	return gi and gi(qid) ~= nil
end

local function QuestProgress(qid)
	local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(qid)
	if objs and objs[1] and (objs[1].numRequired or 0) > 0 then
		return objs[1].numFulfilled or 0, objs[1].numRequired, objs[1].finished
	end
	local getPct = C_QuestLog.GetQuestProgressBarPercent
	local pct = getPct and getPct(qid)
	if pct then return math.floor(pct), 100, pct >= 100 end
	return nil
end

local T = {
	id = Constants.TRACKER_TIMEWALKING,
	label = "Timewalking",
	icon = 4576453,
	category = "weekly",
	group = "weekly",
	order = 2,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" },
	enabledByDefault = true,
	countsForRecommend = true,
}

function T:Scan(charState)
	local data = { available = false }
	-- Active timewalking weekly = the pool quest currently in the log.
	for _, qid in ipairs(Constants.TIMEWALKING_POOL) do
		if IsOnLog(qid) then
			local cur, max, fin = QuestProgress(qid)
			data.available = true
			data.cur, data.max = cur, max
			data.done = fin or C_QuestLog.IsQuestFlaggedCompleted(qid)
			break
		end
	end
	-- Otherwise it may be turned in already this week.
	if not data.available then
		for _, qid in ipairs(Constants.TIMEWALKING_POOL) do
			if C_QuestLog.IsQuestFlaggedCompleted(qid) then
				data.available = true
				data.done = true
				break
			end
		end
	end
	data.lastUpdated = time()
	charState.trackers[self.id] = data
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	if not st.available then
		return Constants.COLOR_GRAY .. EMDASH .. Constants.COLOR_RESET
	end
	if st.done then
		return Constants.COLOR_GREEN .. "Done" .. Constants.COLOR_RESET
	end
	if st.cur and st.max then
		local color = st.cur > 0 and Constants.COLOR_YELLOW or Constants.COLOR_RED
		return string.format("%s%d/%d%s", color, st.cur, st.max, Constants.COLOR_RESET)
	end
	return Constants.COLOR_RED .. "Not Done" .. Constants.COLOR_RESET
end

-- Only relevant on weeks a Timewalking event is running.
function T:IsRelevant(charState)
	return (charState.trackers[self.id] or {}).available == true
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	-- Unavailable counts as complete so it never lingers as a to-do.
	if not st.available then return true end
	return st.done == true
end

function T:GetAction(charState)
	local st = charState.trackers[self.id] or {}
	if st.cur and st.max and not st.done then
		return string.format("Timewalking (%d/%d)", st.cur, st.max)
	end
	return "Timewalking"
end

_G[ADDON_NAME .. "TimewalkingTracker"] = T

if TrackerRegistry then
	TrackerRegistry:Register(T)
end
