local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

-- The Midnight Meta Quest ("the weekly quest"). Each character CHOOSES one
-- objective from a pool (Delves, Battlegrounds, World Boss, ...). The chosen
-- variant becomes a quest in their log with progress, so we detect whichever
-- pool quest is in the log and show its name + progress, e.g. "Delves 2/3".
-- If a variant was already turned in, we fall back to a completed-flag check.

-- First objective of a quest as (current, required, finished). Falls back to a
-- progress-bar percentage for quests that use one.
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
	id = Constants.TRACKER_METAQUEST,
	label = "Meta Quest",
	icon = 4576453,
	category = "weekly",
	group = "weekly",
	order = 1,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" },
	enabledByDefault = true,
	countsForRecommend = true,
}

function T:Scan(charState)
	local names = Constants.META_QUEST_NAMES
	local previous = charState.trackers[self.id] or {}
	local chosen
	-- Several meta objectives can sit in the log at once, so do NOT just take the
	-- first. Prefer the one the player is actively progressing (not finished,
	-- most progress) so we show e.g. "Delves 3/4" rather than a different
	-- objective that happens to already be done.
	for _, qid in ipairs(Constants.META_QUEST_POOL) do
		if IsOnLog(qid) then
			local cur, max, fin = QuestProgress(qid)
			local cand = {
				qid = qid,
				name = names[qid] or "Weekly",
				cur = cur, max = max,
				done = fin == true,
				seenThisReset = true,
			}
			if not chosen then
				chosen = cand
			else
				local candActive   = (not cand.done) and 1 or 0
				local chosenActive = (not chosen.done) and 1 or 0
				if candActive > chosenActive then
					chosen = cand
				elseif candActive == chosenActive and (cand.cur or 0) > (chosen.cur or 0) then
					chosen = cand
				end
			end
		end
	end
	-- After turn-in the quest leaves the log. Only trust its completion flag if
	-- this addon observed that exact quest earlier in the current reset period;
	-- IsQuestFlaggedCompleted can remain true from a previous week.
	if not chosen and previous.seenThisReset and previous.qid
		and C_QuestLog.IsQuestFlaggedCompleted(previous.qid) then
		chosen = {
			qid = previous.qid,
			done = true,
			generic = true,
			seenThisReset = true,
		}
	end
	chosen = chosen or { none = true }
	chosen.lastUpdated = time()
	charState.trackers[self.id] = chosen
end

-- "Delves 2/3" / "Battlegrounds 1/1" / "Raid Done" / "Not chosen".
local function describe(st)
	if st.none or not st.name then return nil end
	if st.cur and st.max then
		return string.format("%s %d/%d", st.name, st.cur, st.max)
	end
	if st.done then return st.name .. " Done" end
	return st.name
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	if st.done then
		return Constants.CHECK_GREEN
	end
	local text = describe(st)
	if not text then
		return Constants.COLOR_GRAY .. "-" .. Constants.COLOR_RESET
	end
	local color
	if (st.cur or 0) > 0 then
		color = Constants.COLOR_YELLOW
	else
		color = Constants.COLOR_RED
	end
	return color .. text .. Constants.COLOR_RESET
end

-- Do not reserve a row for the meta tracker on weeks/characters where none of
-- the recognized weekly quests is available. The tooltip checks this across
-- every displayed character, so one active or completed weekly shows the row.
function T:IsVisible(charState)
	local st = charState.trackers[self.id] or {}
	return st.done == true or st.name ~= nil
end

function T:IsComplete(charState)
	return (charState.trackers[self.id] or {}).done == true
end

function T:GetAction(charState)
	local st = charState.trackers[self.id] or {}
	local name = st.name or "meta"
	if st.cur and st.max then
		local remaining = math.max(0, st.max - st.cur)
		return string.format("Finish the %s weekly quest (%d remaining)", name, remaining)
	end
	return string.format("Finish the %s weekly quest", name)
end

_G[ADDON_NAME .. "MetaQuestTracker"] = T

if TrackerRegistry then
	TrackerRegistry:Register(T)
end
