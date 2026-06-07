local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local T = {
	id = Constants.TRACKER_BOUNTYMAP,
	label = "Bounty Map",
	icon = 4576453,
	category = "weekly",
	group = "delves",
	order = 1,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "QUEST_TURNED_IN" },
	enabledByDefault = true,
	countsForRecommend = true,
}

local function ItemCount(itemID)
	if not itemID or itemID <= 0 then return 0 end
	local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
	return (fn and fn(itemID)) or 0
end

function T:Scan(charState)
	-- Three states. Check the physical item FIRST: if the map is in your bags
	-- you have not used it yet, regardless of the looted-this-week quest flag.
	--   In Bags   = map item is in your bags (looted, not yet used)
	--   Used       = looted this week (quest done) but no longer in bags
	--   Not Looted = no map and not looted this week
	local state
	if ItemCount(Constants.ITEM_BOUNTY_MAP) > 0 then
		state = "inbags"
	elseif Constants.QUEST_BOUNTY_LOOTED > 0
		and C_QuestLog.IsQuestFlaggedCompleted(Constants.QUEST_BOUNTY_LOOTED) then
		state = "used"
	else
		state = "notlooted"
	end
	charState.trackers[self.id] = { state = state, lastUpdated = time() }
end

function T:GetSummary(charState)
	local s = (charState.trackers[self.id] or {}).state
	if s == "used" then
		return Constants.COLOR_GREEN .. "Used" .. Constants.COLOR_RESET
	elseif s == "inbags" then
		return Constants.COLOR_YELLOW .. "In Bags" .. Constants.COLOR_RESET
	end
	return Constants.COLOR_RED .. "Not Looted" .. Constants.COLOR_RESET
end

function T:IsComplete(charState)
	local s = (charState.trackers[self.id] or {}).state
	return s == "used"
end

function T:GetAction(charState)
	local s = (charState.trackers[self.id] or {}).state
	if s == "inbags" then return "Use bounty map" end
	return "Bounty map"
end

_G[ADDON_NAME .. "BountyMapTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
