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
	-- Include bank, reagent bank, and account bank so a stored map is not
	-- mistaken for one that was consumed.
	if not fn then return 0 end
	local ok, count = pcall(fn, itemID, true, false, true, true)
	return ok and count or 0
end

local function HasBountyMap()
	local known = {}
	for _, itemID in ipairs(Constants.ITEM_BOUNTY_MAPS or { Constants.ITEM_BOUNTY_MAP }) do
		known[itemID] = true
		if ItemCount(itemID) > 0 then return true end
	end

	-- Fall back to the actual bag contents. This protects the tracker when
	-- Blizzard introduces another seasonal item ID before databases catch up.
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
		return false
	end
	for bag = 0, 5 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				if known[info.itemID] then return true end
				local link = info.hyperlink and string.lower(info.hyperlink)
				if link and string.find(link, "trovehunter's bounty", 1, true) then return true end
			end
		end
	end
	return false
end

function T:Scan(charState)
	-- Three states. Check the physical item FIRST: if the map is in your bags
	-- you have not used it yet, regardless of the looted-this-week quest flag.
	--   In Bags   = map item is in your bags (looted, not yet used)
	--   Used       = looted this week (quest done) but no longer in bags
	--   Not Looted = no map and not looted this week
	local state
	if HasBountyMap() then
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
		return Constants.CHECK_GREEN
	elseif s == "inbags" then
		return Constants.COLOR_YELLOW .. "In Bags" .. Constants.COLOR_RESET
	end
	return Constants.COLOR_GRAY .. "-" .. Constants.COLOR_RESET
end

function T:IsComplete(charState)
	local s = (charState.trackers[self.id] or {}).state
	return s == "used"
end

function T:GetAction(charState)
	local s = (charState.trackers[self.id] or {}).state
	if s == "inbags" then return "Use your Bounty Map in a Tier 8+ Delve for Hero gear" end
	return "Complete Purging the Vaults for a Bounty Map"
end

_G[ADDON_NAME .. "BountyMapTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
