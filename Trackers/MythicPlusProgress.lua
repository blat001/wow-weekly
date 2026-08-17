local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

local function MapName(mapID)
	if not (mapID and mapID > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
	local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
	return ok and name or nil
end

local Weekly = {
	id = Constants.TRACKER_MPLUS_WEEK,
	label = "This Week",
	icon = 525134,
	category = "weekly",
	group = "mplus",
	order = 1,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_MAPS_UPDATE" },
	enabledByDefault = true,
	countsForRecommend = false,
}

function Weekly:Scan(charState)
	local st = charState.trackers[self.id] or {}
	local runs, best = 0, 0
	if Constants.IsMidnightSeason2Active() and C_MythicPlus and C_MythicPlus.GetRunHistory then
		local ok, history = pcall(C_MythicPlus.GetRunHistory, false, true)
		if ok and type(history) == "table" then
			for _, run in ipairs(history) do
				if run.thisWeek ~= false then
					runs = runs + 1
					best = math.max(best, run.level or 0)
				end
			end
		end
	end
	st.runs, st.best, st.lastUpdated = runs, best, time()
	charState.trackers[self.id] = st
end

function Weekly:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	if (st.runs or 0) == 0 then return Constants.COLOR_GRAY .. "-" .. Constants.COLOR_RESET end
	local noun = st.runs == 1 and "run" or "runs"
	return Constants.COLOR_PURPLE .. "Best +" .. (st.best or 0) .. Constants.COLOR_RESET
		.. Constants.COLOR_GRAY .. " · " .. st.runs .. " " .. noun .. Constants.COLOR_RESET
end

local Keystone = {
	id = Constants.TRACKER_MPLUS_KEY,
	label = "Keystone",
	icon = 525134,
	category = "weekly",
	group = "mplus",
	order = 2,
	cadence = "persistent",
	events = { "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "CHALLENGE_MODE_MAPS_UPDATE" },
	enabledByDefault = true,
	countsForRecommend = false,
}

function Keystone:Scan(charState)
	local st = charState.trackers[self.id] or {}
	local level = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or 0
	local mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0
	st.level, st.mapID, st.mapName, st.lastUpdated = level or 0, mapID or 0, MapName(mapID), time()
	charState.trackers[self.id] = st
end

function Keystone:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	if (st.level or 0) <= 0 then return Constants.COLOR_GRAY .. "-" .. Constants.COLOR_RESET end
	local suffix = st.mapName and (" " .. st.mapName) or ""
	return Constants.COLOR_PURPLE .. "+" .. st.level .. suffix .. Constants.COLOR_RESET
end

TrackerRegistry:Register(Weekly)
TrackerRegistry:Register(Keystone)
