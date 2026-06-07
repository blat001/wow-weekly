local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local T = {
	id = Constants.TRACKER_KEYSTONE,
	label = "Keystone",
	icon = 525134,
	category = "weekly",
	group = "vault",
	order = 4,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "BAG_UPDATE", "CHALLENGE_MODE_MAPS_UPDATE" },
	enabledByDefault = true,
}

function T:Scan(charState)
	local keyLevel, keyName
	if C_MythicPlus then
		if C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
		if C_MythicPlus.GetOwnedKeystoneLevel then
			keyLevel = C_MythicPlus.GetOwnedKeystoneLevel()
		end
		local mapID
		if C_MythicPlus.GetOwnedKeystoneChallengeMapID then
			mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
		end
		if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
			keyName = C_ChallengeMode.GetMapUIInfo(mapID)
		end
	end
	charState.trackers[self.id] = { keyLevel = keyLevel, keyName = keyName, lastUpdated = time() }
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	local keyLevel = st.keyLevel
	if not (keyLevel and keyLevel > 0) then
		return Constants.COLOR_GRAY .. "\226\128\148" .. Constants.COLOR_RESET
	end
	local txt = "+" .. keyLevel
	if st.keyName and st.keyName ~= "" then
		txt = txt .. " " .. st.keyName
	end
	return Constants.COLOR_PURPLE .. txt .. Constants.COLOR_RESET
end

function T:IsComplete(charState)
	return false
end

_G[ADDON_NAME .. "KeystoneTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
