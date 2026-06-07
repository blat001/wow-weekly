local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

-- Weekly Gilded Stash progress (Tier 11 Bountiful Delves). This is NOT a quest
-- or currency: the count comes from a UI widget (the delve dashboard's "Gilded
-- Stash" spell display), the same source the Plumber addon reads. We scan a list
-- of candidate widget IDs for the one whose spell is the Gilded Stash and parse
-- "X/Y" out of its tooltip. The widget is only populated while out near delve
-- content, so when it is unavailable we KEEP the last captured value instead of
-- wiping it (consistent with the addon's snapshot model).
local CREST_SPELL = 1216211
local WIDGET_IDS = {
	6659, 6718, 6719, 6720, 6721, 6722, 6723, 6724, 6725, 6726,
	6727, 6728, 6729, 6794, 7193, 7591,
}

local function ReadStashProgress()
	local getter = C_UIWidgetManager and C_UIWidgetManager.GetSpellDisplayVisualizationInfo
	if not getter then return nil end
	for _, widgetID in ipairs(WIDGET_IDS) do
		local info = getter(widgetID)
		-- NOTE: do NOT gate on shownState. It flips to 0 once the weekly cap is
		-- reached (4/4), but the tooltip still holds the correct count. The
		-- tooltip is the source of truth; the spell match is enough.
		if info and info.spellInfo and info.spellInfo.spellID == CREST_SPELL
			and info.spellInfo.tooltip then
			local cur, max = string.match(info.spellInfo.tooltip, "(%d+)/(%d+)")
			cur, max = tonumber(cur), tonumber(max)
			if cur and max and max > 0 then
				return cur, max
			end
		end
	end
	return nil
end

local T = {
	id = Constants.TRACKER_GILDEDSTASH,
	label = "Gilded Stash",
	icon = 4576453,
	category = "weekly",
	group = "delves",
	order = 4,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "UPDATE_UI_WIDGET", "ZONE_CHANGED_NEW_AREA" },
	enabledByDefault = true,
	countsForRecommend = true,
}

function T:Scan(charState)
	local st = charState.trackers[self.id] or {}
	local cur, max = ReadStashProgress()
	if cur and max then
		st.looted = cur
		st.max = max
		st.lastUpdated = time()
	end
	-- If unavailable here, keep whatever we last captured.
	charState.trackers[self.id] = st
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	if not st.max or st.max <= 0 then
		return Constants.COLOR_GRAY .. "\226\128\148" .. Constants.COLOR_RESET
	end
	local looted = st.looted or 0
	local color
	if looted >= st.max then
		color = Constants.COLOR_GREEN
	elseif looted > 0 then
		color = Constants.COLOR_YELLOW
	else
		color = Constants.COLOR_RED
	end
	return string.format("%s%d/%d%s", color, looted, st.max, Constants.COLOR_RESET)
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	return st.max ~= nil and st.max > 0 and (st.looted or 0) >= st.max
end

-- Only recommend once we actually have the weekly cap for this character.
function T:IsRelevant(charState)
	local st = charState.trackers[self.id] or {}
	return st.max ~= nil and st.max > 0
end

function T:GetAction(charState)
	local st = charState.trackers[self.id] or {}
	return string.format("Gilded Stash (%d/%d)", st.looted or 0, st.max or 0)
end

_G[ADDON_NAME .. "GildedStashTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
