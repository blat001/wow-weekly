local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local T = {
	id = Constants.TRACKER_COFFERKEYSHARDS,
	label = "Coffer Key Shards",
	icon = 4576453,
	category = "weekly",
	group = "delves",
	order = 3,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "CURRENCY_DISPLAY_UPDATE" },
	enabledByDefault = true,
}

function T:Scan(charState)
	local earned, cap = 0, Constants.COFFER_SHARD_WEEKLY_CAP
	local id = Constants.CURRENCY_COFFER_KEY_SHARD
	if id and id > 0 then
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if info then
			-- shards earned since the weekly reset, and the game's weekly cap
			earned = info.quantityEarnedThisWeek or 0
			if (info.maxWeeklyQuantity or 0) > 0 then
				cap = info.maxWeeklyQuantity
			end
		end
	end
	charState.trackers[self.id] = { earned = earned, cap = cap, lastUpdated = time() }
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	local earned = st.earned or 0
	local cap = st.cap or Constants.COFFER_SHARD_WEEKLY_CAP
	if cap > 0 and earned >= cap then
		return Constants.CHECK_GREEN
	end
	return string.format("%s%d/%d%s", Constants.COLOR_YELLOW, earned, cap, Constants.COLOR_RESET)
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	local cap = st.cap or Constants.COFFER_SHARD_WEEKLY_CAP
	return cap > 0 and (st.earned or 0) >= cap
end

_G[ADDON_NAME .. "CofferKeyShardsTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
