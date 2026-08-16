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
	-- Identify the week by the timestamp of its upcoming reset. That timestamp
	-- is constant all week and jumps by exactly one week at the in-game reset,
	-- so dividing by a week gives an ID that increments at the true reset
	-- moment (region-correct: Tue 15:00 UTC for US, Wed 07:00 UTC for EU).
	-- A plain "weeks since epoch" bucket flips at an arbitrary wall-clock time
	-- unrelated to the actual reset day.
	local secs = C_DateAndTime.GetSecondsUntilWeeklyReset()
	if not secs then
		-- API not ready yet; reuse the last computed value rather than risk a
		-- bogus mismatch that would wipe current-week data.
		return WoWWeekly.db.global.currentResetPeriodId or 0
	end
	return math.floor((time() + secs) / 604800)  -- 604800 = seconds in a week
end

function WeeklyReset:CheckAndApplyWeeklyReset()
	local db = WoWWeekly.db
	local currentPeriodId = self:GetCurrentResetPeriodId()
	-- Keep the global "what week is it" cache current.
	db.global.currentResetPeriodId = currentPeriodId

	-- The in-game reset clears EVERY character's weekly progress, logged in or
	-- not. Sweep all stored characters: a stamp behind the current period means
	-- that snapshot is from an old week, so wipe it and restamp. Characters
	-- already stamped with the current period keep their data, so alts played
	-- earlier in the same week are untouched.
	-- Not all tracker state is weekly, though:
	--   * cadence == "persistent": balances that carry across resets in-game
	--     (banked Coffer Keys, crest counts) - kept untouched.
	--   * OnWeeklyReset hook: tracker keeps durable knowledge but resets its
	--     weekly bits itself (professions keep the name, clear done flags).
	--   * everything else - including state left by an unregistered tracker
	--     id - defaults to weekly and is cleared outright.
	local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
	local wipedChars = 0
	for charKey, charState in pairs(db.chars) do
		if charState.resetPeriodId ~= currentPeriodId then
			charState.resetPeriodId = currentPeriodId
			local cleared = false
			for id in pairs(charState.trackers or {}) do
				local tracker = TrackerRegistry and TrackerRegistry:GetTracker(id)
				if tracker and tracker.cadence == "persistent" then
					-- keep as-is
				elseif tracker and tracker.OnWeeklyReset then
					tracker:OnWeeklyReset(charState)
					cleared = true
				else
					charState.trackers[id] = nil
					cleared = true
				end
			end
			if cleared then wipedChars = wipedChars + 1 end
		end
	end
	if wipedChars > 0 then
		WoWWeekly:Print(string.format("New week: cleared weekly progress for %d character(s).", wipedChars))
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
