local ADDON_NAME = "WoWWeekly"
local WoWWeekly = _G[ADDON_NAME]
local Constants = _G[ADDON_NAME .. "Constants"]

local T = {
	id = Constants.TRACKER_READYTOCRAFT,
	label = "Ready to Craft",
	icon = 4576453,
	category = "weekly",
	group = "professions",
	order = 5,
	-- Crest balances carry across the weekly reset; the reset sweep must not
	-- clear this state for characters that haven't logged in.
	cadence = "persistent",
	events = { "PLAYER_LOGIN", "CURRENCY_DISPLAY_UPDATE" },
	enabledByDefault = true,
}

function T:Scan(charState)
	local function CurrencyCount(id)
		if not id or id <= 0 then return 0 end
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		return info and info.quantity or 0
	end
	charState.trackers[self.id] = {
		heroCrests = CurrencyCount(Constants.CURRENCY_HERO_CREST),
		mythCrests = CurrencyCount(Constants.CURRENCY_MYTH_CREST),
		lastUpdated = time(),
	}
end

local function SelectedCrests(st)
	local po = WoWWeekly.db and WoWWeekly.db.profileOptions
	local crestType = po and po.readyCraftCrest or "myth"
	if crestType == "hero" then return st.heroCrests or 0 end
	return st.mythCrests or 0
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	local crests = SelectedCrests(st)
	local ready = crests >= Constants.CREST_CRAFT_THRESHOLD
	if ready then
		return Constants.CHECK_GREEN
	end
	return Constants.COLOR_GRAY.."("..crests..")"..Constants.COLOR_RESET
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	return SelectedCrests(st) >= Constants.CREST_CRAFT_THRESHOLD
end

_G[ADDON_NAME .. "ReadyToCraftTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
