local ADDON_NAME = "WoWWeekly"
local WoWWeekly = _G[ADDON_NAME]

local WeeklyReset = {}

function WeeklyReset:Initialize()
	if not WoWWeekly.db then return end
	self:UpdateResetTime()
	self:CheckAndApplyWeeklyReset()
end

function WeeklyReset:OnPlayerLogin()
	self:Initialize()
end

function WeeklyReset:UpdateResetTime()
	local db = WoWWeekly.db
	local secsUntilReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
	local now = time()
	db.global.nextWeeklyResetAt = now + secsUntilReset
end

function WeeklyReset:GetCurrentResetPeriodId()
	-- Reset period ID: count the number of weekly resets since a fixed epoch.
	-- For simplicity, use a base epoch (e.g., WoW launch) and count weeks from there.
	-- This ensures the same ID across all characters on the same account.
	local EPOCH_BASE = 946684800  -- Jan 1, 2000 00:00 UTC
	local now = time()
	local weeksSinceEpoch = math.floor((now - EPOCH_BASE) / 604800)  -- 604800 = seconds in a week
	return weeksSinceEpoch
end

function WeeklyReset:CheckAndApplyWeeklyReset()
	local db = WoWWeekly.db
	local currentPeriodId = self:GetCurrentResetPeriodId()
	-- Keep the global "what week is it" cache current.
	db.global.currentResetPeriodId = currentPeriodId

	-- Per-character check: stamp THIS character with the current period every login.
	-- If their stamp is behind (a new week has started since we last saw them),
	-- wipe their stale tracker data first. This must be per-character, not global,
	-- so alts logged in later in the same week aren't treated as stale.
	local Database = _G[ADDON_NAME .. "Database"]
	local charKey = Database and Database.charKey
	local charState = charKey and db.chars[charKey]
	if charState and charState.resetPeriodId ~= currentPeriodId then
		self:ApplyWeeklyReset()
	end
end

function WeeklyReset:ApplyWeeklyReset()
	local db = WoWWeekly.db
	local Database = _G[ADDON_NAME .. "Database"]
	local charKey = Database.charKey
	local charState = db.chars[charKey]

	if charState then
		-- New week for this character: clear stale tracker data and restamp.
		charState.resetPeriodId = db.global.currentResetPeriodId
		charState.trackers = {}
		WoWWeekly:Print("Weekly reset applied for " .. charKey)
	end
end

function WeeklyReset:IsWeekStale(charKey)
	local db = WoWWeekly.db
	local charState = db.chars[charKey]
	if not charState then return true end

	local currentPeriodId = self:GetCurrentResetPeriodId()
	return charState.resetPeriodId ~= currentPeriodId
end

_G[ADDON_NAME .. "WeeklyReset"] = WeeklyReset
