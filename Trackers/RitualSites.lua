local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

-- Ritual Sites. Always available each week, with a progress-bar quest
-- (QUEST_RITUAL_SITES) whose completion percentage we read directly. They feed
-- the SAME Great Vault World track as delves, so this tracker shares the delve
-- vault gear rule (skip once in Mythic gear) and there is no separate ritual
-- vault row -- the "World" row under Great Vault already counts the combined
-- delve + ritual contribution.
local EMDASH = "\226\128\148"

-- Returns (percent 0-100, completed bool). percent is nil if the quest is not
-- currently readable (e.g. not yet in this character's log this session).
local function ReadRitualProgress(qid)
	if not qid or qid <= 0 then return nil, false end
	local completed = C_QuestLog.IsQuestFlaggedCompleted(qid)
	if completed then return 100, true end
	local getPct = C_QuestLog and C_QuestLog.GetQuestProgressBarPercent
	local pct = getPct and getPct(qid)
	if pct then return pct, false end
	return nil, false
end

local T = {
	id = Constants.TRACKER_RITUALSITES,
	label = "Weekly",
	icon = 4576453,
	category = "weekly",
	group = "rituals",
	order = 1,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" },
	enabledByDefault = true,
	countsForRecommend = true,
}

function T:Scan(charState)
	local st = charState.trackers[self.id] or {}
	local pct, completed = ReadRitualProgress(Constants.QUEST_RITUAL_SITES)
	if pct ~= nil then
		st.pct = pct
		st.completed = completed
		st.lastUpdated = time()
	end
	-- If unreadable right now, keep the last captured value (snapshot model).
	charState.trackers[self.id] = st
end

-- Shares the delve vault gear ceiling: ritual sites only feed the Hero-capped
-- World vault, so they stop being worth doing once you are in Mythic gear.
function T:StopIlvl(charState)
	return Constants.VAULT_STOP_DELVE
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	if st.pct == nil then
		return Constants.COLOR_GRAY .. EMDASH .. Constants.COLOR_RESET
	end
	local done = st.completed or st.pct >= 100
	-- Outgeared (in Mythic gear): the shared World vault no longer upgrades.
	if not Constants.VaultWorthDoing(charState, self:StopIlvl(charState)) then
		local txt = done and "Done" or string.format("%d%%", math.floor(st.pct))
		return Constants.COLOR_GRAY .. txt .. Constants.COLOR_RESET
	end
	if done then
		return Constants.COLOR_GREEN .. "Done" .. Constants.COLOR_RESET
	end
	local color = st.pct > 0 and Constants.COLOR_YELLOW or Constants.COLOR_RED
	return string.format("%s%d%%%s", color, math.floor(st.pct), Constants.COLOR_RESET)
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	-- Unreadable (nil) counts as complete so it never lingers as a phantom to-do.
	if st.pct == nil then return true end
	return st.completed or st.pct >= 100
end

function T:GetAction(charState)
	local st = charState.trackers[self.id] or {}
	if st.pct and st.pct > 0 then
		return string.format("Ritual sites (%d%%)", math.floor(st.pct))
	end
	return "Ritual sites"
end

_G[ADDON_NAME .. "RitualSitesTracker"] = T

if TrackerRegistry then
	TrackerRegistry:Register(T)
end
