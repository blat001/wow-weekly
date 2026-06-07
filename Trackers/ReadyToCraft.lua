local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local T = {
	id = Constants.TRACKER_READYTOCRAFT,
	label = "Ready to Craft",
	icon = 4576453,
	category = "weekly",
	group = "professions",
	order = 5,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "CURRENCY_DISPLAY_UPDATE" },
	enabledByDefault = true,
}

function T:Scan(charState)
	local q = 0
	local id = Constants.CURRENCY_MYTH_CREST
	if id and id > 0 then
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		q = info and info.quantity or 0
	end
	charState.trackers[self.id] = { crests = q, lastUpdated = time() }
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	local crests = st.crests or 0
	local ready = crests >= Constants.MYTH_CREST_CRAFT_THRESHOLD
	if ready then
		return Constants.COLOR_GREEN.."Yes"..Constants.COLOR_RESET
	end
	return Constants.COLOR_RED.."No ("..crests..")"..Constants.COLOR_RESET
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	return (st.crests or 0) >= Constants.MYTH_CREST_CRAFT_THRESHOLD
end

_G[ADDON_NAME .. "ReadyToCraftTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
