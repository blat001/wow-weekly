local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local T = {
	id = Constants.TRACKER_COFFERKEYS,
	label = "Coffer Keys",
	icon = 4576453,
	category = "weekly",
	group = "delves",
	order = 2,
	-- Banked keys/shards carry across the weekly reset; the reset sweep must
	-- not clear this state for characters that haven't logged in.
	cadence = "persistent",
	events = { "PLAYER_LOGIN", "CURRENCY_DISPLAY_UPDATE" },
	enabledByDefault = true,
}

function T:Scan(charState)
	local keys, shards = 0, 0
	local keyId = Constants.CURRENCY_RESTORED_COFFER_KEY
	if keyId and keyId > 0 then
		local info = C_CurrencyInfo.GetCurrencyInfo(keyId)
		keys = info and info.quantity or 0
	end
	local shardId = Constants.CURRENCY_COFFER_KEY_SHARD
	if shardId and shardId > 0 then
		local info = C_CurrencyInfo.GetCurrencyInfo(shardId)
		shards = info and info.quantity or 0
	end
	charState.trackers[self.id] = { keys = keys, shards = shards, lastUpdated = time() }
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	local keys = st.keys or 0
	local shards = st.shards or 0
	local perKey = Constants.SHARDS_PER_KEY
	-- Effective keys: ones you hold plus ones your shards will become in a delve.
	local fromShards = (perKey > 0) and math.floor(shards / perKey) or 0
	local total = keys + fromShards
	local color = total > 0 and Constants.COLOR_GREEN or Constants.COLOR_RED
	return string.format("%s%d%s", color, total, Constants.COLOR_RESET)
end

function T:IsComplete(charState)
	return false
end

_G[ADDON_NAME .. "CofferKeysTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
